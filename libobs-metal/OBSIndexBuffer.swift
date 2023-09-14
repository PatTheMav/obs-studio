//
//  OBSIndexBuffer.swift
//  libobs-metal
//
//  Created by Patrick Heyer on 16.04.24.
//

import Foundation
import Metal

class MetalIndexBuffer {
    var device: MetalDevice

    var indexData: UnsafeMutableRawPointer?
    var indexBuffer: MTLBuffer?
    var count: Int
    var type: MTLIndexType
    var isDynamic = false

    init(device: MetalDevice, type: MTLIndexType, data: UnsafeMutableRawPointer?, count: Int, dynamic: Bool) {
        self.device = device
        self.indexData = data
        self.count = count
        self.type = type

        if !isDynamic {
            setupMTLBuffers()
        }
    }

    func setupMTLBuffers(_ data: UnsafeMutableRawPointer? = nil) {
        guard let data = data ?? indexData else {
            preconditionFailure("MetalIndexBuffer: Unable to generate MTLBuffer with empty buffer data")
        }

        let byteSize =
            switch type {
            case .uint16:
                2 * count
            case .uint32:
                4 * count
            @unknown default:
                fatalError("MTLIndexType \(type) not supported")
            }

        if !isDynamic {
            indexBuffer = device.device.makeBuffer(
                bytes: data,
                length: byteSize,
                options: .cpuCacheModeWriteCombined)
            indexBuffer?.label = "Index buffer static data"
        } else {
            indexBuffer = device.getBufferForSize(byteSize)
            indexBuffer?.contents().copyMemory(from: data, byteCount: byteSize)
            indexBuffer?.label = "Index buffer dynamic data"
        }

        guard indexBuffer != nil else {
            fatalError("MetalIndexBuffer: Failed to create MTLBuffer")
        }
    }

    deinit {
        bfree(indexData)
    }
}

// MARK: libobs Graphics API

@_cdecl("device_indexbuffer_create")
public func device_indexbuffer_create(
    devicePointer: UnsafeRawPointer, type: gs_index_type, indices: UnsafeMutableRawPointer, num: Int, flags: UInt32
) -> OpaquePointer? {
    let device = Unmanaged<MetalDevice>.fromOpaque(devicePointer).takeUnretainedValue()

    let isDynamic = (Int32(flags) & GS_DYNAMIC) != 0

    let indexBuffer = MetalIndexBuffer(
        device: device,
        type: type.toMTLType(),
        data: indices,
        count: num,
        dynamic: isDynamic
    )

    let indexBufferId = device.indexBuffers.insert(indexBuffer)

    let resource = OBSAPIResource(device: device, resourceId: indexBufferId)

    return resource.getRetained()
}

@_cdecl("device_load_indexbuffer")
public func device_load_indexbuffer(
    devicePointer: UnsafeRawPointer, ibPointer: UnsafeRawPointer?
) {
    let device = Unmanaged<MetalDevice>.fromOpaque(devicePointer).takeUnretainedValue()

    if let ibPointer {
        let resource = Unmanaged<OBSAPIResource>.fromOpaque(ibPointer).takeUnretainedValue()

        guard let indexBuffer = device.indexBuffers[resource.resourceId] else {
            assertionFailure("device_load_indexbuffer (Metal): Invalid index buffer ID provided")
            return
        }

        device.state.indexBuffer = indexBuffer
    } else {
        device.state.indexBuffer = nil
    }
}

@_cdecl("gs_indexbuffer_destroy")
public func gs_indexbuffer_destroy(indexBufferPointer: UnsafeRawPointer) {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(indexBufferPointer).takeRetainedValue()
    let device = resource.device
    device.indexBuffers.remove(resource.resourceId)
}

@_cdecl("gs_indexbuffer_flush")
public func gs_indexbuffer_flush(indexBufferPointer: UnsafeRawPointer) {
    gs_indexbuffer_flush_direct(indexBufferPointer: indexBufferPointer, data: nil)
}

@_cdecl("gs_indexbuffer_flush_direct")
public func gs_indexbuffer_flush_direct(indexBufferPointer: UnsafeRawPointer, data: UnsafeMutableRawPointer?) {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(indexBufferPointer).takeUnretainedValue()
    let device = resource.device

    guard let indexBuffer = device.indexBuffers[resource.resourceId] else {
        assertionFailure("gs_indexbuffer_flush (Metal): Invalid index buffer ID provided")
        return
    }

    guard indexBuffer.isDynamic else {
        assertionFailure("gs_indexbuffer_flush (Metal): Attempted to flush static index buffer")
        return
    }

    indexBuffer.setupMTLBuffers(data)
}

@_cdecl("gs_indexbuffer_get_data")
public func gs_indexbuffer_get_data(indexBufferPointer: UnsafeRawPointer) -> UnsafeMutableRawPointer? {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(indexBufferPointer).takeUnretainedValue()
    let device = resource.device

    guard let indexBuffer = device.indexBuffers[resource.resourceId] else {
        assertionFailure("gs_indexbuffer_flush (Metal): Invalid index buffer ID provided")
        return nil
    }

    return indexBuffer.indexData
}

@_cdecl("gs_indexbuffer_get_num_indices")
public func gs_indexbuffer_get_num_indices(indexBufferPointer: UnsafeRawPointer) -> Int {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(indexBufferPointer).takeUnretainedValue()
    let device = resource.device

    guard let indexBuffer = device.indexBuffers[resource.resourceId] else {
        assertionFailure("gs_indexbuffer_flush (Metal): Invalid index buffer ID provided")
        return 0
    }

    return indexBuffer.count
}

@_cdecl("gs_indexbuffer_get_type")
public func gs_indexbuffer_get_type(indexBufferPointer: UnsafeRawPointer) -> gs_index_type {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(indexBufferPointer).takeUnretainedValue()
    let device = resource.device

    guard let indexBuffer = device.indexBuffers[resource.resourceId] else {
        preconditionFailure("gs_indexbuffer_flush (Metal): Invalid index buffer ID provided")
    }

    switch indexBuffer.type {
    case .uint16: return GS_UNSIGNED_SHORT
    case .uint32: return GS_UNSIGNED_LONG
    @unknown default:
        fatalError("gs_indexbuffer_get_type (Metal): Unsupported index buffer type \(indexBuffer.type)")
    }
}
