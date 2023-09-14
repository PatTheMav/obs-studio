//
//  OBSShaderParser.swift
//  libobs-metal
//
//  Created by Patrick Heyer on 16.04.24.
//

import Foundation
import Metal

class OBSShaderParser {
    typealias BufferType = MetalDevice.BufferType

    enum ParserType {
        case vertex
        case fragment
    }

    enum SampleType {
        case load
        case sample
        case sampleBias
        case sampleGrad
        case sampleLevel
    }

    enum ParserError: Error, CustomStringConvertible {
        case parseFail
        case unsupportedType
        case missingNextToken
        case unexpectedToken
        case missingMainFunction

        var description: String {
            switch self {
            case .parseFail:
                return "Failed to parse provided shader string"
            case .unsupportedType:
                return "Provided GS type is not convertible to a Metal type"
            case .missingNextToken:
                return "Required next token not found in parser token collection"
            case .unexpectedToken:
                return "Required next token had unexpected type in parser token collection"
            case .missingMainFunction:
                return "Shader has no main function"
            }
        }
    }

    struct ShaderFunction {
        var name: String
        var returnType: String
        var types: [String: String]

        var requiresUniforms: Bool
        var textures: [String]
        var samplers: [String]

        var function: UnsafeMutablePointer<shader_func>

        var parameters: [ShaderVariable]
    }

    struct ShaderVariable {
        var name: String
        var type: String
        var mapping: String?
        var storageType: OBSShaderParser.VariableType = []

        var inputFor: Set<String>
        var outputFrom: Set<String>

        var isStage: Bool
        var attributeId: Int?
        var isConstant: Bool

        var variable: UnsafeMutablePointer<shader_var>
    }

    struct ShaderStruct {
        var name: String
        var storageType: OBSShaderParser.VariableType

        var parameters: [ShaderVariable]

        var structVar: UnsafeMutablePointer<shader_struct>
    }

    struct VariableType: OptionSet {
        var rawValue: UInt

        static let typeUniform = VariableType(rawValue: 1 << 0)
        static let typeStruct = VariableType(rawValue: 1 << 1)
        static let typeStructMember = VariableType(rawValue: 1 << 2)
        static let typeInput = VariableType(rawValue: 1 << 3)
        static let typeOutput = VariableType(rawValue: 1 << 4)
        static let typeTexture = VariableType(rawValue: 1 << 5)
        static let typeConstant = VariableType(rawValue: 1 << 6)
    }

    private static let includeTemplate = """
        #include <metal_stdlib>

        using namespace metal;
        """

    private static let variableTemplate = "[qualifier] [type] [name] [mapping]"
    private static let structTemplate = """
        typedef struct {
        [variable]
        } [typename];
        """
    private static let functionTemplate = "[decorator] [type] [name] ([parameters]) {[content]}"

    var type: ParserType
    var content: String
    var file: String

    var parser: shader_parser

    var uniforms: [String: ShaderVariable]
    var uniformsOrder: [String]
    var structs: [String: ShaderStruct]
    var functions: [String: ShaderFunction]
    var functionOrder: [String]

    var constantBufferSize: Int

    init(type: ParserType, content: String, file: String) {
        self.type = type
        self.content = content
        self.file = file
        self.parser = shader_parser()

        withUnsafeMutablePointer(to: &parser) {
            shader_parser_init($0)
        }

        self.functions = [:]
        self.functionOrder = []
        self.uniforms = [:]
        self.uniformsOrder = []
        self.structs = [:]
        self.constantBufferSize = 0
    }

    deinit {
        withUnsafeMutablePointer(to: &parser) { parser in
            shader_parser_free(parser)
        }
    }

    func parse() throws {
        try withUnsafeMutablePointer(to: &parser) { parser in
            let success = shader_parse(parser, content.cString(using: .utf8), content.cString(using: .utf8))

            let parserWarnings = shader_parser_geterrors(parser)

            if let parserWarnings {
                OBSLog(.error, "Metal shader parser errors/warnings:\n%s\n", String(cString: parserWarnings))
            }

            if !success {
                OBSLog(.error, "Metal shader failed to parse: %s", self.file)
                throw ParserError.parseFail
            }
        }
    }

    func convertToString() -> String? {
        do {
            try parse()

            try analyzeUniforms()
            try analyzeParameters()
            try analyzeFunctions()

            let uniforms = try createUniforms()
            let structs = try createStructs()
            let functions = try createFunctions()

            return """
                \(OBSShaderParser.includeTemplate)

                \(uniforms ?? "")

                \(structs ?? "")

                \(functions ?? "")
                """
        } catch {
            OBSLog(.error, "Error while transpiling shader \(file) to a Metal Shader:\n\(error)")
            return nil
        }
    }
}

// MARK: - Analyzers
extension OBSShaderParser {
    private func analyzeUniforms() throws {
        for i in 0..<parser.params.num {
            let uniform: UnsafeMutablePointer<shader_var>? = parser.params.array.advanced(by: i)
            let name: UnsafeMutablePointer<CChar>? = uniform?.pointee.name
            let uniformType: UnsafeMutablePointer<CChar>? = uniform?.pointee.type
            let mapping: UnsafeMutablePointer<CChar>? = uniform?.pointee.mapping

            guard let uniform, let name, let uniformType else {
                throw ParserError.parseFail
            }

            let mappingString: String

            if let mapping {
                mappingString = String(cString: mapping)
            } else {
                mappingString = ""
            }

            var data = ShaderVariable(
                name: String(cString: name),
                type: String(cString: uniformType),
                mapping: mappingString,
                storageType: .typeUniform,
                inputFor: [],
                outputFrom: [],
                isStage: false,
                attributeId: 0,
                isConstant: (uniform.pointee.var_type == SHADER_VAR_CONST),
                variable: uniform
            )

            if type == .fragment {
                if data.type.hasPrefix("texture") {
                    data.storageType.remove(.typeUniform)
                    data.storageType.insert(.typeTexture)
                }
            }
            uniformsOrder.append(data.name)
            uniforms[data.name] = data
        }
    }

