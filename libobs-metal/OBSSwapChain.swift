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
import Metal

class OBSSwapChain {
    private let device: MetalDevice
    var renderTarget: MetalTexture?
    var pixelFormat: MTLPixelFormat
    private let layer: CALayer
    private var view: NSView?
    var viewSize: MTLSize

    init?(device: MetalDevice, size: MTLSize, pixelFormat: MTLPixelFormat) {
        self.device = device
        self.viewSize = size
        self.layer = CALayer()
        self.pixelFormat = pixelFormat

        resize(size)
    }

    @MainActor
    func updateView(_ view: NSView) {
        view.layer = self.layer
        view.wantsLayer = true

        self.view = view
        update()
    }

    func resize(_ size: MTLSize) {
        viewSize = size

        let description = MetalTextureDescription(
            type: .type2D,
            width: viewSize.width,
            height: viewSize.height,
            pixelFormat: pixelFormat,
            mipmapLevels: 0,
            isRenderTarget: true,
            isMipMapped: false
        )

        self.renderTarget = MetalTexture(device: device, description: description)
    }

    func update() {
        guard let renderTarget else {
            return
        }

        layer.contents = renderTarget.texture.iosurface
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
