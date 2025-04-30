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
    layer.displaySyncEnabled = false

    nonisolated(unsafe) let unsafeLayer = layer

    Task { @MainActor in
        view.layer = unsafeLayer
        view.wantsLayer = true
    }

    let metalLayer = MetalState.MetalLayer(
        layer: layer,
        view: view
    )

    let retained = Unmanaged.passRetained(metalLayer).toOpaque()

    return OpaquePointer(retained)
}

@_cdecl("device_resize")
public func device_resize(device: UnsafeMutableRawPointer, width: Int, height: Int) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    guard let layer = device.state.layer else {
        assertionFailure("device_resize (Metal): No active Metal layer available")
        return
    }

    nonisolated(unsafe) let unsafeLayer = layer

    Task { @MainActor in
        let actualWidth =
            switch width {
            case 0: unsafeLayer.layer.frame.size.width - unsafeLayer.layer.frame.origin.x
            default: CGFloat(width)
            }
        let actualHeight =
            switch height {
            case 0: unsafeLayer.layer.frame.size.height - unsafeLayer.layer.frame.origin.y
            default: CGFloat(height)
            }

        unsafeLayer.layer.drawableSize = CGSizeMake(actualWidth, actualHeight)
    }

    device.state.renderPassDescriptor.colorAttachments[0].texture = device.state.renderTarget?.texture
    device.state.renderPassDescriptor.depthAttachment.texture = device.state.depthAttachment
    device.state.renderPassDescriptor.stencilAttachment.texture = device.state.depthAttachment
}

@_cdecl("device_get_size")
public func device_get_size(
    device: UnsafeMutableRawPointer, cx: UnsafeMutablePointer<UInt32>, cy: UnsafeMutablePointer<UInt32>
) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    guard let layer = device.state.layer else {
        // assertionFailure("device_get_size (Metal): No active view")
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

    guard let layer = device.state.layer?.layer else {
        assertionFailure("device_get_width (Metal): No active view")
        return 0
    }

    return UInt32(layer.drawableSize.width)
}

@_cdecl("device_get_height")
public func device_get_height(device: UnsafeRawPointer) -> UInt32 {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    guard let layer = device.state.layer?.layer else {
        assertionFailure("device_get_height (Metal): No active view")
        return 0
    }

    return UInt32(layer.drawableSize.height)
}

@_cdecl("device_load_swapchain")
public func device_load_swapchain(device: UnsafeRawPointer, swap: UnsafeRawPointer) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()
    let layer = Unmanaged<MetalState.MetalLayer>.fromOpaque(swap).takeUnretainedValue()

    guard let nextDrawable = layer.layer.nextDrawable() else {
        assertionFailure("device_load_swapchain (Metal): Failed to retrieve drawable from CAMetalLayer")
        return
    }

    layer.nextDrawable = nextDrawable

    device.state.layer = layer

    let obsTexture = OBSTexture(device: device, texture: nextDrawable.texture)

    device.state.renderTarget = obsTexture
    device.state.renderPassDescriptor.colorAttachments[0].texture = nextDrawable.texture
    device.state.renderPassDescriptor.depthAttachment.texture = nil
    device.state.renderPassDescriptor.stencilAttachment.texture = nil
    device.state.renderPipelineDescriptor.colorAttachments[0].pixelFormat = nextDrawable.texture.pixelFormat
}

@_cdecl("gs_swapchain_destroy")
public func gs_swapchain_destroy(swapChain: UnsafeRawPointer) {
    let _ = Unmanaged<MetalState.MetalLayer>.fromOpaque(swapChain).takeRetainedValue()
}
