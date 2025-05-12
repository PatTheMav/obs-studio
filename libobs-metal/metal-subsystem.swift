//
//  metal-subsystem.swift
//  libobs-metal
//
//  Created by Patrick Heyer on 16.04.24.
//

import Foundation
import Metal
import simd

@_cdecl("device_get_name")
public func device_get_name() -> UnsafePointer<CChar> {
    return device_name
}

@_cdecl("device_get_type")
public func device_get_type() -> Int {
    return Int(GS_DEVICE_METAL)
}

@_cdecl("device_preprocessor_name")
public func device_preprocessor_name() -> UnsafePointer<CChar> {
    return preprocessor_name
}

@_cdecl("device_create")
public func device_create(devicePointer: UnsafeMutableRawPointer, adapter: UInt32) -> Int32 {
    guard NSProtocolFromString("MTLDevice") != nil else {
        OBSLog(.error, "This Mac does not support Metal.")
        return GS_ERROR_NOT_SUPPORTED
    }

    OBSLog(.info, "---------------------------------")

    guard let metalDevice = MTLCreateSystemDefaultDevice() else {
        OBSLog(.error, "Unable to initialize Metal device.")
        return GS_ERROR_FAIL
    }

    var descriptions: [String] = []

    descriptions.append("Initializing Metal...")
    descriptions.append("\t- Name               : \(metalDevice.name)")
    descriptions.append("\t- Unified Memory     : \(metalDevice.hasUnifiedMemory ? "Yes" : "No")")
    descriptions.append("\t- Raytracing Support : \(metalDevice.supportsRaytracing ? "Yes" : "No")")

    if #available(macOS 14.0, *) {
        descriptions.append("\t- Architecture       : \(metalDevice.architecture.name)")
    }

    OBSLog(.info, descriptions.joined(separator: "\n"))

    let device = MetalDevice(device: metalDevice)
    let retained = Unmanaged.passRetained(device).toOpaque()
    devicePointer.storeBytes(of: OpaquePointer(retained), as: OpaquePointer.self)

    return GS_SUCCESS
}

@_cdecl("device_destroy")
public func device_destroy(device: UnsafeMutableRawPointer) {
    _ = Unmanaged<MetalDevice>.fromOpaque(device).takeRetainedValue()
}

@_cdecl("device_enter_context")
public func device_enter_context(device: UnsafeMutableRawPointer) {
    return
}

@_cdecl("device_leave_context")
public func device_leave_context(device: UnsafeMutableRawPointer) {
    return
}

@_cdecl("device_get_device_obj")
public func device_get_device_obj(device: UnsafeMutableRawPointer) -> OpaquePointer? {
    return OpaquePointer(device)
}

@_cdecl("device_blend_function")
public func device_blend_function(device: UnsafeRawPointer, src: gs_blend_type, dest: gs_blend_type) {
    device_blend_function_separate(
        device: device,
        src_c: src,
        dest_c: dest,
        src_a: src,
        dest_a: dest
    )
}

@_cdecl("device_blend_function_separate")
public func device_blend_function_separate(
    device: UnsafeRawPointer, src_c: gs_blend_type, dest_c: gs_blend_type, src_a: gs_blend_type, dest_a: gs_blend_type
) {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    guard let pipelineDescriptor = metalDevice.renderState.pipelineDescriptor else {
        return
    }

    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = src_c.toMTLFactor()
    pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = src_a.toMTLFactor()
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = dest_c.toMTLFactor()
    pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = dest_c.toMTLFactor()
}

@_cdecl("device_blend_op")
public func device_blend_op(device: UnsafeRawPointer, op: gs_blend_op_type) {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    guard let pipelineDescriptor = metalDevice.renderState.pipelineDescriptor else {
        return
    }

    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = op.toMTLOperation()
}

@_cdecl("device_get_color_space")
public func device_get_color_space(device: UnsafeRawPointer) -> gs_color_space {
    // TODO: IMPLEMENT

    return GS_CS_SRGB
}

