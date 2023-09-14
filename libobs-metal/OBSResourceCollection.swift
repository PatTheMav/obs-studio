//
//  OBSResourceCollection.swift
//  libobs-metal
//
//  Created by Patrick Heyer on 16.04.24.
//

import Foundation
import GameplayKit

struct OBSResourceCollection<T> {
    typealias DictionaryType = [Int: T]

    private var elements = DictionaryType()
    private var keyStack: [Int]
    private var capacity: Int

    init(_ capacity: Int) {
        self.capacity = capacity
        self.elements = DictionaryType(minimumCapacity: capacity)
        self.keyStack = Array(1...capacity)
    }
}

extension OBSResourceCollection: Collection {
    typealias Index = DictionaryType.Index
    typealias Element = DictionaryType.Element

    var startIndex: Index { return elements.startIndex }
    var endIndex: Index { return elements.endIndex }

    var keys: DictionaryType.Keys {
        return elements.keys
    }

    subscript(position: Index) -> Element {
        get { return elements[position] }
    }

    subscript(index: Int) -> T? {
        get { return elements[index] }
    }

    func index(after i: Index) -> Index {
        return elements.index(after: i)
    }
}

extension OBSResourceCollection {
    mutating func insert(_ element: T) -> Int {
        if keyStack.count == 0 {
            let newCapacity = capacity * 2
            keyStack.append(contentsOf: Array((capacity + 1)...newCapacity))
            capacity = newCapacity
        }

        let availableKey = keyStack.removeFirst()

        elements[availableKey] = element

        return availableKey
    }

    mutating func remove(_ key: Int) {
        guard elements.keys.contains(key) else {
            OBSLog(.warning, "\(OBSResourceError.invalidKey.description)")
            return
        }

        elements.removeValue(forKey: key)

        keyStack.append(key)
    }

    mutating func replaceAt(_ key: Int, _ element: T) {
        guard elements.keys.contains(key) else {
            assertionFailure(OBSResourceError.invalidKey.description)
            return
        }

        elements.removeValue(forKey: key)
        elements[key] = element
    }
}

extension OBSResourceCollection {
    enum OBSResourceError: Error, CustomStringConvertible {
        case invalidKey

        var description: String {
            switch self {
            case .invalidKey: "Invalid key provided"
            }
        }
    }
}
