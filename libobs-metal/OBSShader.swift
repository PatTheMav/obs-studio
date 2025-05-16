/******************************************************************************
 Copyright (C) 2024 by Patrick Heyer <PatTheMav@users.noreply.github.com>

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 2 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.
 ******************************************************************************/

import Foundation
import Metal

private enum SampleVariant {
    case load
    case sample
    case sampleBias
    case sampleGrad
    case sampleLevel
}

private enum ParserError: Error, CustomStringConvertible {
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

private struct VariableType: OptionSet {
    var rawValue: UInt

    static let typeUniform = VariableType(rawValue: 1 << 0)
    static let typeStruct = VariableType(rawValue: 1 << 1)
    static let typeStructMember = VariableType(rawValue: 1 << 2)
    static let typeInput = VariableType(rawValue: 1 << 3)
    static let typeOutput = VariableType(rawValue: 1 << 4)
    static let typeTexture = VariableType(rawValue: 1 << 5)
    static let typeConstant = VariableType(rawValue: 1 << 6)

}

private struct OBSShaderFunction {
    let name: String

    var returnType: String
    var typeMap: [String: String]

    var requiresUniformBuffers: Bool
    var textures: [String]
    var samplers: [String]

    var arguments: [OBSShaderVariable]

    let gsFunction: UnsafeMutablePointer<shader_func>
}

private struct OBSShaderVariable {
    let name: String

    var type: String
    var mapping: String?
    var storageType: VariableType

    var requiredBy: Set<String>
    var returnedBy: Set<String>

    var isStage: Bool
    var attributeId: Int?
    var isConstant: Bool

    let gsVariable: UnsafeMutablePointer<shader_var>
}

private struct OBSShaderStruct {
    let name: String

    var storageType: VariableType
    var members: [OBSShaderVariable]

    let gsVariable: UnsafeMutablePointer<shader_struct>
}

private struct MSLTemplates {
    static let header = """
        #include <metal_stdlib>

        using namespace metal;
        """

    static let variable = "[qualifier] [type] [name] [mapping]"

    static let shaderStruct = """
        typedef struct {
        [variable]
        } [typename];
        """

    static let function = "[decorator] [type] [name]([parameters]) {[content]}"
}

class OBSShader {
    private let type: MTLFunctionType
    private let content: String
    private let fileLocation: String

    private var parser: shader_parser
    private var parsed: Bool

    private var uniformsOrder = [String]()
    private var uniforms = [String: OBSShaderVariable]()
    private var structs = [String: OBSShaderStruct]()
    private var functionsOrder = [String]()
    private var functions = [String: OBSShaderFunction]()

    lazy var metaData: MetalShader.ShaderData? = buildMetadata()

    init?(type: MTLFunctionType, content: String, fileLocation: String) {
        guard type == .vertex || type == .fragment else {
            preconditionFailure("OBSShader: Unsupported shader type \(type)")
        }

        self.type = type
        self.content = content
        self.fileLocation = fileLocation

        self.parsed = false

        self.parser = shader_parser()

        withUnsafeMutablePointer(to: &parser) {
            shader_parser_init($0)

            let result = shader_parse($0, content.cString(using: .utf8), content.cString(using: .utf8))
            let warnings = shader_parser_geterrors($0)

            if let warnings {
                OBSLog(
                    .error, "OBSShader: Warnings/errors occurred while parsing shader string:\n%s\n",
                    String(cString: warnings))
            }

            if !result {
                OBSLog(.error, "OBSShader: Shader failed to parse: \(fileLocation)")
            } else {
                self.parsed = true
            }
        }
    }

    func transpiled() -> String? {
        do {
            try analyzeUniforms()
            try analyzeParameters()
            try analyzeFunctions()

            let uniforms = try transpileUniforms()
            let structs = try transpileStructs()
            let functions = try transpileFunctions()

            return [MSLTemplates.header, uniforms, structs, functions].joined(separator: "\n\n")
        } catch {
            OBSLog(.error, "OBSShader: Error while transpiling shader \(fileLocation) to MSL:\n\(error)")
            return nil
        }
    }

