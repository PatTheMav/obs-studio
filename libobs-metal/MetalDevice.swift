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

import AppKit
import Foundation
import Metal
import simd

class MetalDevice {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private var pipelines = [Int: MTLRenderPipelineState]()

    private let identityMatrix: matrix_float4x4
    private let fallbackVertexBuffer: MTLBuffer

    var renderState: MetalRenderState
    var requiresSync: Bool = false

    private var displayLink: CVDisplayLink?

    init(device: MTLDevice) {
        self.device = device

        guard let commandQueue = device.makeCommandQueue() else {
            preconditionFailure("MetalDevice: Failed to create command queue")
        }

        self.commandQueue = commandQueue

        identityMatrix = matrix_float4x4.init(diagonal: SIMD4(1.0, 1.0, 1.0, 1.0))

        guard let buffer = device.makeBuffer(length: 1, options: .storageModePrivate) else {
            preconditionFailure("MetalDevice: Failed to create fallback vertex buffer")
        }

        fallbackVertexBuffer = buffer

        renderState = MetalRenderState(
            viewMatrix: identityMatrix,
            viewProjectionMatrix: identityMatrix,
            projectionMatrix: identityMatrix,
            renderTarget: nil,
            textures: [],
            samplers: [],
            commandBuffer: nil,
            clearState: nil,
            viewPort: MTLViewport(),
            cullMode: .none,
            scissorRectEnabled: false,
            scissorRect: nil,
            gsColorSpace: GS_CS_SRGB
        )

        renderState.pipelineDescriptor = MTLRenderPipelineDescriptor()
        renderState.renderPassDescriptor = MTLRenderPassDescriptor()
        renderState.depthStencilDescriptor = MTLDepthStencilDescriptor()

        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)

        guard let displayLink else {
            preconditionFailure("MetalDevice: Failed to set up display link")
        }

        func enableSync(data: UnsafeMutableRawPointer?) {
            guard let data else { return }
            let metalDevice = unsafeBitCast(data, to: MetalDevice.self)

            metalDevice.requiresSync = true
        }

        func displayLinkCallback(
            displayLink: CVDisplayLink, _ now: UnsafePointer<CVTimeStamp>, _ outputTime: UnsafePointer<CVTimeStamp>,
            _ flagsIn: CVOptionFlags, _ flagsOut: UnsafeMutablePointer<CVOptionFlags>,
            _ displayLinkContext: UnsafeMutableRawPointer?
        ) -> CVReturn {

            guard obs_initialized() else { return kCVReturnSuccess }

            obs_queue_task(OBS_TASK_GRAPHICS, enableSync, displayLinkContext, false)

            return kCVReturnSuccess
        }

