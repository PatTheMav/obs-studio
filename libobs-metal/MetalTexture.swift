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

private let bgraSurfaceFormat: FourCharCode = 0x42_47_52_41
private let l10rSurfaceFormat: FourCharCode = 0x6C_31_30_72

struct MetalTextureDescription {
    let type: MTLTextureType
    let width: Int
    let height: Int
    let depth: Int
    let pixelFormat: MTLPixelFormat
    let mipmapLevels: Int
    let isRenderTarget: Bool
    let isMipMapped: Bool
}

enum MetalTextureMapMode {
    case unmapped
    case read
    case write
}

struct MetalTextureMapping {
    let mode: MetalTextureMapMode
    let rowSize: Int
    let data: UnsafeMutableRawPointer
}

class MetalTexture: Equatable {
    private let device: MetalDevice
    private let resourceID: Int
    private var mappingMode: MetalTextureMapMode

    public var data: UnsafeMutableRawPointer?
    public var texture: MTLTexture
    public var type: MTLTextureType {
        texture.textureType
    }

    static func == (lhs: MetalTexture, rhs: MetalTexture) -> Bool {
        lhs.resourceID == rhs.resourceID
    }

    static func != (lhs: MetalTexture, rhs: MetalTexture) -> Bool {
        lhs.resourceID != rhs.resourceID
    }

    private static func bindSurface(device: MetalDevice, surface: IOSurfaceRef) -> MTLTexture? {
        let pixelFormat = IOSurfaceGetPixelFormat(surface)
        let texturePixelFormat: MTLPixelFormat =
            switch pixelFormat {
            case bgraSurfaceFormat: .bgra8Unorm
            case l10rSurfaceFormat: .bgr10a2Unorm
            default: .invalid
            }

        guard texturePixelFormat != .invalid else {
            assertionFailure("MetalDevice: IOSurface pixel format is not supported")
            return nil
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texturePixelFormat,
            width: IOSurfaceGetWidth(surface),
            height: IOSurfaceGetHeight(surface),
            mipmapped: false)

        descriptor.usage = [.shaderRead]

        let texture = device.makeTexture(descriptor)

        return texture
    }

    init?(device: MetalDevice, description: MetalTextureDescription) {
        self.device = device

        let descriptor: MTLTextureDescriptor

        switch description.type {
        case .type2D:
            descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: description.pixelFormat,
                width: description.width,
                height: description.height,
                mipmapped: description.isMipMapped
            )
            descriptor.arrayLength = 1
        case .type3D:
            descriptor = MTLTextureDescriptor()
            descriptor.textureType = .type3D
            descriptor.pixelFormat = description.pixelFormat
            descriptor.width = description.width
            descriptor.height = description.height
            descriptor.depth = description.depth
            descriptor.arrayLength = 1
        case .typeCube:
            descriptor = MTLTextureDescriptor.textureCubeDescriptor(
                pixelFormat: description.pixelFormat,
                size: description.width * 6 * 6,
                mipmapped: description.isMipMapped
            )
            descriptor.arrayLength = 6
        default:
            assertionFailure("MetalTexture: Unsupported texture format: \(description.type)")
            return nil
        }

        descriptor.cpuCacheMode = .writeCombined
        descriptor.storageMode =
            switch description.isRenderTarget {
            case true: .private
            case false: .shared
            }
        descriptor.usage =
            switch description.isRenderTarget {
            case true: [.shaderRead, .renderTarget]
            case false: .shaderRead
            }

        if description.type != .type3D && description.isMipMapped {
            descriptor.mipmapLevelCount = description.mipmapLevels
        }

        let texture = device.makeTexture(descriptor)

        guard let texture else {
            assertionFailure(
                "MetalTexture: Failed to create texture with size \(description.width)x\(description.height)")
            return nil
        }

        self.texture = texture

