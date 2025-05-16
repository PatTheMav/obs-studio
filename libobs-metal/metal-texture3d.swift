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

@_cdecl("device_voltexture_create")
public func device_voltexture_create(
    device: UnsafeRawPointer, size: UInt32, color_format: gs_color_format, levels: UInt32,
    data: UnsafePointer<UnsafePointer<UInt8>?>?, flags: UInt32
) -> OpaquePointer? {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    let description = MetalTextureDescription(
        type: .type3D,
        width: Int(size),
        height: Int(size),
        depth: Int(size),
        pixelFormat: color_format.toMTLFormat(),
        mipmapLevels: Int(levels),
        isRenderTarget: (Int32(flags) & GS_RENDER_TARGET) != 0,
        isMipMapped: (Int32(flags) & GS_BUILD_MIPMAPS) != 0
    )

    let metalTexture = MetalTexture(device: metalDevice, description: description)

    guard let metalTexture else {
        return nil
    }

    if let data {
        metalTexture.upload(data: data, mipmapLevels: description.mipmapLevels)
    }

    return metalTexture.getRetained()
}

@_cdecl("gs_voltexture_destroy")
public func gs_voltexture_destroy(texture: UnsafeRawPointer) {
    let _ = Unmanaged<MetalTexture>.fromOpaque(texture).takeRetainedValue()
}

@_cdecl("gs_voltexture_get_width")
public func gs_voltexture_get_width(voltex: UnsafeRawPointer) -> UInt32 {
    let metalTexture = Unmanaged<MetalTexture>.fromOpaque(voltex).takeUnretainedValue()

    return UInt32(metalTexture.texture.width)
}

@_cdecl("gs_voltexture_get_height")
public func gs_voltexture_get_height(voltex: UnsafeRawPointer) -> UInt32 {
    let metalTexture = Unmanaged<MetalTexture>.fromOpaque(voltex).takeUnretainedValue()

    return UInt32(metalTexture.texture.height)
}

@_cdecl("gs_voltexture_get_depth")
public func gs_voltexture_get_depth(voltex: UnsafeRawPointer) -> UInt32 {
    let metalTexture = Unmanaged<MetalTexture>.fromOpaque(voltex).takeUnretainedValue()

    return UInt32(metalTexture.texture.depth)
}

@_cdecl("gs_voltexture_get_color_format")
public func gs_voltexture_get_color_format(voltex: UnsafeRawPointer) -> gs_color_format {
    let metalTexture = Unmanaged<MetalTexture>.fromOpaque(voltex).takeUnretainedValue()

    return metalTexture.texture.pixelFormat.toGSColorFormat()
}