@_cdecl("device_update_color_space")
public func device_update_color_space(device: UnsafeRawPointer) {
    // TODO: IMPLEMENT
}

@_cdecl("device_load_default_samplerstate")
public func device_load_default_samplerstate(device: UnsafeRawPointer, b_3d: Bool, unit: Int) {
    // TODO: Figure out what to do here
}

@_cdecl("device_get_render_target")
public func device_get_render_target(device: UnsafeRawPointer) -> OpaquePointer? {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    guard let renderTarget = metalDevice.renderState.renderTarget else {
        return nil
    }

    return renderTarget.getUnretained()
}

@_cdecl("device_set_render_target")
public func device_set_render_target(device: UnsafeRawPointer, tex: UnsafeRawPointer?, zstencil: UnsafeRawPointer?) {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    defer {
        if metalDevice.renderState.renderTarget == nil {
            metalDevice.renderState.pipelineDescriptor?.colorAttachments[0].pixelFormat = .invalid
            metalDevice.renderState.renderPassDescriptor?.colorAttachments[0].texture = nil
        }
    }

    if let tex {
        let metalTexture = Unmanaged<MetalTexture>.fromOpaque(tex).takeUnretainedValue()

        metalDevice.renderState.renderTarget = metalTexture
        metalDevice.renderState.pipelineDescriptor?.colorAttachments[0].pixelFormat = metalTexture.texture.pixelFormat
        metalDevice.renderState.renderPassDescriptor?.colorAttachments[0].texture = metalTexture.texture
    } else {
        metalDevice.renderState.renderTarget = nil
    }

    defer {
        if metalDevice.renderState.stencilAttachment == nil {
            metalDevice.renderState.pipelineDescriptor?.depthAttachmentPixelFormat = .invalid
            metalDevice.renderState.pipelineDescriptor?.stencilAttachmentPixelFormat = .invalid
            metalDevice.renderState.renderPassDescriptor?.depthAttachment.texture = nil
            metalDevice.renderState.renderPassDescriptor?.stencilAttachment.texture = nil
        }
    }

    if let zstencil {
        let zstencilAttachment = Unmanaged<MetalTexture>.fromOpaque(zstencil).takeUnretainedValue()

        metalDevice.renderState.stencilAttachment = zstencilAttachment
        metalDevice.renderState.pipelineDescriptor?.depthAttachmentPixelFormat = zstencilAttachment.texture.pixelFormat
        metalDevice.renderState.pipelineDescriptor?.stencilAttachmentPixelFormat =
            zstencilAttachment.texture.pixelFormat
        metalDevice.renderState.renderPassDescriptor?.depthAttachment.texture = zstencilAttachment.texture
        metalDevice.renderState.renderPassDescriptor?.stencilAttachment.texture = zstencilAttachment.texture
    } else {
        metalDevice.renderState.stencilAttachment = nil
    }
}

@_cdecl("device_set_render_target_with_color_space")
public func device_set_render_target_with_color_space(
    device: UnsafeRawPointer, tex: UnsafeRawPointer?, zstencil: UnsafeRawPointer?, space: gs_color_space
) {
    device_set_render_target(
        device: device,
        tex: tex,
        zstencil: zstencil
    )

    // TODO: IMPLEMENT
}

@_cdecl("device_enable_framebuffer_srgb")
public func device_enable_framebuffer_srgb(device: UnsafeRawPointer, enable: Bool) {
    // TODO: IMPLEMENT
    return
}

@_cdecl("device_framebuffer_srgb_enabled")
public func device_framebuffer_srgb_enabled(device: UnsafeRawPointer) -> Bool {
    // TODO: IMPLEMENT
    return false
}

@_cdecl("device_begin_scene")
public func device_begin_scene(device: UnsafeRawPointer) {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    metalDevice.makeCommandBuffer()
}

