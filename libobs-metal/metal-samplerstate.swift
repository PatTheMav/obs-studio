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

@_cdecl("device_samplerstate_create")
public func device_samplerstate_create(device: UnsafeRawPointer, info: gs_sampler_info) -> OpaquePointer? {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    let descriptor = MTLSamplerDescriptor()

    descriptor.sAddressMode = info.address_u.toMTLMode()
    descriptor.tAddressMode = info.address_v.toMTLMode()
    descriptor.rAddressMode = info.address_w.toMTLMode()

    descriptor.minFilter = info.filter.toMTLFilter()
    descriptor.magFilter = info.filter.toMTLFilter()
    descriptor.mipFilter = info.filter.toMTLMipFilter()

    descriptor.maxAnisotropy = Int(info.max_anisotropy)

    descriptor.compareFunction = .always
    descriptor.borderColor =
        if (info.border_color & 0x00_00_00_FF) == 0 {
            .transparentBlack
        } else if info.border_color == 0xFF_FF_FF_FF {
            .opaqueWhite
        } else {
            .opaqueBlack
        }

    guard let samplerState = device.makeSamplerState(descriptor: descriptor) else {
        preconditionFailure("device_samplerstate_create: Unable to create sampler state")
    }

    let retained = Unmanaged.passRetained(samplerState).toOpaque()

    return OpaquePointer(retained)
}

@_cdecl("gs_samplerstate_destroy")
public func gs_samplerstate_destroy(samplerstate: UnsafeRawPointer) {
    let _ = Unmanaged<MTLSamplerState>.fromOpaque(samplerstate).takeRetainedValue()
}

@_cdecl("device_load_samplerstate")
public func device_load_samplerstate(device: UnsafeRawPointer, samplerstate: UnsafeRawPointer, unit: UInt32) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()
    let samplerState = Unmanaged<MTLSamplerState>.fromOpaque(samplerstate).takeUnretainedValue()

    device.renderState.samplers[Int(unit)] = samplerState
}
