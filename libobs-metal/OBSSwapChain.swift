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
import CoreVideo
import Foundation
import Metal

class OBSSwapChain {
    private weak var device: MetalDevice?
    private let layer: CAMetalLayer
    private var view: NSView?
    private var drawable: CAMetalDrawable?
    private var renderTarget: MetalTexture
    private var placeHolder: MTLTexture

    var viewSize: MTLSize
    var requiresViewUpdate: Bool = false

    init?(device: MetalDevice, size: MTLSize, pixelFormat: MTLPixelFormat) {
        self.device = device
        self.viewSize = size
        self.layer = device.makeLayer()
        self.layer.pixelFormat = pixelFormat

        guard let texture = MetalTexture(device: device) else {
            preconditionFailure("OBSSwapChain: Failed to initialize MetalTexture object")
        }

        self.renderTarget = texture
        self.placeHolder = texture.texture

        resize(size)
    }

    @MainActor
    func updateView(_ view: NSView) {
        layer.drawableSize = CGSize(width: viewSize.width, height: viewSize.height)
        view.layer = self.layer
        view.wantsLayer = true

        self.view = view
    }

    func resize(_ size: MTLSize) {
        viewSize = size

        layer.drawableSize = CGSize(width: viewSize.width, height: viewSize.height)
    }

    func prepareDrawable() {
        guard let device = self.device, device.requiresSync else {
            return
        }

        guard let renderPassDescriptor = device.renderState.renderPassDescriptor else { return }
        guard let renderPipelineDescriptor = device.renderState.pipelineDescriptor else { return }

        guard let drawable = layer.nextDrawable() else { return }

        self.drawable = drawable

        self.renderTarget.texture = drawable.texture
        device.renderState.renderTarget = self.renderTarget
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.depthAttachment.texture = nil
        renderPassDescriptor.stencilAttachment.texture = nil
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = drawable.texture.pixelFormat
    }

    func update() {
        guard let device = self.device, let drawable = self.drawable,
            let commandBuffer = device.renderState.commandBuffer
        else {
            return
        }

        commandBuffer.present(drawable)

        renderTarget.texture = placeHolder
        self.drawable = nil
    }

    func getRetained() -> OpaquePointer {
        let retained = Unmanaged.passRetained(self).toOpaque()

        return OpaquePointer(retained)
    }

    func getUnretained() -> OpaquePointer {
        let unretained = Unmanaged.passUnretained(self).toOpaque()

        return OpaquePointer(unretained)
    }

    deinit {
        return
    }
}
