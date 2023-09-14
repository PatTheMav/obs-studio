//
//  OBSShader.swift
//  libobs-metal
//
//  Created by Patrick Heyer on 16.04.24.
//

import Foundation
import Metal
import simd

class MetalShader {
    typealias BufferType = MetalDevice.BufferType
    var device: MetalDevice

    var data: [UInt8]
    var bufferSize = 0
    var textureCount = 0

    let source: String
    let library: MTLLibrary
    let function: MTLFunction
    var uniforms: [ShaderUniform]
    let bufferOrder: [BufferType]
    var descriptor: MTLVertexDescriptor? = nil
    var samplers: [(Int, MTLSamplerState)]?

    init(device: MetalDevice, source: String, type: MTLFunctionType, shaderData: ShaderData) {
        self.device = device
        self.source = source
        self.bufferSize =
            if (shaderData.bufferSize & 15) != 0 { (shaderData.bufferSize + 15) & ~15 } else { shaderData.bufferSize }
        self.data = Array(repeating: 0, count: self.bufferSize)
        self.uniforms = shaderData.uniforms
        self.bufferOrder = shaderData.bufferOrder
        self.textureCount = shaderData.textureCount

        switch type {
        case .vertex:
            guard let descriptor = shaderData.vertexDescriptor else {
                fatalError("MetalShader: Vertex shader missing MTLVertexDescriptor")
            }

            self.descriptor = descriptor
        case .fragment:
            guard let samplerDescriptors = shaderData.samplerDescriptor else {
                fatalError("MetalShader: Fragment shader missing MTLSamplerDescriptor")
            }

            var samplers = [(Int, MTLSamplerState)]()

            for descriptor in samplerDescriptors {
                guard let samplerState = device.device.makeSamplerState(descriptor: descriptor) else {
                    assertionFailure("MetalShader: Failed to create sampler state")
                    break
                }

                let samplerStateId = device.samplerStates.insert(samplerState)

                samplers.append((samplerStateId, samplerState))
            }

            self.samplers = samplers
        default:
            fatalError("MetalShader: Unsupported shader type provided")
        }

        do {
            self.library = try device.device.makeLibrary(source: source, options: nil)
            guard let function = self.library.makeFunction(name: "_main") else {
                fatalError("MetalShader: Failed to create '_main' function for shader")
            }

            self.function = function
        } catch {
            fatalError(
                "MetalShader: Failed to convert shader program:\n\(error.localizedDescription)\nContents: \(source)")
        }
    }

    func updateUniform(uniform: inout ShaderUniform) {
        guard let currentValues = uniform.currentValues else {
            preconditionFailure("MetalShader: Required current values not set")
        }

        if uniform.gsType == GS_SHADER_PARAM_TEXTURE {
            let textureId = Int(currentValues.withUnsafeBytes({ $0.load(as: Int32.self) }))

            guard let texture = device.textures[textureId] else {
                preconditionFailure("MetalShader: No texture with ID \(textureId) found")
            }

            device.state.textures[uniform.textureSlot] = texture

            if uniform.samplerState > 0 {
                guard let samplerState = device.samplerStates[uniform.samplerState] else {
                    preconditionFailure("MetalShader: No sampler state with ID \(uniform.samplerState) found")
                }

                device.state.samplers[uniform.textureSlot] = samplerState
                uniform.samplerState = 0
            }
        } else {
            if uniform.hasUpdates {
                let startIndex = uniform.byteOffset
                let endIndex = uniform.byteOffset + currentValues.count

                data.replaceSubrange(startIndex..<endIndex, with: currentValues)
            }
        }

        uniform.hasUpdates = false
    }

    func uploadParameters(encoder: MTLRenderCommandEncoder) {
        for var uniform in uniforms {
            updateUniform(uniform: &uniform)
        }

        guard bufferSize > 0 else {
            return
        }

        switch function.functionType {
        case .vertex:
            switch data.count {
            case 0..<4096: encoder.setVertexBytes(&data, length: data.count, index: 30)
            default:
                let buffer = device.getBufferForSize(data.count)
                buffer.label = "Vertex shader uniform buffer"
                buffer.contents().copyMemory(from: data, byteCount: data.count)
                encoder.setVertexBuffer(buffer, offset: 0, index: 30)
            }
        case .fragment:
            switch data.count {
            case 0..<4096: encoder.setFragmentBytes(&data, length: data.count, index: 30)
            default:
                let buffer = device.getBufferForSize(data.count)
                buffer.label = "Fragment shader uniform buffer"
                buffer.contents().copyMemory(from: data, byteCount: data.count)
                encoder.setFragmentBuffer(buffer, offset: 0, index: 30)
            }
        default:
            fatalError("MetalShader: Unsupport shader type \(function.functionType)")
        }
    }
}

