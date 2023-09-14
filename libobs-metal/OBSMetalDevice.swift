//
//  OBSMetalDevice.swift
//  libobs-metal
//
//  Created by Patrick Heyer on 16.04.24.
//

import AppKit
import Foundation
import Metal
import simd

struct MetalState {
    struct MetalLayer {
        let layer: CAMetalLayer
        let view: NSView
        var nextDrawable: CAMetalDrawable?
        var textureId: Int?
    }

    struct ClearState {
        var colorAction: MTLLoadAction
        var depthAction: MTLLoadAction
        var stencilAction: MTLLoadAction
        var clearColor: MTLClearColor?
        var clearDepth: Double
        var clearStencil: UInt32
        var clearTargetId: Int
    }

    var viewMatrix: matrix_float4x4
    var viewProjectionMatrix: matrix_float4x4
    var projectionMatrix: matrix_float4x4

    var renderTarget: MTLTexture?
    var renderTargetId = 0
    var vertexBuffer: MetalVertexBuffer?
    var indexBuffer: MetalIndexBuffer?
    var depthAttachment: MTLTexture?
    var stencilAttachment: MTLTexture?

    var renderPipelineDescriptor = MTLRenderPipelineDescriptor()
    var renderPassDescriptor = MTLRenderPassDescriptor()
    var commandBuffer: MTLCommandBuffer?

    var textures: [MTLTexture?]
    var samplers: [MTLSamplerState?]

    var vertexShader: MetalShader? = nil
    var vertexShaderId: Int = 0
    var fragmentShader: MetalShader? = nil
    var fragmentShaderId: Int = 0

    var storeAction: MTLStoreAction = .store
    var loadAction: MTLLoadAction = .load

    var clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
    var clearDepth = 0.0
    var clearStencil: UInt32 = 0
    var clearTargetId = 0

    var clearState: ClearState?

    var colorLoadAction: MTLLoadAction = .load
    var depthLoadAction: MTLLoadAction = .load
    var stencilLoadAction: MTLLoadAction = .load

    var cullMode: MTLCullMode = .back
    var scissorEnabled = false
    var viewPort = MTLViewport()
    var scissorRect = MTLScissorRect()

    var depthTestEnabled = false
    var depthWriteEnabled = false
    var stencilTestEnabled = false
    var stencilWriteTestEnabled = false

    var depthStencilDescriptor = MTLDepthStencilDescriptor()

    var gsColorSpace: gs_color_space = GS_CS_SRGB

    var layerId: Int?
    var nextDrawable: CAMetalDrawable?

    var numDraws = 0
}

class MetalDevice {
    typealias MetalLayer = MetalState.MetalLayer

    var device: MTLDevice
    var commandQueue: MTLCommandQueue

    var renderPipelines: [Int: MTLRenderPipelineState]
    var state: MetalState
    var priorState: MetalState?

    var textures = OBSResourceCollection<MTLTexture>(64)
    var samplerStates = OBSResourceCollection<MTLSamplerState>(64)
    var surfaces = OBSResourceCollection<(NSView, CAMetalLayer)>(8)
    var shaders = OBSResourceCollection<MetalShader>(64)
    var layers = OBSResourceCollection<MetalLayer>(8)

    var currentBuffers = [MTLBuffer]()
    var availableBuffers = [MTLBuffer]()
    var bufferPools = BufferQueue<[MTLBuffer]>()
    var projectionStack = BufferQueue<matrix_float4x4>()
    var clearStates = BufferQueue<MetalState.ClearState>()

    var vertexBuffers = OBSResourceCollection<MetalVertexBuffer>(16)
    var indexBuffers = OBSResourceCollection<MetalIndexBuffer>(16)

    var queue: DispatchQueue

    init(device: MTLDevice) {
        self.device = device
        self.renderPipelines = [:]

        guard let commandQueue = device.makeCommandQueue() else {
            preconditionFailure("MTLDevice: Failed to create MTLCommandQueue")
        }

        self.commandQueue = commandQueue
        if #available(macOS 14.0, *) {
            self.queue = DispatchSerialQueue(label: "libobs-metal-serial.queue", qos: .userInteractive)
        } else {
            self.queue = DispatchQueue(label: "libobs-metal-serial.queue")
        }

        let identity = matrix_float4x4.init(diagonal: SIMD4(1.0, 1.0, 1.0, 1.0))

