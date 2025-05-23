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

@_cdecl("device_texture_create")
public func device_texture_create(
    device: UnsafeRawPointer, width: UInt32, height: UInt32, color_format: gs_color_format, levels: UInt32,
    data: UnsafePointer<UnsafePointer<UInt8>?>?, flags: UInt32
) -> OpaquePointer? {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    let pixelFormat =
        if metalDevice.renderState.srgbState {
            color_format.toMTLsRGBFormat()
        } else {
            color_format.toMTLFormat()
        }

    let description = MetalTextureDescription(
        type: .type2D,
        width: Int(width),
        height: Int(height),
        depth: 0,
        pixelFormat: pixelFormat,
        mipmapLevels: Int(levels),
        isRenderTarget: (Int32(flags) & GS_RENDER_TARGET) != 0,
        isMipMapped: (Int32(flags) & GS_BUILD_MIPMAPS) != 0
    )

    guard let metalTexture = MetalTexture(device: metalDevice, description: description) else {
        return nil
    }

    if let data {
        metalTexture.upload(data: data, mipmapLevels: description.mipmapLevels)
    }

    return metalTexture.getRetained()
}

@_cdecl("device_cubetexture_create")
public func device_cubetexture_create(
    device: UnsafeRawPointer, size: UInt32, color_format: gs_color_format, levels: UInt32,
    data: UnsafePointer<UnsafePointer<UInt8>?>?, flags: UInt32
) -> OpaquePointer? {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    let description = MetalTextureDescription(
        type: .typeCube,
        width: Int(size),
        height: Int(size),
        depth: 0,
        pixelFormat: color_format.toMTLFormat(),
        mipmapLevels: Int(levels),
        isRenderTarget: (Int32(flags) & GS_RENDER_TARGET) != 0,
        isMipMapped: (Int32(flags) & GS_BUILD_MIPMAPS) != 0
    )

    guard let metalTexture = MetalTexture(device: metalDevice, description: description) else {
        return nil
    }

    if let data {
        metalTexture.upload(data: data, mipmapLevels: description.mipmapLevels)
    }

    return metalTexture.getRetained()
}

@_cdecl("gs_texture_destroy")
public func gs_texture_destroy(texture: UnsafeRawPointer) {
    let _ = Unmanaged<MetalTexture>.fromOpaque(texture).takeRetainedValue()
}

@_cdecl("device_get_texture_type")
public func device_get_texture_type(texture: UnsafeRawPointer) -> gs_texture_type {
    let texture = Unmanaged<MetalTexture>.fromOpaque(texture).takeUnretainedValue()

    return texture.texture.textureType.toGSTextureType()
}

@_cdecl("device_load_texture")
public func device_load_texture(device: UnsafeRawPointer, tex: UnsafeRawPointer, unit: UInt32) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()
    let texture = Unmanaged<MetalTexture>.fromOpaque(tex).takeUnretainedValue()

    device.renderState.textures[Int(unit)] = texture.texture
}

@_cdecl("device_load_texture_srgb")
public func device_load_texture_srgb(device: UnsafeRawPointer, tex: UnsafeRawPointer, unit: UInt32) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()
    let texture = Unmanaged<MetalTexture>.fromOpaque(tex).takeUnretainedValue()

    if texture.sRGBtexture != nil {
        device.renderState.textures[Int(unit)] = texture.sRGBtexture!
    } else {
        device.renderState.textures[Int(unit)] = texture.texture
    }

}

@_cdecl("device_copy_texture_region")
public func device_copy_texture_region(
    device: UnsafeRawPointer, dst: UnsafeRawPointer, dst_x: UInt32, dst_y: UInt32, src: UnsafeRawPointer, src_x: UInt32,
    src_y: UInt32, src_w: UInt32, src_h: UInt32
) {
    let source = Unmanaged<MetalTexture>.fromOpaque(src).takeUnretainedValue()
    let destination = Unmanaged<MetalTexture>.fromOpaque(dst).takeUnretainedValue()

    let sourceOrigin = MTLOrigin(x: Int(src_x), y: Int(src_y), z: 0)
    let destinationOrigin = MTLOrigin(x: Int(dst_x), y: Int(dst_y), z: 0)
    let size = MTLSize(width: Int(src_w), height: Int(src_h), depth: 1)

    source.copyRegion(to: destination, sourceOrigin: sourceOrigin, size: size, destinationOrigin: destinationOrigin)
}

@_cdecl("device_copy_texture")
public func device_copy_texture(device: UnsafeRawPointer, dst: UnsafeRawPointer, src: UnsafeRawPointer) {
    let source = Unmanaged<MetalTexture>.fromOpaque(src).takeUnretainedValue()
    let destination = Unmanaged<MetalTexture>.fromOpaque(dst).takeUnretainedValue()

    source.copy(to: destination)
}

