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

class MetalShader {
    class ShaderUniform {
        let name: String
        let gsType: gs_shader_param_type
        fileprivate let textureSlot: Int
        var samplerState: MTLSamplerState?
        fileprivate let byteOffset: Int

        var currentValues: [UInt8]?
        var defaultValues: [UInt8]?
        fileprivate var hasUpdates: Bool

        init(
            name: String, gsType: gs_shader_param_type, textureSlot: Int, samplerState: MTLSamplerState?,
            byteOffset: Int
        ) {
            self.name = name
            self.gsType = gsType

            self.textureSlot = textureSlot
            self.samplerState = samplerState
            self.byteOffset = byteOffset
            self.currentValues = nil
            self.defaultValues = nil
            self.hasUpdates = false
        }

        public func setParameter<T>(data: UnsafePointer<T>?, size: Int) {
            guard let data else {
                assertionFailure(
                    "MetalShader.ShaderUniform: Attempted to set a shader parameter with an empty data pointer")
                return
            }

            data.withMemoryRebound(to: UInt8.self, capacity: size) {
                self.currentValues = Array(UnsafeBufferPointer<UInt8>(start: $0, count: size))
            }

            hasUpdates = true
        }
    }

    struct ShaderData {
        let uniforms: [ShaderUniform]
        let bufferOrder: [MetalBuffer.BufferDataType]

        let vertexDescriptor: MTLVertexDescriptor?
        let samplerDescriptors: [MTLSamplerDescriptor]?

        let bufferSize: Int
        let textureCount: Int
    }

    private let device: MetalDevice
    let source: String
    private var uniformData: [UInt8]
    private var uniformSize: Int
    private var uniformBuffer: MTLBuffer?

    private let library: MTLLibrary
    let function: MTLFunction
    var uniforms: [ShaderUniform]
    var vertexDescriptor: MTLVertexDescriptor?
    var textureCount = 0
    var samplers: [MTLSamplerState]?

    let type: MTLFunctionType
    let bufferOrder: [MetalBuffer.BufferDataType]

    init?(device: MetalDevice, source: String, type: MTLFunctionType, data: ShaderData) {
        self.device = device
        self.source = source
        self.type = type
        self.uniforms = data.uniforms
        self.bufferOrder = data.bufferOrder
        self.uniformSize =
            if (data.bufferSize & 15) != 0 {
                (data.bufferSize + 15) & ~15
            } else {
                data.bufferSize
            }
        self.uniformData = [UInt8](repeating: 0, count: self.uniformSize)
        self.textureCount = data.textureCount

        switch type {
        case .vertex:
            guard let descriptor = data.vertexDescriptor else {
                assertionFailure("MetalShader: Attempted to create vertex shader without vertex descriptor")
                return nil
            }

            self.vertexDescriptor = descriptor
        case .fragment:
            guard let samplerDescriptors = data.samplerDescriptors else {
                assertionFailure("MetalShader: Attempted to create fragment shader without sampler descriptors")
                return nil
            }

            var samplers = [MTLSamplerState]()
            samplers.reserveCapacity(samplerDescriptors.count)

            for descriptor in samplerDescriptors {
                guard let samplerState = device.makeSamplerState(descriptor: descriptor) else {
                    assertionFailure("MetalShader: Failed to create sampler state with descriptor")
                    return nil
                }

                samplers.append(samplerState)
            }

            self.samplers = samplers
        default:
            preconditionFailure("MetalShader: Unsupported shader type \(type)")
        }

        guard let library = device.makeShaderLibrary(source: source, options: nil) else {
            assertionFailure("MetalShader: Failed to create shader library")
            return nil
        }

        guard let function = library.makeFunction(name: "_main") else {
            assertionFailure("MetalShader: Failed to create shader '_main' function")
            return nil
        }

        self.library = library
        self.function = function
    }

    private func updateUniform(uniform: inout ShaderUniform) {
        guard let currentValues = uniform.currentValues else {
            return
        }

        if uniform.gsType == GS_SHADER_PARAM_TEXTURE {
            let shaderTexture = currentValues.withUnsafeBufferPointer {
                $0.baseAddress?.withMemoryRebound(to: gs_shader_texture.self, capacity: 1) {
                    $0.pointee.tex
                }
            }

            if let shaderTexture {
                let texture = Unmanaged<MetalTexture>.fromOpaque(UnsafeRawPointer(shaderTexture)).takeUnretainedValue()

                device.renderState.textures[uniform.textureSlot] = texture.texture
            }

            if let samplerState = uniform.samplerState {
                device.renderState.samplers[uniform.textureSlot] = samplerState
                uniform.samplerState = nil
            }
        } else {
            if uniform.hasUpdates {
                let startIndex = uniform.byteOffset
                let endIndex = uniform.byteOffset + currentValues.count

                uniformData.replaceSubrange(startIndex..<endIndex, with: currentValues)
            }
        }

        uniform.hasUpdates = false
    }

    private func createOrUpdateBuffer(buffer: inout MTLBuffer?, data: inout [UInt8]) {
        let size = MemoryLayout<UInt8>.size * data.count
        let alignedSize = (size + 0x0F) & ~0x0F

        if buffer != nil {
            if buffer!.length == alignedSize {
                buffer!.contents().copyMemory(from: data, byteCount: size)
                return
            }
        }

        buffer = device.makeBuffer(bytes: data, length: alignedSize)
    }

    func uploadShaderParameters(encoder: MTLRenderCommandEncoder) {
        for var uniform in uniforms {
            updateUniform(uniform: &uniform)
        }

        guard uniformSize > 0 else {
            return
        }

        switch function.functionType {
        case .vertex:
            switch uniformData.count {
            case 0..<4096: encoder.setVertexBytes(&uniformData, length: uniformData.count, index: 30)
            default:
                createOrUpdateBuffer(buffer: &uniformBuffer, data: &uniformData)
                #if DEBUG
                    uniformBuffer?.label = "Vertex shader uniform buffer"
                #endif
                encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 30)
            }
        case .fragment:
            switch uniformData.count {
            case 0..<4096: encoder.setFragmentBytes(&uniformData, length: uniformData.count, index: 30)
            default:
                createOrUpdateBuffer(buffer: &uniformBuffer, data: &uniformData)
                #if DEBUG
                    uniformBuffer?.label = "Fragment shader uniform buffer"
                #endif
                encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 30)
            }
        default:
            fatalError("MetalShader: Unsupported shader type \(function.functionType)")
        }
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
