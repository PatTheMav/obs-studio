//
//  OBSTexture.swift
//  libobs-metal
//
//  Created by Patrick Heyer on 16.04.24.
//

import Foundation
import Metal

extension MetalDevice {
    func makeTexture2D(
        width: Int, height: Int, pixelFormat: MTLPixelFormat, mipLevels: Int, renderTarget: Bool, mipmapped: Bool
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: mipmapped
        )

        descriptor.arrayLength = 1
        descriptor.cpuCacheMode = .writeCombined
        descriptor.storageMode = .managed
        descriptor.usage = renderTarget ? [.shaderRead, .renderTarget] : .shaderRead

        if mipmapped {
            descriptor.mipmapLevelCount = mipLevels
        }

        return device.makeTexture(descriptor: descriptor)
    }

    func makeTextureCube(size: Int, pixelFormat: MTLPixelFormat, mipLevels: Int, mipmapped: Bool) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: pixelFormat,
            size: 6 * size * size,
            mipmapped: mipmapped
        )

        descriptor.arrayLength = 6
        descriptor.cpuCacheMode = .writeCombined
        descriptor.storageMode = .managed
        descriptor.usage = .shaderRead

        if mipmapped {
            descriptor.mipmapLevelCount = mipLevels
        }

        return device.makeTexture(descriptor: descriptor)
    }

    func makeTextureFromIOSurface(surface: IOSurfaceRef) -> MTLTexture? {
        let surfacePixelFormat = IOSurfaceGetPixelFormat(surface)

        guard
            surfacePixelFormat == FourCharCode(stringLiteral: "l10r")
                || surfacePixelFormat == FourCharCode(stringLiteral: "BGRA")
        else {
            assertionFailure("MetalDevice: IOSurface pixel format is neither BGRA or l10r")
            return nil
        }

        let pixelFormat: MTLPixelFormat =
            switch surfacePixelFormat.string {
            case "BGRA": .bgra8Unorm
            case "l10r": .bgr10a2Unorm
            default: .invalid
            }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: IOSurfaceGetWidth(surface),
            height: IOSurfaceGetHeight(surface),
            mipmapped: false
        )

        return device.makeTexture(descriptor: descriptor, iosurface: surface, plane: 0)
    }
}

// MARK: libobs Graphics API

@_cdecl("device_texture_create")
public func device_texture_create(
    device: UnsafeRawPointer, width: UInt32, height: UInt32, colorFormat: gs_color_format, levels: UInt32,
    textureData: UnsafePointer<UnsafePointer<UInt8>>?, flags: UInt32
) -> OpaquePointer? {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    let texture = device.makeTexture2D(
        width: Int(width),
        height: Int(height),
        pixelFormat: colorFormat.toMTLFormat(),
        mipLevels: Int(levels),
        renderTarget: (Int32(flags) & GS_RENDER_TARGET) != 0,
        mipmapped: (Int32(flags) & GS_BUILD_MIPMAPS) != 0
    )

    guard let texture else {
        assertionFailure("device_texture_create (Metal): Failed to create texture (\(width)x\(height))")
        return nil
    }

    let textureId = device.textures.insert(texture)
    let resource = OBSAPIResource(device: device, resourceId: textureId)

    if let textureData {
        var data = [[UInt8]]()
        var levelWidth = width
        var levelHeight = height

        for level in 0..<levels {
            let dataSize = Int(levelWidth * levelHeight) * texture.pixelFormat.bitsPerPixel() / 8
            let dataArray = Array(
                UnsafeBufferPointer(start: textureData.advanced(by: Int(level)).pointee, count: dataSize)
            )

            data.append(dataArray)

            levelWidth = levelWidth / 2
            levelHeight = levelHeight / 2
        }

        resource.data = data[0]

        texture.upload(data: data)

        if (Int32(flags) & GS_BUILD_MIPMAPS) != 0 {
            guard let encoder = device.state.commandBuffer?.makeBlitCommandEncoder() else {
                assertionFailure("device_texture_create (Metal): No command buffer available")
                return nil
            }

            encoder.generateMipmaps(for: texture)
            encoder.endEncoding()
        }
    }

    return resource.getRetained()
}