    private func analyzeParameters() throws {
        for i in 0..<parser.structs.num {
            let shaderStruct: UnsafeMutablePointer<shader_struct>? = parser.structs.array.advanced(by: i)
            let name: UnsafeMutablePointer<CChar>? = shaderStruct?.pointee.name

            guard let shaderStruct, let name else {
                throw ParserError.parseFail
            }

            var parameters: [ShaderVariable] = []

            for j in 0..<shaderStruct.pointee.vars.num {
                let variablePointer: UnsafeMutablePointer<shader_var>? = shaderStruct.pointee.vars.array.advanced(by: j)
                let variableName: UnsafeMutablePointer<CChar>? = variablePointer?.pointee.name
                let variableType: UnsafeMutablePointer<CChar>? = variablePointer?.pointee.type
                let variableMapping: UnsafeMutablePointer<CChar>? = variablePointer?.pointee.mapping

                guard let variablePointer, let variableName, let variableType else {
                    throw ParserError.parseFail
                }

                let mapping: String? = if let variableMapping { String(cString: variableMapping) } else { nil }

                let variable = ShaderVariable(
                    name: String(cString: variableName),
                    type: String(cString: variableType),
                    mapping: mapping,
                    storageType: .typeStructMember,
                    inputFor: [],
                    outputFrom: [],
                    isStage: false,
                    attributeId: nil,
                    isConstant: false,
                    variable: variablePointer
                )

                parameters.append(variable)
            }

            let data = ShaderStruct(
                name: String(cString: name),
                storageType: [],
                parameters: parameters,
                structVar: shaderStruct)

            structs[data.name] = data
        }

        for i in 0..<parser.funcs.num {
            let function: UnsafeMutablePointer<shader_func>? = parser.funcs.array.advanced(by: i)
            let functionName: UnsafeMutablePointer<CChar>? = function?.pointee.name
            let returnType: UnsafeMutablePointer<CChar>? = function?.pointee.return_type

            guard let function, let functionName, let returnType else {
                throw ParserError.parseFail
            }

            var functionData = ShaderFunction(
                name: String(cString: functionName),
                returnType: String(cString: returnType),
                types: [:],
                requiresUniforms: false,
                textures: [],
                samplers: [],
                function: function,
                parameters: []
            )

            for j in 0..<function.pointee.params.num {
                let parameter: UnsafeMutablePointer<shader_var>? = function.pointee.params.array.advanced(by: j)
                let parameterName: UnsafeMutablePointer<CChar>? = parameter?.pointee.name
                let parameterType: UnsafeMutablePointer<CChar>? = parameter?.pointee.type
                let parameterMapping: UnsafeMutablePointer<CChar>? = parameter?.pointee.mapping

                guard let parameter, let parameterName, let parameterType else {
                    throw ParserError.parseFail
                }

                let mapping: String?

                if let parameterMapping {
                    mapping = String(cString: parameterMapping)
                } else {
                    mapping = nil
                }

                var parameterData = ShaderVariable(
                    name: String(cString: parameterName),
                    type: String(cString: parameterType),
                    mapping: mapping,
                    storageType: .typeInput,
                    inputFor: [functionData.name],
                    outputFrom: [],
                    isStage: false,
                    attributeId: nil,
                    isConstant: (parameter.pointee.var_type == SHADER_VAR_CONST),
                    variable: parameter
                )

                if parameterData.type == functionData.returnType {
                    parameterData.outputFrom.insert(functionData.name)
                }

                if !functionData.types.keys.contains(parameterData.name) {
                    functionData.types[parameterData.name] = parameterData.type
                }

                for var shaderStruct in structs.values {
                    if shaderStruct.name == parameterData.type {
                        shaderStruct.storageType.insert(.typeInput)
                        parameterData.storageType.insert(.typeStruct)

                        if shaderStruct.name == functionData.returnType {
                            shaderStruct.storageType.insert(.typeOutput)
                            parameterData.storageType.insert(.typeOutput)
                            parameterData.type.append("_In")
                            functionData.returnType.append("_Out")
                        }

                        structs.updateValue(shaderStruct, forKey: shaderStruct.name)
                    }
                }

                functionData.parameters.append(parameterData)
            }

            if var shaderStruct = structs[functionData.returnType] {
                shaderStruct.storageType.insert(.typeOutput)
                structs.updateValue(shaderStruct, forKey: shaderStruct.name)
            }

            functions[functionData.name] = functionData
        }
    }

    private func analyzeFunctions() throws {
        for i in 0..<parser.funcs.num {
            let function: UnsafeMutablePointer<shader_func>? = parser.funcs.array.advanced(by: i)
            let token = function?.pointee.start

            guard var function, var token else {
                throw ParserError.parseFail
            }

            let functionName = String(cString: function.pointee.name)
            let functionData = functions[functionName]

            guard var functionData else {
                throw ParserError.parseFail
            }

            try analyzeFunction(function: &function, functionData: &functionData, token: &token, end: "}")

            functionData.textures = functionData.textures.unique()
            functionData.samplers = functionData.samplers.unique()

            functions.updateValue(functionData, forKey: functionName)
            functionOrder.append(functionName)
        }
    }

