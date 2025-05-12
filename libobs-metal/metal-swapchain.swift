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

import AppKit
import Foundation

@_cdecl("device_swapchain_create")
public func device_swapchain_create(device: UnsafeMutableRawPointer, data: UnsafePointer<gs_init_data>)
    -> OpaquePointer?
{
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()
    var view = data.pointee.window.view.takeUnretainedValue() as! NSView
    let size = MTLSize(
        width: Int(data.pointee.cx),
        height: Int(data.pointee.cy),
        depth: 0
    )

    guard let swapChain = OBSSwapChain(device: device, size: size, pixelFormat: data.pointee.format.toMTLFormat())
    else {
        return nil
    }

    device.renderState.swapChain = swapChain

    nonisolated(unsafe) let unsafeSwap = swapChain

    Task { @MainActor in
        unsafeSwap.updateView(view)
    }

    return swapChain.getRetained()
}

@_cdecl("device_resize")
public func device_resize(device: UnsafeMutableRawPointer, width: UInt32, height: UInt32) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    guard let swapChain = device.renderState.swapChain else {
        return
    }

    swapChain.resize(MTLSize(width: Int(width), height: Int(height), depth: 0))

    guard let renderTarget = swapChain.renderTarget else {
        return
    }

    device.renderState.renderPassDescriptor?.colorAttachments[0].texture = renderTarget.texture
    device.renderState.renderPassDescriptor?.depthAttachment.texture = nil
    device.renderState.renderPassDescriptor?.stencilAttachment.texture = nil
}

@_cdecl("device_get_size")
public func device_get_size(
    device: UnsafeMutableRawPointer, cx: UnsafeMutablePointer<UInt32>, cy: UnsafeMutablePointer<UInt32>
) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    guard let swapChain = device.renderState.swapChain else {
        cx.pointee = 0
        cy.pointee = 0
        return
    }

    cx.pointee = UInt32(swapChain.viewSize.width)
    cy.pointee = UInt32(swapChain.viewSize.height)
}

@_cdecl("device_get_width")
public func device_get_width(device: UnsafeRawPointer) -> UInt32 {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    guard let swapChain = device.renderState.swapChain else {
        return 0
    }

    return UInt32(swapChain.viewSize.width)
}

@_cdecl("device_get_height")
public func device_get_height(device: UnsafeRawPointer) -> UInt32 {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    guard let swapChain = device.renderState.swapChain else {
        return 0
    }

    return UInt32(swapChain.viewSize.height)
}

@_cdecl("device_load_swapchain")
public func device_load_swapchain(device: UnsafeRawPointer, swap: UnsafeRawPointer) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()
    let swapChain = Unmanaged<OBSSwapChain>.fromOpaque(swap).takeUnretainedValue()

    guard let renderTarget = swapChain.renderTarget else {
        return
    }

    device.renderState.renderTarget = renderTarget
    device.renderState.renderPassDescriptor?.colorAttachments[0].texture = renderTarget.texture
    device.renderState.renderPassDescriptor?.depthAttachment.texture = nil
    device.renderState.renderPassDescriptor?.stencilAttachment.texture = nil
    device.renderState.pipelineDescriptor?.colorAttachments[0].pixelFormat = renderTarget.texture.pixelFormat
}

@_cdecl("gs_swapchain_destroy")
public func gs_swapchain_destroy(swapChain: UnsafeRawPointer) {
    let _ = Unmanaged<OBSSwapChain>.fromOpaque(swapChain).takeRetainedValue()
}
