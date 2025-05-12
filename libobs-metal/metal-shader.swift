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

@_cdecl("device_vertexshader_create")
public func device_vertexshader_create(
    device: UnsafeRawPointer, shader: UnsafePointer<CChar>, file: UnsafePointer<CChar>,
    error_string: UnsafeMutablePointer<UnsafeMutablePointer<CChar>>
) -> OpaquePointer? {

    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    let content = String(cString: shader)
    let fileLocation = String(cString: file)

    let obsShader = OBSShader(type: .vertex, content: content, fileLocation: fileLocation)

    let parsed = obsShader?.transpiled()
    let metaData = obsShader?.metaData

    guard let parsed, let metaData else {
        return nil
    }

    guard let metalShader = MetalShader(device: device, source: parsed, type: .vertex, data: metaData) else {
        return nil
    }

    return metalShader.getRetained()
}

@_cdecl("device_pixelshader_create")
public func device_pixelshader_create(
    device: UnsafeRawPointer, shader: UnsafePointer<CChar>, file: UnsafePointer<CChar>,
    error_string: UnsafeMutablePointer<UnsafeMutablePointer<CChar>>
) -> OpaquePointer? {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    let content = String(cString: shader)
    let fileLocation = String(cString: file)

    let obsShader = OBSShader(type: .fragment, content: content, fileLocation: fileLocation)

    let parsed = obsShader?.transpiled()
    let metaData = obsShader?.metaData

    guard let parsed, let metaData else {
        return nil
    }

    guard let metalShader = MetalShader(device: device, source: parsed, type: .fragment, data: metaData) else {
        return nil
    }

    return metalShader.getRetained()
}

@_cdecl("device_load_vertexshader")
public func device_load_vertexsahder(device: UnsafeRawPointer, vertShader: UnsafeRawPointer?) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    if let vertShader {
        let metalShader = Unmanaged<MetalShader>.fromOpaque(vertShader).takeUnretainedValue()

        guard metalShader.type == .vertex else {
            assertionFailure("device_load_vertexshader: Invalid shader type \(metalShader.type)")
            return
        }

        device.renderState.vertexShader = metalShader
        device.renderState.pipelineDescriptor?.vertexFunction = metalShader.function
        device.renderState.pipelineDescriptor?.vertexDescriptor = metalShader.vertexDescriptor
    } else {
        device.renderState.vertexShader = nil
        device.renderState.pipelineDescriptor?.vertexFunction = nil
        device.renderState.pipelineDescriptor?.vertexDescriptor = nil
    }
}

@_cdecl("device_load_pixelshader")
public func device_load_pixelshader(device: UnsafeRawPointer, pixelShader: UnsafeRawPointer?) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    device.renderState.textures.removeAll()
    device.renderState.samplers.removeAll()

    if let pixelShader {
        let metalShader = Unmanaged<MetalShader>.fromOpaque(pixelShader).takeUnretainedValue()

        guard metalShader.type == .fragment else {
            assertionFailure("device_load_pixelshader: Invalid shader type \(metalShader.type)")
            return
        }

        device.renderState.fragmentShader = metalShader
        device.renderState.pipelineDescriptor?.fragmentFunction = metalShader.function

        if let samplers = metalShader.samplers {
            device.renderState.samplers.replaceSubrange(0..<samplers.count, with: samplers)
        }
    } else {
        device.renderState.pipelineDescriptor?.fragmentFunction = nil
    }
}

@_cdecl("device_get_vertex_shader")
public func device_get_vertex_shader(device: UnsafeRawPointer) -> OpaquePointer? {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    if let metalShader = device.renderState.vertexShader {
        return metalShader.getUnretained()
    } else {
        return nil
    }
}

@_cdecl("device_get_pixel_shader")
public func device_get_pixel_shader(device: UnsafeRawPointer) -> OpaquePointer? {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    if let metalShader = device.renderState.fragmentShader {
        return metalShader.getUnretained()
    } else {
        return nil
    }
}

@_cdecl("gs_shader_destroy")
public func gs_shader_destroy(shader: UnsafeRawPointer) {
    let _ = Unmanaged<MetalShader>.fromOpaque(shader).takeRetainedValue()
}

@_cdecl("gs_shader_get_num_params")
public func gs_shader_get_num_params(shader: UnsafeRawPointer) -> UInt32 {
    let metalShader = Unmanaged<MetalShader>.fromOpaque(shader).takeUnretainedValue()

    return UInt32(metalShader.uniforms.count)
}

@_cdecl("gs_shader_get_param_by_idx")
public func gs_shader_get_param_by_idx(shader: UnsafeRawPointer, param: UInt32) -> OpaquePointer? {
    let metalShader = Unmanaged<MetalShader>.fromOpaque(shader).takeUnretainedValue()

    guard param < metalShader.uniforms.count else {
        return nil
    }

    let uniform = metalShader.uniforms[Int(param)]
    let unretained = Unmanaged.passUnretained(uniform).toOpaque()

    return OpaquePointer(unretained)
}

@_cdecl("gs_shader_get_param_by_name")
public func gs_shader_get_param_by_name(shader: UnsafeRawPointer, param: UnsafeMutablePointer<CChar>) -> OpaquePointer?
{
    let metalShader = Unmanaged<MetalShader>.fromOpaque(shader).takeUnretainedValue()
    let paramName = String(cString: param)

    for uniform in metalShader.uniforms {
        if uniform.name == paramName {
            let unretained = Unmanaged.passUnretained(uniform).toOpaque()
            return OpaquePointer(unretained)
        }
    }

    return nil
}