@_cdecl("device_cubetexture_create")
public func device_cubetexture_create(
    device: UnsafeRawPointer, size: UInt32, colorFormat: gs_color_format, levels: UInt32,
    textureData: UnsafePointer<UnsafePointer<UInt8>>?, flags: UInt32
) -> OpaquePointer? {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    let texture = device.makeTextureCube(
        size: Int(size),
        pixelFormat: colorFormat.toMTLFormat(),
        mipLevels: Int(levels),
        mipmapped: (Int32(flags) & GS_BUILD_MIPMAPS) != 0
    )

    guard let texture else {
        assertionFailure("device_cubetexture_create (Metal): Failed to create texture (\(size))")
        return nil
    }

    let textureId = device.textures.insert(texture)
    let resource = OBSAPIResource(device: device, resourceId: textureId)

    if let textureData {
        var data = [[UInt8]]()
        var levelWidth = size
        var levelHeight = size

        for level in 0..<levels {
            let dataSize = Int(levelWidth * levelHeight) * texture.pixelFormat.bitsPerPixel() / 8
            let dataArray = Array(
                UnsafeBufferPointer(start: textureData.advanced(by: Int(level)).pointee, count: dataSize)
            )
            data.append(dataArray)

            levelWidth = levelWidth / 2
            levelHeight = levelHeight / 2
        }

        resource.data = data[0]
        texture.upload(data: data)

        if (Int32(flags) & GS_BUILD_MIPMAPS) != 0 {
            guard let encoder = device.state.commandBuffer?.makeBlitCommandEncoder() else {
                assertionFailure("device_cubetexture_create (Metal): No command buffer available")
                return nil
            }

            encoder.generateMipmaps(for: texture)
            encoder.endEncoding()
        }
    }

    return resource.getRetained()
}

@_cdecl("device_voltexture_create")
public func device_voltexture_create(
    device: UnsafeRawPointer, width: UInt32, height: UInt32, depth: UInt32, colorFormat: gs_color_format,
    levels: UInt32, data: UnsafePointer<UnsafePointer<UInt8>>, flags: UInt32
) -> OpaquePointer? {
    return nil
}

@_cdecl("gs_texture_destroy")
public func gs_texture_destroy(texture: UnsafeRawPointer) {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(texture).takeRetainedValue()
    let device = resource.device

    device.textures.remove(resource.resourceId)
}

@_cdecl("device_get_texture_type")
public func device_get_texture_type(texture: UnsafeRawPointer) -> gs_texture_type {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(texture).takeUnretainedValue()
    let device = resource.device

    guard let type = device.textures[resource.resourceId]?.textureType else {
        preconditionFailure("device_get_texture_type (Metal): Invalid texture ID provided")
    }

    return type.toGSTextureType()
}

/// Loads a texture into a texture unit
///
/// The provided ``MetalResource`` instance contains the ID of the texture and will be used to find a preconfigured ``OBSTexture`` instance. If found, the reference will be added to the ``OBSMetalDevice`` `currentTextures` collection at the index provided by the texture unit variable.
///
/// - Parameters:
///   - device: Opaque pointer to ``MetalRenderer`` instance
///   - tex: Opaque pointer to  ``MetalResource`` instance
///   - unit: Texture unit for which the texture should be set up
@_cdecl("device_load_texture")
public func device_load_texture(device: UnsafeRawPointer, tex: UnsafeRawPointer, unit: Int) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(tex).takeUnretainedValue()

    guard let texture = device.textures[resource.resourceId] else {
        preconditionFailure("device_load_texture (Metal): Invalid texture ID provided")
    }

    device.state.textures[unit] = texture
}

@_cdecl("device_copy_texture_region")
public func device_copy_texture_region(
    device: UnsafeRawPointer, dst: UnsafeRawPointer, dst_x: UInt32, dst_y: UInt32, src: UnsafeRawPointer, src_x: UInt32,
    src_y: UInt32, src_w: UInt32, src_h: UInt32
) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()
    let sourceResource = Unmanaged<OBSAPIResource>.fromOpaque(src).takeUnretainedValue()
    let destinationResource = Unmanaged<OBSAPIResource>.fromOpaque(dst).takeUnretainedValue()

    guard let sourceTexture = device.textures[sourceResource.resourceId] else {
        preconditionFailure("device_copy_texture_region (Metal): Invalid source texture ID provided")
    }

    guard let destinationTexture = device.textures[destinationResource.resourceId] else {
        preconditionFailure("device_copy_texture_region (Metal): Invalid destination texture ID provided")
    }

    let sourceOrigin = MTLOrigin(x: Int(src_x), y: Int(src_y), z: 0)
    let destinationOrigin = MTLOrigin(x: Int(dst_x), y: Int(dst_y), z: 0)
    let size = MTLSize(width: Int(src_w), height: Int(src_h), depth: 1)

    let copyWidth =
        switch size.width {
        case 0: sourceTexture.width - sourceOrigin.x
        default: size.width
        }
    let copyHeight =
        switch size.height {
        case 0: sourceTexture.height - sourceOrigin.y
        default: size.height
        }

    let destinationWidth = destinationTexture.width - destinationOrigin.x
    let destinationHeight = destinationTexture.height - destinationOrigin.y

    guard destinationWidth >= copyWidth && destinationHeight >= copyHeight else {
        preconditionFailure(
            "device_copy_texture_region (Metal): Destination region is not large enough to hold source region")
    }

    let actualSize = MTLSize(width: copyWidth, height: copyHeight, depth: 1)

    guard let encoder = device.state.commandBuffer?.makeBlitCommandEncoder() else {
        preconditionFailure("device_copy_texture_region (Metal): Failed to create blit command encoder")
    }

    encoder.copy(
        from: sourceTexture,
        sourceSlice: 0,
        sourceLevel: 0,
        sourceOrigin: sourceOrigin,
        sourceSize: actualSize,
        to: destinationTexture,
        destinationSlice: 0,
        destinationLevel: 0,
        destinationOrigin: destinationOrigin
    )

    encoder.endEncoding()
}