// MARK: - Equatable Protocol
extension MetalShader: Equatable {
    static func == (lhs: MetalShader, rhs: MetalShader) -> Bool {
        return lhs.source == rhs.source && lhs.function.functionType == rhs.function.functionType
    }
}

// MARK: - Data management structs
extension MetalShader {
    struct ShaderData {
        let uniforms: [ShaderUniform]
        let bufferOrder: [BufferType]
        let vertexDescriptor: MTLVertexDescriptor?

        let samplerDescriptor: [MTLSamplerDescriptor]?
        let bufferSize: Int
        let textureCount: Int
    }

    class ShaderUniform {
        let name: String
        let gsType: gs_shader_param_type
        let textureSlot: Int
        var samplerState: Int
        let byteOffset: Int

        var currentValues: [UInt8]?
        var defaultValues: [UInt8]?
        var hasUpdates: Bool

        init(name: String, gsType: gs_shader_param_type, textureSlot: Int, samplerState: Int, byteOffset: Int) {
            self.name = name
            self.gsType = gsType

            self.textureSlot = textureSlot
            self.samplerState = samplerState
            self.byteOffset = byteOffset
            self.currentValues = nil
            self.defaultValues = nil
            self.hasUpdates = false
        }

        func setParameter<T>(data: UnsafePointer<T>?, size: Int) {
            guard let data else {
                assertionFailure("Attempted to set shader parameter with a nil pointer")
                return
            }

            data.withMemoryRebound(to: UInt8.self, capacity: size) {
                self.currentValues = Array(UnsafeBufferPointer(start: $0, count: size))
            }
            hasUpdates = true
        }
    }
}

extension MetalDevice {
    func updateShader(shader: MetalShader) {
        switch shader.function.functionType {
        case .vertex:
            state.vertexShader = shader
            state.renderPipelineDescriptor.vertexFunction = shader.function
            state.renderPipelineDescriptor.vertexDescriptor = shader.descriptor
        case .fragment:
            state.fragmentShader = shader
            state.renderPipelineDescriptor.fragmentFunction = shader.function

            state.textures = [MTLTexture?](repeating: nil, count: Int(GS_MAX_TEXTURES))
            state.samplers = [MTLSamplerState?](repeating: nil, count: Int(GS_MAX_TEXTURES))

            if let newSamplers = shader.samplers?.map({ $0.1 }) {
                state.samplers.replaceSubrange(0..<newSamplers.count, with: newSamplers)
            }
        default:
            fatalError(
                "device_load_vertexshader (Metal): Incompatible shader type found (\(shader.function.functionType))")
        }
    }
}

// MARK: - libobs Graphics API

@_cdecl("device_vertexshader_create")
public func device_vertexshader_create(
    device: UnsafeRawPointer, shaderString: UnsafePointer<CChar>, file: UnsafePointer<CChar>,
    errorString: UnsafeMutablePointer<UnsafeMutablePointer<CChar>>
) -> OpaquePointer? {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    let content = String(cString: shaderString)
    let fileName = String(cString: file)

    let parser = OBSShaderParser(type: .vertex, content: content, file: fileName)
    let shaderContent = parser.convertToString()

    if let shaderContent {
        let shader = MetalShader(
            device: device,
            source: shaderContent,
            type: .vertex,
            shaderData: parser.buildMetadata()
        )

        let shaderId = device.shaders.insert(shader)
        let resource = OBSAPIResource(device: device, resourceId: shaderId)
        return resource.getRetained()
    }

    return nil
}

@_cdecl("device_pixelshader_create")
public func device_pixelshader_create(
    device: UnsafeRawPointer, shaderString: UnsafePointer<CChar>, file: UnsafePointer<CChar>,
    errorString: UnsafeMutablePointer<UnsafeMutablePointer<CChar>>
) -> OpaquePointer? {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    let content = String(cString: shaderString)
    let fileName = String(cString: file)

    let parser = OBSShaderParser(type: .fragment, content: content, file: fileName)
    let shaderContent = parser.convertToString()

    if let shaderContent {
        let shader = MetalShader(
            device: device,
            source: shaderContent,
            type: .fragment,
            shaderData: parser.buildMetadata()
        )

        let shaderId = device.shaders.insert(shader)
        let resource = OBSAPIResource(device: device, resourceId: shaderId)
        return resource.getRetained()
    }

    return nil
}

