//
//  metal-subsystem.swift
//  libobs-metal
//
//  Created by Patrick Heyer on 16.04.24.
//

import AppKit
import Foundation
import Metal
import simd

enum OBSLogLevel: Int32 {
    case error = 100
    case warning = 200
    case info = 300
    case debug = 400
}

func OBSLog(_ level: OBSLogLevel, _ format: String, _ args: CVarArg...) {
    let logMessage = String.localizedStringWithFormat(format, args)

    logMessage.withCString { cMessage in
        withVaList([cMessage]) { arguments in
            blogva(level.rawValue, "%s", arguments)
        }
    }
}

final class OBSAPIResource {
    var device: MetalDevice
    var resourceId: Int
    var data: [UInt8]?

    init(device: MetalDevice, resourceId: Int) {
        self.device = device
        self.resourceId = resourceId
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

struct BufferQueue<T> {
    private var elements: [T] = []

    mutating func push(_ value: T) {
        elements.append(value)
    }

    mutating func pop() -> T? {
        guard !elements.isEmpty else {
            return nil
        }

        return elements.removeFirst()
    }

    var head: T? {
        return elements.first
    }

    var tail: T? {
        return elements.last
    }

    var count: Int {
        return elements.count
    }
}

extension MTLPixelFormat {
    func toGSColorFormat() -> gs_color_format {
        switch self {
        case .a8Unorm:
            return GS_A8
        case .r8Unorm:
            return GS_R8
        case .rgba8Unorm:
            return GS_RGBA
        case .bgra8Unorm:
            return GS_BGRA
        case .rgb10a2Unorm:
            return GS_R10G10B10A2
        case .rgba16Unorm:
            return GS_RGBA16
        case .r16Unorm:
            return GS_R16
        case .rgba16Float:
            return GS_RGBA16F
        case .rgba32Float:
            return GS_RGBA32F
        case .rg16Float:
            return GS_RG16F
        case .rg32Float:
            return GS_RG32F
        case .r16Float:
            return GS_R16F
        case .r32Float:
            return GS_R32F
        case .bc1_rgba:
            return GS_DXT1
        case .bc2_rgba:
            return GS_DXT3
        case .bc3_rgba:
            return GS_DXT5
        default:
            return GS_UNKNOWN
        }
    }

    func bitsPerPixel() -> Int {
        switch self {
        case .invalid:
            return 0
        case .a8Unorm, .r8Unorm, .r8Unorm_srgb, .r8Snorm, .r8Uint, .r8Sint:
            return 8
        case .r16Unorm, .r16Snorm, .r16Uint, .r16Sint, .r16Float:
            return 16
        case .rg8Unorm, .rg8Unorm_srgb, .rg8Snorm, .rg8Uint, .rg8Sint:
            return 16
        case .b5g6r5Unorm, .a1bgr5Unorm, .abgr4Unorm, .bgr5A1Unorm:
            return 16
        case .r32Uint, .r32Sint, .r32Float, .rg16Unorm, .rg16Snorm, .rg16Uint, .rg16Sint, .rg16Float:
            return 32
        case .rgba8Unorm, .rgba8Unorm_srgb, .rgba8Snorm, .rgba8Uint, .rgba8Sint, .bgra8Unorm, .bgra8Unorm_srgb:
            return 32
        case .bgr10_xr, .bgr10_xr_srgb, .rgb10a2Unorm, .rgb10a2Uint, .rg11b10Float, .rgb9e5Float, .bgr10a2Unorm:
            return 32
        case .bgra10_xr, .bgra10_xr_srgb, .rg32Uint, .rg32Sint, .rg32Float, .rgba16Unorm, .rgba16Snorm, .rgba16Uint,
            .rgba16Sint, .rgba16Float:
            return 64
        case .rgba32Uint, .rgba32Sint, .rgba32Float:
            return 128
        case .bc1_rgba, .bc1_rgba_srgb:
            return 64
        case .bc2_rgba, .bc2_rgba_srgb, .bc3_rgba, .bc3_rgba_srgb:
            return 128
        case .bc4_rUnorm, .bc4_rSnorm:
            return 8
        case .bc5_rgUnorm, .bc5_rgSnorm:
            return 16
        case .bc6H_rgbFloat, .bc6H_rgbuFloat, .bc7_rgbaUnorm, .bc7_rgbaUnorm_srgb:
            return 32
        case .pvrtc_rgb_2bpp, .pvrtc_rgb_2bpp_srgb:
            return 6
        case .pvrtc_rgba_2bpp, .pvrtc_rgba_2bpp_srgb:
            return 8
        case .pvrtc_rgb_4bpp, .pvrtc_rgb_4bpp_srgb:
            return 12
        case .pvrtc_rgba_4bpp, .pvrtc_rgba_4bpp_srgb:
            return 16
        case .eac_r11Unorm, .eac_r11Snorm:
            return 8
        case .eac_rg11Unorm, .eac_rg11Snorm:
            return 16
        case .eac_rgba8, .eac_rgba8_srgb, .etc2_rgb8a1, .etc2_rgb8a1_srgb:
            return 32
        case .etc2_rgb8, .etc2_rgb8_srgb:
            return 24
        case .astc_4x4_srgb, .astc_5x4_srgb, .astc_5x5_srgb, .astc_6x5_srgb, .astc_6x6_srgb, .astc_8x5_srgb,
            .astc_8x6_srgb, .astc_8x8_srgb, .astc_10x5_srgb, .astc_10x6_srgb, .astc_10x8_srgb, .astc_10x10_srgb,
            .astc_12x10_srgb, .astc_12x12_srgb:
            return 16
        case .astc_4x4_ldr, .astc_5x4_ldr, .astc_5x5_ldr, .astc_6x5_ldr, .astc_6x6_ldr, .astc_8x5_ldr, .astc_8x6_ldr,
            .astc_8x8_ldr, .astc_10x5_ldr, .astc_10x6_ldr, .astc_10x8_ldr, .astc_10x10_ldr, .astc_12x10_ldr,
            .astc_12x12_ldr:
            return 16
        case .astc_4x4_hdr, .astc_5x4_hdr, .astc_5x5_hdr, .astc_6x5_hdr, .astc_6x6_hdr, .astc_8x5_hdr, .astc_8x6_hdr,
            .astc_8x8_hdr, .astc_10x5_hdr, .astc_10x6_hdr, .astc_10x8_hdr, .astc_10x10_hdr, .astc_12x10_hdr,
            .astc_12x12_hdr:
            return 16
        case .gbgr422, .bgrg422:
            return 32
        case .depth16Unorm:
            return 16
        case .depth32Float:
            return 32
        case .stencil8:
            return 8
        case .depth24Unorm_stencil8:
            return 32
        case .depth32Float_stencil8:
            return 40
        case .x32_stencil8:
            return 40
        case .x24_stencil8:
            return 32
        @unknown default:
            fatalError("Unknown MTLPixelFormat")
        }
    }
}

extension MTLTextureType {
    func toGSTextureType() -> gs_texture_type {
        switch self {
        case .type2D:
            return GS_TEXTURE_2D
        case .type3D:
            return GS_TEXTURE_3D
        case .typeCube:
            return GS_TEXTURE_CUBE
        default:
            fatalError("Unsupported texture type")
        }
    }
}

extension MTLCullMode {
    func toGSMode() -> gs_cull_mode {
        switch self {
        case .back:
            return GS_BACK
        case .front:
            return GS_FRONT
        case .none:
            return GS_NEITHER
        @unknown default:
            fatalError("Metal: Unsupported cull mode \(self)")
        }
    }
}

extension MTLViewport: Equatable {
    public static func < (lhs: MTLViewport, rhs: MTLViewport) -> Bool {
        return lhs != rhs
    }

    public static func == (lhs: MTLViewport, rhs: MTLViewport) -> Bool {
        if lhs.width == rhs.width && lhs.height == rhs.height && lhs.originX == rhs.originX
            && lhs.originY == rhs.originY
        {
            return true
        } else {
            return false
        }
    }
}

extension MTLTexture {
    func download() -> [UInt8] {
        var data = [UInt8](repeating: 0, count: width * height * self.pixelFormat.bitsPerPixel() / 8)
        let region = MTLRegionMake2D(0, 0, width, height)
        getBytes(&data, bytesPerRow: width * self.pixelFormat.bitsPerPixel() / 8, from: region, mipmapLevel: 0)

        return data
    }

    func map(data: inout UnsafeMutablePointer<UInt8>) {
        let region = MTLRegionMake2D(0, 0, width, height)
        getBytes(&data, bytesPerRow: width * self.pixelFormat.bitsPerPixel() / 8, from: region, mipmapLevel: 0)
    }

    func upload(data: [[UInt8]]) {
        var levelWidth = self.width
        var levelHeight = self.height
        let bitsPerPixel = self.pixelFormat.bitsPerPixel()

        for level in 0..<self.mipmapLevelCount {
            if data.count == 0 || level > data.count {
                break
            }

            let rowSizeBytes = levelWidth * bitsPerPixel / 8
            let rowSizeHeight = levelWidth * levelHeight * bitsPerPixel / 8

            let region = MTLRegionMake2D(0, 0, levelWidth, levelHeight)

            self.replace(
                region: region,
                mipmapLevel: level,
                slice: 0,
                withBytes: data[level],
                bytesPerRow: rowSizeBytes,
                bytesPerImage: rowSizeHeight)

            levelWidth = levelWidth / 2
            levelHeight = levelHeight / 2
        }
    }
}

extension FourCharCode: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        var code: FourCharCode = 0

        if value.count == 4 && value.utf8.count == 4 {
            for byte in value.utf8 {
                code = code << 8 + FourCharCode(byte)
            }
        } else {
            code = 0x3F_3F_3F_3F
        }

        self = code
    }

