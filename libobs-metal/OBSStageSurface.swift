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

    descriptor.storageMode = .managed

    guard let stageSurface = device.device.makeTexture(descriptor: descriptor) else {
        assertionFailure("device_stagesurface_create (Metal): Failed to create stage surface (\(width)x\(height)")
        return nil
    }

    let stageSurfaceId = device.textures.insert(stageSurface)
    let resource = OBSAPIResource(device: device, resourceId: stageSurfaceId)

    return resource.getRetained()
}

@_cdecl("gs_stagesurface_destroy")
public func gs_stagesurface_destroy(stageSurface: UnsafeRawPointer) {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(stageSurface).takeRetainedValue()
    let device = resource.device

    device.textures.remove(resource.resourceId)
}

@_cdecl("gs_stagesurface_get_width")
public func gs_stagesurface_get_width(stageSurface: UnsafeRawPointer) -> UInt32 {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(stageSurface).takeUnretainedValue()
    let device = resource.device

    guard let stageSurface = device.textures[resource.resourceId] else {
        assertionFailure("gs_stagesurface_get_width (Metal): Invalid stage surface ID provided")
        return 0
    }

    return UInt32(stageSurface.width)
}

@_cdecl("gs_stagesurface_get_height")
public func gs_stagesurface_get_height(stageSurface: UnsafeRawPointer) -> UInt32 {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(stageSurface).takeUnretainedValue()
    let device = resource.device

    guard let stageSurface = device.textures[resource.resourceId] else {
        assertionFailure("gs_stagesurface_get_height (Metal): Invalid stage surface ID provided")
        return 0
    }

    return UInt32(stageSurface.height)
}

@_cdecl("gs_stagesurface_get_color_format")
public func gs_stagesurface_get_color_format(stageSurface: UnsafeRawPointer) -> gs_color_format {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(stageSurface).takeUnretainedValue()
    let device = resource.device

    guard let stageSurface = device.textures[resource.resourceId] else {
        assertionFailure("gs_stagesurface_get_color_format (Metal): Invalid stage surface ID provided")
        return GS_UNKNOWN
    }

    return stageSurface.pixelFormat.toGSColorFormat()
}

@_cdecl("gs_stagesurface_map")
public func gs_stagesurface_map(
    stageSurface: UnsafeRawPointer, dataPointer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>,
    linesize: UnsafeMutablePointer<UInt32>
) -> Bool {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(stageSurface).takeUnretainedValue()
    let device = resource.device

    guard let stageSurface = device.textures[resource.resourceId] else {
        assertionFailure("gs_stagesurface_map (Metal): Invalid stage surface ID provided")
        return false
    }

    guard let encoder = device.state.commandBuffer?.makeBlitCommandEncoder() else {
        preconditionFailure("gs_stagesurface_map (Metal): Failed to create blit command encoder")
    }

    encoder.synchronize(texture: stageSurface, slice: 0, level: 0)
    encoder.endEncoding()

    resource.data = stageSurface.download()

    guard var data = resource.data else {
        assertionFailure("gs_stagesurface_map (Metal): Failed to download texture data")
        return false
    }

    data.withUnsafeMutableBufferPointer {
        dataPointer.pointee = $0.baseAddress ?? nil
    }

    linesize.pointee = UInt32(stageSurface.width * stageSurface.pixelFormat.bitsPerPixel() / 8)

    return true
}

@_cdecl("gs_stagesurface_unmap")
public func gs_stagesurface_unmap(tex: UnsafeRawPointer) {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(tex).takeUnretainedValue()
    resource.data = nil
}
