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

@_cdecl("device_vertexbuffer_create")
public func device_vertexbuffer_create(device: UnsafeRawPointer, data: UnsafeMutablePointer<gs_vb_data>, flags: UInt32)
    -> OpaquePointer
{
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    let vertexBuffer = MetalVertexBuffer(
        device: device,
        data: data,
        dynamic: (Int32(flags) & GS_DYNAMIC) != 0
    )

    return vertexBuffer.getRetained()
}

@_cdecl("device_vertexbuffer_destroy")
public func device_vertexbuffer_destroy(vertBuffer: UnsafeRawPointer) {
    let _ = Unmanaged<MetalBuffer>.fromOpaque(vertBuffer).takeRetainedValue()
}

@_cdecl("device_load_vertexbuffer")
public func device_load_vertexbuffer(device: UnsafeRawPointer, vertBuffer: UnsafeMutableRawPointer?) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    if let vertBuffer {
        device.renderState.vertexBuffer = Unmanaged<MetalVertexBuffer>.fromOpaque(vertBuffer).takeUnretainedValue()
    } else {
        device.renderState.vertexBuffer = nil
    }
}

@_cdecl("gs_vertexbuffer_flush")
public func gs_vertexbuffer_flush(vertbuffer: UnsafeRawPointer) {
    gs_vertexbuffer_flush_direct(vertbuffer: vertbuffer, data: nil)
}

@_cdecl("gs_vertexbuffer_flush_direct")
public func gs_vertexbuffer_flush_direct(vertbuffer: UnsafeRawPointer, data: UnsafeMutablePointer<gs_vb_data>?) {
    let vertexBuffer = Unmanaged<MetalVertexBuffer>.fromOpaque(vertbuffer).takeUnretainedValue()

    vertexBuffer.setupBuffers(data: data)
}

@_cdecl("gs_vertexbuffer_get_data")
public func gs_vertexbuffer_get_data(vertBuffer: UnsafeRawPointer) -> UnsafeMutablePointer<gs_vb_data>? {
    let vertexBuffer = Unmanaged<MetalVertexBuffer>.fromOpaque(vertBuffer).takeUnretainedValue()

    return vertexBuffer.vertexData
}