/// Loads a sampler state into a texture unit
///
///  The provided ``MetalResource`` instance contains the ID of the sampler state and will be used to find a preconfigured ``OBSSamplerState`` instance. If found, the reference will be added to the ``OBSMetalDevice``'  `currentSamplerStates` collection at the index provided by the texture unit variable.
///
/// - Parameters:
///   - device: Opaque pointer to ``MetalRenderer`` instance
///   - ss: Opaque pointer to ``MetalResource`` instance
///   - unit: Texture unit for which the texture should be set up

/// Loads a vertex shader
///
///  The provided ``MetalResource`` instance contains the ID of the vertex shader and will be used to find a preconfigured ``OBSVertexSahder`` instance. If found, the reference will be set as the ``OBSMetalDevice``' `currentVertexShader``.
///
/// - Parameters:
///   - device: Opaque pointer to ``MetalRenderer`` instance
///   - vertShader: Opaque ponter to ``MetalResource`` instance
@_cdecl("device_load_vertexshader")
public func device_load_vertexshader(device: UnsafeRawPointer, vertShader: UnsafeRawPointer?) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    if let vertShader {
        let resource = Unmanaged<OBSAPIResource>.fromOpaque(vertShader).takeUnretainedValue()

        guard let shader = device.shaders[resource.resourceId] else {
            assertionFailure("device_load_vertexshader (Metal): Invalid vertex shader ID provided")
            return
        }

        guard shader.function.functionType == .vertex else {
            assertionFailure(
                "device_load_vertexshader (Metal): Invalid shader type provided: \(shader.function.functionType)")
            return
        }

        device.updateShader(shader: shader)
        device.state.vertexShaderId = resource.resourceId
    } else {
        device.state.vertexShader = nil
        device.state.renderPipelineDescriptor.vertexFunction = nil
        device.state.renderPipelineDescriptor.vertexDescriptor = nil
        device.state.vertexShaderId = 0
    }
}

@_cdecl("device_load_pixelshader")
public func device_load_pixelshader(device: UnsafeRawPointer, pixelShader: UnsafeRawPointer?) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    if let pixelShader {
        let resource = Unmanaged<OBSAPIResource>.fromOpaque(pixelShader).takeUnretainedValue()

        guard let shader = device.shaders[resource.resourceId] else {
            assertionFailure("device_load_pixelshader (Metal): Invalid pixel shader ID provided")
            return
        }

        guard shader.function.functionType == .fragment else {
            assertionFailure(
                "device_load_pixelshader (Metal): Invalid shader type provided: \(shader.function.functionType)")
            return
        }

        device.updateShader(shader: shader)
        device.state.fragmentShaderId = resource.resourceId
    } else {
        device.state.textures = [MTLTexture?](repeating: nil, count: Int(GS_MAX_TEXTURES))
        device.state.samplers = [MTLSamplerState?](repeating: nil, count: Int(GS_MAX_TEXTURES))

        device.state.renderPipelineDescriptor.fragmentFunction = nil
        device.state.fragmentShaderId = 0
    }
}

@_cdecl("device_get_vertex_shader")
public func device_get_vertex_shader(device: UnsafeRawPointer) -> OpaquePointer? {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    let shaderId = device.state.vertexShaderId

    if shaderId > 0 {
        let resource = OBSAPIResource(device: device, resourceId: shaderId)
        return resource.getRetained()
    } else {
        return nil
    }
}

@_cdecl("device_get_pixel_shader")
public func device_get_pixel_shader(device: UnsafeRawPointer) -> OpaquePointer? {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    let shaderId = device.state.fragmentShaderId

    if shaderId > 0 {
        let resource = OBSAPIResource(device: device, resourceId: shaderId)
        return resource.getRetained()
    } else {
        return nil
    }
}

@_cdecl("gs_shader_destroy")
public func gs_shader_destroy(shader: UnsafeRawPointer) {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(shader).takeRetainedValue()
    let device = resource.device

    device.shaders.remove(resource.resourceId)
}

