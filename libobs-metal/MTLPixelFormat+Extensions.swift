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
