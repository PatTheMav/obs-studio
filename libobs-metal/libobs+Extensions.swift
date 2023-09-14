//
//  libobs+Extensions.swift
//  libobs-metal
//
//  Created by Patrick Heyer on 16.04.24.
//

import Metal

extension strref {
    mutating func getString() -> String {
        let buffer = UnsafeRawBufferPointer(start: self.array, count: self.len)

        let string = String(decoding: buffer, as: UTF8.self)

        return string
    }

    mutating func isEqualTo(_ comparison: String) -> Bool {
        return strref_cmp(&self, comparison.cString(using: .utf8)) == 0
    }

    mutating func isEqualToCString(_ comparison: UnsafeMutablePointer<CChar>?) -> Bool {
        if let comparison {
            let result = withUnsafeMutablePointer(to: &self) {
                strref_cmp($0, comparison) == 0
            }

            return result
        }

        return false
    }
}

extension cf_parser {
    mutating func advanceToken() -> Bool {
        let result = withUnsafeMutablePointer(to: &self) {
            cf_next_token($0)
        }

        return result
    }

    mutating func hasNextToken() -> Bool {
        let result = withUnsafeMutablePointer(to: &self) {
            var nextToken: UnsafeMutablePointer<cf_token>?

            switch $0.pointee.cur_token.pointee.type {
            case CFTOKEN_SPACETAB, CFTOKEN_NEWLINE, CFTOKEN_NONE:
                nextToken = $0.pointee.cur_token
            default:
                nextToken = $0.pointee.cur_token.advanced(by: 1)
            }

            if var nextToken {
                while nextToken.pointee.type == CFTOKEN_SPACETAB || nextToken.pointee.type == CFTOKEN_NEWLINE {
                    nextToken = nextToken.successor()
                }

                return nextToken.pointee.type != CFTOKEN_NONE
            } else {
                return false
            }
        }

        return result
    }

    mutating func tokenIsEqualTo(_ comparison: String) -> Bool {
        let result = withUnsafeMutablePointer(to: &self) {
            cf_token_is($0, comparison.cString(using: .utf8))
        }

        return result
    }
}

extension gs_shader_param_type {
    func getSize() -> Int {
        switch self {
        case GS_SHADER_PARAM_BOOL, GS_SHADER_PARAM_INT, GS_SHADER_PARAM_FLOAT:
            return MemoryLayout<Float32>.size
        case GS_SHADER_PARAM_INT2, GS_SHADER_PARAM_VEC2:
            return MemoryLayout<Float32>.size * 2
        case GS_SHADER_PARAM_INT3, GS_SHADER_PARAM_VEC3:
            return MemoryLayout<Float32>.size * 3
        case GS_SHADER_PARAM_INT4, GS_SHADER_PARAM_VEC4:
            return MemoryLayout<Float32>.size * 4
        case GS_SHADER_PARAM_MATRIX4X4:
            return MemoryLayout<Float32>.size * 4 * 4
        case GS_SHADER_PARAM_TEXTURE, GS_SHADER_PARAM_STRING, GS_SHADER_PARAM_UNKNOWN:
            return 0
        default:
            return 0
        }
    }
}

extension gs_color_format {
    func toMTLFormat() -> MTLPixelFormat {
        switch self {
        case GS_UNKNOWN:
            return .invalid
        case GS_A8:
            return .a8Unorm
        case GS_R8:
            return .r8Unorm
        case GS_RGBA:
            return .rgba8Unorm
        case GS_BGRX:
            return .bgra8Unorm
        case GS_BGRA:
            return .bgra8Unorm
        case GS_R10G10B10A2:
            return .rgb10a2Unorm
        case GS_RGBA16:
            return .rgba16Unorm
        case GS_R16:
            return .r16Unorm
        case GS_RGBA16F:
            return .rgba16Float
        case GS_RGBA32F:
            return .rgba32Float
        case GS_RG16F:
            return .rg16Float
        case GS_RG32F:
            return .rg32Float
        case GS_R16F:
            return .r16Float
        case GS_R32F:
            return .r32Float
        case GS_DXT1:
            return .bc1_rgba
        case GS_DXT3:
            return .bc2_rgba
        case GS_DXT5:
            return .bc3_rgba
        case GS_R8G8:
            return .rg8Unorm
        default:
            return .invalid
        }
    }
}

extension gs_color_space {
    func toGSColorFormat() -> gs_color_format {
        switch self {
        case GS_CS_SRGB_16F, GS_CS_709_SCRGB:
            return GS_RGBA16F
        default:
            return GS_RGBA
        }
    }
}

extension gs_depth_test {
    func toMTLFunction() -> MTLCompareFunction {
        switch self {
        case GS_NEVER:
            return .never
        case GS_LESS:
            return .less
        case GS_LEQUAL:
            return .lessEqual
        case GS_EQUAL:
            return .equal
        case GS_GEQUAL:
            return .greaterEqual
        case GS_GREATER:
            return .greater
        case GS_NOTEQUAL:
            return .notEqual
        case GS_ALWAYS:
            return .always
        default:
            return .never
        }
    }
}

extension gs_stencil_op_type {
    func toMTLOperation() -> MTLStencilOperation {
        switch self {
        case GS_KEEP:
            return .keep
        case GS_ZERO:
            return .zero
        case GS_REPLACE:
            return .replace
        case GS_INCR:
            return .incrementWrap
        case GS_DECR:
            return .decrementWrap
        case GS_INVERT:
            return .invert
        default:
            return .keep
        }
    }
}