    private func analyzeFunction(
        function: inout UnsafeMutablePointer<shader_func>, functionData: inout ShaderFunction,
        token: inout UnsafeMutablePointer<cf_token>, end: String
    ) throws {

        let uniformNames = (uniforms.filter { !$0.value.storageType.contains(.typeTexture) }).keys

        while token.pointee.type != CFTOKEN_NONE {
            token = token.successor()

            if token.pointee.str.isEqualTo(end) {
                break
            }

            let stringToken = token.pointee.str.getString()

            if token.pointee.type == CFTOKEN_NAME {
                if uniformNames.contains(stringToken) && functionData.requiresUniforms == false {
                    functionData.requiresUniforms = true
                }

                if functions.keys.contains(stringToken), let function = functions[stringToken] {
                    if function.requiresUniforms && functionData.requiresUniforms == false {
                        functionData.requiresUniforms = true
                    }

                    functionData.textures.append(contentsOf: function.textures)
                    functionData.samplers.append(contentsOf: function.samplers)
                }

                if type == .fragment {
                    for uniform in uniforms.values {
                        if stringToken == uniform.name && uniform.storageType.contains(.typeTexture) {
                            functionData.textures.append(stringToken)
                        }
                    }

                    for i in 0..<parser.samplers.num {
                        let sampler: UnsafeMutablePointer<shader_sampler>? = parser.samplers.array.advanced(by: i)
                        let samplerName: UnsafeMutablePointer<CChar>? = sampler?.pointee.name

                        if let samplerName {
                            let name = String(cString: samplerName)

                            if stringToken == name {
                                functionData.samplers.append(stringToken)
                            }
                        }
                    }
                }
            } else if token.pointee.type == CFTOKEN_OTHER {
                if token.pointee.str.isEqualTo("{") {
                    try analyzeFunction(function: &function, functionData: &functionData, token: &token, end: "}")
                } else if token.pointee.str.isEqualTo("(") {
                    try analyzeFunction(function: &function, functionData: &functionData, token: &token, end: ")")
                }
            }
        }
    }
}

// MARK: - String Composers
extension OBSShaderParser {
    private func createUniforms() throws -> String? {
        var output: [String] = []

        for uniformName in uniformsOrder {
            if var uniform = uniforms[uniformName] {
                uniform.isStage = false
                uniform.attributeId = nil

                if !uniform.storageType.contains(.typeTexture) {
                    let variableString = try convertVariable(variable: uniform)
                    output.append("\(variableString);")
                }
            }
        }

        if output.count > 0 {
            let replacements = [
                ("[variable]", output.joined(separator: "\n")),
                ("[typename]", "UniformData"),
            ]

            let uniformString = replacements.reduce(into: OBSShaderParser.structTemplate) { string, replacement in
                string = string.replacingOccurrences(of: replacement.0, with: replacement.1)
            }

            return uniformString
        } else {
            return nil
        }
    }

    private func createStructs() throws -> String? {
        var output: [String] = []

        for var shaderStruct in structs.values {
            if shaderStruct.storageType.isSuperset(of: [.typeInput, .typeOutput]) {
                for suffix in ["_In", "_Out"] {
                    var variables: [String] = []

                    for (structVariableId, var structVariable) in shaderStruct.parameters.enumerated() {
                        let variableString: String
                        switch suffix {
                        case "_In":
                            structVariable.storageType.formUnion([.typeInput])
                            structVariable.attributeId = structVariableId
                            variableString = try convertVariable(variable: structVariable)
                            structVariable.storageType.remove(.typeInput)
                        case "_Out":
                            structVariable.storageType.formUnion([.typeOutput])
                            variableString = try convertVariable(variable: structVariable)
                            structVariable.storageType.remove(.typeOutput)
                        default:
                            throw ParserError.parseFail
                        }

                        variables.append("\(variableString);")
                        shaderStruct.parameters[structVariableId] = structVariable
                    }

                    let replacements = [
                        ("[variable]", variables.joined(separator: "\n")),
                        ("[typename]", "\(shaderStruct.name)\(suffix)"),
                    ]

                    let result = replacements.reduce(into: OBSShaderParser.structTemplate) {
                        string, replacement in
                        string = string.replacingOccurrences(of: replacement.0, with: replacement.1)
                    }

                    output.append(result)
                }
            } else {
                var variables: [String] = []

                for (structVariableId, var structVariable) in shaderStruct.parameters.enumerated() {
                    if shaderStruct.storageType.contains(.typeInput) {
                        structVariable.storageType.insert(.typeInput)
                        structVariable.attributeId = structVariableId
                    } else if shaderStruct.storageType.contains(.typeOutput) {
                        structVariable.storageType.insert(.typeOutput)
                    }

                    let variableString = try convertVariable(variable: structVariable)

                    structVariable.storageType.subtract([.typeInput, .typeOutput])

                    variables.append("\(variableString);")
                    shaderStruct.parameters[structVariableId] = structVariable
                }

                let replacements = [
                    ("[variable]", variables.joined(separator: "\n")),
                    ("[typename]", shaderStruct.name),
                ]

                let result = replacements.reduce(into: OBSShaderParser.structTemplate) {
                    string, replacement in
                    string = string.replacingOccurrences(of: replacement.0, with: replacement.1)
                }

                output.append(result)
            }
        }

        if output.count > 0 {
            return output.joined(separator: "\n\n")
        } else {
            return nil
        }
    }