    public init(extendedGraphemeClusterLiteral value: String) {
        self = FourCharCode(stringLiteral: value)
    }

    public var string: String? {
        let cString: [CChar] = [
            CChar(self >> 24 & 0xFF),
            CChar(self >> 16 & 0xFF),
            CChar(self >> 8 & 0xFF),
            CChar(self & 0xFF),
            0,
        ]

        return String(cString: cString)
    }
}

extension FourCharCode {
    func convertToGSFormat() -> gs_color_format {
        switch self.string?.lowercased() {
        case "bgra":
            return GS_BGRA
        case "w30r":
            return GS_R10G10B10A2
        case "l10r":
            return GS_R10G10B10A2
        default:
            return GS_UNKNOWN
        }
    }
}

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
    OBSLog(.info, "Initializing Metal...")

    guard let metalDevice = MTLCreateSystemDefaultDevice() else {
        OBSLog(.error, "Unable to initialize Metal device.")
        return GS_ERROR_FAIL
    }

    var descriptions: [String] = []

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
    return nil
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
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    device.state.renderPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = src_c.toMTLFactor()
    device.state.renderPipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = src_a.toMTLFactor()
    device.state.renderPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = dest_c.toMTLFactor()
    device.state.renderPipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = dest_c.toMTLFactor()
}

