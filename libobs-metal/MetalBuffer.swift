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

enum MetalBufferType {
    case vertex
    case index
}

class MetalBuffer {
    enum BufferDataType {
        case vertex
        case normal
        case tangent
        case color
        case texcoord
    }

    private let device: MTLDevice
    fileprivate let isDynamic: Bool

    init(device: MetalDevice, isDynamic: Bool) {
        self.device = device.device
        self.isDynamic = isDynamic
    }

    fileprivate func createOrUpdateBuffer<T>(
        buffer: inout MTLBuffer?, data: UnsafeMutablePointer<T>, count: Int, dynamic: Bool
    ) {
        let size = MemoryLayout<T>.size * count
        let alignedSize = (size + 15) & ~15

        if buffer != nil {
            if dynamic && buffer!.length == alignedSize {
                buffer!.contents().copyMemory(from: data, byteCount: size)
                return
            }
        }

        buffer = device.makeBuffer(
            bytes: data, length: alignedSize, options: [.cpuCacheModeWriteCombined, .storageModeShared])
    }

    func getRetained() -> OpaquePointer {
        let retained = Unmanaged.passRetained(self).toOpaque()

        return OpaquePointer(retained)
    }

    func getUnretained() -> OpaquePointer {
        let unretained = Unmanaged.passUnretained(self).toOpaque()

        return OpaquePointer(unretained)
    }
}

final class MetalVertexBuffer: MetalBuffer {
    public var vertexData: UnsafeMutablePointer<gs_vb_data>?
    private var points: MTLBuffer?
    private var normals: MTLBuffer?
    private var tangents: MTLBuffer?
    private var vertexColors: MTLBuffer?
    private var uvCoordinates: [MTLBuffer?]

    init(device: MetalDevice, data: UnsafeMutablePointer<gs_vb_data>, dynamic: Bool) {
        self.vertexData = data
        self.uvCoordinates = Array(repeating: nil, count: data.pointee.num_tex)

        super.init(device: device, isDynamic: dynamic)

        if !dynamic {
            setupBuffers()
        }
    }

    public func setupBuffers(data: UnsafeMutablePointer<gs_vb_data>? = nil) {
        guard let data = data ?? self.vertexData else {
            preconditionFailure("MetalBuffer: Unable to create MTLBuffers without vertex data")
        }

        let numVertices = data.pointee.num

        createOrUpdateBuffer(buffer: &points, data: data.pointee.points, count: numVertices, dynamic: isDynamic)

        #if DEBUG
            points?.label = "Vertex buffer points data"
        #endif

        if let normalsData = data.pointee.normals {
            createOrUpdateBuffer(buffer: &normals, data: normalsData, count: numVertices, dynamic: isDynamic)

            #if DEBUG
                normals?.label = "Vertex buffer normals data"
            #endif
        }

        if let tangentsData = data.pointee.tangents {
            createOrUpdateBuffer(buffer: &tangents, data: tangentsData, count: numVertices, dynamic: isDynamic)

            #if DEBUG
                tangents?.label = "Vertex buffer tangents data"
            #endif
        }

        if let colorsData = data.pointee.colors {
            var unpackedColors = [SIMD4<Float>]()
            unpackedColors.reserveCapacity(4)

            for i in 0..<numVertices {
                let vertexColor = colorsData.advanced(by: i)

                vertexColor.withMemoryRebound(to: UInt8.self, capacity: 4) {
                    let colorValues = UnsafeBufferPointer<UInt8>(start: $0, count: 4)

                    let color = SIMD4<Float>(
                        x: Float(colorValues[0]) / 255.0,
                        y: Float(colorValues[1]) / 255.0,
                        z: Float(colorValues[2]) / 255.0,
                        w: Float(colorValues[3]) / 255.0
                    )

                    unpackedColors.append(color)
                }
            }

            unpackedColors.withUnsafeMutableBufferPointer {
                createOrUpdateBuffer(
                    buffer: &vertexColors, data: $0.baseAddress!, count: numVertices, dynamic: isDynamic)
            }

            #if DEBUG
                vertexColors?.label = "Vertex buffer colors data"
            #endif
        }

        guard data.pointee.num_tex > 0 else {
            return
        }

        let textureVertices = UnsafeMutableBufferPointer<gs_tvertarray>(
            start: data.pointee.tvarray, count: data.pointee.num_tex)

        for (textureSlot, textureVertex) in textureVertices.enumerated() {
            textureVertex.array.withMemoryRebound(to: Float32.self, capacity: textureVertex.width * numVertices) {
                createOrUpdateBuffer(
                    buffer: &uvCoordinates[textureSlot], data: $0, count: textureVertex.width * numVertices,
                    dynamic: isDynamic)
            }

            #if DEBUG
                uvCoordinates[textureSlot]?.label = "Vertex buffer texture uv data (texture slot \(textureSlot))"
            #endif
        }
    }

    public func getShaderBuffers(shader: MetalShader) -> [MTLBuffer] {
        var bufferList = [MTLBuffer]()

        for bufferType in shader.bufferOrder {
            switch bufferType {
            case .vertex:
                if let points {
                    bufferList.append(points)
                }
            case .normal:
                if let normals { bufferList.append(normals) }
            case .tangent:
                if let tangents { bufferList.append(tangents) }
            case .color:
                if let vertexColors { bufferList.append(vertexColors) }
            case .texcoord:
                guard shader.textureCount == uvCoordinates.count else {
                    assertionFailure(
                        "MetalBuffer: Amount of available texture uv coordinates not sufficient for vertex shader")
                    break
                }

                for i in 0..<shader.textureCount {
                    if let uvCoordinate = uvCoordinates[i] {
                        bufferList.append(uvCoordinate)
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

final class MetalIndexBuffer: MetalBuffer {
    public var indexData: UnsafeMutableRawPointer?
    public var count: Int
    public var type: MTLIndexType

    var indices: MTLBuffer?

    init(device: MetalDevice, type: MTLIndexType, data: UnsafeMutableRawPointer?, count: Int, dynamic: Bool) {
        self.indexData = data
        self.count = count
        self.type = type

        super.init(device: device, isDynamic: dynamic)

        if !dynamic {
            setupBuffers()
        }
    }

    public func setupBuffers(_ data: UnsafeMutableRawPointer? = nil) {
        guard let indexData = data ?? indexData else {
            preconditionFailure("MetalIndexBuffer: Unable to generate MTLBuffer without buffer data")
        }

        let byteSize =
            switch type {
            case .uint16: 2 * count
            case .uint32: 4 * count
            @unknown default:
                fatalError("MTLIndexType \(type) is not supported")
            }

        indexData.withMemoryRebound(to: UInt8.self, capacity: byteSize) {
            createOrUpdateBuffer(buffer: &indices, data: $0, count: byteSize, dynamic: isDynamic)
        }

        #if DEBUG
            if !isDynamic {
                indices?.label = "Index buffer static data"
            } else {
                indices?.label = "Index buffer dynamic data"
            }
        #endif
    }

    deinit {
        bfree(indexData)
    }
}