@_cdecl("device_copy_texture")
public func device_copy_texture(device: UnsafeRawPointer, dst: UnsafeRawPointer, src: UnsafeRawPointer) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()
    let sourceResource = Unmanaged<OBSAPIResource>.fromOpaque(src).takeUnretainedValue()
    let destinationResource = Unmanaged<OBSAPIResource>.fromOpaque(dst).takeUnretainedValue()

    guard let sourceTexture = device.textures[sourceResource.resourceId] else {
        preconditionFailure("device_copy_texture (Metal): Invalid source texture ID provided")
    }

    guard let destinationTexture = device.textures[destinationResource.resourceId] else {
        preconditionFailure("device_copy_texture (Metal): Invalid destination texture ID provided")
    }

    guard let encoder = device.state.commandBuffer?.makeBlitCommandEncoder() else {
        preconditionFailure("device_copy_texture (Metal): Failed to create blit command encoder")
    }

    encoder.copy(from: sourceTexture, to: destinationTexture)
    encoder.endEncoding()
}

@_cdecl("device_stage_texture")
public func device_stage_texture(device: UnsafeRawPointer, dst: UnsafeRawPointer, src: UnsafeRawPointer) {
    device_copy_texture(device: device, dst: dst, src: src)
}

@_cdecl("gs_texture_get_width")
public func gs_texture_get_width(tex: UnsafeRawPointer) -> UInt32 {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(tex).takeUnretainedValue()
    let device = resource.device

    guard let texture = device.textures[resource.resourceId] else {
        preconditionFailure("gs_texture_get_width (Metal): Invalid texture ID provided")
    }

    if texture.textureType == .type2D {
        return UInt32(texture.width)
    }

    return 0
}

@_cdecl("gs_texture_get_height")
public func gs_texture_get_height(tex: UnsafeRawPointer) -> UInt32 {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(tex).takeUnretainedValue()
    let device = resource.device

    guard let texture = device.textures[resource.resourceId] else {
        preconditionFailure("gs_texture_get_height (Metal): Invalid texture ID provided")
    }

    if texture.textureType == .type2D {
        return UInt32(texture.height)
    }

    return 0
}

@_cdecl("gs_texture_get_color_format")
public func gs_texture_get_color_format(tex: UnsafeRawPointer) -> gs_color_format {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(tex).takeUnretainedValue()
    let device = resource.device

    guard let texture = device.textures[resource.resourceId] else {
        preconditionFailure("gs_texture_get_color_format (Metal): Invalid texture ID provided")
    }

    if texture.textureType == .type2D {
        return texture.pixelFormat.toGSColorFormat()
    }

    return GS_UNKNOWN
}

@_cdecl("gs_texture_map")
public func gs_texture_map(
    tex: UnsafeRawPointer, ptr: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>,
    linesize: UnsafeMutablePointer<UInt32>
) -> Bool {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(tex).takeUnretainedValue()
    let device = resource.device

    guard let texture = device.textures[resource.resourceId] else {
        preconditionFailure("gs_texture_map (Metal): Invalid texture ID provided")
    }

    guard texture.textureType == .type2D else {
        return false
    }

    resource.data = texture.download()

    guard resource.data != nil else {
        assertionFailure("gs_texture_map (Metal): Failed to download texture data")
        return false
    }

    resource.data!.withUnsafeMutableBufferPointer {
        ptr.pointee = $0.baseAddress ?? nil
    }

    linesize.pointee = UInt32(texture.width * texture.pixelFormat.bitsPerPixel() / 8)

    return true
}