@_cdecl("device_blend_op")
public func device_blend_op(device: UnsafeRawPointer, op: gs_blend_op_type) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    device.state.renderPipelineDescriptor.colorAttachments[0].rgbBlendOperation = op.toMTLOperation()
}

@_cdecl("device_get_color_space")
public func device_get_color_space(device: UnsafeRawPointer) -> gs_color_space {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    return device.state.gsColorSpace
}

@_cdecl("device_update_color_space")
public func device_update_color_space(device: UnsafeRawPointer) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    // TODO: Figure out sRGB stuff
}

@_cdecl("device_timer_create")
public func device_timer_create(device: UnsafeRawPointer) {
    return
}

@_cdecl("device_timer_range_create")
public func device_timer_range_create(device: UnsafeRawPointer) {
    return
}

@_cdecl("device_load_default_samplerstate")
public func device_load_default_samplerstate(device: UnsafeRawPointer, b_3d: Bool, unit: Int) {
    // TODO: Figure out what to do here
}

@_cdecl("device_get_render_target")
public func device_get_render_target(device: UnsafeRawPointer) -> OpaquePointer? {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    if device.state.renderTarget != nil {
        let resource = OBSAPIResource(device: device, resourceId: device.state.renderTargetId)
        return resource.getRetained()
    } else {
        return nil
    }
}

