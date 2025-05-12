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

@_cdecl("device_indexbuffer_create")
public func device_indexbuffer_create(
    device: UnsafeRawPointer, type: gs_index_type, indices: UnsafeMutableRawPointer, num: UInt32, flags: UInt32
) -> OpaquePointer? {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    let indexBuffer = MetalIndexBuffer(
        device: device,
        type: type.toMTLType(),
        data: indices,
        count: Int(num),
        dynamic: (Int32(flags) & GS_DYNAMIC) != 0
    )

    return indexBuffer.getRetained()
}

@_cdecl("device_load_indexbuffer")
public func device_load_indexbuffer(device: UnsafeRawPointer, indexbuffer: UnsafeRawPointer?) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    if let indexbuffer {
        device.renderState.currentIndexBuffer = Unmanaged<MetalIndexBuffer>.fromOpaque(indexbuffer)
            .takeUnretainedValue()
    } else {
        device.renderState.currentIndexBuffer = nil
    }
}

@_cdecl("gs_indexbuffer_destroy")
public func gs_indexbuffer_destroy(indexBuffer: UnsafeRawPointer) {
    let _ = Unmanaged<MetalIndexBuffer>.fromOpaque(indexBuffer).takeRetainedValue()
}

@_cdecl("gs_indexbuffer_flush")
public func gs_indexbuffer_flush(indexBuffer: UnsafeRawPointer) {
    gs_indexbuffer_flush_direct(indexBuffer: indexBuffer, data: nil)
}

@_cdecl("gs_indexbuffer_flush_direct")
public func gs_indexbuffer_flush_direct(indexBuffer: UnsafeRawPointer, data: UnsafeMutableRawPointer?) {
    let indexBuffer = Unmanaged<MetalIndexBuffer>.fromOpaque(indexBuffer).takeUnretainedValue()

    indexBuffer.setupBuffers(data)
}

@_cdecl("gs_indexbuffer_get_data")
public func gs_indexbuffer_get_data(indexBuffer: UnsafeRawPointer) -> UnsafeMutableRawPointer? {
    let indexBuffer = Unmanaged<MetalIndexBuffer>.fromOpaque(indexBuffer).takeUnretainedValue()

    return indexBuffer.indexData
}

@_cdecl("gs_indexbuffer_get_num_indices")
public func gs_indexbuffer_get_num_indices(indexBuffer: UnsafeRawPointer) -> UInt32 {
    let indexBuffer = Unmanaged<MetalIndexBuffer>.fromOpaque(indexBuffer).takeUnretainedValue()

    return UInt32(indexBuffer.count)
}

@_cdecl("gs_indexbuffer_get_type")
public func gs_indexbuffer_get_type(indexBuffer: UnsafeRawPointer) -> gs_index_type {
    let indexBuffer = Unmanaged<MetalIndexBuffer>.fromOpaque(indexBuffer).takeUnretainedValue()

    switch indexBuffer.type {
    case .uint16: return GS_UNSIGNED_SHORT
    case .uint32: return GS_UNSIGNED_LONG
    @unknown default:
        fatalError("gs_indexbuffer_get_type: Unsupported index buffer type \(indexBuffer.type)")
    }
}