@_cdecl("gs_texture_unmap")
public func gs_texture_unmap(tex: UnsafeRawPointer) {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(tex).takeUnretainedValue()
    let device = resource.device

    guard let texture = device.textures[resource.resourceId] else {
        preconditionFailure("gs_texture_unmap (Metal): Invalid texture ID provided")
    }

    guard texture.textureType == .type2D else {
        return
    }

    if resource.data != nil {
        var textureData = [[UInt8]]()
        textureData.append(resource.data!)

        texture.upload(data: textureData)
    }
}

@_cdecl("gs_texture_get_obj")
public func gs_texture_get_obj(tex: UnsafeRawPointer) -> OpaquePointer? {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(tex).takeUnretainedValue()
    let device = resource.device

    guard let texture = device.textures[resource.resourceId] else {
        preconditionFailure("gs_texture_get_obj (Metal): Invalid texture ID provided")
    }

    guard texture.textureType == .type2D else {
        return nil
    }

    let unretained = Unmanaged.passUnretained(texture).toOpaque()
    return OpaquePointer(unretained)
}

@_cdecl("gs_cubetexture_destroy")
public func gs_cubetexture_destroy(cubetex: UnsafeRawPointer) {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(cubetex).takeRetainedValue()
    let device = resource.device

    device.textures.remove(resource.resourceId)
}

@_cdecl("gs_cubetexture_get_size")
public func gs_cubetexture_get_size(cubetex: UnsafeRawPointer) -> UInt32 {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(cubetex).takeUnretainedValue()
    let device = resource.device

    guard let texture = device.textures[resource.resourceId] else {
        preconditionFailure("gs_cubetexture_get_size (Metal): Invalid texture ID provided")
    }

    guard texture.textureType == .typeCube else {
        return 0
    }

    return UInt32(texture.width)
}

@_cdecl("gs_cubetexture_get_color_format")
public func gs_cubetexture_get_color_format(cubetex: UnsafeRawPointer) -> gs_color_format {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(cubetex).takeUnretainedValue()
    let device = resource.device

    guard let texture = device.textures[resource.resourceId] else {
        preconditionFailure("gs_cubetexture_get_color_format (Metal): Invalid texture ID provided")
    }

    guard texture.textureType == .typeCube else {
        return GS_UNKNOWN
    }

    return texture.pixelFormat.toGSColorFormat()
}

@_cdecl("gs_voltexture_destroy")
public func gs_voltexture_destroy(tex: UnsafeRawPointer) {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(tex).takeRetainedValue()
    let device = resource.device

    device.textures.remove(resource.resourceId)
}

@_cdecl("gs_voltexture_get_width")
public func gs_voltexture_get_width(voltex: UnsafeRawPointer) -> UInt32 {
    return 0
}

@_cdecl("gs_voltexture_get_height")
public func gs_voltexture_get_height(voltex: UnsafeRawPointer) -> UInt32 {
    return 0
}

@_cdecl("gs_voltexture_get_depth")
public func gs_voltexture_get_depth(voltex: UnsafeRawPointer) -> UInt32 {
    return 0
}

@_cdecl("gs_voltexture_get_color_format")
public func gs_voltexture_get_color_format(voltex: UnsafeRawPointer) -> gs_color_format {
    return GS_UNKNOWN
}

@_cdecl("device_shared_texture_available")
public func device_shared_texture_available(device: UnsafeRawPointer) -> Bool {
    return true
}

@_cdecl("device_texture_create_from_iosurface")
public func device_texture_create_from_iosurface(device: UnsafeRawPointer, iosurf: IOSurfaceRef) -> OpaquePointer? {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    guard let texture = device.makeTextureFromIOSurface(surface: iosurf) else {
        assertionFailure("device_texture_create_from_iosurface (Metal): Failed to create texture")
        return nil
    }

    let textureId = device.textures.insert(texture)
    let resource = OBSAPIResource(device: device, resourceId: textureId)
    return resource.getRetained()
}

@_cdecl("gs_texture_rebind_iosurface")
public func gs_texture_rebind_iosurface(texture: UnsafeRawPointer, iosurf: IOSurfaceRef) -> Bool {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(texture).takeUnretainedValue()
    let device = resource.device

    guard let texture = device.makeTextureFromIOSurface(surface: iosurf) else {
        assertionFailure("device_texture_create_from_iosurface (Metal): Failed to create texture")
        return false
    }

    device.textures.replaceAt(resource.resourceId, texture)

    return true
}

@_cdecl("device_texture_open_shared")
public func device_texture_open_shared(device: UnsafeRawPointer, handle: UInt32) -> OpaquePointer? {
    if let ref = IOSurfaceLookupFromMachPort(handle) {
        let texture = device_texture_create_from_iosurface(device: device, iosurf: ref)

        return texture
    } else {
        return nil
    }
}