@_cdecl("device_set_render_target")
public func device_set_render_target(device: UnsafeRawPointer, tex: UnsafeRawPointer?, zstencil: UnsafeRawPointer?) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    defer {
        if device.state.renderTarget == nil {
            device.state.renderPipelineDescriptor.colorAttachments[0].pixelFormat = .invalid
            device.state.renderPassDescriptor.colorAttachments[0].texture = nil
        }
    }

    if let tex {
        let resource = Unmanaged<OBSAPIResource>.fromOpaque(tex).takeUnretainedValue()

        let textureId = resource.resourceId

        guard let texture = device.textures[textureId] else {
            assertionFailure("device_set_render_target (Metal): Invalid texture ID provided")
            device.state.renderTarget = nil
            return
        }
        device.state.renderTarget = texture
        device.state.renderTargetId = textureId
        device.state.renderPipelineDescriptor.colorAttachments[0].pixelFormat = texture.pixelFormat
        device.state.renderPassDescriptor.colorAttachments[0].texture = texture
    } else {
        device.state.renderTarget = nil
    }

    defer {
        if device.state.stencilAttachment == nil {
            device.state.renderPipelineDescriptor.depthAttachmentPixelFormat = .invalid
            device.state.renderPipelineDescriptor.stencilAttachmentPixelFormat = .invalid
            device.state.renderPassDescriptor.depthAttachment.texture = nil
            device.state.renderPassDescriptor.stencilAttachment.texture = nil
        }
    }

    if let zstencil {
        let resource = Unmanaged<OBSAPIResource>.fromOpaque(zstencil).takeUnretainedValue()

        let stencilBufferId = resource.resourceId

        guard let stencilAttachment = device.textures[stencilBufferId] else {
            assertionFailure("device_set_render_target (Metal): Invalid stencil buffer ID provided")
            device.state.stencilAttachment = nil
            return
        }
        device.state.stencilAttachment = stencilAttachment
        device.state.renderPipelineDescriptor.depthAttachmentPixelFormat = stencilAttachment.pixelFormat
        device.state.renderPipelineDescriptor.stencilAttachmentPixelFormat = stencilAttachment.pixelFormat
        device.state.renderPassDescriptor.depthAttachment.texture = stencilAttachment
        device.state.renderPassDescriptor.stencilAttachment.texture = stencilAttachment
    } else {
        device.state.stencilAttachment = nil
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

    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()
    device.state.gsColorSpace = space
}

@_cdecl("device_enable_framebuffer_srgb")
public func device_enable_framebuffer_srgb(device: UnsafeRawPointer, enable: Bool) {
    // TODO: Figure out what to do

    return
}

@_cdecl("device_framebuffer_srgb_enabled")
public func device_framebuffer_srgb_enabled(device: UnsafeRawPointer) -> Bool {
    // TODO: Figure out what to do
    return false
}

@_cdecl("device_begin_frame")
public func device_begin_frame(device: UnsafeRawPointer) {
    return
}

@_cdecl("device_begin_scene")
public func device_begin_scene(device: UnsafeRawPointer) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    //    device.state.textures = [MTLTexture?](repeating: nil, count: Int(GS_MAX_TEXTURES)) // Maybe set to nil instead, check other places to initialise if necessary
    device.state.commandBuffer = device.commandQueue.makeCommandBuffer()
}

@_cdecl("device_draw")
public func device_draw(device: UnsafeRawPointer, drawMode: gs_draw_mode, startVertex: UInt32, numVertices: UInt32) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    device.draw(
        primitiveType: drawMode.toMTLPrimitiveType(), vertexStart: Int(startVertex), vertexCount: Int(numVertices))
}

@_cdecl("device_end_scene")
public func device_end_scene(device: UnsafeRawPointer) {
    return
}

@_cdecl("device_clear")
public func device_clear(
    device: UnsafeRawPointer, clearFlags: UInt32, color: UnsafePointer<vec4>, depth: Float, stencil: UInt8
) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    var clearState = MetalState.ClearState(
        colorAction: .load,
        depthAction: .load,
        stencilAction: .load,
        clearColor: nil,
        clearDepth: 0.0,
        clearStencil: 0,
        clearTargetId: device.state.renderTargetId
    )

    if device.state.renderTarget != nil {
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

    if device.state.stencilAttachment != nil {
        if (Int32(clearFlags) & GS_CLEAR_DEPTH) == 1 {
            clearState.clearDepth = Double(depth)
            clearState.depthAction = .clear
        }

        if (Int32(clearFlags) & GS_CLEAR_STENCIL) == 1 {
            clearState.clearStencil = UInt32(stencil)
            clearState.stencilAction = .clear
        }
    }

    device.clearStates.push(clearState)
    device.state.clearTargetId = device.state.renderTargetId
}

