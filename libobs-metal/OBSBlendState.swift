//
//  OBSBlendState.swift
//  libobs-metal
//
//  Created by Patrick Heyer on 16.04.24.
//

import Foundation
import Metal

/// Blend State structs combine Blend Factor and Blend Channels information to contain all information necessary to customize blend operations in the renderer.
struct OBSBlendState: Comparable {
    /// This struct combines the ``MTLBlendFactor``s for the color channel and alpha channel into a single container.
    ///
    /// The struct is comparable, so existing blend factors can be compared with new ones to check for differences.
    struct OBSBlendFactor: Comparable {
        static func < (lhs: OBSBlendFactor, rhs: OBSBlendFactor) -> Bool {
            return lhs != rhs
        }

        static func == (lhs: OBSBlendFactor, rhs: OBSBlendFactor) -> Bool {
            if lhs.color == rhs.color && lhs.alpha == rhs.alpha {
                return true
            } else {
                return false
            }
        }

        let color: MTLBlendFactor
        let alpha: MTLBlendFactor

        init(color: MTLBlendFactor, alpha: MTLBlendFactor) {
            self.color = color
            self.alpha = alpha
        }
    }

    static func < (lhs: OBSBlendState, rhs: OBSBlendState) -> Bool {
        return lhs != rhs
    }

    static func == (lhs: OBSBlendState, rhs: OBSBlendState) -> Bool {
        if lhs.sourceFactors == rhs.sourceFactors {
            return true
        } else {
            return false
        }
    }

    var enabled = false
    let sourceFactors: OBSBlendFactor
    let destinationFactors: OBSBlendFactor

    var channelsEnabled: MTLColorWriteMask

    init(sourceFactors: OBSBlendFactor, destinationFactors: OBSBlendFactor, channelsEnabled: MTLColorWriteMask?) {
        self.sourceFactors = sourceFactors
        self.destinationFactors = destinationFactors

        if let channelsEnabled {
            self.channelsEnabled = channelsEnabled
        } else {
            self.channelsEnabled = .all
        }
    }
}