@_cdecl("gs_shader_get_num_params")
public func gs_shader_get_num_params(shader: UnsafeRawPointer) -> Int {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(shader).takeUnretainedValue()
    let device = resource.device

    guard let shader = device.shaders[resource.resourceId] else {
        assertionFailure("gs_shader_get_num_parameters (Metal): Invalid shader ID provided")
        return 0
    }

    return shader.uniforms.count
}

@_cdecl("gs_shader_get_param_by_idx")
public func gs_shader_get_param_by_idx(shader: UnsafeRawPointer, param: UInt32) -> OpaquePointer? {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(shader).takeUnretainedValue()
    let device = resource.device

    guard let shader = device.shaders[resource.resourceId] else {
        assertionFailure("gs_shader_get_param_by_idx (Metal): Invalid shader ID provided")
        return nil
    }

    if param < shader.uniforms.count {
        let unretained = Unmanaged.passUnretained(shader.uniforms[Int(param)]).toOpaque()
        return OpaquePointer(unretained)
    } else {
        return nil
    }
}

@_cdecl("gs_shader_get_param_by_name")
public func gs_shader_get_param_by_name(shader: UnsafeRawPointer, param: UnsafeMutablePointer<CChar>) -> OpaquePointer?
{
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(shader).takeUnretainedValue()
    let device = resource.device

    guard let shader = device.shaders[resource.resourceId] else {
        assertionFailure("gs_shader_get_param_by_name (Metal): Invalid shader ID provided")
        return nil
    }

    let paramName = String(cString: param)

    for uniform in shader.uniforms {
        if uniform.name == paramName {
            let unretained = Unmanaged.passUnretained(uniform).toOpaque()
            return OpaquePointer(unretained)
        }
    }

    return nil
}

@_cdecl("gs_shader_get_viewproj_matrix")
public func gs_shader_get_viewproj_matrix(shader: UnsafeRawPointer) -> OpaquePointer? {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(shader).takeUnretainedValue()
    let device = resource.device

    guard let shader = device.shaders[resource.resourceId] else {
        assertionFailure("gs_shader_get_viewproj_matrix (Metal): Invalid shader ID provided")
        return nil
    }

    guard shader.function.functionType == .vertex else {
        assertionFailure("gs_shader_get_viewproj_matrix (Metal): Provided shader is not a vertex shader")
        return nil
    }

    for uniform in shader.uniforms {
        if uniform.name == "viewProj" {
            let unretained = Unmanaged.passUnretained(uniform).toOpaque()
            return OpaquePointer(unretained)
        }
    }

    return nil
}

@_cdecl("gs_shader_get_world_matrix")
public func gs_shader_get_world_matrix(shader: UnsafeRawPointer) -> OpaquePointer? {
    /// World Matrix support is not used in OBS
    return nil
}

@_cdecl("gs_shader_get_param_info")
public func gs_shader_get_param_info(shaderParam: UnsafeRawPointer, info: UnsafeMutablePointer<gs_shader_param_info>) {
    let shaderParam = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()

    info.pointee.name = nil
    info.pointee.type = shaderParam.gsType
}

@_cdecl("gs_shader_set_bool")
public func gs_shader_set_bool(shaderParam: UnsafeRawPointer, val: Bool) {
    let shaderParam = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()

    withUnsafePointer(to: val) {
        shaderParam.setParameter(data: $0, size: MemoryLayout<Int32>.size)
    }
}

@_cdecl("gs_shader_set_float")
public func gs_shader_set_float(shaderParam: UnsafeRawPointer, val: Float32) {
    let shaderParam = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()

    withUnsafePointer(to: val) {
        shaderParam.setParameter(data: $0, size: MemoryLayout<Float32>.size)
    }
}

@_cdecl("gs_shader_set_int")
public func gs_shader_set_int(shaderParam: UnsafeRawPointer, val: Int32) {
    let shaderParam = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()

    withUnsafePointer(to: val) {
        shaderParam.setParameter(data: $0, size: MemoryLayout<Int32>.size)
    }
}

@_cdecl("gs_shader_set_matrix3")
public func gs_shader_set_matrix3(shaderParam: UnsafeRawPointer, val: UnsafePointer<matrix3>) {
    let shaderParam = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()

    var mat: matrix4 = matrix4()
    matrix4_from_matrix3(&mat, val)

    shaderParam.setParameter(data: &mat, size: MemoryLayout<matrix4>.size)
}

@_cdecl("gs_shader_set_matrix4")
public func gs_shader_set_matrix4(shaderParam: UnsafeRawPointer, val: UnsafePointer<matrix4>) {
    let shaderParam = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()

    shaderParam.setParameter(data: val, size: MemoryLayout<matrix4>.size)
}