@_cdecl("device_draw")
public func device_draw(device: UnsafeRawPointer, drawMode: gs_draw_mode, startVertex: UInt32, numVertices: UInt32) {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    metalDevice.draw(
        primitiveType: drawMode.toMTLPrimitiveType(),
        vertexStart: Int(startVertex),
        vertexCount: Int(numVertices)
    )
}

@_cdecl("device_clear")
public func device_clear(
    device: UnsafeRawPointer, clearFlags: UInt32, color: UnsafePointer<vec4>, depth: Float, stencil: UInt8
) {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    var clearState = MetalRenderState.ClearState()

    if metalDevice.renderState.renderTarget != nil {
        if (Int32(clearFlags) & GS_CLEAR_COLOR) == 1 {
            clearState.colorAction = .clear
            clearState.clearColor = MTLClearColor(
                red: Double(color.pointee.x),
                green: Double(color.pointee.y),
                blue: Double(color.pointee.z),
                alpha: Double(color.pointee.w)
            )
        }
    }

    if metalDevice.renderState.stencilAttachment != nil {
        if (Int32(clearFlags) & GS_CLEAR_DEPTH) == 1 {
            clearState.clearDepth = Double(depth)
            clearState.depthAction = .clear
        }

        if (Int32(clearFlags) & GS_CLEAR_STENCIL) == 1 {
            clearState.clearStencil = UInt32(stencil)
            clearState.stencilAction = .clear
        }
    }

    metalDevice.renderState.clearState = clearState
    metalDevice.renderState.clearTarget = metalDevice.renderState.renderTarget
}

@_cdecl("device_is_present_ready")
public func device_is_present_ready(device: UnsafeRawPointer) -> Bool {
    return true
}

@_cdecl("device_present")
public func device_present(device: UnsafeRawPointer) {
    device_flush(device: device)

    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    guard let swapChain = metalDevice.renderState.swapChain else {
        return
    }

    swapChain.update()
}

@_cdecl("device_flush")
public func device_flush(device: UnsafeRawPointer) {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    metalDevice.renderState.commandBuffer?.commit()
    metalDevice.renderState.commandBuffer?.waitUntilCompleted()
    metalDevice.renderState.commandBuffer = nil
}

@_cdecl("device_set_cull_mode")
public func device_set_cull_mode(device: UnsafeRawPointer, mode: gs_cull_mode) {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    metalDevice.renderState.cullMode = mode.toMTLMode()
}

@_cdecl("device_get_cull_mode")
public func device_get_cull_mode(device: UnsafeRawPointer) -> gs_cull_mode {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    return metalDevice.renderState.cullMode.toGSMode()
}

@_cdecl("device_enable_blending")
public func device_enable_blending(device: UnsafeRawPointer, enable: Bool) {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    metalDevice.renderState.pipelineDescriptor?.colorAttachments[0].isBlendingEnabled = enable
}

@_cdecl("device_enable_depth_test")
public func device_enable_depth_test(device: UnsafeRawPointer, enable: Bool) {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    metalDevice.renderState.depthStencilDescriptor?.isDepthWriteEnabled = enable
}

@_cdecl("device_enable_stencil_test")
public func device_enable_stencil_test(device: UnsafeRawPointer, enable: Bool) {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    metalDevice.renderState.depthStencilDescriptor?.frontFaceStencil.readMask = enable ? 1 : 0
    metalDevice.renderState.depthStencilDescriptor?.backFaceStencil.readMask = enable ? 1 : 0
}

@_cdecl("device_enable_stencil_write")
public func device_enable_stencil_write(device: UnsafeRawPointer, enable: Bool) {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    metalDevice.renderState.depthStencilDescriptor?.frontFaceStencil.writeMask = enable ? 1 : 0
    metalDevice.renderState.depthStencilDescriptor?.backFaceStencil.writeMask = enable ? 1 : 0
}