@_cdecl("device_is_present_ready")
public func device_is_present_ready(device: UnsafeRawPointer) -> Bool {
    return true
}

@_cdecl("device_present")
public func device_present(device: UnsafeRawPointer) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    guard let layerId = device.state.layerId, var layer = device.layers[layerId], let drawable = layer.nextDrawable
    else {
        preconditionFailure("device_present (Metal): No drawable for layer available")
    }

    if device.state.numDraws == 0 {
        device.clear()
    }

    defer {
        device.state.commandBuffer = nil
        device.state.numDraws = 0

        layer.nextDrawable = nil
        device.layers.replaceAt(layerId, layer)
    }

    device.state.commandBuffer?.present(drawable)

    weak var weakDevice = device

    device.state.commandBuffer?.addCompletedHandler { _ in
        if let device = weakDevice {
            device.queue.sync(flags: .barrier) {
                device.bufferPools.push(device.currentBuffers)

                if let availableBuffers = device.bufferPools.pop() {
                    device.availableBuffers = availableBuffers
                }

                device.currentBuffers = []
            }
        }
    }

    device.state.commandBuffer?.commit()
}

@_cdecl("device_flush")
public func device_flush(devicePointer: UnsafeRawPointer) {
    let device = Unmanaged<MetalDevice>.fromOpaque(devicePointer).takeUnretainedValue()

    device.state.commandBuffer?.commit()
    device.state.commandBuffer?.waitUntilCompleted()

    defer {
        device.state.commandBuffer = nil
        device.state.numDraws = 0
    }

    if device.currentBuffers.count > 0 {
        device.queue.sync(flags: .barrier) {
            device.bufferPools.push(device.currentBuffers)

            if let buffers = device.bufferPools.pop() {
                device.availableBuffers = buffers
            }

            device.currentBuffers = []
        }
    }
}

@_cdecl("device_set_cull_mode")
public func device_set_cull_mode(devicePointer: UnsafeRawPointer, mode: gs_cull_mode) {
    let device = Unmanaged<MetalDevice>.fromOpaque(devicePointer).takeUnretainedValue()

    device.state.cullMode = mode.toMTLMode()
}

@_cdecl("device_get_cull_mode")
public func device_get_cull_mode(devicePointer: UnsafeRawPointer) -> gs_cull_mode {
    let device = Unmanaged<MetalDevice>.fromOpaque(devicePointer).takeUnretainedValue()

    return device.state.cullMode.toGSMode()
}

@_cdecl("device_enable_blending")
public func device_enable_blending(devicePointer: UnsafeRawPointer, enable: Bool) {
    let device = Unmanaged<MetalDevice>.fromOpaque(devicePointer).takeUnretainedValue()

    device.state.renderPipelineDescriptor.colorAttachments[0].isBlendingEnabled = enable
}

@_cdecl("device_enable_depth_test")
public func device_enable_depth_test(devicePointer: UnsafeRawPointer, enable: Bool) {
    let device = Unmanaged<MetalDevice>.fromOpaque(devicePointer).takeUnretainedValue()
    device.state.depthTestEnabled = enable
    device.state.depthStencilDescriptor.isDepthWriteEnabled = enable
}

@_cdecl("device_enable_stencil_test")
public func device_enable_stencil_test(devicePointer: UnsafeRawPointer, enable: Bool) {
    let device = Unmanaged<MetalDevice>.fromOpaque(devicePointer).takeUnretainedValue()

    device.state.stencilTestEnabled = enable
    device.state.depthStencilDescriptor.frontFaceStencil.readMask = enable ? 1 : 0
    device.state.depthStencilDescriptor.backFaceStencil.readMask = enable ? 1 : 0
}

@_cdecl("device_enable_stencil_write")
public func device_enable_stencil_write(devicePointer: UnsafeRawPointer, enable: Bool) {
    let device = Unmanaged<MetalDevice>.fromOpaque(devicePointer).takeUnretainedValue()

    device.state.stencilWriteTestEnabled = enable
    device.state.depthStencilDescriptor.frontFaceStencil.writeMask = enable ? 1 : 0
    device.state.depthStencilDescriptor.backFaceStencil.writeMask = enable ? 1 : 0
}