    private func createFunctions() throws -> String? {
        var output: [String] = []

        for functionName in functionOrder {
            guard let function = functions[functionName], var token = function.function.pointee.start else {
                throw ParserError.parseFail
            }

            var stageConsumed = false
            let isMain = functionName == "main"

            var parameters: [String] = []
            for var parameter in function.parameters {
                if isMain && !stageConsumed {
                    parameter.isStage = true
                    stageConsumed = true
                }

                try parameters.append(convertVariable(variable: parameter))
            }

            if (uniforms.values.filter { !$0.storageType.contains(.typeTexture) }).count > 0 {
                if isMain {
                    parameters.append("constant UniformData &uniforms [[buffer(30)]]")
                } else if function.requiresUniforms {
                    parameters.append("constant UniformData &uniforms")
                }
            }

            if type == .fragment {
                var textureId = 0

                for uniform in uniforms.values {
                    if uniform.storageType.contains(.typeTexture) {
                        if isMain {
                            let variableString = try convertVariable(variable: uniform)

                            parameters.append("\(variableString) [[texture(\(textureId))]]")
                            textureId += 1
                        } else if function.textures.contains(uniform.name) {
                            let variableString = try convertVariable(variable: uniform)
                            parameters.append(variableString)
                        }
                    }
                }

                var samplerId = 0
                for i in 0..<parser.samplers.num {
                    let samplerPointer: UnsafeMutablePointer<shader_sampler>? = parser.samplers.array.advanced(by: i)
                    let samplerName: UnsafeMutablePointer<CChar>? = samplerPointer?.pointee.name

                    if let samplerName {
                        let name = String(cString: samplerName)

                        if isMain {
                            let variableString = "sampler \(name) [[sampler(\(samplerId))]]"
                            parameters.append(variableString)
                            samplerId += 1
                        } else if function.samplers.contains(name) {
                            let variableString = "sampler \(name)"
                            parameters.append(variableString)
                        }
                    }
                }
            }

            let mappedType = try convertToMTLType(gsType: function.returnType)

            let functionContent: String
            var replacements: [(String, String)]

            if isMain {
                replacements = [
                    ("[name]", "_main"),
                    ("[parameters]", parameters.joined(separator: ", ")),
                ]

                switch type {
                case .vertex:
                    replacements.append(("[decorator]", "[[vertex]]"))
                case .fragment:
                    replacements.append(("[decorator]", "[[fragment]]"))
                }

                let temporaryContent = try createFunctionContent(token: &token, end: "}")

                if type == .fragment && isMain && mappedType == "float3" {
                    replacements.append(("[type]", "float4"))

                    let regex = try NSRegularExpression(pattern: "return (.+);")
                    functionContent = regex.stringByReplacingMatches(
                        in: temporaryContent, range: NSRange(location: 0, length: temporaryContent.count),
                        withTemplate: "return float4($1, 1);")
                } else {
                    functionContent = temporaryContent
                    replacements.append(("[type]", mappedType))
                }

                replacements.append(("[content]", functionContent))
            } else {
                functionContent = try createFunctionContent(token: &token, end: "}")

                replacements = [
                    ("[decorator]", ""),
                    ("[type]", mappedType),
                    ("[name]", function.name),
                    ("[parameters]", parameters.joined(separator: ", ")),
                    ("[content]", functionContent),
                ]
            }

            let result = replacements.reduce(into: OBSShaderParser.functionTemplate) {
                string, replacement in
                string = string.replacingOccurrences(of: replacement.0, with: replacement.1)
            }

            output.append(result)
        }

        if output.count > 0 {
            return output.joined(separator: "\n\n")
        } else {
            return nil
        }
    }
}

// MARK: - Composer Helper Functions
extension OBSShaderParser {
    private func convertVariable(variable: ShaderVariable) throws -> String {
        var mappings: [String] = []

        var metalMapping: String
        var indent = 0

        let metalType = try convertToMTLType(gsType: variable.type)

        if variable.storageType.contains(.typeUniform) {
            indent = 4
        } else if variable.storageType.isSuperset(of: [.typeInput, .typeStructMember]) {
            switch type {
            case .vertex:
                indent = 4

                if let attributeId = variable.attributeId {
                    mappings.append("attribute(\(attributeId))")
                }

            case .fragment:
                indent = 4

                let mappingPointer: UnsafeMutablePointer<CChar>? = variable.variable.pointee.mapping
                if let mappingPointer,
                    let mappedString = convertToMTLMapping(gsMapping: String(cString: mappingPointer))
                {
                    mappings.append(mappedString)
                }
            }
        } else if variable.storageType.isSuperset(of: [.typeOutput, .typeStructMember]) {
            indent = 4

            let mappingPointer: UnsafeMutablePointer<CChar>? = variable.variable.pointee.mapping
            if let mappingPointer, let mappedString = convertToMTLMapping(gsMapping: String(cString: mappingPointer)) {
                mappings.append(mappedString)
            }
        } else {
            indent = 0

            if variable.isStage {
                let mappingPointer: UnsafeMutablePointer<CChar>? = variable.variable.pointee.mapping
                if let mappingPointer,
                    let mappedString = convertToMTLMapping(gsMapping: String(cString: mappingPointer))
                {
                    mappings.append(mappedString)
                } else {
                    mappings.append("stage_in")
                }
            }
        }

        if mappings.count > 0 {
            metalMapping = " [[\(mappings.joined(separator: ", "))]]"
        } else {
            metalMapping = ""
        }

        let qualifier =
            if variable.storageType.contains(.typeConstant) {
                " constant"
            } else {
                ""
            }

        let result = "\(String(repeating: " ", count: indent))\(qualifier)\(metalType) \(variable.name)\(metalMapping)"

        return result
    }

