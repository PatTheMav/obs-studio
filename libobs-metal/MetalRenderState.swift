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
import simd

struct MetalRenderState {
    struct ClearState {
        var colorAction: MTLLoadAction = .load
        var depthAction: MTLLoadAction = .load
        var stencilAction: MTLLoadAction = .load
        var clearColor: MTLClearColor = MTLClearColor()
        var clearDepth: Double = 0.0
        var clearStencil: UInt32 = 0
        var clearTarget: MetalTexture? = nil
    }

    struct BlendState {
        var sourceRgb: MTLBlendFactor = .one
        var sourceAlpha: MTLBlendFactor = .one
        var destinationRgb: MTLBlendFactor = .one
        var destinationAlpha: MTLBlendFactor = .one
        var operation: MTLBlendOperation = .add
    }

    var viewMatrix: matrix_float4x4
    var viewProjectionMatrix: matrix_float4x4
    var projectionMatrix: matrix_float4x4
    var projections = [matrix_float4x4]()

    var renderTarget: MetalTexture?
    var sRGBrenderTarget: MetalTexture?
    var clearTarget: MetalTexture?

    var textures: [MTLTexture?]
    var samplers: [MTLSamplerState?]

    var commandBuffer: MTLCommandBuffer?

    var vertexBuffer: MetalVertexBuffer?
    var indexBuffer: MetalIndexBuffer?
    var stencilAttachment: MetalTexture?

    var vertexShader: MetalShader?
    var fragmentShader: MetalShader?

    var pipelineDescriptor: MTLRenderPipelineDescriptor?
    var renderPassDescriptor: MTLRenderPassDescriptor?
    var depthStencilDescriptor: MTLDepthStencilDescriptor?

    var swapChain: OBSSwapChain?

    var clearState: ClearState?
    var viewPort: MTLViewport
    var cullMode: MTLCullMode

    var scissorRectEnabled: Bool
    var scissorRect: MTLScissorRect?

    var srgbState: Bool = false
    var updateRenderTarget: Bool = false

    var gsColorSpace: gs_color_space
}