        self.state = MetalState(
            viewMatrix: identity,
            viewProjectionMatrix: identity,
            projectionMatrix: identity,
            renderTarget: nil,
            vertexBuffer: nil,
            commandBuffer: nil,
            textures: [],
            samplers: []
        )

        self.bufferPools.push([MTLBuffer]())
        self.bufferPools.push([MTLBuffer]())
    }

    func setRenderTarget(_ texture: MTLTexture, stencilBuffer: MTLTexture?, pixelFormat: MTLPixelFormat?) {
        guard texture.textureType == .type2D else {
            OBSLog(.error, "setRenderTarget (Metal): Provided texture is not a 2D texture")
            return
        }

        state.renderTarget = texture

        if let stencilBuffer {
            state.depthAttachment = stencilBuffer
            state.stencilAttachment = stencilBuffer
            state.storeAction = .store
        }
    }

    func draw(primitiveType: MTLPrimitiveType, vertexStart: Int, vertexCount: Int) {
        guard state.commandBuffer != nil else {  // TODO: Figure out what to do when draw calls are initiated before begin_scene was called
            return
        }

        guard let vertexBuffer = state.vertexBuffer else {
            preconditionFailure("MetalDevice (Draw): No vertex buffer set")
        }

        guard let vertexShader = state.vertexShader else {
            preconditionFailure("MetalDevice (Draw): No vertex shader set")
        }

        guard let fragmentShader = state.fragmentShader else {
            preconditionFailure("MetalDevice (Draw): No fragment shader set")
        }

        let stateHash = state.renderPipelineDescriptor.hashValue

        var renderPipelineState = renderPipelines[stateHash]

        if renderPipelineState == nil {
            do {
                renderPipelineState = try device.makeRenderPipelineState(descriptor: state.renderPipelineDescriptor)

                renderPipelines[stateHash] = renderPipelineState
            } catch {
                preconditionFailure(
                    "MetalDevice: Failed to create render pipeline state: \(error.localizedDescription)")
            }
        }

        if state.clearTargetId != state.renderTargetId {
            state.renderPassDescriptor.colorAttachments[0].loadAction = .load
            state.renderPassDescriptor.depthAttachment.loadAction = .load
            state.renderPassDescriptor.stencilAttachment.loadAction = .load
        } else if let clearState = clearStates.pop() {
            if clearState.colorAction == .clear {
                state.renderPassDescriptor.colorAttachments[0].loadAction = .clear

                guard let clearColor = clearState.clearColor else {
                    preconditionFailure(
                        "MetalDevice (draw): Attempted to add loadAction of type 'clear' without a clear color")
                }

                state.renderPassDescriptor.colorAttachments[0].clearColor = clearColor
            } else {
                state.renderPassDescriptor.colorAttachments[0].loadAction = .load
            }

            if clearState.depthAction == .clear {
                state.renderPassDescriptor.depthAttachment.loadAction = .clear
                state.renderPassDescriptor.depthAttachment.clearDepth = clearState.clearDepth
            } else {
                state.renderPassDescriptor.depthAttachment.loadAction = .load
            }

            if clearState.stencilAction == .clear {
                state.renderPassDescriptor.stencilAttachment.loadAction = .clear
                state.renderPassDescriptor.stencilAttachment.clearStencil = clearState.clearStencil
            } else {
                state.renderPassDescriptor.stencilAttachment.loadAction = .load
            }

            if let nextClearState = clearStates.head {
                state.clearTargetId = nextClearState.clearTargetId
            } else {
                state.clearTargetId = 0
            }
        }

        guard let commandEncoder = state.commandBuffer?.makeRenderCommandEncoder(descriptor: state.renderPassDescriptor)
        else {
            assertionFailure("MetalDevice: Unable to create render command encoder")
            return
        }

        commandEncoder.setRenderPipelineState(renderPipelineState!)

        if let effect: OpaquePointer = gs_get_effect() {
            gs_effect_update_params(effect)
        }

        commandEncoder.setViewport(state.viewPort)
        commandEncoder.setFrontFacing(.counterClockwise)
        commandEncoder.setCullMode(state.cullMode)

        if state.scissorEnabled {
            commandEncoder.setScissorRect(state.scissorRect)
        }

        let depthStencilState = device.makeDepthStencilState(descriptor: state.depthStencilDescriptor)
        commandEncoder.setDepthStencilState(depthStencilState)

        var gsViewmatrix: matrix4 = matrix4()
        gs_matrix_get(&gsViewmatrix)

        let viewMatrix = matrix_float4x4(
            rows: [
                SIMD4(gsViewmatrix.x.x, gsViewmatrix.x.y, gsViewmatrix.x.z, gsViewmatrix.x.w),
                SIMD4(gsViewmatrix.y.x, gsViewmatrix.y.y, gsViewmatrix.y.z, gsViewmatrix.y.w),
                SIMD4(gsViewmatrix.z.x, gsViewmatrix.z.y, gsViewmatrix.z.z, gsViewmatrix.z.w),
                SIMD4(gsViewmatrix.t.x, gsViewmatrix.t.y, gsViewmatrix.t.z, gsViewmatrix.t.w),
            ]
        )

        state.viewProjectionMatrix = (viewMatrix * state.projectionMatrix)

        if let viewProjectionUniform = vertexShader.uniforms.filter({ $0.name == "ViewProj" }).first {
            viewProjectionUniform.setParameter(
                data: &state.viewProjectionMatrix, size: MemoryLayout<matrix_float4x4>.size)
        }

        vertexShader.uploadParameters(encoder: commandEncoder)
        fragmentShader.uploadParameters(encoder: commandEncoder)

        let vertexBuffers = vertexBuffer.getBuffersForShader(shader: vertexShader)
        let offsets = Array(repeating: 0, count: vertexBuffers.count)

        commandEncoder.setVertexBuffers(
            vertexBuffers,
            offsets: offsets,
            range: 0..<vertexBuffers.count
        )

        for (index, texture) in state.textures.enumerated() {
            if let texture {
                commandEncoder.setFragmentTexture(texture, index: index)
            }
        }

        for (index, samplerState) in state.samplers.enumerated() {
            if let samplerState {
                commandEncoder.setFragmentSamplerState(samplerState, index: index)
            }
        }

        if let indexBuffer = state.indexBuffer, let bufferData = indexBuffer.indexBuffer {
            commandEncoder.drawIndexedPrimitives(
                type: primitiveType,
                indexCount: (vertexCount > 0) ? vertexCount : indexBuffer.count,
                indexType: indexBuffer.type,
                indexBuffer: bufferData,
                indexBufferOffset: 0)
        } else {
            let count: Int

            if vertexCount == 0 {
                guard let vertexData = vertexBuffer.vertexData else {
                    preconditionFailure(
                        "MetalDevice (draw): No vertex count provided and vertex buffer has no vertex data")
                }
                count = vertexData.pointee.num
            } else {
                count = vertexCount
            }

            commandEncoder.drawPrimitives(
                type: primitiveType,
                vertexStart: vertexStart,
                vertexCount: count
            )
        }

        commandEncoder.endEncoding()

        state.numDraws = state.numDraws + 1
    }

    func clear() {
        guard state.commandBuffer != nil else {  // TODO: Figure out what to do when draw calls are initiated before begin_scene was called
            return
        }

        state.renderPassDescriptor.colorAttachments[0].loadAction = .clear
        state.renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        state.renderPassDescriptor.depthAttachment.loadAction = .clear
        state.renderPassDescriptor.depthAttachment.clearDepth = 0.0
        state.renderPassDescriptor.stencilAttachment.loadAction = .clear
        state.renderPassDescriptor.stencilAttachment.clearStencil = 0

        guard let commandEncoder = state.commandBuffer?.makeRenderCommandEncoder(descriptor: state.renderPassDescriptor)
        else {
            assertionFailure("MetalDevice: Unable to create render command encoder")
            return
        }

        commandEncoder.endEncoding()
    }

    func getBufferForSize(_ size: Int) -> MTLBuffer {
        let alignedSize = (size + 15) & ~15

        var matchingBuffer: MTLBuffer? = nil

        self.queue.sync(flags: .barrier) {
            for (index, buffer) in availableBuffers.enumerated() {
                if buffer.length >= alignedSize {
                    matchingBuffer = buffer
                    availableBuffers.remove(at: index)
                    currentBuffers.append(buffer)
                    break
                }
            }
        }

        guard matchingBuffer == nil else {
            return matchingBuffer!
        }

        let options: MTLResourceOptions = [.cpuCacheModeWriteCombined, .storageModeShared]

        guard let buffer = device.makeBuffer(length: alignedSize, options: options) else {
            preconditionFailure("MetalDevice: Unable to create buffer for \(alignedSize) bytes")
        }

        self.queue.sync(flags: .barrier) {
            currentBuffers.append(buffer)
        }

        return buffer
    }
}

extension MetalDevice {
    enum BufferType {
        case vertex
        case normal
        case tangent
        case color
        case texcoord
    }
}