    private func createFunctionContent(token: inout UnsafeMutablePointer<cf_token>, end: String) throws -> String {
        var content = ""

        outerloop: while token.pointee.type != CFTOKEN_NONE {
            token = token.successor()

            if token.pointee.str.isEqualTo(end) {
                break
            }

            let stringToken = token.pointee.str.getString()

            if token.pointee.type == CFTOKEN_NAME {
                let type = try convertToMTLType(gsType: stringToken)

                if stringToken == "obs_glsl_compile" {
                    content.append("false")
                    continue
                }

                if type != stringToken {
                    content.append(type)
                    continue
                }

                if let intrinsic = try createMetalInstrinsic(intrinsic: stringToken) {
                    content.append(intrinsic)
                    continue
                }

                if stringToken == "mul" {
                    try content.append(createMultiplication(token: &token))
                    continue
                } else if stringToken == "mad" {
                    try content.append(createMultiplyAdd(token: &token))
                    continue
                } else {
                    for uniform in uniforms.values {
                        if uniform.name == stringToken && uniform.storageType.contains(.typeTexture) {
                            try content.append(createSampler(token: &token))
                            continue outerloop
                        }
                    }
                }

                if uniforms.keys.contains(stringToken) {
                    let priorToken = token.predecessor()
                    let priorString = priorToken.pointee.str.getString()
                    if priorString != "." {
                        content.append("uniforms.\(stringToken)")
                        continue
                    }
                }

                for shaderStruct in structs.values {
                    if shaderStruct.name == stringToken {
                        if shaderStruct.storageType.isSuperset(of: [.typeInput, .typeOutput]) {
                            content.append("\(stringToken)_Out")
                            continue outerloop
                        }

                        break
                    }
                }

                if let comparison = try checkComparison(token: &token) {
                    content.append(comparison)
                    continue
                }

                content.append(stringToken)
            } else if token.pointee.type == CFTOKEN_OTHER {
                if token.pointee.str.isEqualTo("{") {
                    let blockContent = try createFunctionContent(token: &token, end: "}")
                    content.append("{\(blockContent)}")
                    continue
                } else if token.pointee.str.isEqualTo("(") {
                    let priorToken = token.predecessor()
                    let functionName = priorToken.pointee.str.getString()

                    var functionParameters: [String] = []

                    let parameters = try createFunctionContent(token: &token, end: ")")

                    if functionName == "int3" {
                        let intParameters = parameters.split(
                            separator: ",", maxSplits: 3, omittingEmptySubsequences: true)

                        switch intParameters.count {
                        case 3:
                            functionParameters.append(
                                "int(\(intParameters[0])), int(\(intParameters[1])), int(\(intParameters[2]))")
                        case 2:
                            functionParameters.append("int2(\(intParameters[0])), int(\(intParameters[1]))")
                        case 1:
                            functionParameters.append("\(intParameters)")
                        default:
                            throw ParserError.parseFail
                        }
                    } else {
                        functionParameters.append(parameters)
                    }

                    if let additionalParameters = createAdditionalFunctionParameters(functionName: functionName) {
                        functionParameters.append(additionalParameters)
                    }

                    content.append("(\(functionParameters.joined(separator: ", ")))")
                    continue
                }

                content.append(stringToken)
            } else {
                content.append(stringToken)
            }
        }

        return content
    }

    private func createMetalInstrinsic(intrinsic: String) throws -> String? {
        switch intrinsic {
        case "clip":
            throw ParserError.unsupportedType
        case "ddx":
            return "dfdx"
        case "ddy":
            return "dfdy"
        case "frac":
            return "fract"
        case "lerp":
            return "mix"
        default:
            return nil
        }
    }

    private func createMultiplication(token: inout UnsafeMutablePointer<cf_token>) throws -> String {
        var cfp = parser.cfp
        cfp.cur_token = token

        guard cfp.advanceToken() else {
            throw ParserError.missingNextToken
        }

        guard cfp.tokenIsEqualTo("(") else {
            throw ParserError.unexpectedToken
        }

        guard cfp.hasNextToken() else {
            throw ParserError.missingNextToken
        }

        let first = try createFunctionContent(token: &cfp.cur_token, end: ",")

        guard cfp.advanceToken() else {
            throw ParserError.missingNextToken
        }

        cfp.cur_token = cfp.cur_token.predecessor()

        let second = try createFunctionContent(token: &cfp.cur_token, end: ")")

        token = cfp.cur_token

        return "(\(first)) * (\(second))"
    }

    private func createMultiplyAdd(token: inout UnsafeMutablePointer<cf_token>) throws -> String {
        var cfp = parser.cfp
        cfp.cur_token = token

        guard cfp.advanceToken() else {
            throw ParserError.missingNextToken
        }

        guard cfp.tokenIsEqualTo("(") else {
            throw ParserError.unexpectedToken
        }

        guard cfp.hasNextToken() else {
            throw ParserError.missingNextToken
        }

        let first = try createFunctionContent(token: &cfp.cur_token, end: ",")

        guard cfp.hasNextToken() else {
            throw ParserError.missingNextToken
        }

        let second = try createFunctionContent(token: &cfp.cur_token, end: ",")

        guard cfp.hasNextToken() else {
            throw ParserError.missingNextToken
        }

        let third = try createFunctionContent(token: &cfp.cur_token, end: ")")

        token = cfp.cur_token

        return "((\(first)) * (\(second))) + (\(third))"
    }