@_cdecl("gs_shader_set_vec2")
public func gs_shader_set_vec2(shaderParam: UnsafeRawPointer, val: UnsafePointer<vec2>) {
    let shaderParam = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()

    shaderParam.setParameter(data: val, size: MemoryLayout<vec2>.size)
}

@_cdecl("gs_shader_set_vec3")
public func gs_shader_set_vec3(shaderParam: UnsafeRawPointer, val: UnsafePointer<vec3>) {
    let shaderParam = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()

    shaderParam.setParameter(data: val, size: MemoryLayout<vec3>.size)
}

@_cdecl("gs_shader_set_vec4")
public func gs_shader_set_vec4(shaderParam: UnsafeRawPointer, val: UnsafePointer<vec4>) {
    let shaderParam = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()

    shaderParam.setParameter(data: val, size: MemoryLayout<vec4>.size)
}

@_cdecl("gs_shader_set_texture")
public func gs_shader_set_texture(shaderParam: UnsafeRawPointer, val: UnsafeRawPointer?) {
    let shaderParam = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()

    var textureId = 0

    if let val {
        let resource = Unmanaged<OBSAPIResource>.fromOpaque(val).takeUnretainedValue()

        textureId = resource.resourceId
    }

    withUnsafePointer(to: textureId) {
        shaderParam.setParameter(data: $0, size: MemoryLayout<Int32>.size)
    }
}

@_cdecl("gs_shader_set_val")
public func gs_shader_set_val(shaderParam: UnsafeRawPointer, val: UnsafeRawPointer, size: Int) {
    let shaderParam = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()

    var valueSize = 0

    switch shaderParam.gsType {
    case GS_SHADER_PARAM_FLOAT:
        valueSize = MemoryLayout<Float32>.size
    case GS_SHADER_PARAM_BOOL, GS_SHADER_PARAM_INT:
        valueSize = MemoryLayout<Int32>.size
    case GS_SHADER_PARAM_INT2:
        valueSize = MemoryLayout<Int32>.size * 2
    case GS_SHADER_PARAM_INT3:
        valueSize = MemoryLayout<Int32>.size * 3
    case GS_SHADER_PARAM_INT4:
        valueSize = MemoryLayout<Int32>.size * 4
    case GS_SHADER_PARAM_VEC2:
        valueSize = MemoryLayout<Float32>.size * 2
    case GS_SHADER_PARAM_VEC3:
        valueSize = MemoryLayout<Float32>.size * 3
    case GS_SHADER_PARAM_VEC4:
        valueSize = MemoryLayout<Float32>.size * 4
    case GS_SHADER_PARAM_MATRIX4X4:
        valueSize = MemoryLayout<Float32>.size * 4 * 4
    case GS_SHADER_PARAM_TEXTURE:
        valueSize = MemoryLayout<gs_shader_texture>.size
    default:
        valueSize = 0
    }

    if valueSize != size {
        assertionFailure("gs_shader_set_val (Metal): Size of shader parameter does not match size of input")
        return
    }

    if shaderParam.gsType == GS_SHADER_PARAM_TEXTURE {
        let texture: UnsafePointer<gs_shader_texture> = val.bindMemory(to: gs_shader_texture.self, capacity: 1)
        let resource = Unmanaged<OBSAPIResource>.fromOpaque(UnsafeRawPointer(texture.pointee.tex)).takeUnretainedValue()

        withUnsafePointer(to: resource.resourceId) {
            shaderParam.setParameter(data: $0, size: MemoryLayout<Int32>.size)
        }
    } else {
        let bytes = val.bindMemory(to: UInt8.self, capacity: size)
        shaderParam.setParameter(data: bytes, size: size)
    }
}

@_cdecl("gs_shader_set_default")
public func gs_shader_set_default(shaderParam: UnsafeRawPointer) {
    let shaderParam = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()

    if let defaultValues = shaderParam.defaultValues {
        if shaderParam.currentValues != nil {
            shaderParam.currentValues = defaultValues
        } else {
            shaderParam.currentValues = Array(defaultValues)
        }
    }
}

@_cdecl("gs_shader_set_next_sampler")
public func gs_shader_set_next_sampler(shaderParam: UnsafeRawPointer, sampler: UnsafeRawPointer) {
    let shaderParam = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(sampler).takeUnretainedValue()

    shaderParam.samplerState = resource.resourceId
}