@_cdecl("device_enable_color")
public func device_enable_color(devicePointer: UnsafeRawPointer, red: Bool, green: Bool, blue: Bool, alpha: Bool) {
    let device = Unmanaged<MetalDevice>.fromOpaque(devicePointer).takeUnretainedValue()

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

    device.state.renderPipelineDescriptor.colorAttachments[0].writeMask = colorMask
}

@_cdecl("device_depth_function")
public func device_depth_function(devicePointer: UnsafeRawPointer, test: gs_depth_test) {
    let device = Unmanaged<MetalDevice>.fromOpaque(devicePointer).takeUnretainedValue()

    device.state.depthStencilDescriptor.depthCompareFunction = test.toMTLFunction()
}

@_cdecl("device_stencil_function")
public func device_stencil_function(devicePointer: UnsafeRawPointer, side: gs_stencil_side, test: gs_depth_test) {
    let device = Unmanaged<MetalDevice>.fromOpaque(devicePointer).takeUnretainedValue()

    let function = test.toMTLFunction()

    if side == GS_STENCIL_FRONT {
        device.state.depthStencilDescriptor.frontFaceStencil.stencilCompareFunction = function
        device.state.depthStencilDescriptor.backFaceStencil.stencilCompareFunction = .never
    } else if side == GS_STENCIL_BACK {
        device.state.depthStencilDescriptor.frontFaceStencil.stencilCompareFunction = .never
        device.state.depthStencilDescriptor.backFaceStencil.stencilCompareFunction = function
    }
}

@_cdecl("device_stencil_op")
public func device_stencil_op(
    devicePointer: UnsafeRawPointer, side: gs_stencil_side, fail: gs_stencil_op_type, zfail: gs_stencil_op_type,
    zpass: gs_stencil_op_type
) {
    let device = Unmanaged<MetalDevice>.fromOpaque(devicePointer).takeUnretainedValue()

    if side == GS_STENCIL_FRONT {
        device.state.depthStencilDescriptor.frontFaceStencil.stencilFailureOperation = fail.toMTLOperation()
        device.state.depthStencilDescriptor.frontFaceStencil.depthFailureOperation = zfail.toMTLOperation()
        device.state.depthStencilDescriptor.frontFaceStencil.depthStencilPassOperation = zpass.toMTLOperation()

        device.state.depthStencilDescriptor.backFaceStencil.stencilFailureOperation = .keep
        device.state.depthStencilDescriptor.backFaceStencil.depthFailureOperation = .keep
        device.state.depthStencilDescriptor.backFaceStencil.depthStencilPassOperation = .keep
    } else if side == GS_STENCIL_BACK {
        device.state.depthStencilDescriptor.frontFaceStencil.stencilFailureOperation = .keep
        device.state.depthStencilDescriptor.frontFaceStencil.depthFailureOperation = .keep
        device.state.depthStencilDescriptor.frontFaceStencil.depthStencilPassOperation = .keep

        device.state.depthStencilDescriptor.backFaceStencil.stencilFailureOperation = fail.toMTLOperation()
        device.state.depthStencilDescriptor.backFaceStencil.depthFailureOperation = zfail.toMTLOperation()
        device.state.depthStencilDescriptor.backFaceStencil.depthStencilPassOperation = zpass.toMTLOperation()
    }
}

@_cdecl("device_set_viewport")
public func device_set_viewport(devicePointer: UnsafeRawPointer, x: Int32, y: Int32, width: Int32, height: Int32) {
    let device = Unmanaged<MetalDevice>.fromOpaque(devicePointer).takeUnretainedValue()

    let viewPort = MTLViewport(
        originX: Double(x), originY: Double(y), width: Double(width), height: Double(height), znear: 0.0, zfar: 1.0)

    device.state.viewPort = viewPort
}

@_cdecl("device_get_viewport")
public func device_get_viewport(devicePointer: UnsafeRawPointer, rect: UnsafeMutablePointer<gs_rect>) {
    let device = Unmanaged<MetalDevice>.fromOpaque(devicePointer).takeUnretainedValue()

    rect.pointee.x = Int32(device.state.viewPort.originX)
    rect.pointee.y = Int32(device.state.viewPort.originY)
    rect.pointee.cx = Int32(device.state.viewPort.width)
    rect.pointee.cy = Int32(device.state.viewPort.height)
}