    private func createSampler(token: inout UnsafeMutablePointer<cf_token>) throws -> String {
        var cfp = parser.cfp
        cfp.cur_token = token

        let stringToken = token.pointee.str.getString()

        guard cfp.advanceToken() else {
            throw ParserError.missingNextToken
        }

        guard cfp.tokenIsEqualTo(".") else {
            throw ParserError.unexpectedToken
        }

        guard cfp.advanceToken() else {
            throw ParserError.missingNextToken
        }

        guard cfp.cur_token.pointee.type == CFTOKEN_NAME else {
            throw ParserError.unexpectedToken
        }

        let textureCall: String

        if cfp.tokenIsEqualTo("Sample") {
            textureCall = try createTextureCall(token: &cfp.cur_token, callType: .sample)
        } else if cfp.tokenIsEqualTo("SampleBias") {
            textureCall = try createTextureCall(token: &cfp.cur_token, callType: .sampleBias)
        } else if cfp.tokenIsEqualTo("SampleGrad") {
            textureCall = try createTextureCall(token: &cfp.cur_token, callType: .sampleGrad)
        } else if cfp.tokenIsEqualTo("SampleLevel") {
            textureCall = try createTextureCall(token: &cfp.cur_token, callType: .sampleLevel)
        } else if cfp.tokenIsEqualTo("Load") {
            textureCall = try createTextureCall(token: &cfp.cur_token, callType: .load)
        } else {
            throw ParserError.missingNextToken
        }

        token = cfp.cur_token
        return "\(stringToken).\(textureCall)"
    }

    private func createTextureCall(token: inout UnsafeMutablePointer<cf_token>, callType: SampleType) throws -> String {
        var cfp = parser.cfp
        cfp.cur_token = token

        guard cfp.advanceToken() else {
            throw ParserError.missingNextToken
        }

        guard cfp.tokenIsEqualTo("(") else {
            throw ParserError.unexpectedToken
        }

        guard cfp.hasNextToken() else {
            throw ParserError.missingNextToken
        }

        switch callType {
        case .sample:
            let first = try createFunctionContent(token: &cfp.cur_token, end: ",")

            guard cfp.hasNextToken() else {
                throw ParserError.missingNextToken
            }

            let second = try createFunctionContent(token: &cfp.cur_token, end: ")")

            token = cfp.cur_token
            return "sample(\(first), \(second))"
        case .sampleBias:
            let first = try createFunctionContent(token: &cfp.cur_token, end: ",")

            guard cfp.hasNextToken() else {
                throw ParserError.missingNextToken
            }

            let second = try createFunctionContent(token: &cfp.cur_token, end: ",")

            guard cfp.hasNextToken() else {
                throw ParserError.missingNextToken
            }

            let third = try createFunctionContent(token: &cfp.cur_token, end: ")")

            token = cfp.cur_token
            return "sample(\(first), \(second), bias(\(third)))"
        case .sampleGrad:
            let first = try createFunctionContent(token: &cfp.cur_token, end: ",")

            guard cfp.hasNextToken() else {
                throw ParserError.missingNextToken
            }

            let second = try createFunctionContent(token: &cfp.cur_token, end: ",")

            guard cfp.hasNextToken() else {
                throw ParserError.missingNextToken
            }

            let third = try createFunctionContent(token: &cfp.cur_token, end: ",")

            guard cfp.hasNextToken() else {
                throw ParserError.missingNextToken
            }

            let fourth = try createFunctionContent(token: &cfp.cur_token, end: ")")

            token = cfp.cur_token
            return "sample(\(first), \(second), gradient2d(\(third),\(fourth)))"
        case .sampleLevel:
            let first = try createFunctionContent(token: &cfp.cur_token, end: ",")

            guard cfp.hasNextToken() else {
                throw ParserError.missingNextToken
            }

            let second = try createFunctionContent(token: &cfp.cur_token, end: ",")

            guard cfp.hasNextToken() else {
                throw ParserError.missingNextToken
            }

            let third = try createFunctionContent(token: &cfp.cur_token, end: ")")

            token = cfp.cur_token
            return "sample(\(first), \(second), level(\(third)))"
        case .load:
            let first = try createFunctionContent(token: &cfp.cur_token, end: ")")

            let loadCall: String

            if first.hasPrefix("int3(") {
                let loadParameters = first[
                    first.index(first.startIndex, offsetBy: 5)..<first.index(first.endIndex, offsetBy: -1)
                ].split(separator: ",", maxSplits: 3, omittingEmptySubsequences: true)

                switch loadParameters.count {
                case 3:
                    loadCall = "read(uint2(\(loadParameters[0]), \(loadParameters[1])), uint(\(loadParameters[2])))"
                case 2:
                    loadCall = "read(uint2(\(loadParameters[0])), uint(\(loadParameters[1])))"
                case 1:
                    loadCall = "read(uint2(\(loadParameters[0]).xy), 0)"
                default:
                    throw ParserError.parseFail
                }
            } else {
                loadCall = "read(uint2(\(first).xy), 0)"
            }

            token = cfp.cur_token
            return loadCall
        }
    }

