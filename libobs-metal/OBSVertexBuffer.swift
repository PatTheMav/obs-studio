//
//  OBSVertexBuffer.swift
//  libobs-metal
//
//  Created by Patrick Heyer on 16.04.24.
//

import Foundation
import Metal
import simd

class MetalVertexBuffer_OLD {
    var device: MetalDevice

    var vertexData: UnsafeMutablePointer<gs_vb_data>?
    var textureBuffers: [MTLBuffer?]
    var vertexBuffer: MTLBuffer?
    var normalBuffer: MTLBuffer?
    var colorBuffer: MTLBuffer?
    var tangentBuffer: MTLBuffer?

    var isDynamic = false

    init(device: MetalDevice, data: UnsafeMutablePointer<gs_vb_data>, dynamic: Bool) {
        self.device = device
        self.isDynamic = dynamic
        self.vertexData = data
        self.isDynamic = dynamic
        self.textureBuffers = [MTLBuffer?](repeating: nil, count: data.pointee.num_tex)

        if !isDynamic {
            setupMTLBuffers()
        }
    }

    func createOrUpdateBuffer<T>(buffer: inout MTLBuffer?, data: UnsafeMutablePointer<T>, count: Int, dynamic: Bool) {
        let size = MemoryLayout<T>.size * count
        let alignedSize = (size + 15) & ~15

        if dynamic && buffer != nil && buffer!.length == alignedSize {
            buffer!.contents().copyMemory(from: data, byteCount: size)
        } else {
            buffer = device.device.makeBuffer(
                bytes: data, length: alignedSize, options: [.cpuCacheModeWriteCombined, .storageModeShared])
        }
    }

    func setupMTLBuffers(_ data: UnsafeMutablePointer<gs_vb_data>? = nil) {
        guard let data = data ?? vertexData else {
            preconditionFailure("MetalVertexBuffer: Unable to generate MTLBuffer with empty buffer data")
        }

        let numVertices = data.pointee.num
        let normals: UnsafeMutablePointer<vec3>? = data.pointee.normals
        let tangents: UnsafeMutablePointer<vec3>? = data.pointee.tangents
        let colors: UnsafeMutablePointer<UInt32>? = data.pointee.colors

        createOrUpdateBuffer(buffer: &vertexBuffer, data: data.pointee.points, count: numVertices, dynamic: isDynamic)

        vertexBuffer?.label = "Vertex buffer points data"

        if let normals {
            createOrUpdateBuffer(buffer: &normalBuffer, data: normals, count: numVertices, dynamic: isDynamic)
            normalBuffer?.label = "Vertex buffer normals data"
        }

        if let tangents {
            createOrUpdateBuffer(buffer: &tangentBuffer, data: tangents, count: numVertices, dynamic: isDynamic)
            tangentBuffer?.label = "Vertex buffer tangents data"
        }

        if let colors {
            var unpackedColors: [SIMD4<Float>] = []

            for i in 0..<numVertices {
                colors.advanced(by: i).withMemoryRebound(to: UInt8.self, capacity: 4) {
                    let color = SIMD4<Float>(
                        x: Float($0.advanced(by: 0).pointee) / 255.0,
                        y: Float($0.advanced(by: 1).pointee) / 255.0,
                        z: Float($0.advanced(by: 2).pointee) / 255.0,
                        w: Float($0.advanced(by: 3).pointee) / 255.0
                    )

                    unpackedColors.append(color)
                }
            }

            unpackedColors.withUnsafeMutableBufferPointer {
                createOrUpdateBuffer(
                    buffer: &colorBuffer, data: $0.baseAddress!, count: numVertices, dynamic: isDynamic)
            }
            colorBuffer?.label = "Vertex buffer colors data"
        }

        for i in 0..<data.pointee.num_tex {
            let textureVertex: UnsafeMutablePointer<gs_tvertarray>? = data.pointee.tvarray.advanced(by: i)

            if let textureVertex {
                textureVertex.pointee.array.withMemoryRebound(
                    to: Float32.self, capacity: textureVertex.pointee.width * numVertices
                ) {
                    createOrUpdateBuffer(
                        buffer: &textureBuffers[i], data: $0, count: textureVertex.pointee.width * numVertices,
                        dynamic: isDynamic)
                }

                textureBuffers[i]?.label = "Vertex buffer texture uv data (\(i))"
            }
        }
    }

    func getBuffersForShader(shader: MetalShader) -> [MTLBuffer] {
        var bufferList: [MTLBuffer] = []

        for bufferType in shader.bufferOrder {
            switch bufferType {
            case .vertex:
                guard let vertexBuffer else {
                    preconditionFailure("Required vertex buffer points data for vertex shader not found")
                }
                bufferList.append(vertexBuffer)
            case .normal:
                guard let normalBuffer else {
                    preconditionFailure("Required vertex buffer normals data for vertex shader not found")
                }
                bufferList.append(normalBuffer)
            case .tangent:
                guard let tangentBuffer else {
                    preconditionFailure("Required vertex buffer tangents data for vertex shader not found")
                }
                bufferList.append(tangentBuffer)
            case .color:
                guard let colorBuffer else {
                    preconditionFailure("Required vertex buffer color data for vertex shader not found")
                }
                bufferList.append(colorBuffer)
            case .texcoord:
                guard shader.textureCount <= textureBuffers.count else {
                    preconditionFailure("Required amount of texture coordinates for vertex shader not found")
                }

                for i in 0..<shader.textureCount {
                    if let buffer = textureBuffers[i] {
                        bufferList.append(buffer)
                    }
                }
            }
        }

        return bufferList
    }

