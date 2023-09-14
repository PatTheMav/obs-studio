//
//  OBSSwapChain.swift
//  libobs-metal
//
//  Created by Patrick Heyer on 16.04.24.
//

import AppKit
import Foundation
import Metal

// MARK: libobs Graphics API

@_cdecl("device_swapchain_create")
public func device_swapchain_create(device: UnsafeMutableRawPointer, data: UnsafePointer<gs_init_data>)
    -> OpaquePointer?
{
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()
    let view = data.pointee.window.view.takeUnretainedValue() as? NSView

    guard let view else {
        assertionFailure("device_swapchain_create (Metal): No valid NSView provided")
        return nil
    }

    let layer = CAMetalLayer()
    layer.device = device.device
    layer.drawableSize = CGSizeMake(CGFloat(data.pointee.cx), CGFloat(data.pointee.cy))
    view.layer = layer
    view.wantsLayer = true

    let metalLayer = MetalState.MetalLayer(
        layer: layer,
        view: view
    )

    let layerId = device.layers.insert(metalLayer)
    let resource = OBSAPIResource(device: device, resourceId: layerId)

    return resource.getRetained()
}

@_cdecl("device_resize")
public func device_resize(device: UnsafeMutableRawPointer, width: Int, height: Int) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    guard let layerId = device.state.layerId, let layer = device.layers[layerId] else {
        assertionFailure("device_resize (Metal): No active Metal layer available")
        return
    }

    DispatchQueue.main.async {
        let actualWidth =
            switch width {
            case 0: layer.layer.frame.size.width - layer.layer.frame.origin.x
            default: CGFloat(width)
            }
        let actualHeight =
            switch height {
            case 0: layer.layer.frame.size.height - layer.layer.frame.origin.y
            default: CGFloat(height)
            }

        layer.layer.drawableSize = CGSizeMake(actualWidth, actualHeight)
    }

    device.state.renderPassDescriptor.colorAttachments[0].texture = device.state.renderTarget
    device.state.renderPassDescriptor.depthAttachment.texture = device.state.depthAttachment
    device.state.renderPassDescriptor.stencilAttachment.texture = device.state.depthAttachment
}

@_cdecl("device_get_size")
public func device_get_size(
    device: UnsafeMutableRawPointer, cx: UnsafeMutablePointer<UInt32>, cy: UnsafeMutablePointer<UInt32>
) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    guard let layerId = device.state.layerId, let layer = device.layers[layerId] else {
        assertionFailure("device_get_size (Metal): No active view")
        cx.pointee = 0
        cy.pointee = 0
        return
    }

    cx.pointee = UInt32(layer.layer.drawableSize.width)
    cy.pointee = UInt32(layer.layer.drawableSize.height)
}

@_cdecl("device_get_width")
public func device_get_width(device: UnsafeRawPointer) -> UInt32 {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    guard let layerId = device.state.layerId, let layer = device.layers[layerId]?.layer else {
        assertionFailure("device_get_width (Metal): No active view")
        return 0
    }

    return UInt32(layer.drawableSize.width)
}

@_cdecl("device_get_height")
public func device_get_height(device: UnsafeRawPointer) -> UInt32 {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    guard let layerId = device.state.layerId, let layer = device.layers[layerId]?.layer else {
        assertionFailure("device_get_height (Metal): No active view")
        return 0
    }

    return UInt32(layer.drawableSize.height)
}

@_cdecl("device_load_swapchain")
public func device_load_swapchain(device: UnsafeRawPointer, swap: UnsafeRawPointer) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(swap).takeUnretainedValue()

    guard var metalLayer = device.layers[resource.resourceId] else {
        assertionFailure("device_load_swapchain (Metal): Invalid layer ID provided")
        return
    }

    device.state.layerId = resource.resourceId

    guard let nextDrawable = metalLayer.layer.nextDrawable() else {
        assertionFailure("device_load_swapchain (Metal): Failed to retrieve drawable from CAMetalLayer")
        return
    }

    let drawableId: Int

    if let priorTextureId = metalLayer.textureId {
        device.textures.replaceAt(priorTextureId, nextDrawable.texture)
        drawableId = priorTextureId
    } else {
        drawableId = device.textures.insert(nextDrawable.texture)
    }

    metalLayer.nextDrawable = nextDrawable
    metalLayer.textureId = drawableId

    device.layers.replaceAt(resource.resourceId, metalLayer)

    device.state.renderTarget = nextDrawable.texture
    device.state.renderPassDescriptor.colorAttachments[0].texture = nextDrawable.texture
    device.state.renderPassDescriptor.depthAttachment.texture = nil
    device.state.renderPassDescriptor.stencilAttachment.texture = nil
    device.state.renderPipelineDescriptor.colorAttachments[0].pixelFormat = nextDrawable.texture.pixelFormat

    //    guard let surface = device.surfaces[resource.resourceId] else {
    //        assertionFailure("device_load_swapchain (Metal): Invalid surface ID provided")
    //        return
    //    }
    //
    //    device.state.layer = surface.1
    //
    //    guard let nextDrawable = surface.1.nextDrawable() else {
    //        assertionFailure("device_load_swapchain (Metal): Failed to retrieve drawable from CAMetalLayer")
    //        return
    //    }
    //
    //    let drawableId = device.textures.insert(nextDrawable.texture)
    //    device.state.nextDrawable = nextDrawable
    //    device.state.renderTarget = nextDrawable.texture
    //    device.state.renderTargetId = drawableId
    //    device.state.renderPassDescriptor.colorAttachments[0].texture = nextDrawable.texture
    //    device.state.renderPassDescriptor.depthAttachment.texture = nil
    //    device.state.renderPassDescriptor.stencilAttachment.texture = nil
    //    device.state.renderPipelineDescriptor.colorAttachments[0].pixelFormat = nextDrawable.texture.pixelFormat
}

@_cdecl("gs_swapchain_destroy")
public func gs_swapchain_destroy(swapChain: UnsafeRawPointer) {
    let resource = Unmanaged<OBSAPIResource>.fromOpaque(swapChain).takeRetainedValue()
    let device = resource.device

    guard var metalLayer = device.layers[resource.resourceId] else {
        assertionFailure("device_swapchain_destroy (Metal): Invalid layer ID provided")
        return
    }

    if let textureId = metalLayer.textureId {
        device.textures.remove(textureId)
    }

    metalLayer.nextDrawable = nil
    device.layers.remove(resource.resourceId)
}