@_cdecl("device_enable_color")
public func device_enable_color(device: UnsafeRawPointer, red: Bool, green: Bool, blue: Bool, alpha: Bool) {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    var colorMask = MTLColorWriteMask()

    if red {
        colorMask.insert(.red)
    }

    if green {
        colorMask.insert(.green)
    }

    if blue {
        colorMask.insert(.blue)
    }

    if alpha {
        colorMask.insert(.alpha)
    }

    metalDevice.renderState.pipelineDescriptor?.colorAttachments[0].writeMask = colorMask
}

@_cdecl("device_depth_function")
public func device_depth_function(device: UnsafeRawPointer, test: gs_depth_test) {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    metalDevice.renderState.depthStencilDescriptor?.depthCompareFunction = test.toMTLFunction()
}

@_cdecl("device_stencil_function")
public func device_stencil_function(device: UnsafeRawPointer, side: gs_stencil_side, test: gs_depth_test) {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    let function = test.toMTLFunction()

    if side == GS_STENCIL_FRONT {
        metalDevice.renderState.depthStencilDescriptor?.frontFaceStencil.stencilCompareFunction = function
        metalDevice.renderState.depthStencilDescriptor?.backFaceStencil.stencilCompareFunction = .never
    } else if side == GS_STENCIL_BACK {
        metalDevice.renderState.depthStencilDescriptor?.frontFaceStencil.stencilCompareFunction = .never
        metalDevice.renderState.depthStencilDescriptor?.backFaceStencil.stencilCompareFunction = function
    } else {
        metalDevice.renderState.depthStencilDescriptor?.frontFaceStencil.stencilCompareFunction = function
        metalDevice.renderState.depthStencilDescriptor?.backFaceStencil.stencilCompareFunction = function
    }
}

@_cdecl("device_stencil_op")
public func device_stencil_op(
    device: UnsafeRawPointer, side: gs_stencil_side, fail: gs_stencil_op_type, zfail: gs_stencil_op_type,
    zpass: gs_stencil_op_type
) {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    if side == GS_STENCIL_FRONT {
        metalDevice.renderState.depthStencilDescriptor?.frontFaceStencil.stencilFailureOperation = fail.toMTLOperation()
        metalDevice.renderState.depthStencilDescriptor?.frontFaceStencil.depthFailureOperation = zfail.toMTLOperation()
        metalDevice.renderState.depthStencilDescriptor?.frontFaceStencil.depthStencilPassOperation =
            zpass.toMTLOperation()

        metalDevice.renderState.depthStencilDescriptor?.backFaceStencil.stencilFailureOperation = .keep
        metalDevice.renderState.depthStencilDescriptor?.backFaceStencil.depthFailureOperation = .keep
        metalDevice.renderState.depthStencilDescriptor?.backFaceStencil.depthStencilPassOperation = .keep
    } else if side == GS_STENCIL_BACK {
        metalDevice.renderState.depthStencilDescriptor?.frontFaceStencil.stencilFailureOperation = .keep
        metalDevice.renderState.depthStencilDescriptor?.frontFaceStencil.depthFailureOperation = .keep
        metalDevice.renderState.depthStencilDescriptor?.frontFaceStencil.depthStencilPassOperation = .keep

        metalDevice.renderState.depthStencilDescriptor?.backFaceStencil.stencilFailureOperation = fail.toMTLOperation()
        metalDevice.renderState.depthStencilDescriptor?.backFaceStencil.depthFailureOperation = zfail.toMTLOperation()
        metalDevice.renderState.depthStencilDescriptor?.backFaceStencil.depthStencilPassOperation =
            zpass.toMTLOperation()
    } else {
        metalDevice.renderState.depthStencilDescriptor?.frontFaceStencil.stencilFailureOperation = fail.toMTLOperation()
        metalDevice.renderState.depthStencilDescriptor?.frontFaceStencil.depthFailureOperation = zfail.toMTLOperation()
        metalDevice.renderState.depthStencilDescriptor?.frontFaceStencil.depthStencilPassOperation =
            zpass.toMTLOperation()

        metalDevice.renderState.depthStencilDescriptor?.backFaceStencil.stencilFailureOperation = fail.toMTLOperation()
        metalDevice.renderState.depthStencilDescriptor?.backFaceStencil.depthFailureOperation = zfail.toMTLOperation()
        metalDevice.renderState.depthStencilDescriptor?.backFaceStencil.depthStencilPassOperation =
            zpass.toMTLOperation()
    }
}

