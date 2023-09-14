//
//  OBSSamplerState.swift
//  libobs-metal
//
//  Created by Patrick Heyer on 16.04.24.
//

import Foundation
import Metal

// MARK: libobs Graphics API

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
            .opaqueBlack
        } else if (info.border_color & 0xFF_FF_FF_FF) == 0 {
            .opaqueWhite
        } else {
            .transparentBlack
        }

    guard let samplerState = device.device.makeSamplerState(descriptor: descriptor) else {
        preconditionFailure("device_samplerstate_create (Metal): Failed to create sampler state")
    }

    let samplerStateId = device.samplerStates.insert(samplerState)
    let resource = OBSAPIResource(device: device, resourceId: samplerStateId)

    return resource.getRetained()
}

@_cdecl("gs_samplerstate_destroy")
public func gs_samplerstate_destroy(samplerState: UnsafeRawPointer) {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(samplerState).takeRetainedValue()
    let device = resource.device

    device.samplerStates.remove(resource.resourceId)
}

/// Loads a sampler state into a texture unit
///
///  The provided ``MetalResource`` instance contains the ID of the sampler state and will be used to find a preconfigured ``OBSSamplerState`` instance. If found, the reference will be added to the ``OBSMetalDevice``'  `currentSamplerStates` collection at the index provided by the texture unit variable.
///
/// - Parameters:
///   - device: Opaque pointer to ``MetalRenderer`` instance
///   - ss: Opaque pointer to ``MetalResource`` instance
///   - unit: Texture unit for which the texture should be set up
@_cdecl("device_load_samplerstate")
public func device_load_samplerstate(device: UnsafeRawPointer, ss: UnsafeRawPointer, unit: Int) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(ss).takeUnretainedValue()

    guard let samplerState = device.samplerStates[resource.resourceId] else {
        assertionFailure("device_load_samplerstate (Metal): Invalid sampler state ID provided")
        return
    }

    device.state.samplers[unit] = samplerState
}