@_cdecl("gs_shader_get_viewproj_matrix")
public func gs_shader_get_viewproj_matrix(shader: UnsafeRawPointer) -> OpaquePointer? {
    let metalShader = Unmanaged<MetalShader>.fromOpaque(shader).takeUnretainedValue()
    let paramName = "viewProj"

    for uniform in metalShader.uniforms {
        if uniform.name == paramName {
            let unretained = Unmanaged.passUnretained(uniform).toOpaque()
            return OpaquePointer(unretained)
        }
    }

    return nil
}

@_cdecl("gs_shader_get_world_matrix")
public func gs_shader_get_world_matrix(shader: UnsafeRawPointer) -> OpaquePointer? {
    let metalShader = Unmanaged<MetalShader>.fromOpaque(shader).takeUnretainedValue()
    let paramName = "worldProj"

    for uniform in metalShader.uniforms {
        if uniform.name == paramName {
            let unretained = Unmanaged.passUnretained(uniform).toOpaque()
            return OpaquePointer(unretained)
        }
    }

    return nil
}

@_cdecl("gs_shader_get_param_info")
public func gs_shader_get_param_info(shaderParam: UnsafeRawPointer, info: UnsafeMutablePointer<gs_shader_param_info>) {
    let shaderUniform = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()

    info.pointee.name = nil
    info.pointee.type = shaderUniform.gsType
}

@_cdecl("gs_shader_set_bool")
public func gs_shader_set_bool(shaderParam: UnsafeRawPointer, val: Bool) {
    let shaderUniform = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()

    withUnsafePointer(to: val) {
        shaderUniform.setParameter(data: $0, size: MemoryLayout<Int32>.size)
    }
}

@_cdecl("gs_shader_set_float")
public func gs_shader_set_float(shaderParam: UnsafeRawPointer, val: Float32) {
    let shaderUniform = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()

    withUnsafePointer(to: val) {
        shaderUniform.setParameter(data: $0, size: MemoryLayout<Float32>.size)
    }
}

@_cdecl("gs_shader_set_int")
public func gs_shader_set_int(shaderParam: UnsafeRawPointer, val: Int32) {
    let shaderUniform = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()

    withUnsafePointer(to: val) {
        shaderUniform.setParameter(data: $0, size: MemoryLayout<Int32>.size)
    }
}

@_cdecl("gs_shader_set_matrix3")
public func gs_shader_set_matrix3(shaderParam: UnsafeRawPointer, val: UnsafePointer<matrix3>) {
    let shaderUniform = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()

    var newMatrix = matrix4()
    matrix4_from_matrix3(&newMatrix, val)

    shaderUniform.setParameter(data: &newMatrix, size: MemoryLayout<matrix4>.size)
}

@_cdecl("gs_shader_set_matrix4")
public func gs_shader_set_matrix4(shaderParam: UnsafeRawPointer, val: UnsafePointer<matrix4>) {
    let shaderUniform = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()

    shaderUniform.setParameter(data: val, size: MemoryLayout<matrix4>.size)
}

@_cdecl("gs_shader_set_vec2")
public func gs_shader_set_vec2(shaderParam: UnsafeRawPointer, val: UnsafePointer<vec2>) {
    let shaderUniform = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()

    shaderUniform.setParameter(data: val, size: MemoryLayout<vec2>.size)
}

@_cdecl("gs_shader_set_vec3")
public func gs_shader_set_vec3(shaderParam: UnsafeRawPointer, val: UnsafePointer<vec3>) {
    let shaderUniform = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()

    shaderUniform.setParameter(data: val, size: MemoryLayout<vec3>.size)
}

@_cdecl("gs_shader_set_vec4")
public func gs_shader_set_vec4(shaderParam: UnsafeRawPointer, val: UnsafePointer<vec4>) {
    let shaderUniform = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()

    shaderUniform.setParameter(data: val, size: MemoryLayout<vec4>.size)
}

@_cdecl("gs_shader_set_texture")
public func gs_shader_set_texture(shaderParam: UnsafeRawPointer, val: UnsafePointer<gs_shader_texture>?) {
    let shaderUniform = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()

    if let val {
        shaderUniform.setParameter(data: val, size: MemoryLayout<gs_shader_texture>.size)
    }
}

@_cdecl("gs_shader_set_val")
public func gs_shader_set_val(shaderParam: UnsafeRawPointer, val: UnsafeRawPointer, size: UInt32) {
    let shaderUniform = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()

    let size = Int(size)
    var valueSize = shaderUniform.gsType.getSize()

    guard valueSize == size else {
        assertionFailure("gs_shader_set_val: Required size of uniform does not match size of input")
        return
    }

    if shaderUniform.gsType == GS_SHADER_PARAM_TEXTURE {
        let shaderTexture = val.bindMemory(to: gs_shader_texture.self, capacity: 1)

        shaderUniform.setParameter(data: shaderTexture, size: valueSize)
    } else {
        let bytes = val.bindMemory(to: UInt8.self, capacity: valueSize)
        shaderUniform.setParameter(data: bytes, size: valueSize)
    }
}

@_cdecl("gs_shader_set_default")
public func gs_shader_set_default(shaderParam: UnsafeRawPointer) {
    let shaderUniform = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()

    if let defaultValues = shaderUniform.defaultValues {
        shaderUniform.currentValues = Array(defaultValues)
    }
}

@_cdecl("gs_shader_set_next_sampler")
public func gs_shader_set_next_sampler(shaderParam: UnsafeRawPointer, sampler: UnsafeRawPointer) {
    let shaderUniform = Unmanaged<MetalShader.ShaderUniform>.fromOpaque(shaderParam).takeUnretainedValue()

    let samplerState = Unmanaged<MTLSamplerState>.fromOpaque(sampler).takeUnretainedValue()

    shaderUniform.samplerState = samplerState
}
