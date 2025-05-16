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

@MainActor
@_cdecl("device_swapchain_create")
public func device_swapchain_create(device: UnsafeMutableRawPointer, data: UnsafePointer<gs_init_data>)
    -> OpaquePointer?
{
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()
    let view = data.pointee.window.view.takeUnretainedValue() as! NSView
    let size = MTLSize(
        width: Int(data.pointee.cx),
        height: Int(data.pointee.cy),
        depth: 0
    )

    guard let swapChain = OBSSwapChain(device: device, size: size, pixelFormat: data.pointee.format.toMTLFormat())
    else {
        return nil
    }

    swapChain.updateView(view)

    return swapChain.getRetained()
}

@_cdecl("device_resize")
public func device_resize(device: UnsafeMutableRawPointer, width: UInt32, height: UInt32) {
    let device = Unmanaged<MetalDevice>.fromOpaque(device).takeUnretainedValue()

    guard let swapChain = device.renderState.swapChain else {
        return
    }

    swapChain.resize(MTLSize(width: Int(width), height: Int(height), depth: 0))
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

    swapChain.prepareDrawable()

    device.renderState.swapChain = swapChain
}

@_cdecl("gs_swapchain_destroy")
public func gs_swapchain_destroy(swapChain: UnsafeMutableRawPointer) {
    let _ = Unmanaged<OBSSwapChain>.fromOpaque(swapChain).takeRetainedValue()
}
