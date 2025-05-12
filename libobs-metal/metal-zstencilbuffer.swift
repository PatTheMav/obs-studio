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

@_cdecl("device_zstencil_create")
public func device_zstencil_create(device: UnsafeRawPointer, width: UInt32, height: UInt32, format: gs_zstencil_format)
    -> OpaquePointer?
{
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    let description = MetalTextureDescription(
        type: .type2D,
        width: Int(width),
        height: Int(height),
        pixelFormat: format.toMTLFormat(),
        mipmapLevels: 0,
        isRenderTarget: false,
        isMipMapped: false
    )

    let stencilBuffer = MetalTexture(device: device, description: description)

    return stencilBuffer?.getRetained()
}

@_cdecl("device_get_zstencil_target")
public func device_get_zstencil_target(device: UnsafeRawPointer) -> OpaquePointer? {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    guard let stencilAttachment = device.renderState.stencilAttachment else {
        return nil
    }

    return stencilAttachment.getUnretained()
}

@_cdecl("gs_zstencil_destroy")
public func gs_zstencil_destroy(zstencil: UnsafeRawPointer) {
    let _ = Unmanaged<MetalTexture>.fromOpaque(zstencil).takeRetainedValue()
}