    deinit {
        gs_vbdata_destroy(vertexData)
    }
}

// MARK: libobs Graphics API

/// Creates a vertex buffer object with the provided vertex data
/// - Parameters:
///   - device: ``OBSGraphicsDevice`` instance for the Metal device
///   - vertexData: `libobs`-internal vertex data object
///   - flags: `libobs`-internal vertex buffer flags
/// - Returns: Opaque pointer of ``MetalResource`` instance with vertex buffer ID and ``OBSGraphicsDevice``
@_cdecl("device_vertexbuffer_create_OLD")
public func device_vertexbuffer_create_OLD(
    devicePointer: UnsafeRawPointer, vertexData: UnsafeMutablePointer<gs_vb_data>, flags: UInt32
) -> OpaquePointer? {
    let device = Unmanaged<MetalDevice>.fromOpaque(devicePointer).takeUnretainedValue()

    let vertexBuffer = MetalVertexBuffer(
        device: device,
        data: vertexData,
        dynamic: (Int32(flags) & GS_DYNAMIC) != 0
    )

    let retained = Unmanaged.passRetained(vertexBuffer).toOpaque()

    return OpaquePointer(retained)
}

/// Removes a vertex buffer object
///
/// The provided ``MetalResource`` instance contains a ``OBSGraphicsDevice`` reference and the ID of the vertex buffer. The buffer will be removed from the ``OBSResource`` collection of vertex buffers.
///
/// - Parameter vertBuffer: Opaque pointer to ``MetalResource`` instance
@_cdecl("gs_vertexbuffer_destroy_OLD")
public func gs_vertexbuffer_destroy_OLD(vertBuffer: UnsafeRawPointer) {
    let _ = Unmanaged<MetalVertexBuffer>.fromOpaque(vertBuffer).takeRetainedValue()
}

/// Load a vertex buffer object
///
/// The provided ``MetalResource`` instance contains the ID of the vertex buffer and will be set as the `currentVertexBuffer` property on the ``OBSGraphicsDevice`` instance. If a NULL pointer is provided as the vertex buffer reference, the `currentVertexBuffer` property is set to `nil` accordingly.
///
/// - Parameters:
///   - device: Opaque pointer to ``MetalRenderer`` instance
///   - vb: Opaque pointer to ``MetalResource`` instance
@_cdecl("device_load_vertexbuffer_OLD")
public func device_load_vertexbuffer_OLD(device: UnsafeRawPointer, vb: UnsafeRawPointer?) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    //    if let vb {
    //        let vertexBuffer = Unmanaged<MetalVertexBuffer>.fromOpaque(vb).takeUnretainedValue()
    //
    //        device.state.vertexBuffer = vertexBuffer
    //    } else {
    //        device.state.vertexBuffer = nil
    //    }
}

/// Flush the vertex buffer data
///
/// The provided ``MetalResource`` instance contains a ``OBSGraphicsDevice`` reference and the ID of the vertex buffer. If a valid ``OBSVertexBuffer`` instance can be found with the provided ID, the vertex buffer's `prepare` method is called without external data to prepare ``MTLBuffer`` objects for the internal vertex buffer data.
///
/// - Parameter vertbuffer: Opaque pointer to ``MetalResource`` instance
@_cdecl("gs_vertexbuffer_flush_OLD")
public func gs_vertexbuffer_flush_OLD(vertbuffer: UnsafeRawPointer) {
    gs_vertexbuffer_flush_direct(vertbuffer: vertbuffer, data: nil)
}

/// Flush the vertex buffer with provided data
///
/// The provided ``MetalResource`` instance contains a ``OBSGraphicsDevice`` reference and the ID of the vertex buffer. If a valid ``OBSVertexBuffer`` instance can be found with the provided ID, the vertex buffer's `prepare` method is called with the provided data (an ``UnsafeMutablePointer`` of `libobs`-specific vertex buffer data) to prepare ``MTLBuffer`` objects.
///
/// - Parameters:
///   - vertbuffer: Opaque pointer to  ``MetalResource`` instance
///   - data: ``UnsafeMutablePointer`` of `libobs` vertex buffer data
@_cdecl("gs_vertexbuffer_flush_direct_OLD")
public func gs_vertexbuffer_flush_direct_OLD(vertbuffer: UnsafeRawPointer, data: UnsafeMutablePointer<gs_vb_data>?) {
    let vertexBuffer = Unmanaged<MetalVertexBuffer>.fromOpaque(vertbuffer).takeUnretainedValue()
    vertexBuffer.setupMTLBuffers(data)
}

/// Get vertex buffer data
///
///  The provided ``MetalResource`` instance contains a ``OBSGraphicsDevice`` reference and the ID of the vertex buffer. If a valid ``OBSVertexBuffer`` instance can be found with the provided ID, a reference to the internal `libobs`-specific vertex buffer data is returned
///
/// - Parameter vertbuffer: Opaque pointer to ``MetalResource`` instance
/// - Returns: Optional ``UnsafeMutablePointer`` of `libobs`-specific vertex buffer data
@_cdecl("gs_vertexbuffer_get_data_OLD")
public func gs_vertexbuffer_get_data_OLD(vertbuffer: UnsafeRawPointer) -> UnsafeMutablePointer<gs_vb_data>? {
    let vertexBuffer = Unmanaged<MetalVertexBuffer>.fromOpaque(vertbuffer).takeUnretainedValue()

    return vertexBuffer.vertexData
}