@_cdecl("device_stage_texture")
public func device_stage_texture(device: UnsafeRawPointer, dst: UnsafeRawPointer, src: UnsafeRawPointer) {
    device_copy_texture(device: device, dst: dst, src: src)
}

@_cdecl("gs_texture_get_width")
public func device_texture_get_width(tex: UnsafeRawPointer) -> UInt32 {
    let texture = Unmanaged<MetalTexture>.fromOpaque(tex).takeUnretainedValue()

    return UInt32(texture.texture.width)
}

@_cdecl("gs_texture_get_height")
public func device_texture_get_height(tex: UnsafeRawPointer) -> UInt32 {
    let texture = Unmanaged<MetalTexture>.fromOpaque(tex).takeUnretainedValue()

    return UInt32(texture.texture.height)
}

@_cdecl("gs_texture_get_color_format")
public func gs_texture_get_color_format(tex: UnsafeRawPointer) -> gs_color_format {
    let texture = Unmanaged<MetalTexture>.fromOpaque(tex).takeUnretainedValue()

    return texture.texture.pixelFormat.toGSColorFormat()
}

@_cdecl("gs_texture_map")
public func gs_texture_map(
    tex: UnsafeRawPointer, ptr: UnsafeMutablePointer<UnsafeMutableRawPointer>, linesize: UnsafeMutablePointer<UInt32>
) -> Bool {
    let texture = Unmanaged<MetalTexture>.fromOpaque(tex).takeUnretainedValue()

    guard texture.texture.textureType == .type2D else {
        return false
    }

    guard let mapping = texture.map(mode: .write) else {
        return false
    }

    ptr.pointee = mapping.data
    linesize.pointee = UInt32(mapping.rowSize)

    return true
}

@_cdecl("gs_texture_unmap")
public func gs_texture_unmap(tex: UnsafeRawPointer) {
    let texture = Unmanaged<MetalTexture>.fromOpaque(tex).takeUnretainedValue()

    guard texture.texture.textureType == .type2D else {
        return
    }

    texture.unmap()
}

@_cdecl("gs_texture_get_obj")
public func gs_texture_get_obj(tex: UnsafeRawPointer) -> OpaquePointer {
    let texture = Unmanaged<MetalTexture>.fromOpaque(tex).takeUnretainedValue()

    let unretained = Unmanaged.passUnretained(texture.texture).toOpaque()

    return OpaquePointer(unretained)
}

@_cdecl("gs_cubetexture_destroy")
public func gs_cubetexture_destroy(cubetex: UnsafeRawPointer) {
    let _ = Unmanaged<MetalTexture>.fromOpaque(cubetex).takeRetainedValue()
}

@_cdecl("gs_cubetexture_get_size")
public func gs_cubetexture_get_size(cubetex: UnsafeRawPointer) -> UInt32 {
    let texture = Unmanaged<MetalTexture>.fromOpaque(cubetex).takeUnretainedValue()

    return UInt32(texture.texture.width)
}

@_cdecl("gs_cubetexture_get_color_format")
public func gs_cubetexture_get_color_format(cubetex: UnsafeRawPointer) -> gs_color_format {
    let texture = Unmanaged<MetalTexture>.fromOpaque(cubetex).takeUnretainedValue()

    return texture.texture.pixelFormat.toGSColorFormat()
}

@_cdecl("device_shared_texture_available")
public func device_shared_texture_available(device: UnsafeRawPointer) -> Bool {
    return true
}

@_cdecl("device_texture_create_from_iosurface")
public func device_texture_create_from_iosurface(device: UnsafeRawPointer, iosurf: IOSurfaceRef) -> OpaquePointer? {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    let texture = MetalTexture(device: device, surface: iosurf)

    guard let texture else {
        return nil
    }

    return texture.getRetained()
}

@_cdecl("gs_texture_rebind_iosurface")
public func gs_texture_rebind_iosurface(texture: UnsafeRawPointer, iosurf: IOSurfaceRef) -> Bool {
    let texture = Unmanaged<MetalTexture>.fromOpaque(texture).takeUnretainedValue()

    return texture.rebind(surface: iosurf)
}

@_cdecl("device_texture_open_shared")
public func device_texture_open_shared(device: UnsafeRawPointer, handle: UInt32) -> OpaquePointer? {
    if let reference = IOSurfaceLookupFromMachPort(handle) {
        let texture = device_texture_create_from_iosurface(device: device, iosurf: reference)

        return texture
    } else {
        return nil
    }
}