extension gs_blend_type {
    func toMTLFactor() -> MTLBlendFactor {
        switch self {
        case GS_BLEND_ZERO:
            return .zero
        case GS_BLEND_ONE:
            return .one
        case GS_BLEND_SRCCOLOR:
            return .sourceColor
        case GS_BLEND_INVSRCCOLOR:
            return .oneMinusSourceColor
        case GS_BLEND_SRCALPHA:
            return .sourceAlpha
        case GS_BLEND_INVSRCALPHA:
            return .oneMinusSourceAlpha
        case GS_BLEND_DSTCOLOR:
            return .destinationColor
        case GS_BLEND_INVDSTCOLOR:
            return .oneMinusDestinationColor
        case GS_BLEND_DSTALPHA:
            return .destinationAlpha
        case GS_BLEND_INVDSTALPHA:
            return .oneMinusDestinationAlpha
        case GS_BLEND_SRCALPHASAT:
            return .sourceAlphaSaturated
        default:
            return .one
        }
    }
}

extension gs_blend_op_type {
    func toMTLOperation() -> MTLBlendOperation {
        switch self {
        case GS_BLEND_OP_ADD:
            return .add
        case GS_BLEND_OP_MAX:
            return .max
        case GS_BLEND_OP_MIN:
            return .min
        case GS_BLEND_OP_SUBTRACT:
            return .subtract
        case GS_BLEND_OP_REVERSE_SUBTRACT:
            return .reverseSubtract
        default:
            fatalError("Unsupported blend operation")
        }
    }
}

extension gs_cull_mode {
    func toMTLMode() -> MTLCullMode {
        switch self {
        case GS_BACK:
            return .back
        case GS_FRONT:
            return .front
        case GS_NEITHER:
            return .none
        default:
            return .back
        }
    }
}

extension gs_draw_mode {
    func toMTLPrimitiveType() -> MTLPrimitiveType {
        switch self {
        case GS_POINTS:
            return .point
        case GS_LINES:
            return .line
        case GS_LINESTRIP:
            return .lineStrip
        case GS_TRIS:
            return .triangle
        case GS_TRISTRIP:
            return .triangleStrip
        default:
            return .point
        }
    }
}

extension gs_rect {
    func toMTLViewport() -> MTLViewport {
        let viewport = MTLViewport(
            originX: Double(self.x),
            originY: Double(self.y),
            width: Double(self.cx),
            height: Double(self.cy),
            znear: 0.0,
            zfar: 1.0)

        return viewport
    }

    func toMTLScissorRect() -> MTLScissorRect {
        let scissorRect = MTLScissorRect(
            x: Int(self.x),
            y: Int(self.y),
            width: Int(self.cx),
            height: Int(self.cy))

        return scissorRect
    }
}

extension gs_zstencil_format {
    func toMTLFormat() -> MTLPixelFormat {
        switch self {
        case GS_ZS_NONE:
            return .invalid
        case GS_Z16:
            return .depth16Unorm
        case GS_Z24_S8:
            return .depth24Unorm_stencil8
        case GS_Z32F:
            return .depth32Float
        case GS_Z32F_S8X24:
            return .depth32Float_stencil8
        default:
            return .invalid
        }
    }
}

extension gs_index_type {
    func toMTLType() -> MTLIndexType {
        switch self {
        case GS_UNSIGNED_LONG:
            return .uint16
        case GS_UNSIGNED_SHORT:
            return .uint32
        default:
            fatalError("Unsupported index type")
        }
    }

    func toByteSize() -> Int {
        switch self {
        case GS_UNSIGNED_LONG:
            return 4
        case GS_UNSIGNED_SHORT:
            return 2
        default:
            fatalError("Unsupported index type")
        }
    }
}

extension gs_address_mode {
    func toMTLMode() -> MTLSamplerAddressMode {
        switch self {
        case GS_ADDRESS_WRAP:
            return .repeat
        case GS_ADDRESS_CLAMP:
            return .clampToEdge
        case GS_ADDRESS_MIRROR:
            return .mirrorRepeat
        case GS_ADDRESS_BORDER:
            return .clampToBorderColor
        case GS_ADDRESS_MIRRORONCE:
            return .mirrorClampToEdge
        default:
            return .repeat
        }
    }
}

extension gs_sample_filter {
    func toMTLFilter() -> MTLSamplerMinMagFilter {
        switch self {
        case GS_FILTER_POINT, GS_FILTER_MIN_MAG_POINT_MIP_LINEAR, GS_FILTER_MIN_POINT_MAG_LINEAR_MIP_POINT,
            GS_FILTER_MIN_POINT_MAG_MIP_LINEAR:
            return .nearest
        case GS_FILTER_LINEAR, GS_FILTER_MIN_LINEAR_MAG_MIP_POINT, GS_FILTER_MIN_LINEAR_MAG_POINT_MIP_LINEAR,
            GS_FILTER_MIN_MAG_LINEAR_MIP_POINT, GS_FILTER_ANISOTROPIC:
            return .linear
        default:
            return .nearest
        }
    }

    func toMTLMipFilter() -> MTLSamplerMipFilter {
        switch self {
        case GS_FILTER_POINT, GS_FILTER_MIN_MAG_POINT_MIP_LINEAR, GS_FILTER_MIN_POINT_MAG_LINEAR_MIP_POINT,
            GS_FILTER_MIN_POINT_MAG_MIP_LINEAR:
            return .nearest
        case GS_FILTER_LINEAR, GS_FILTER_MIN_LINEAR_MAG_MIP_POINT, GS_FILTER_MIN_LINEAR_MAG_POINT_MIP_LINEAR,
            GS_FILTER_MIN_MAG_LINEAR_MIP_POINT, GS_FILTER_ANISOTROPIC:
            return .linear
        default:
            return .nearest
        }
    }
}