        self.resourceID = Hasher().finalize()
        self.mappingMode = .unmapped
    }

    init?(device: MetalDevice, surface: IOSurfaceRef) {
        self.device = device

        guard let texture = MetalTexture.bindSurface(device: device, surface: surface) else {
            assertionFailure("MetalTexture: Failed to create texture with IOSurface")
            return nil
        }

        self.texture = texture
        self.resourceID = Hasher().finalize()
        self.mappingMode = .unmapped
    }

    init?(device: MetalDevice, texture: MTLTexture) {
        self.device = device
        self.texture = texture
        self.resourceID = Hasher().finalize()
        self.mappingMode = .unmapped
    }

    func rebind(surface: IOSurfaceRef) -> Bool {
        guard let texture = MetalTexture.bindSurface(device: device, surface: surface) else {
            assertionFailure("MetalTexture: Failed to rebind IOSurface to texture")
            return false
        }

        self.texture = texture

        return true
    }

    func download(data: UnsafeMutableRawPointer, mipmapLevel: Int = 0) {
        let mipmapWidth = texture.width >> mipmapLevel
        let mipmapHeight = texture.height >> mipmapLevel

        let rowSize = mipmapWidth * texture.pixelFormat.bitsPerPixel() / 8
        let region = MTLRegionMake2D(0, 0, mipmapWidth, mipmapHeight)

        texture.getBytes(data, bytesPerRow: rowSize, from: region, mipmapLevel: mipmapLevel)
    }

    func upload(data: UnsafePointer<UnsafePointer<UInt8>?>, mipmapLevels: Int) {
        let bytesPerPixel = texture.pixelFormat.bitsPerPixel() / 8

        switch texture.textureType {
        case .type2D, .typeCube:
            let textureCount = if texture.textureType == .typeCube { 6 } else { 1 }

            let data = UnsafeBufferPointer(start: data, count: (textureCount * mipmapLevels))

            for i in 0..<textureCount {
                for mipmapLevel in 0..<mipmapLevels {
                    let index = mipmapLevels * i + mipmapLevel

                    guard let data = data[index] else { break }

                    let mipmapWidth = texture.width >> mipmapLevel
                    let mipmapHeight = texture.height >> mipmapLevel
                    let rowSize = mipmapWidth * bytesPerPixel
                    let imageSize = rowSize * mipmapHeight

                    let region = MTLRegionMake2D(0, 0, mipmapWidth, mipmapHeight)

                    texture.replace(
                        region: region, mipmapLevel: mipmapLevel, slice: i, withBytes: data, bytesPerRow: rowSize,
                        bytesPerImage: imageSize)
                }
            }
        case .type3D:
            let data = UnsafeBufferPointer(start: data, count: mipmapLevels)

            for (mipmapLevel, mipmapData) in data.enumerated() {
                guard let mipmapData else { break }

                let mipmapWidth = texture.width >> mipmapLevel
                let mipmapHeight = texture.height >> mipmapLevel
                let mipmapDepth = texture.depth >> mipmapLevel
                let rowSize = mipmapWidth * bytesPerPixel
                let imageSize = rowSize * mipmapHeight

                let region = MTLRegionMake3D(0, 0, 0, mipmapWidth, mipmapHeight, mipmapDepth)

                texture.replace(
                    region: region,
                    mipmapLevel: mipmapLevel,
                    slice: 0,
                    withBytes: mipmapData,
                    bytesPerRow: rowSize,
                    bytesPerImage: imageSize
                )
            }
        default:
            assertionFailure("MetalTexture: Unsupported texture type \(texture.textureType)")
            return
        }

        if texture.mipmapLevelCount > 1 {
            guard let encoder = device.renderState.commandBuffer?.makeBlitCommandEncoder() else {
                assertionFailure("MetalDevice: Unable to create Blit command encoder")
                return
            }

            encoder.generateMipmaps(for: texture)
            encoder.endEncoding()
        }
    }

    func map(mode: MetalTextureMapMode, mipmapLevel: Int = 0) -> MetalTextureMapping? {
        guard mappingMode == .unmapped else {
            assertionFailure("MetalTexture: Attempted to map already-mapped texture.")
            return nil
        }

        let mipmapWidth = texture.width >> mipmapLevel
        let mipmapHeight = texture.height >> mipmapLevel

        let rowSize = mipmapWidth * texture.pixelFormat.bitsPerPixel() / 8
        let dataSize = rowSize * mipmapHeight

        let data = UnsafeMutableRawBufferPointer.allocate(byteCount: dataSize, alignment: 1)

        guard let baseAddress = data.baseAddress else {
            return nil
        }

        if mode == .read {
            download(data: baseAddress, mipmapLevel: mipmapLevel)
        }

        self.data = baseAddress
        self.mappingMode = mode

        let mapping = MetalTextureMapping(
            mode: mode,
            rowSize: rowSize,
            data: baseAddress
        )

        return mapping
    }

    func unmap(mipmapLevel: Int = 0) {
        guard mappingMode != .unmapped else {
            assertionFailure("MetalTexture: Attempted to unmap an unmapped texture")
            return
        }

        let mipmapWidth = texture.width >> mipmapLevel
        let mipmapHeight = texture.height >> mipmapLevel

        let rowSize = mipmapWidth * texture.pixelFormat.bitsPerPixel() / 8
        let region = MTLRegionMake2D(0, 0, mipmapWidth, mipmapHeight)

        if let textureData = self.data {
            if self.mappingMode == .write {
                texture.replace(
                    region: region,
                    mipmapLevel: mipmapLevel,
                    withBytes: textureData,
                    bytesPerRow: rowSize
                )
            }

            textureData.deallocate()
            self.data = nil
        }

        self.mappingMode = .unmapped
    }

    func copyRegion(to destination: MetalTexture, sourceOrigin: MTLOrigin, size: MTLSize, destinationOrigin: MTLOrigin)
    {

        let copyWidth =
            switch size.width {
            case 0: texture.width - sourceOrigin.x
            default: size.width
            }
        let copyheight =
            switch size.height {
            case 0: texture.height - sourceOrigin.y
            default: size.height
            }

        let destinationWidth = destination.texture.width - destinationOrigin.x
        let destinationHeight = destination.texture.height - destinationOrigin.y

        guard destinationWidth >= copyWidth && destinationHeight >= copyheight else {
            preconditionFailure(
                "device_copy_texture_region: Destination region is not large enough to hold source region")
        }

        let actualSize = MTLSize(width: copyWidth, height: copyheight, depth: 1)

        guard let encoder = device.renderState.commandBuffer?.makeBlitCommandEncoder() else {
            assertionFailure("MetalDevice: Unable to create Blit command encoder")
            return
        }

        encoder.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: sourceOrigin,
            sourceSize: actualSize,
            to: destination.texture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: destinationOrigin
        )

        encoder.endEncoding()
    }

    func copy(to destination: MetalTexture) {
        guard let encoder = device.renderState.commandBuffer?.makeBlitCommandEncoder() else {
            assertionFailure("MetalDevice: Unable to create Blit command encoder")
            return
        }

        encoder.copy(from: texture, to: destination.texture)
        encoder.endEncoding()
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