    private func checkComparison(token: inout UnsafeMutablePointer<cf_token>) throws -> String? {
        var isComparator = false

        let nextToken = token.successor()

        if nextToken.pointee.type == CFTOKEN_OTHER {
            let comparators = ["==", "!=", "<", "<=", ">=", ">"]

            for comparator in comparators {
                if nextToken.pointee.str.isEqualTo(comparator) {
                    isComparator = true
                    break
                }
            }
        }

        if isComparator {
            var cfp = parser.cfp
            cfp.cur_token = token

            let first = cfp.cur_token.pointee.str.getString()

            guard cfp.advanceToken() else {
                throw ParserError.missingNextToken
            }

            let comparator = cfp.cur_token.pointee.str.getString()

            guard cfp.advanceToken() else {
                throw ParserError.missingNextToken
            }

            let second = cfp.cur_token.pointee.str.getString()

            return "all(\(first) \(comparator) \(second)"
        } else {
            return nil
        }
    }

    private func createAdditionalFunctionParameters(functionName: String) -> String? {
        var output: [String] = []

        for function in functions.values {
            if function.name != functionName {
                continue
            }

            if function.requiresUniforms {
                output.append("uniforms")
            }

            for texture in function.textures {
                for uniform in uniforms.values {
                    if uniform.name == texture && uniform.storageType.contains(.typeTexture) {
                        output.append(texture)
                    }
                }
            }

            for sampler in function.samplers {
                for i in 0..<parser.samplers.num {
                    let samplerPointer: UnsafeMutablePointer<shader_sampler>? = parser.samplers.array.advanced(by: i)

                    if let samplerPointer {
                        if sampler == String(cString: samplerPointer.pointee.name) {
                            output.append(sampler)
                        }
                    }
                }
            }
        }

        if output.count > 0 {
            return output.joined(separator: ", ")
        }

        return nil
    }
}

// MARK: - Shader Data Calculation Helpers
extension OBSShaderParser {
    //    func buildShaderParameterInfo() -> [OBSShaderParameterInfo] {
    //        var parameters: [OBSShaderParameterInfo] = []
    //
    //        var textureCounter = 0
    //
    //        for uniform in uniforms.values {
    //            let uniformType = String(cString: uniform.variable.pointee.type)
    //
    //            if uniform.variable.pointee.var_type != SHADER_VAR_UNIFORM || uniformType == "sampler" {
    //                continue
    //            }
    //
    //            let type = get_shader_param_type(uniform.variable.pointee.type)
    //            let textureId = if type == GS_SHADER_PARAM_TEXTURE { textureCounter } else { 0 }
    //
    //            let info = OBSShaderParameterInfo(
    //                name: uniform.name,
    //                type: type,
    //                arrayCount: Int(uniform.variable.pointee.array_count),
    //                textureId: textureId,
    //                samplerStateId: 0,
    //                position: 0,
    //                currentValues: nil,
    //                defaultValues: Array(
    //                    UnsafeMutableBufferPointer(
    //                        start: uniform.variable.pointee.default_val.array,
    //                        count: uniform.variable.pointee.default_val.num)),
    //                valueSize: uniform.variable.pointee.default_val.num,
    //                isChanged: false
    //            )
    //
    //            if info.type == GS_SHADER_PARAM_TEXTURE {
    //                textureCounter += 1
    //            }
    //
    //            parameters.append(info)
    //        }
    //
    //        return parameters
    //    }
}

// MARK: - GS to Metal Type Converters
extension OBSShaderParser {
    private func convertToMTLMapping(gsMapping: String) -> String? {
        switch gsMapping {
        case "POSITION":
            return "position"
        case "COLOR":
            switch type {
            //            case .fragment:
            //                return "color(0)"
            default:
                return nil
            }
        case "VERTEXID":
            return "vertex_id"
        default:
            return nil
        }
    }

    private func convertToMTLType(gsType: String) throws -> String {
        switch gsType {
        case "texture2d":
            return "texture2d<float>"
        case "texture3d":
            return "texture3d<float>"
        case "texture_cube":
            return "texturecube<float>"
        case "texture_rect":
            throw ParserError.unsupportedType
        case "half2":
            return "float2"
        case "half3":
            return "float3"
        case "half4":
            return "float4"
        case "half":
            return "float"
        case "min16float2":
            return "half2"
        case "min16float3":
            return "half3"
        case "min16float4":
            return "half4"
        case "min16float":
            return "half"
        case "min10float":
            throw ParserError.unsupportedType
        case "double":
            throw ParserError.unsupportedType
        case "min16int2":
            return "short2"
        case "min16int3":
            return "short3"
        case "min16int4":
            return "short4"
        case "min16int":
            return "short"
        case "min16uint2":
            return "ushort2"
        case "min16uint3":
            return "ushort3"
        case "min16uint4":
            return "ushort4"
        case "min16uint":
            return "ushort"
        case "min13int":
            throw ParserError.unsupportedType
        default:
            return gsType
        }
    }
}

