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
public func device_stagesurface_create_OLD(
    device: UnsafeRawPointer, width: UInt32, height: UInt32, format: gs_color_format
)
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
public func gs_stagesurface_destroy_OLD(stageSurface: UnsafeRawPointer) {
    let _ = Unmanaged<OBSTexture>.fromOpaque(stageSurface).takeRetainedValue()
}

@_cdecl("gs_stagesurface_get_width")
public func gs_stagesurface_get_width_OLD(stageSurface: UnsafeRawPointer) -> UInt32 {
    let stageSurface = Unmanaged<OBSTexture>.fromOpaque(stageSurface).takeUnretainedValue()

    return UInt32(stageSurface.texture.width)
}

@_cdecl("gs_stagesurface_get_height")
public func gs_stagesurface_get_height_OLD(stageSurface: UnsafeRawPointer) -> UInt32 {
    let stageSurface = Unmanaged<OBSTexture>.fromOpaque(stageSurface).takeUnretainedValue()

    return UInt32(stageSurface.texture.height)
}

@_cdecl("gs_stagesurface_get_color_format")
public func gs_stagesurface_get_color_format_OLD(stageSurface: UnsafeRawPointer) -> gs_color_format {
    let stageSurface = Unmanaged<OBSTexture>.fromOpaque(stageSurface).takeUnretainedValue()

    return stageSurface.texture.pixelFormat.toGSColorFormat()
}

@_cdecl("gs_stagesurface_map")
public func gs_stagesurface_map_OLD(
    stageSurface: UnsafeRawPointer, dataPointer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>,
    linesize: UnsafeMutablePointer<UInt32>
) -> Bool {
    let stageSurface = Unmanaged<OBSTexture>.fromOpaque(stageSurface).takeUnretainedValue()

    let rowSize = stageSurface.texture.width * stageSurface.texture.pixelFormat.bitsPerPixel() / 8
    let dataSize = rowSize * stageSurface.texture.height
    let region = MTLRegionMake2D(0, 0, stageSurface.texture.width, stageSurface.texture.height)

    let textureData = UnsafeMutableRawBufferPointer.allocate(byteCount: dataSize, alignment: 8)

    if let textureData = textureData.baseAddress {
        stageSurface.texture.getBytes(textureData, bytesPerRow: rowSize, from: region, mipmapLevel: 0)

        dataPointer.pointee = textureData.assumingMemoryBound(to: UInt8.self)
        linesize.pointee = UInt32(rowSize)

        stageSurface.data = textureData
        return true
    } else {
        return false
    }
}

@_cdecl("gs_stagesurface_unmap")
public func gs_stagesurface_unmap_OLD(tex: UnsafeRawPointer) {
    let stageSurface = Unmanaged<OBSTexture>.fromOpaque(tex).takeUnretainedValue()

    let rowSize = stageSurface.texture.width * stageSurface.texture.pixelFormat.bitsPerPixel() / 8
    let region = MTLRegionMake2D(0, 0, stageSurface.texture.width, stageSurface.texture.height)

    if let textureData = stageSurface.data {
        stageSurface.texture.replace(region: region, mipmapLevel: 0, withBytes: textureData, bytesPerRow: rowSize)

        textureData.deallocate()
    }
}