    private func buildMetadata() -> MetalShader.ShaderData? {
        var uniformInfo = [MetalShader.ShaderUniform]()

        var textureSlot = 0
        var uniformBufferSize = 0

        for uniformName in uniformsOrder {
            guard let uniform = uniforms[uniformName] else {
                preconditionFailure("No uniform data found for '\(uniformName)'")
            }

            let gsType = get_shader_param_type(uniform.gsVariable.pointee.type)
            let isTexture = uniform.storageType.contains(.typeTexture)
            let byteSize =
                switch isTexture {
                case true: 0
                case false: gsType.getSize()
                }

            if (uniformBufferSize & 15) != 0 {
                let alignment = (uniformBufferSize + 15) & ~15

                if byteSize + uniformBufferSize > alignment {
                    uniformBufferSize = alignment
                }
            }

            let shaderUniform = MetalShader.ShaderUniform(
                name: uniform.name,
                gsType: gsType,
                textureSlot: (isTexture ? textureSlot : 0),
                samplerState: nil,
                byteOffset: uniformBufferSize
            )

            shaderUniform.defaultValues = Array(
                UnsafeMutableBufferPointer(
                    start: uniform.gsVariable.pointee.default_val.array,
                    count: uniform.gsVariable.pointee.default_val.num)
            )

            shaderUniform.currentValues = shaderUniform.defaultValues

            uniformBufferSize += byteSize

            if isTexture {
                textureSlot += 1
            }

            uniformInfo.append(shaderUniform)
        }

        guard let mainFunction = functions["main"] else {
            assertionFailure("No main function in OBS shader")
            return nil
        }

        let parameterMapper = { (mapping: String) -> MetalBuffer.BufferDataType? in
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

        let descriptorMapper = { (parameter: OBSShaderVariable) -> (MTLVertexFormat, Int)? in
            guard let mapping = parameter.mapping else {
                return nil
            }

            let type = parameter.type

            switch mapping {
            case "COLOR":
                return (.float4, MemoryLayout<vec4>.size)
            case "POSITION", "NORMAL", "TANGENT":
                return (.float4, MemoryLayout<vec4>.size)
            case _ where mapping.hasPrefix("TEXCOORD"):
                guard let numCoordinates = type[type.index(type.startIndex, offsetBy: 5)].wholeNumberValue else {
                    preconditionFailure("OBSShader: Unsupported type \(type) for texture parameter")
                }

                let format: MTLVertexFormat =
                    switch numCoordinates {
                    case 0: .float
                    case 2: .float2
                    case 3: .float3
                    case 4: .float4
                    default:
                        preconditionFailure("OBSShader: Unsupported amount of texture coordinates '\(numCoordinates)'")
                    }

                return (format, MemoryLayout<Float32>.size * numCoordinates)
            case "VERTEXID":
                return nil
            default:
                preconditionFailure("OBSShader: Unsupported mapping \(mapping)")
            }
        }

        switch type {
        case .vertex:
            var bufferOrder = [MetalBuffer.BufferDataType]()
            var descriptorData = [(MTLVertexFormat, Int)?]()
            let descriptor = MTLVertexDescriptor()

            for argument in mainFunction.arguments {
                if argument.storageType.contains(.typeStruct) {
                    let actualStructType = argument.type.replacingOccurrences(of: "_In", with: "")

                    guard let shaderStruct = structs[actualStructType] else {
                        preconditionFailure(
                            "OBSShader: No struct of type \(actualStructType) specified in shader, but used as argument type for main function"
                        )
                    }

                    for shaderParameter in shaderStruct.members {
                        if let mapping = shaderParameter.mapping, let mapping = parameterMapper(mapping) {
                            bufferOrder.append(mapping)
                        }

                        if let description = descriptorMapper(shaderParameter) {
                            descriptorData.append(description)
                        }
                    }
                } else {
                    if let mapping = argument.mapping, let mapping = parameterMapper(mapping) {
                        bufferOrder.append(mapping)
                    }

                    if let description = descriptorMapper(argument) {
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
                samplerDescriptors: nil,
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
                            .opaqueBlack
                        case 0xFF_FF_FF_FF:
                            .opaqueWhite
                        default:
                            .transparentBlack
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
                samplerDescriptors: samplers,
                bufferSize: uniformBufferSize,
                textureCount: 0
            )
        default:
            assertionFailure("OBSShader: Unsupported shader type \(type)")
            return nil
        }
    }

    /// Analyzes shader uniform parameters parsed by the ``libobs`` shader parser.
    ///
    /// Each global variable declared as a "uniform" is stored as an ``OBSShaderVariable`` struct, which will be extended with additional
    /// metadata by later analystics steps.
    ///
    /// This is necessary as MSL does not support global variables and all data needs to be explicitly provided
    /// via buffer objects, which requires these "unforms" to be wrapped into a single struct and passed as an explicit buffer object.
    private func analyzeUniforms() throws {
        for i in 0..<parser.params.num {
            let uniform: UnsafeMutablePointer<shader_var>? = parser.params.array.advanced(by: i)

            guard let uniform, let name = uniform.pointee.name, let type = uniform.pointee.type else {
                throw ParserError.parseFail
            }

            let mapping: String? =
                if let mapping = uniform.pointee.mapping {
                    String(cString: mapping)
                } else {
                    nil
                }

            var data = OBSShaderVariable(
                name: String(cString: name),
                type: String(cString: type),
                mapping: mapping,
                storageType: .typeUniform,
                requiredBy: [],
                returnedBy: [],
                isStage: false,
                attributeId: 0,
                isConstant: (uniform.pointee.var_type == SHADER_VAR_CONST),
                gsVariable: uniform
            )

            if self.type == .fragment {
                if data.type.hasPrefix("texture") {
                    data.storageType.remove(.typeUniform)
                    data.storageType.insert(.typeTexture)
                }
            }

            uniformsOrder.append(data.name)
            uniforms.updateValue(data, forKey: data.name)

        }
    }

    /// Analyzes struct parameter declarations parsed by the ``libobs`` shader parser.
    ///
    /// Structured data declarations are used to pass data into and out of shaders.
    ///
    /// Whereas HLSL allows one to use "InOut" structures with attribute mappings (e.g., using the same type defintion for vertex data going in and out of a vertex shader), MSL does not allow the mixing of input mappings and output mappings in the same type definition.
    ///
    /// Thus when the same struct type is used as an input argument for a function but also used as its output type, it needs to be split up into two separate types for the MSL shader.
    ///
    /// This function will first detect all struct type definitions in the shader file and then check if it is used as an input argument or function output and update the associated ``OBSShaderVariable`` structs accordingly.
    private func analyzeParameters() throws {
        for i in 0..<parser.structs.num {
            let shaderStruct: UnsafeMutablePointer<shader_struct>? = parser.structs.array.advanced(by: i)

            guard let shaderStruct, let name = shaderStruct.pointee.name else {
                throw ParserError.parseFail
            }

            var parameters = [OBSShaderVariable]()
            parameters.reserveCapacity(shaderStruct.pointee.vars.num)

            for j in 0..<shaderStruct.pointee.vars.num {
                let variablePointer: UnsafeMutablePointer<shader_var>? = shaderStruct.pointee.vars.array.advanced(by: j)

                guard let variablePointer, let variableName = variablePointer.pointee.name,
                    let variableType = variablePointer.pointee.type
                else {
                    throw ParserError.parseFail
                }

                let mapping: String? =
                    if let variableMapping = variablePointer.pointee.mapping { String(cString: variableMapping) } else {
                        nil
                    }

                let variable = OBSShaderVariable(
                    name: String(cString: variableName),
                    type: String(cString: variableType),
                    mapping: mapping,
                    storageType: .typeStructMember,
                    requiredBy: [],
                    returnedBy: [],
                    isStage: false,
                    attributeId: nil,
                    isConstant: false,
                    gsVariable: variablePointer
                )

                parameters.append(variable)
            }

            let data = OBSShaderStruct(
                name: String(cString: name),
                storageType: [],
                members: parameters,
                gsVariable: shaderStruct
            )

            structs.updateValue(data, forKey: data.name)
        }

        for i in 0..<parser.funcs.num {
            let function: UnsafeMutablePointer<shader_func>? = parser.funcs.array.advanced(by: i)

            guard let function, let functionName = function.pointee.name, let returnType = function.pointee.return_type
            else {
                throw ParserError.parseFail
            }

            var functionData = OBSShaderFunction(
                name: String(cString: functionName),
                returnType: String(cString: returnType),
                typeMap: [:],
                requiresUniformBuffers: false,
                textures: [],
                samplers: [],
                arguments: [],
                gsFunction: function,
            )

            for j in 0..<function.pointee.params.num {
                let parameter: UnsafeMutablePointer<shader_var>? = function.pointee.params.array.advanced(by: j)

                guard let parameter, let parameterName = parameter.pointee.name,
                    let parameterType = parameter.pointee.type
                else {
                    throw ParserError.parseFail
                }

                let mapping: String? =
                    if let parameterMapping = parameter.pointee.mapping {
                        String(cString: parameterMapping)
                    } else {
                        nil
                    }

                var parameterData = OBSShaderVariable(
                    name: String(cString: parameterName),
                    type: String(cString: parameterType),
                    mapping: mapping,
                    storageType: .typeInput,
                    requiredBy: [functionData.name],
                    returnedBy: [],
                    isStage: false,
                    attributeId: nil,
                    isConstant: (parameter.pointee.var_type == SHADER_VAR_CONST),
                    gsVariable: parameter
                )

                if parameterData.type == functionData.returnType {
                    parameterData.returnedBy.insert(functionData.name)
                }

                if !functionData.typeMap.keys.contains(parameterData.name) {
                    functionData.typeMap.updateValue(parameterData.type, forKey: parameterData.name)
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

                functionData.arguments.append(parameterData)
            }

            if var shaderStruct = structs[functionData.returnType] {
                shaderStruct.storageType.insert(.typeOutput)
                structs.updateValue(shaderStruct, forKey: shaderStruct.name)
            }

            functions.updateValue(functionData, forKey: functionData.name)
        }
    }

    /// Analyzes function data parsed by the ``libobs`` shader parser
    ///
    /// As MSL does not support uniforms or using the same struct type for input and output, function bodies themselves need to be parsed again and checked for their usage of these types or variables.
    ///
    /// Due to the way that the ``libobs`` parser works, each body of a block (either within curly braces or parentheses) is analyzed recursively and updating the same ``OBSShaderFunction`` struct.
    ///
    /// After a full analysis pass, this struct should contain  information about all uniforms, textures, and samplers used (or passed on) by the function.
    private func analyzeFunctions() throws {
        for i in 0..<parser.funcs.num {
            let function: UnsafeMutablePointer<shader_func>? = parser.funcs.array.advanced(by: i)

            guard var function, var token = function.pointee.start, let functionName = function.pointee.name else {
                throw ParserError.parseFail
            }

            let functionData = functions[String(cString: functionName)]

            guard var functionData else {
                throw ParserError.parseFail
            }

            try analyzeFunction(function: &function, functionData: &functionData, token: &token, end: "}")

            functionData.textures = functionData.textures.unique()
            functionData.samplers = functionData.samplers.unique()

            functions.updateValue(functionData, forKey: functionData.name)
            functionsOrder.append(functionData.name)
        }
    }

    /// Analyzes a function body or source scope to check for use of global variables, textures, or samplers.
    ///
    /// Because MSL does not support global variables, unforms, textures, or samplers need to be passed explicitly to a function. This requires scanning the entire function body (recursively in the case of separate function scopes denoted by curvy brackets or parantheses) for any occurrence of a known uniform, texture, or sampler variable name.
    ///
    /// - Parameters:
    ///   - function: Pointer to a ``shader_func`` element representing a parsed shader function
    ///   - functionData: Reference to a ``OBSShaderFunction`` struct, which will be updated by this function
    ///   - token: Pointer to a ``cf_token`` element used to interact with the shader parser provided by ``libobs``
    ///   - end: The sentinel character at which analysis (and parsing) should stop
    private func analyzeFunction(
        function: inout UnsafeMutablePointer<shader_func>, functionData: inout OBSShaderFunction,
        token: inout UnsafeMutablePointer<cf_token>, end: String
    ) throws {
        let uniformNames =
            (uniforms.filter {
                !$0.value.storageType.contains(.typeTexture)
            }).keys

        while token.pointee.type != CFTOKEN_NONE {
            token = token.successor()

            if token.pointee.str.isEqualTo(end) {
                break
            }

            let stringToken = token.pointee.str.getString()

            if token.pointee.type == CFTOKEN_NAME {
                if uniformNames.contains(stringToken) && functionData.requiresUniformBuffers == false {
                    functionData.requiresUniformBuffers = true
                }

                if let function = functions[stringToken] {
                    if function.requiresUniformBuffers && functionData.requiresUniformBuffers == false {
                        functionData.requiresUniformBuffers = true
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

                        guard let sampler, let samplerName = sampler.pointee.name else {
                            break
                        }

                        if stringToken == String(cString: samplerName) {
                            functionData.samplers.append(stringToken)
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

    private func transpileUniforms() throws -> String {
        var output = [String]()

        for uniformName in uniformsOrder {
            if var uniform = uniforms[uniformName] {
                uniform.isStage = false
                uniform.attributeId = 0

                if !uniform.storageType.contains(.typeTexture) {
                    let variableString = try transpileVariable(variable: uniform)
                    output.append("\(variableString);")
                }
            }
        }

        if output.count > 0 {
            let replacements = [
                ("[variable]", output.joined(separator: "\n")),
                ("[typename]", "UniformData"),
            ]

            let uniformString = replacements.reduce(into: MSLTemplates.shaderStruct) { string, replacement in
                string = string.replacingOccurrences(of: replacement.0, with: replacement.1)
            }

            return uniformString
        } else {
            return ""
        }
    }

    private func transpileStructs() throws -> String {
        var output = [String]()

        for var shaderStruct in structs.values {
            if shaderStruct.storageType.isSuperset(of: [.typeInput, .typeOutput]) {
                for suffix in ["_In", "_Out"] {
                    var variables = [String]()

                    for (structVariableId, var structVariable) in shaderStruct.members.enumerated() {
                        let variableString: String

                        switch suffix {
                        case "_In":
                            structVariable.storageType.formUnion([.typeInput])
                            structVariable.attributeId = structVariableId
                            variableString = try transpileVariable(variable: structVariable)
                            structVariable.storageType.remove([.typeInput])
                        case "_Out":
                            structVariable.storageType.formUnion([.typeOutput])
                            variableString = try transpileVariable(variable: structVariable)
                            structVariable.storageType.remove([.typeOutput])
                        default:
                            throw ParserError.parseFail
                        }

                        variables.append("\(variableString);")
                        shaderStruct.members[structVariableId] = structVariable
                    }

                    let replacements = [
                        ("[variable]", variables.joined(separator: "\n")),
                        ("[typename]", "\(shaderStruct.name)\(suffix)"),
                    ]

                    let result = replacements.reduce(into: MSLTemplates.shaderStruct) {
                        string, replacement in
                        string = string.replacingOccurrences(of: replacement.0, with: replacement.1)
                    }

                    output.append(result)
                }
            } else {
                var variables = [String]()

                for (structVariableId, var structVariable) in shaderStruct.members.enumerated() {
                    if shaderStruct.storageType.contains(.typeInput) {
                        structVariable.storageType.insert(.typeInput)
                        structVariable.attributeId = structVariableId
                    } else if shaderStruct.storageType.contains(.typeOutput) {
                        structVariable.storageType.insert(.typeOutput)
                    }

                    let variableString = try transpileVariable(variable: structVariable)

                    structVariable.storageType.subtract([.typeInput, .typeOutput])

                    variables.append("\(variableString);")
                    shaderStruct.members[structVariableId] = structVariable
                }

                let replacements = [
                    ("[variable]", variables.joined(separator: "\n")),
                    ("[typename]", shaderStruct.name),
                ]

                let result = replacements.reduce(into: MSLTemplates.shaderStruct) {
                    string, replacement in
                    string = string.replacingOccurrences(of: replacement.0, with: replacement.1)
                }

                output.append(result)
            }
        }

        if output.count > 0 {
            return output.joined(separator: "\n\n")
        } else {
            return ""
        }
    }

    private func transpileFunctions() throws -> String {
        var output = [String]()

        for functionName in functionsOrder {
            guard let function = functions[functionName], var token = function.gsFunction.pointee.start else {
                throw ParserError.parseFail
            }

            var stageConsumed = false
            let isMain = functionName == "main"

            var variables = [String]()
            for var variable in function.arguments {
                if isMain && !stageConsumed {
                    variable.isStage = true
                    stageConsumed = true
                }

                try variables.append(transpileVariable(variable: variable))
            }

            if (uniforms.values.filter { !$0.storageType.contains(.typeTexture) }).count > 0 {
                if isMain {
                    variables.append("constant UniformData &uniforms [[buffer(30)]]")
                } else if function.requiresUniformBuffers {
                    variables.append("constant UniformData &uniforms")
                }
            }

            if type == .fragment {
                var textureId = 0

                for uniform in uniforms.values {
                    if uniform.storageType.contains(.typeTexture) {
                        if isMain {
                            let variableString = try transpileVariable(variable: uniform)

                            variables.append("\(variableString) [[texture(\(textureId))]]")
                            textureId += 1
                        } else if function.textures.contains(uniform.name) {
                            let variableString = try transpileVariable(variable: uniform)
                            variables.append(variableString)
                        }
                    }
                }

                var samplerId = 0
                for i in 0..<parser.samplers.num {
                    let sampler: UnsafeMutablePointer<shader_sampler>? = parser.samplers.array.advanced(by: i)

                    if let sampler, let samplerName = sampler.pointee.name {
                        let name = String(cString: samplerName)

                        if isMain {
                            let variableString = "sampler \(name) [[sampler(\(samplerId))]]"
                            variables.append(variableString)
                            samplerId += 1
                        } else if function.samplers.contains(name) {
                            let variabelString = "sampler \(name)"
                            variables.append(variabelString)
                        }
                    }
                }
            }

            let mappedType = try convertToMTLType(gsType: function.returnType)

            let functionContent: String
            var replacements = [(String, String)]()

            if isMain {
                replacements = [
                    ("[name]", "_main"),
                    ("[parameters]", variables.joined(separator: ", ")),
                ]

                switch type {
                case .vertex:
                    replacements.append(("[decorator]", "[[vertex]]"))
                case .fragment:
                    replacements.append(("[decorator]", "[[fragment]]"))
                default:
                    fatalError("OBSShader: Unsupported shader type \(type)")
                }

                let temporaryContent = try transpileFunctionContent(token: &token, end: "}")

                if type == .fragment && isMain && mappedType == "float3" {
                    replacements.append(("[type]", "float4"))

                    // TODO: Replace with Swift-native Regex once macOS 13 is minimum target
                    let regex = try NSRegularExpression(pattern: "return (.+);")
                    functionContent = regex.stringByReplacingMatches(
                        in: temporaryContent,
                        range: NSRange(location: 0, length: temporaryContent.count),
                        withTemplate: "return float4($1, 1);"
                    )
                } else {
                    functionContent = temporaryContent
                    replacements.append(("[type]", mappedType))
                }

                replacements.append(("[content]", functionContent))
            } else {
                functionContent = try transpileFunctionContent(token: &token, end: "}")

                replacements = [
                    ("[decorator]", ""),
                    ("[type]", mappedType),
                    ("[name]", function.name),
                    ("[parameters]", variables.joined(separator: ", ")),
                    ("[content]", functionContent),
                ]
            }

            let result = replacements.reduce(into: MSLTemplates.function) {
                string, replacement in
                string = string.replacingOccurrences(of: replacement.0, with: replacement.1)
            }

            output.append(result)
        }

        if output.count > 0 {
            return output.joined(separator: "\n\n")
        } else {
            return ""
        }
    }

    private func transpileVariable(variable: OBSShaderVariable) throws -> String {
        var mappings = [String]()

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

                if let mappingPointer = variable.gsVariable.pointee.mapping,
                    let mappedString = convertToMTLMapping(gsMapping: String(cString: mappingPointer))
                {
                    mappings.append(mappedString)
                }
            default:
                fatalError("OBSShader: Unsupported shader function type \(type)")
            }
        } else if variable.storageType.isSuperset(of: [.typeOutput, .typeStructMember]) {
            indent = 4

            if let mappingPointer = variable.gsVariable.pointee.mapping,
                let mappedString = convertToMTLMapping(gsMapping: String(cString: mappingPointer))
            {
                mappings.append(mappedString)
            }
        } else {
            indent = 0

            if variable.isStage {
                if let mappingPointer = variable.gsVariable.pointee.mapping,
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
                " constant "
            } else {
                ""
            }

        let result = "\(String(repeating: " ", count: indent))\(qualifier)\(metalType) \(variable.name)\(metalMapping)"

        return result
    }

    private func transpileFunctionContent(token: inout UnsafeMutablePointer<cf_token>, end: String) throws -> String {
        var content = [String]()

        while token.pointee.type != CFTOKEN_NONE {
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

                if let intrinsic = try convertToMTLIntrinsic(intrinsic: stringToken) {
                    content.append(intrinsic)
                    continue
                }

                if stringToken == "mul" {
                    try content.append(convertToMTLMultiplication(token: &token))
                    continue
                } else if stringToken == "mad" {
                    try content.append(convertToMTLMultiplyAdd(token: &token))
                    continue
                } else {
                    var skip = false
                    for uniform in uniforms.values {
                        if uniform.name == stringToken && uniform.storageType.contains(.typeTexture) {
                            try content.append(createSampler(token: &token))
                            skip = true
                            break
                        }
                    }

                    if skip {
                        continue
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

                var skip = false
                for shaderStruct in structs.values {
                    if shaderStruct.name == stringToken {
                        if shaderStruct.storageType.isSuperset(of: [.typeInput, .typeOutput]) {
                            content.append("\(stringToken)_Out")
                            skip = true
                            break
                        }
                    }
                }

                if skip {
                    continue
                }

                if let comparison = try convertToMTLComparison(token: &token) {
                    content.append(comparison)
                    continue
                }

                content.append(stringToken)
            } else if token.pointee.type == CFTOKEN_OTHER {
                if token.pointee.str.isEqualTo("{") {
                    let blockContent = try transpileFunctionContent(token: &token, end: "}")
                    content.append("{\(blockContent)}")
                    continue
                } else if token.pointee.str.isEqualTo("(") {
                    let priorToken = token.predecessor()
                    let functionName = priorToken.pointee.str.getString()

                    var functionParameters = [String]()

                    let parameters = try transpileFunctionContent(token: &token, end: ")")

                    if functionName == "int3" {
                        let intParameters = parameters.split(
                            separator: ",", maxSplits: 3, omittingEmptySubsequences: true)

                        switch intParameters.count {
                        case 3:
                            functionParameters.append(
                                "int(\(intParameters[0])), int(\(intParameters[1])), int(\(intParameters[2]))")
                        case 2:
                            functionParameters.append("int2(\(intParameters[1])), int(\(intParameters[1]))")
                        case 1:
                            functionParameters.append("\(intParameters)")
                        default:
                            throw ParserError.parseFail
                        }
                    } else {
                        functionParameters.append(parameters)
                    }

                    if let additionalArguments = generateAdditionalArguments(for: functionName) {
                        functionParameters.append(additionalArguments)
                    }

                    content.append("(\(functionParameters.joined(separator: ", ")))")
                    continue
                }

                content.append(stringToken)
            } else {
                content.append(stringToken)
            }
        }

        return content.joined()
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

    private func convertToMTLMapping(gsMapping: String) -> String? {
        switch gsMapping {
        case "POSITION":
            return "position"
        case "VERTEXID":
            return "vertex_id"
        default:
            return nil
        }
    }

    private func convertToMTLComparison(token: inout UnsafeMutablePointer<cf_token>) throws -> String? {
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

            let lhs = cfp.cur_token.pointee.str.getString()

            guard cfp.advanceToken() else { throw ParserError.missingNextToken }

            let comparator = cfp.cur_token.pointee.str.getString()

            guard cfp.advanceToken() else { throw ParserError.missingNextToken }

            let rhs = cfp.cur_token.pointee.str.getString()

            return "all(\(lhs) \(comparator) \(rhs))"
        } else {
            return nil
        }
    }

    private func convertToMTLIntrinsic(intrinsic: String) throws -> String? {
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

    private func convertToMTLMultiplication(token: inout UnsafeMutablePointer<cf_token>) throws -> String {
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

        let lhs = try transpileFunctionContent(token: &cfp.cur_token, end: ",")

        guard cfp.advanceToken() else {
            throw ParserError.missingNextToken
        }

        cfp.cur_token = cfp.cur_token.predecessor()

        let rhs = try transpileFunctionContent(token: &cfp.cur_token, end: ")")

        token = cfp.cur_token

        return "(\(lhs)) * (\(rhs))"
    }

    private func convertToMTLMultiplyAdd(token: inout UnsafeMutablePointer<cf_token>) throws -> String {
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

        let first = try transpileFunctionContent(token: &cfp.cur_token, end: ",")

        guard cfp.hasNextToken() else {
            throw ParserError.missingNextToken
        }

        let second = try transpileFunctionContent(token: &cfp.cur_token, end: ",")

        guard cfp.hasNextToken() else {
            throw ParserError.missingNextToken
        }

        let third = try transpileFunctionContent(token: &cfp.cur_token, end: ")")

        token = cfp.cur_token

        return "((\(first)) * (\(second))) + (\(third))"
    }

    private func createSampler(token: inout UnsafeMutablePointer<cf_token>) throws -> String {
        var cfp = parser.cfp
        cfp.cur_token = token

        let stringToken = token.pointee.str.getString()

        guard cfp.advanceToken() else { throw ParserError.missingNextToken }
        guard cfp.tokenIsEqualTo(".") else { throw ParserError.unexpectedToken }
        guard cfp.advanceToken() else { throw ParserError.missingNextToken }
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

    private func createTextureCall(token: inout UnsafeMutablePointer<cf_token>, callType: SampleVariant) throws
        -> String
    {
        var cfp = parser.cfp
        cfp.cur_token = token

        guard cfp.advanceToken() else { throw ParserError.missingNextToken }
        guard cfp.tokenIsEqualTo("(") else { throw ParserError.unexpectedToken }
        guard cfp.hasNextToken() else { throw ParserError.missingNextToken }

        switch callType {
        case .sample:
            let first = try transpileFunctionContent(token: &cfp.cur_token, end: ",")
            guard cfp.hasNextToken() else { throw ParserError.missingNextToken }

            let second = try transpileFunctionContent(token: &cfp.cur_token, end: ")")

            token = cfp.cur_token
            return "sample(\(first), \(second))"
        case .sampleBias:
            let first = try transpileFunctionContent(token: &cfp.cur_token, end: ",")
            guard cfp.hasNextToken() else { throw ParserError.missingNextToken }

            let second = try transpileFunctionContent(token: &cfp.cur_token, end: ",")
            guard cfp.hasNextToken() else { throw ParserError.missingNextToken }

            let third = try transpileFunctionContent(token: &cfp.cur_token, end: ")")

            token = cfp.cur_token
            return "sample(\(first), \(second), bias(\(third)))"
        case .sampleGrad:
            let first = try transpileFunctionContent(token: &cfp.cur_token, end: ",")
            guard cfp.hasNextToken() else { throw ParserError.missingNextToken }

            let second = try transpileFunctionContent(token: &cfp.cur_token, end: ",")
            guard cfp.hasNextToken() else { throw ParserError.missingNextToken }

            let third = try transpileFunctionContent(token: &cfp.cur_token, end: ",")
            guard cfp.hasNextToken() else { throw ParserError.missingNextToken }

            let fourth = try transpileFunctionContent(token: &cfp.cur_token, end: ")")

            token = cfp.cur_token
            return "sample(\(first), \(second), gradient2d(\(third), \(fourth)))"
        case .sampleLevel:
            let first = try transpileFunctionContent(token: &cfp.cur_token, end: ",")
            guard cfp.hasNextToken() else { throw ParserError.missingNextToken }

            let second = try transpileFunctionContent(token: &cfp.cur_token, end: ",")
            guard cfp.hasNextToken() else { throw ParserError.missingNextToken }

            let third = try transpileFunctionContent(token: &cfp.cur_token, end: ")")

            token = cfp.cur_token
            return "sample(\(first), \(second), level(\(third)))"
        case .load:
            let first = try transpileFunctionContent(token: &cfp.cur_token, end: ")")

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

    private func generateAdditionalArguments(for functionName: String) -> String? {
        var output = [String]()

        for function in functions.values {
            if function.name != functionName {
                continue
            }

            if function.requiresUniformBuffers {
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

    deinit {
        withUnsafeMutablePointer(to: &parser) {
            shader_parser_free($0)
        }
    }
}