        let opaqueSelf = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkSetOutputCallback(displayLink, displayLinkCallback, opaqueSelf)
        CVDisplayLinkStart(displayLink)
    }

    func makeCommandBuffer() {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            preconditionFailure("MetalDevice: Unable to create command buffer")
        }

        renderState.commandBuffer = commandBuffer
    }

    func makeLayer() -> CAMetalLayer {
        let layer = CAMetalLayer()
        layer.device = device
        //layer.displaySyncEnabled = false

        return layer
    }

    func makeShaderLibrary(source: String, options: MTLCompileOptions?) -> MTLLibrary? {
        do {
            let library = try device.makeLibrary(source: source, options: options)

            return library
        } catch {
            return nil
        }
    }

    func draw(primitiveType: MTLPrimitiveType, vertexStart: Int, vertexCount: Int) {
        guard renderState.commandBuffer != nil else {
            return
        }

        guard let renderTarget = renderState.renderTarget else {
            return
        }

        guard renderState.vertexBuffer != nil || vertexCount > 0 else {
            //        guard let vertexBuffer = renderState.vertexBuffer else {
            assertionFailure("MetalDevice: Attempted to render without a vertex buffer set")
            return
        }

        guard let vertexShader = renderState.vertexShader else {
            assertionFailure("MetalDevice: Attempted to render without vertex shader set")
            return
        }

        guard let fragmentShader = renderState.fragmentShader else {
            assertionFailure("MetalDevice: Attempted to render without fragment shader set")
            return
        }

        guard let renderPipelineDescriptor = renderState.pipelineDescriptor else {
            assertionFailure("MetalDevice: Unable to create render pipeline state without pipeline descriptor")
            return
        }

        guard let renderPassDescriptor = renderState.renderPassDescriptor else {
            assertionFailure("MetalDevice: Unable to create command encoder without render pass descriptor")
            return
        }

        if renderState.updateRenderTarget {
            if renderState.srgbState && renderTarget.sRGBtexture != nil {
                renderPipelineDescriptor.colorAttachments[0].pixelFormat = renderTarget.sRGBtexture!.pixelFormat
                renderPassDescriptor.colorAttachments[0].texture = renderTarget.sRGBtexture!
            } else {
                renderPipelineDescriptor.colorAttachments[0].pixelFormat = renderTarget.texture.pixelFormat
                renderPassDescriptor.colorAttachments[0].texture = renderTarget.texture
            }

            if let zstencilAttachment = renderState.stencilAttachment {
                renderPipelineDescriptor.depthAttachmentPixelFormat = zstencilAttachment.texture.pixelFormat
                renderPipelineDescriptor.stencilAttachmentPixelFormat = zstencilAttachment.texture.pixelFormat
                renderPassDescriptor.depthAttachment.texture = zstencilAttachment.texture
                renderPassDescriptor.stencilAttachment.texture = zstencilAttachment.texture
            } else {
                renderPipelineDescriptor.depthAttachmentPixelFormat = .invalid
                renderPipelineDescriptor.stencilAttachmentPixelFormat = .invalid
                renderPassDescriptor.depthAttachment.texture = nil
                renderPassDescriptor.stencilAttachment.texture = nil

            }
        }

        let stateHash = renderState.pipelineDescriptor.hashValue

        var renderPipelineState = pipelines[stateHash]

        if renderPipelineState == nil {
            do {
                renderPipelineState = try device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)

                pipelines.updateValue(renderPipelineState!, forKey: stateHash)
            } catch {
                assertionFailure("MetalDevice: Failed to create render pipeline state")
                return
            }
        }

        if let clearState = renderState.clearState {
            if clearState.colorAction == .clear {
                renderPassDescriptor.colorAttachments[0].loadAction = .clear
                renderPassDescriptor.colorAttachments[0].clearColor = clearState.clearColor
            } else {
                renderPassDescriptor.colorAttachments[0].loadAction = clearState.colorAction
            }

            if clearState.depthAction == .clear {
                renderPassDescriptor.depthAttachment.loadAction = .clear
                renderPassDescriptor.depthAttachment.clearDepth = clearState.clearDepth
            } else {
                renderPassDescriptor.depthAttachment.loadAction = clearState.depthAction
            }

            if clearState.stencilAction == .clear {
                renderPassDescriptor.stencilAttachment.loadAction = .clear
                renderPassDescriptor.stencilAttachment.clearStencil = clearState.clearStencil
            } else {
                renderPassDescriptor.stencilAttachment.loadAction = clearState.stencilAction
            }

            renderState.clearState = nil
        } else {
            renderPassDescriptor.colorAttachments[0].loadAction = .load
            renderPassDescriptor.depthAttachment.loadAction = .load
            renderPassDescriptor.stencilAttachment.loadAction = .load
        }

        guard let commandEncoder = renderState.commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else {
            assertionFailure("MetalDevice: Unable to create render command encoder")
            return
        }

        commandEncoder.setRenderPipelineState(renderPipelineState!)

        if let effect: OpaquePointer = gs_get_effect() {
            gs_effect_update_params(effect)
        }

        commandEncoder.setViewport(renderState.viewPort)
        commandEncoder.setFrontFacing(.counterClockwise)
        commandEncoder.setCullMode(renderState.cullMode)

        if let scissorRect = renderState.scissorRect, renderState.scissorRectEnabled {
            commandEncoder.setScissorRect(scissorRect)
        }

        guard let depthStencilDescriptor = renderState.depthStencilDescriptor else {
            assertionFailure("MetalDevice: No depth stencil descriptor")
            return
        }

        let depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)
        commandEncoder.setDepthStencilState(depthStencilState)

        var gsViewMatrix: matrix4 = matrix4()
        gs_matrix_get(&gsViewMatrix)

        let viewMatrix = matrix_float4x4(
            rows: [
                SIMD4(gsViewMatrix.x.x, gsViewMatrix.x.y, gsViewMatrix.x.z, gsViewMatrix.x.w),
                SIMD4(gsViewMatrix.y.x, gsViewMatrix.y.y, gsViewMatrix.y.z, gsViewMatrix.y.w),
                SIMD4(gsViewMatrix.z.x, gsViewMatrix.z.y, gsViewMatrix.z.z, gsViewMatrix.z.w),
                SIMD4(gsViewMatrix.t.x, gsViewMatrix.t.y, gsViewMatrix.t.z, gsViewMatrix.t.w),
            ]
        )

        renderState.viewProjectionMatrix = (viewMatrix * renderState.projectionMatrix)

        if let viewProjectionUniform = vertexShader.uniforms.filter({ $0.name == "ViewProj" }).first {
            viewProjectionUniform.setParameter(
                data: &renderState.viewProjectionMatrix, size: MemoryLayout<matrix_float4x4>.size)
        }

        vertexShader.uploadShaderParameters(encoder: commandEncoder)
        fragmentShader.uploadShaderParameters(encoder: commandEncoder)

        if renderState.vertexBuffer == nil {
            commandEncoder.setVertexBuffers([fallbackVertexBuffer], offsets: [0], range: 0..<1)
        } else {
            let vertexBuffers = renderState.vertexBuffer!.getShaderBuffers(shader: vertexShader)
            let offsets = Array(repeating: 0, count: vertexBuffers.count)

            commandEncoder.setVertexBuffers(
                vertexBuffers,
                offsets: offsets,
                range: 0..<vertexBuffers.count
            )
        }

        //        let vertexBuffers = vertexBuffer.getShaderBuffers(shader: vertexShader)

        for (index, texture) in renderState.textures.enumerated() {
            if let texture {
                commandEncoder.setFragmentTexture(texture, index: index)
            }
        }

        for (index, samplerState) in renderState.samplers.enumerated() {
            if let samplerState {
                commandEncoder.setFragmentSamplerState(samplerState, index: index)
            }
        }

        if let indexBuffer = renderState.indexBuffer, let bufferData = indexBuffer.indices {
            commandEncoder.drawIndexedPrimitives(
                type: primitiveType,
                indexCount: (vertexCount > 0) ? vertexCount : indexBuffer.count,
                indexType: indexBuffer.type,
                indexBuffer: bufferData,
                indexBufferOffset: 0
            )
        } else {
            if renderState.vertexBuffer == nil {
                commandEncoder.drawPrimitives(
                    type: primitiveType,
                    vertexStart: vertexStart,
                    vertexCount: vertexCount)
            } else {
                guard let vertexData = renderState.vertexBuffer!.vertexData else {
                    assertionFailure("MetalDevice: No vertex count provided and vertex buffer has no vertex data")
                    return
                }

                commandEncoder.drawPrimitives(
                    type: primitiveType,
                    vertexStart: vertexStart,
                    vertexCount: vertexData.pointee.num)
            }
        }

        commandEncoder.endEncoding()
    }

    func shutdown() {
        guard let displayLink else { return }

        CVDisplayLinkStop(displayLink)
        self.displayLink = nil
    }

    deinit {
        shutdown()
    }
}