@_cdecl("device_set_viewport")
public func device_set_viewport(device: UnsafeRawPointer, x: Int32, y: Int32, width: Int32, height: Int32) {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    let viewPort = MTLViewport(
        originX: Double(x),
        originY: Double(y),
        width: Double(width),
        height: Double(height),
        znear: 0.0,
        zfar: 1.0
    )

    metalDevice.renderState.viewPort = viewPort
}

@_cdecl("device_get_viewport")
public func device_get_viewport(device: UnsafeRawPointer, rect: UnsafeMutablePointer<gs_rect>) {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    rect.pointee.x = Int32(metalDevice.renderState.viewPort.originX)
    rect.pointee.y = Int32(metalDevice.renderState.viewPort.originY)
    rect.pointee.cx = Int32(metalDevice.renderState.viewPort.width)
    rect.pointee.cy = Int32(metalDevice.renderState.viewPort.height)
}

@_cdecl("device_set_scissor_rect")
public func device_set_scissor_rect(device: UnsafeRawPointer, rect: UnsafePointer<gs_rect>?) {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    if let rect {
        metalDevice.renderState.scissorRect = rect.pointee.toMTLScissorRect()
        metalDevice.renderState.scissorRectEnabled = true
    } else {
        metalDevice.renderState.scissorRect = nil
        metalDevice.renderState.scissorRectEnabled = false
    }
}

@_cdecl("device_ortho")
public func device_ortho(
    device: UnsafeRawPointer, left: Float, right: Float, top: Float, bottom: Float, near: Float, far: Float
) {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    let rml = right - left
    let bmt = bottom - top
    let fmn = far - near

    metalDevice.renderState.projectionMatrix = matrix_float4x4(
        rows: [
            SIMD4((2.0 / rml), 0.0, 0.0, 0.0),
            SIMD4(0.0, (2.0 / -bmt), 0.0, 0.0),
            SIMD4(0.0, 0.0, (1 / fmn), 0.0),
            SIMD4((left + right) / -rml, (bottom + top) / bmt, near / -fmn, 1.0),
        ]
    )
}

@_cdecl("device_frustum")
public func device_frustum(
    device: UnsafeRawPointer, left: Float, right: Float, top: Float, bottom: Float, near: Float, far: Float
) {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    let rml = right - left
    let tmb = top - bottom
    let fmn = far - near

    metalDevice.renderState.projectionMatrix = matrix_float4x4(
        columns: (
            SIMD4(((2 * near) / rml), 0.0, 0.0, 0.0),
            SIMD4(0.0, ((2 * near) / tmb), 0.0, 0.0),
            SIMD4(((left + right) / rml), ((top + bottom) / tmb), (-far / fmn), -1.0),
            SIMD4(0.0, 0.0, (-(far * near) / fmn), 0.0)
        )
    )
}

@_cdecl("device_projection_push")
public func device_projection_push(device: UnsafeRawPointer) {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    metalDevice.renderState.projections.insert(metalDevice.renderState.projectionMatrix, at: 0)
}

@_cdecl("device_projection_pop")
public func device_projection_pop(device: UnsafeRawPointer) {
    let metalDevice = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    metalDevice.renderState.projectionMatrix = metalDevice.renderState.projections.removeFirst()
}

@_cdecl("device_is_monitor_hdr")
public func device_is_monitor_hdr(device: UnsafeRawPointer) -> Bool {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    // TODO: IMPLEMENT
    return false
}
