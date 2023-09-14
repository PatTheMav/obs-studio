//
//  OBSBlendState.swift
//  libobs-metal
//
//  Created by Patrick Heyer on 16.04.24.
//

import Foundation
import Metal

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

struct OBSBlendChannels: OptionSet {
    var rawValue: UInt

    static let red = OBSBlendChannels(rawValue: 1 << 0)
    static let blue = OBSBlendChannels(rawValue: 1 << 1)
    static let green = OBSBlendChannels(rawValue: 1 << 2)
    static let alpha = OBSBlendChannels(rawValue: 1 << 4)

    static let all: OBSBlendChannels = [.red, .blue, .green, .alpha]
}

struct OBSBlendState: Comparable {
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
