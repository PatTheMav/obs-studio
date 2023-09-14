//
//  OBSZStencilBuffer.swift
//  libobs-metal
//
//  Created by Patrick Heyer on 16.04.24.
//

import Foundation
import Metal

// MARK: libobs Graphics API

@_cdecl("device_zstencil_create")
public func device_zstencil_create(device: UnsafeRawPointer, width: UInt32, height: UInt32, format: gs_zstencil_format)
    -> OpaquePointer?
{
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    let stencilBuffer = device.makeTexture2D(
        width: Int(width),
        height: Int(height),
        pixelFormat: format.toMTLFormat(),
        mipLevels: 0,
        renderTarget: false,
        mipmapped: false
    )

    guard let stencilBuffer else {
        assertionFailure("device_zstencil_create (Metal): Failed to create texture (\(width)x\(height))")
        return nil
    }

    let stencilBufferId = device.textures.insert(stencilBuffer)
    let resource = OBSAPIResource(device: device, resourceId: stencilBufferId)

    return resource.getRetained()
}

@_cdecl("device_get_zstencil_target")
public func device_get_zstencil_target(device: UnsafeRawPointer) -> OpaquePointer? {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    let stencilBuffer = device.state.stencilAttachment

    guard let stencilBuffer else {
        return nil
    }

    let unretained = Unmanaged.passUnretained(stencilBuffer).toOpaque()
    return OpaquePointer(unretained)
}

@_cdecl("gs_zstencil_destroy")
public func gs_zstencil_destroy(zstencil: UnsafeRawPointer) {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(zstencil).takeRetainedValue()
    let device = resource.device

    device.textures.remove(resource.resourceId)
}
