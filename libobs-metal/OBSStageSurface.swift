//
//  OBSStageSurface.swift
//  libobs-metal
//
//  Created by Patrick Heyer on 16.04.24.
//

import Foundation
import Metal

// MARK: libobs Graphics API
@_cdecl("device_stagesurface_create")
public func device_stagesurface_create(device: UnsafeRawPointer, width: UInt32, height: UInt32, format: gs_color_format)
    -> OpaquePointer?
{
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: format.toMTLFormat(),
        width: Int(width),
        height: Int(height),
        mipmapped: false
    )

    descriptor.storageMode = .shared

    guard let stageSurface = device.device.makeTexture(descriptor: descriptor) else {
        assertionFailure("device_stagesurface_create (Metal): Failed to create stage surface (\(width)x\(height)")
        return nil
    }

    let texture = OBSTexture(device: device, texture: stageSurface)

    let retained = Unmanaged.passRetained(texture).toOpaque()

    return OpaquePointer(retained)
}

@_cdecl("gs_stagesurface_destroy")
public func gs_stagesurface_destroy(stageSurface: UnsafeRawPointer) {
    let _ = Unmanaged<OBSTexture>.fromOpaque(stageSurface).takeRetainedValue()
}

@_cdecl("gs_stagesurface_get_width")
public func gs_stagesurface_get_width(stageSurface: UnsafeRawPointer) -> UInt32 {
    let stageSurface = Unmanaged<OBSTexture>.fromOpaque(stageSurface).takeUnretainedValue()

    return UInt32(stageSurface.texture.width)
}

@_cdecl("gs_stagesurface_get_height")
public func gs_stagesurface_get_height(stageSurface: UnsafeRawPointer) -> UInt32 {
    let stageSurface = Unmanaged<OBSTexture>.fromOpaque(stageSurface).takeUnretainedValue()

    return UInt32(stageSurface.texture.height)
}

@_cdecl("gs_stagesurface_get_color_format")
public func gs_stagesurface_get_color_format(stageSurface: UnsafeRawPointer) -> gs_color_format {
    let stageSurface = Unmanaged<OBSTexture>.fromOpaque(stageSurface).takeUnretainedValue()

    return stageSurface.texture.pixelFormat.toGSColorFormat()
}

@_cdecl("gs_stagesurface_map")
public func gs_stagesurface_map(
    stageSurface: UnsafeRawPointer, dataPointer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>,
    linesize: UnsafeMutablePointer<UInt32>
) -> Bool {
    let stageSurface = Unmanaged<OBSTexture>.fromOpaque(stageSurface).takeUnretainedValue()
    let device = stageSurface.device

    guard let encoder = device.state.commandBuffer?.makeBlitCommandEncoder() else {
        preconditionFailure("gs_stagesurface_map (Metal): Failed to create blit command encoder")
    }

    encoder.synchronize(texture: stageSurface.texture, slice: 0, level: 0)
    encoder.endEncoding()

    stageSurface.download()

    stageSurface.data.withUnsafeMutableBufferPointer {
        dataPointer.pointee = $0.baseAddress
    }

    linesize.pointee = UInt32(stageSurface.texture.width * stageSurface.texture.pixelFormat.bitsPerPixel() / 8)

    return true
}

@_cdecl("gs_stagesurface_unmap")
public func gs_stagesurface_unmap(tex: UnsafeRawPointer) {
    let stageSurface = Unmanaged<OBSTexture>.fromOpaque(tex).takeUnretainedValue()

    stageSurface.upload()
}
