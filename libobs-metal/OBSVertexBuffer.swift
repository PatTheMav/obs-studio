//
//  OBSVertexBuffer.swift
//  libobs-metal
//
//  Created by Patrick Heyer on 16.04.24.
//

import Foundation
import Metal
import simd

class MetalVertexBuffer {
    var device: MetalDevice

    var vertexData: UnsafeMutablePointer<gs_vb_data>?
    var textureBuffers: [MTLBuffer?] = []
    var vertexBuffer: MTLBuffer?
    var normalBuffer: MTLBuffer?
    var colorBuffer: MTLBuffer?
    var tangentBuffer: MTLBuffer?

    var isDynamic = false

    init(device: MetalDevice, data: UnsafeMutablePointer<gs_vb_data>, dynamic: Bool) {
        self.device = device
        self.isDynamic = dynamic
        self.vertexData = data

        if !isDynamic {
            setupMTLBuffers()
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

        let options: MTLResourceOptions

        if !isDynamic {
            options = [.cpuCacheModeWriteCombined, .storageModeManaged]

            vertexBuffer = device.device.makeBuffer(
                bytes: data.pointee.points,
                length: MemoryLayout<vec3>.size * numVertices,
                options: options
            )
        } else {
            options = [.cpuCacheModeWriteCombined, .storageModeShared]

            vertexBuffer = device.getBufferForSize(MemoryLayout<vec3>.size * numVertices)
            vertexBuffer?.contents().copyMemory(
                from: data.pointee.points, byteCount: MemoryLayout<vec3>.size * numVertices)
        }

        vertexBuffer?.label = "Vertex buffer points data"

        if let normals {
            if !isDynamic {
                normalBuffer = device.device.makeBuffer(
                    bytes: normals,
                    length: MemoryLayout<vec3>.size * numVertices,
                    options: options)
            } else {
                normalBuffer = device.getBufferForSize(MemoryLayout<vec3>.size * numVertices)
                normalBuffer?.contents().copyMemory(
                    from: data.pointee.normals, byteCount: MemoryLayout<vec3>.size * numVertices)
            }

            normalBuffer?.label = "Vertex buffer normals data"
        }

        if let tangents {
            if !isDynamic {
                tangentBuffer = device.device.makeBuffer(
                    bytes: tangents,
                    length: MemoryLayout<vec3>.size * numVertices,
                    options: options)
            } else {
                tangentBuffer = device.getBufferForSize(MemoryLayout<vec3>.size * numVertices)
                tangentBuffer?.contents().copyMemory(
                    from: data.pointee.tangents, byteCount: MemoryLayout<vec3>.size * numVertices)
            }

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

            if !isDynamic {
                colorBuffer = device.device.makeBuffer(
                    bytes: unpackedColors,
                    length: MemoryLayout<SIMD4<Float>>.size * numVertices,
                    options: options)
            } else {
                colorBuffer = device.getBufferForSize(MemoryLayout<SIMD4<Float>>.size * numVertices)
                colorBuffer?.contents().copyMemory(
                    from: unpackedColors, byteCount: MemoryLayout<SIMD4<Float>>.size * numVertices)
            }

            colorBuffer?.label = "Vertex buffer colors data"
        }

        textureBuffers = []

        for i in 0..<data.pointee.num_tex {
            let textureVertex: UnsafeMutablePointer<gs_tvertarray>? = data.pointee.tvarray.advanced(by: i)

            if let textureVertex {
                let textureBuffer: MTLBuffer?

                if !isDynamic {
                    textureBuffer = device.device.makeBuffer(
                        bytes: textureVertex.pointee.array,
                        length: MemoryLayout<Float32>.size * textureVertex.pointee.width * numVertices,
                        options: options)
                } else {
                    textureBuffer = device.getBufferForSize(
                        MemoryLayout<Float32>.size * textureVertex.pointee.width * numVertices)

                    guard let textureBuffer else {
                        preconditionFailure("MetalVertexBuffer: Failed to create MTLBuffer texture uv data (\(i))")
                    }

                    textureBuffer.contents().copyMemory(
                        from: textureVertex.pointee.array,
                        byteCount: MemoryLayout<Float32>.size * textureVertex.pointee.width * numVertices)
                }

                textureBuffer?.label = "Vertex buffer texture uv data (\(i))"
                textureBuffers.append(textureBuffer)
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
@_cdecl("device_vertexbuffer_create")
public func device_vertexbuffer_create(
    devicePointer: UnsafeRawPointer, vertexData: UnsafeMutablePointer<gs_vb_data>, flags: UInt32
) -> OpaquePointer? {
    let device = Unmanaged<MetalDevice>.fromOpaque(devicePointer).takeUnretainedValue()

    let vertexBuffer = MetalVertexBuffer(
        device: device,
        data: vertexData,
        dynamic: (Int32(flags) & GS_DYNAMIC) != 0
    )

    let vertexBufferId = device.vertexBuffers.insert(vertexBuffer)
    let resource = OBSAPIResource(device: device, resourceId: vertexBufferId)

    return resource.getRetained()
}

/// Removes a vertex buffer object
///
/// The provided ``MetalResource`` instance contains a ``OBSGraphicsDevice`` reference and the ID of the vertex buffer. The buffer will be removed from the ``OBSResource`` collection of vertex buffers.
///
/// - Parameter vertBuffer: Opaque pointer to ``MetalResource`` instance
@_cdecl("gs_vertexbuffer_destroy")
public func gs_vertexbuffer_destroy(vertBuffer: UnsafeRawPointer) {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(vertBuffer).takeRetainedValue()
    let device = resource.device

    device.vertexBuffers.remove(resource.resourceId)
}

/// Load a vertex buffer object
///
/// The provided ``MetalResource`` instance contains the ID of the vertex buffer and will be set as the `currentVertexBuffer` property on the ``OBSGraphicsDevice`` instance. If a NULL pointer is provided as the vertex buffer reference, the `currentVertexBuffer` property is set to `nil` accordingly.
///
/// - Parameters:
///   - device: Opaque pointer to ``MetalRenderer`` instance
///   - vb: Opaque pointer to ``MetalResource`` instance
@_cdecl("device_load_vertexbuffer")
public func device_load_vertexbuffer(device: UnsafeRawPointer, vb: UnsafeRawPointer?) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    if let vb {
        let resource = Unmanaged<OBSAPIResource>.fromOpaque(vb).takeUnretainedValue()

        guard let vertexBuffer = device.vertexBuffers[resource.resourceId] else {
            assertionFailure("device_load_vertexbuffer (Metal): Invalid vertex buffer ID provided")
            return
        }

        device.state.vertexBuffer = vertexBuffer
    } else {
        device.state.vertexBuffer = nil
    }
}

/// Flush the vertex buffer data
///
/// The provided ``MetalResource`` instance contains a ``OBSGraphicsDevice`` reference and the ID of the vertex buffer. If a valid ``OBSVertexBuffer`` instance can be found with the provided ID, the vertex buffer's `prepare` method is called without external data to prepare ``MTLBuffer`` objects for the internal vertex buffer data.
///
/// - Parameter vertbuffer: Opaque pointer to ``MetalResource`` instance
@_cdecl("gs_vertexbuffer_flush")
public func gs_vertexbuffer_flush(vertbuffer: UnsafeRawPointer) {
    gs_vertexbuffer_flush_direct(vertbuffer: vertbuffer, data: nil)
}

/// Flush the vertex buffer with provided data
///
/// The provided ``MetalResource`` instance contains a ``OBSGraphicsDevice`` reference and the ID of the vertex buffer. If a valid ``OBSVertexBuffer`` instance can be found with the provided ID, the vertex buffer's `prepare` method is called with the provided data (an ``UnsafeMutablePointer`` of `libobs`-specific vertex buffer data) to prepare ``MTLBuffer`` objects.
///
/// - Parameters:
///   - vertbuffer: Opaque pointer to  ``MetalResource`` instance
///   - data: ``UnsafeMutablePointer`` of `libobs` vertex buffer data
@_cdecl("gs_vertexbuffer_flush_direct")
public func gs_vertexbuffer_flush_direct(vertbuffer: UnsafeRawPointer, data: UnsafeMutablePointer<gs_vb_data>?) {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(vertbuffer).takeUnretainedValue()
    let device = resource.device

    guard let vertexBuffer = device.vertexBuffers[resource.resourceId] else {
        assertionFailure("device_vertexbuffer_flush_direct (Metal): Invalid vertex buffer ID provided")
        return
    }

    guard vertexBuffer.isDynamic else {
        assertionFailure("device_vertexbuffer_flush_direct (Metal): Attempted to flush a static vertex buffer")
        return
    }

    vertexBuffer.setupMTLBuffers(data)
}

/// Get vertex buffer data
///
///  The provided ``MetalResource`` instance contains a ``OBSGraphicsDevice`` reference and the ID of the vertex buffer. If a valid ``OBSVertexBuffer`` instance can be found with the provided ID, a reference to the internal `libobs`-specific vertex buffer data is returned
///
/// - Parameter vertbuffer: Opaque pointer to ``MetalResource`` instance
/// - Returns: Optional ``UnsafeMutablePointer`` of `libobs`-specific vertex buffer data
@_cdecl("gs_vertexbuffer_get_data")
public func gs_vertexbuffer_get_data(vertbuffer: UnsafeRawPointer) -> UnsafeMutablePointer<gs_vb_data>? {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(vertbuffer).takeUnretainedValue()
    let device = resource.device

    guard let vertexBuffer = device.vertexBuffers[resource.resourceId] else {
        assertionFailure("device_vertexbuffer_get_data (Metal): Invalid vertex buffer ID provided")
        return nil
    }

    return vertexBuffer.vertexData
}