extension OBSShaderParser {
    func buildMetadata() -> MetalShader.ShaderData {
        var uniformInfo: [MetalShader.ShaderUniform] = []

        var textureSlot = 0
        var uniformBufferSize = 0

        for uniformName in uniformsOrder {
            guard let uniform = uniforms[uniformName] else {
                preconditionFailure("No uniform data found for '\(uniformName)'")
            }

            let gsType = get_shader_param_type(uniform.variable.pointee.type)
            let isTexture = uniform.storageType.contains(.typeTexture)
            let byteSize = gsType.getSize()

            if (uniformBufferSize & 15) != 0 {
                let alignment = (uniformBufferSize + 15) & ~15

                if byteSize + uniformBufferSize > alignment {
                    uniformBufferSize = alignment
                }
            }

            let info = MetalShader.ShaderUniform(
                name: uniform.name,
                gsType: gsType,
                textureSlot: (isTexture ? textureSlot : 0),
                samplerState: 0,
                byteOffset: uniformBufferSize
            )

            info.defaultValues = Array(
                UnsafeMutableBufferPointer(
                    start: uniform.variable.pointee.default_val.array,
                    count: uniform.variable.pointee.default_val.num))
            info.defaultValues = info.currentValues

            uniformBufferSize += byteSize

            if isTexture {
                textureSlot += 1
            }

            uniformInfo.append(info)
        }

        guard let mainFunction = functions["main"] else {
            preconditionFailure("No main function found in OBS shader")
        }

        let parameterMapper = { (mapping: String) -> BufferType? in
            switch mapping {
            case "POSITION":
                .vertex
            case "NORMAL":
                .normal
            case "TANGENT":
                .tangent
            case "COLOR":
                .color
            case _ where mapping.hasPrefix("TEXCOORD"):
                .texcoord
            default:
                .none
            }
        }

        let descriptorMapper = { (parameter: ShaderVariable) -> (MTLVertexFormat, Int)? in
            let mapping = parameter.mapping
            let type = parameter.type

            guard let mapping else {
                return nil
            }

            switch mapping {
            case "COLOR":
                return (.float4, MemoryLayout<vec4>.size)
            case "POSITION", "NORMAL", "TANGENT":
                return (.float4, MemoryLayout<vec4>.size)
            case _ where mapping.hasPrefix("TEXCOORD"):
                guard let numCoordinates = type[type.index(type.startIndex, offsetBy: 5)].wholeNumberValue else {
                    preconditionFailure("Unsupported type \(type) for texture parameter")
                }

                let format: MTLVertexFormat =
                    switch numCoordinates {
                    case 0: .float
                    case 2: .float2
                    case 3: .float3
                    case 4: .float4
                    default:
                        preconditionFailure("Unsupported type \(type) for texture parameter")
                    }

                return (format, MemoryLayout<Float32>.size * numCoordinates)
            case "VERTEXID":
                return nil
            default:
                preconditionFailure("Unsupported mapping \(mapping)")
            }
        }

        switch type {
        case .vertex:
            var bufferOrder: [BufferType] = []
            var descriptorData: [(MTLVertexFormat, Int)?] = []
            let descriptor = MTLVertexDescriptor()

            for parameter in mainFunction.parameters {
                if parameter.storageType.contains(.typeStruct) {
                    guard let shaderStruct = structs[parameter.type.replacingOccurrences(of: "_In", with: "")] else {
                        preconditionFailure(
                            "No struct with name \(parameter.name) found, but specified on main function")
                    }

                    for shaderParameter in shaderStruct.parameters {
                        if let mapping = shaderParameter.mapping, let mapping = parameterMapper(mapping) {
                            bufferOrder.append(mapping)
                        }

                        if let description = descriptorMapper(shaderParameter) {
                            descriptorData.append(description)
                        }
                    }
                } else {
                    if let mapping = parameter.mapping, let mapping = parameterMapper(mapping) {
                        bufferOrder.append(mapping)
                    }

                    if let description = descriptorMapper(parameter) {
                        descriptorData.append(description)
                    }
                }
            }

            let textureUnitCount = bufferOrder.filter({ $0 == .texcoord }).count

            for (attributeId, description) in descriptorData.filter({ $0 != nil }).enumerated() {
                descriptor.attributes[attributeId].bufferIndex = attributeId
                descriptor.attributes[attributeId].format = description!.0
                descriptor.layouts[attributeId].stride = description!.1
            }

            return MetalShader.ShaderData(
                uniforms: uniformInfo,
                bufferOrder: bufferOrder,
                vertexDescriptor: descriptor,
                samplerDescriptor: nil,
                bufferSize: uniformBufferSize,
                textureCount: textureUnitCount
            )
        case .fragment:
            var samplers = [MTLSamplerDescriptor]()

            for i in 0..<parser.samplers.num {
                let sampler: UnsafeMutablePointer<shader_sampler>? = parser.samplers.array.advanced(by: i)

                if let sampler {
                    var sampler_info = gs_sampler_info()
                    shader_sampler_convert(sampler, &sampler_info)

                    let borderColor: MTLSamplerBorderColor =
                        switch sampler_info.border_color {
                        case 0x00_00_00_FF:
                            .transparentBlack
                        case 0xFF_FF_FF_FF:
                            .opaqueWhite
                        default:
                            .opaqueBlack
                        }

                    let descriptor = MTLSamplerDescriptor()
                    descriptor.sAddressMode = sampler_info.address_u.toMTLMode()
                    descriptor.tAddressMode = sampler_info.address_v.toMTLMode()
                    descriptor.rAddressMode = sampler_info.address_w.toMTLMode()
                    descriptor.minFilter = sampler_info.filter.toMTLFilter()
                    descriptor.magFilter = sampler_info.filter.toMTLFilter()
                    descriptor.mipFilter = sampler_info.filter.toMTLMipFilter()
                    descriptor.borderColor = borderColor
                    descriptor.maxAnisotropy = Int(sampler_info.max_anisotropy)

                    samplers.append(descriptor)
                }
            }

            return MetalShader.ShaderData(
                uniforms: uniformInfo,
                bufferOrder: [],
                vertexDescriptor: nil,
                samplerDescriptor: samplers,
                bufferSize: uniformBufferSize,
                textureCount: 0
            )
        }
    }
}