@_cdecl("device_set_scissor_rect")
public func device_set_scissor_rect(devicePointer: UnsafeRawPointer, rect: UnsafePointer<gs_rect>?) {
    let device = Unmanaged<MetalDevice>.fromOpaque(devicePointer).takeUnretainedValue()

    if let rect {
        device.state.scissorRect = rect.pointee.toMTLScissorRect()
        device.state.scissorEnabled = true
    } else {
        device.state.scissorEnabled = false
    }
}

@_cdecl("device_ortho")
public func device_ortho(
    devicePointer: UnsafeRawPointer, left: Float, right: Float, top: Float, bottom: Float, near: Float, far: Float
) {
    let device = Unmanaged<MetalDevice>.fromOpaque(devicePointer).takeUnretainedValue()

    let rml = right - left
    let bmt = bottom - top
    let fmn = far - near

    device.state.projectionMatrix = matrix_float4x4(
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
    devicePointer: UnsafeRawPointer, left: Float, right: Float, top: Float, bottom: Float, near: Float, far: Float
) {
    let device = Unmanaged<MetalDevice>.fromOpaque(devicePointer).takeUnretainedValue()

    let rml = right - left
    let tmb = top - bottom
    let fmn = far - near

    device.state.projectionMatrix = matrix_float4x4(
        columns: (
            SIMD4(((2 * near) / rml), 0.0, 0.0, 0.0),
            SIMD4(0.0, ((2 * near) / tmb), 0.0, 0.0),
            SIMD4(((left + right) / rml), ((top + bottom) / tmb), (-far / fmn), -1.0),
            SIMD4(0.0, 0.0, (-(far * near) / fmn), 0.0)
        )
    )
}

@_cdecl("device_projection_push")
public func device_projection_push(devicePointer: UnsafeRawPointer) {
    let device = Unmanaged<MetalDevice>.fromOpaque(devicePointer).takeUnretainedValue()

    device.projectionStack.push(device.state.projectionMatrix)
}

@_cdecl("device_projection_pop")
public func device_projection_pop(devicePointer: UnsafeRawPointer) {
    let device = Unmanaged<MetalDevice>.fromOpaque(devicePointer).takeUnretainedValue()

    guard device.projectionStack.count > 0 else {
        assertionFailure("device_projection_pop (Metal): Projection matrix stack is empty")
        return
    }

    device.state.projectionMatrix = device.projectionStack.pop()!
}

@_cdecl("gs_timer_destroy")
public func gs_timer_destroy(timer: UnsafeRawPointer) {
    return
}

@_cdecl("gs_timer_begin")
public func gs_timer_begin(timer: UnsafeRawPointer) {
    return
}

@_cdecl("gs_timer_end")
public func gs_timer_end(timer: UnsafeRawPointer) {
    return
}

@_cdecl("gs_timer_get_data")
public func gs_timer_get_data(timer: UnsafeRawPointer) -> Bool {
    return false
}

@_cdecl("gs_timer_range_destroy")
public func gs_timer_range_destroy(range: UnsafeRawPointer) {
    return
}

@_cdecl("gs_timer_range_begin")
public func gs_timer_range_begin(range: UnsafeRawPointer) {
    return
}

@_cdecl("gs_timer_range_end")
public func gs_timer_range_end(range: UnsafeRawPointer) {
    return
}

@_cdecl("gs_timer_range_get_data")
public func gs_timer_range_get_data(range: UnsafeRawPointer, disjoint: Bool, frequency: UInt64) -> Bool {
    return false
}

@_cdecl("device_is_monitor_hdr")
public func device_is_monitor_hdr(device: UnsafeRawPointer) -> Bool {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    return false
}

@_cdecl("device_debug_marker_begin")
public func device_debug_marker_begin(device: UnsafeRawPointer, monitor: UnsafeMutableRawPointer) {
    return
}

@_cdecl("device_debug_marker_end")
public func device_debug_marker_end(device: UnsafeRawPointer) {
    return
}

@_cdecl("device_set_cube_render_target")
public func device_set_cube_render_target(
    device: UnsafeRawPointer, cubetex: UnsafeRawPointer, side: Int, zstencil: UnsafeRawPointer
) {
    return
}
