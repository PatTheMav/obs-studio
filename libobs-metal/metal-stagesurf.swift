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

@_cdecl("device_stagesurface_create")
public func device_stagesurface_create(device: UnsafeRawPointer, width: UInt32, height: UInt32, format: gs_color_format)
    -> OpaquePointer?
{
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    let description = MetalTextureDescription(
        type: .type2D,
        width: Int(width),
        height: Int(height),
        depth: 0,
        pixelFormat: format.toMTLFormat(),
        mipmapLevels: 0,
        isRenderTarget: false,
        isMipMapped: false
    )

    let texture = MetalTexture(device: device, description: description)

    return texture?.getRetained()
}

@_cdecl("gs_stagesurface_destroy")
public func gs_stagesurface_destroy(stagesurf: UnsafeRawPointer) {
    let _ = Unmanaged<MetalTexture>.fromOpaque(stagesurf).takeRetainedValue()
}

@_cdecl("gs_stagesurface_get_width")
public func gs_stagesurface_get_width(stagesurf: UnsafeRawPointer) -> UInt32 {
    let stageSurface = Unmanaged<MetalTexture>.fromOpaque(stagesurf).takeUnretainedValue()

    return UInt32(stageSurface.texture.width)
}

@_cdecl("gs_stagesurface_get_height")
public func gs_stagesurface_get_height(stagesurf: UnsafeRawPointer) -> UInt32 {
    let stageSurface = Unmanaged<MetalTexture>.fromOpaque(stagesurf).takeUnretainedValue()

    return UInt32(stageSurface.texture.height)
}

@_cdecl("gs_stagesurface_get_color_format")
public func gs_stagesurface_get_height(stagesurf: UnsafeRawPointer) -> gs_color_format {
    let stageSurface = Unmanaged<MetalTexture>.fromOpaque(stagesurf).takeUnretainedValue()

    return stageSurface.texture.pixelFormat.toGSColorFormat()
}

@_cdecl("gs_stagesurface_map")
public func gs_stagesurface_map(
    stagesurf: UnsafeRawPointer, ptr: UnsafeMutablePointer<UnsafeMutableRawPointer>,
    linesize: UnsafeMutablePointer<UInt32>
) -> Bool {
    let stageSurface = Unmanaged<MetalTexture>.fromOpaque(stagesurf).takeUnretainedValue()

    guard stageSurface.type == .type2D else {
        return false
    }

    guard let mapping = stageSurface.map(mode: .read) else {
        return false
    }

    ptr.pointee = mapping.data
    linesize.pointee = UInt32(mapping.rowSize)

    return true
}

@_cdecl("gs_stagesurface_unmap")
public func gs_stagesurface_unmap(stagesurf: UnsafeRawPointer) {
    let stageSurface = Unmanaged<MetalTexture>.fromOpaque(stagesurf).takeUnretainedValue()

    guard stageSurface.type == .type2D else {
        return
    }

    stageSurface.unmap()
}
