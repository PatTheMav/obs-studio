//
//  OBSIndexBuffer.swift
//  libobs-metal
//
//  Created by Patrick Heyer on 16.04.24.
//

import Foundation
import Metal

class MetalIndexBuffer_OLD {
    let device: MetalDevice

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
        self.isDynamic = dynamic

        if !isDynamic {
            setupMTLBuffers()
        }
    }

    func createOrUpdateBuffer<T>(buffer: inout MTLBuffer?, data: UnsafeMutablePointer<T>, count: Int, dynamic: Bool) {
        let size = MemoryLayout<T>.size * count
        let alignedSize = (size + 15) & ~15

        if dynamic && buffer != nil && buffer!.length == alignedSize {
            buffer!.contents().copyMemory(from: data, byteCount: alignedSize)
        } else {
            buffer = device.device.makeBuffer(
                bytes: data, length: alignedSize, options: [.cpuCacheModeWriteCombined, .storageModeShared])
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

        data.withMemoryRebound(to: UInt8.self, capacity: byteSize) {
            createOrUpdateBuffer(buffer: &indexBuffer, data: $0, count: byteSize, dynamic: isDynamic)
        }

        if !isDynamic {
            indexBuffer?.label = "Index buffer static data"
        } else {
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

@_cdecl("device_indexbuffer_create_OLD")
public func device_indexbuffer_create_OLD(
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

    let retained = Unmanaged.passRetained(indexBuffer).toOpaque()

    return OpaquePointer(retained)
}

@_cdecl("device_load_indexbuffer_OLD")
public func device_load_indexbuffer_OLD(
    devicePointer: UnsafeRawPointer, ibPointer: UnsafeRawPointer?
) {
    let device = Unmanaged<MetalDevice>.fromOpaque(devicePointer).takeUnretainedValue()

    if let ibPointer {
        let indexBuffer = Unmanaged<MetalIndexBuffer>.fromOpaque(ibPointer).takeUnretainedValue()
        device.state.indexBuffer = indexBuffer
    } else {
        device.state.indexBuffer = nil
    }
}

@_cdecl("gs_indexbuffer_destroy_OLD")
public func gs_indexbuffer_destroy_OLD(indexBufferPointer: UnsafeRawPointer) {
    let _ = Unmanaged<MetalIndexBuffer>.fromOpaque(indexBufferPointer).takeRetainedValue()
}

@_cdecl("gs_indexbuffer_flush_OLD")
public func gs_indexbuffer_flush_OLD(indexBufferPointer: UnsafeRawPointer) {
    gs_indexbuffer_flush_direct(indexBufferPointer: indexBufferPointer, data: nil)
}

@_cdecl("gs_indexbuffer_flush_direct_OLD")
public func gs_indexbuffer_flush_direct_OLD(indexBufferPointer: UnsafeRawPointer, data: UnsafeMutableRawPointer?) {
    let indexBuffer = Unmanaged<MetalIndexBuffer>.fromOpaque(indexBufferPointer).takeUnretainedValue()

    indexBuffer.setupMTLBuffers(data)
}

@_cdecl("gs_indexbuffer_get_data_OLD")
public func gs_indexbuffer_get_data_OLD(indexBufferPointer: UnsafeRawPointer) -> UnsafeMutableRawPointer? {
    let indexBuffer = Unmanaged<MetalIndexBuffer>.fromOpaque(indexBufferPointer).takeUnretainedValue()

    return indexBuffer.indexData
}

@_cdecl("gs_indexbuffer_get_num_indices_OLD")
public func gs_indexbuffer_get_num_indices_OLD(indexBufferPointer: UnsafeRawPointer) -> Int {
    let indexBuffer = Unmanaged<MetalIndexBuffer>.fromOpaque(indexBufferPointer).takeUnretainedValue()

    return indexBuffer.count
}

@_cdecl("gs_indexbuffer_get_type_OLD")
public func gs_indexbuffer_get_type_OLD(indexBufferPointer: UnsafeRawPointer) -> gs_index_type {
    let indexBuffer = Unmanaged<MetalIndexBuffer>.fromOpaque(indexBufferPointer).takeUnretainedValue()

    switch indexBuffer.type {
    case .uint16: return GS_UNSIGNED_SHORT
    case .uint32: return GS_UNSIGNED_LONG
    @unknown default:
        fatalError("gs_indexbuffer_get_type (Metal): Unsupported index buffer type \(indexBuffer.type)")
    }
}
