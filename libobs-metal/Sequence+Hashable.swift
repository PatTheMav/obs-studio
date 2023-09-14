//
//  Sequence+Hashable.swift
//  libobs-metal
//
//  Created by Patrick Heyer on 16.04.24.
//

extension Sequence where Iterator.Element: Hashable {
    func unique() -> [Iterator.Element] {
        var seen: Set<Iterator.Element> = []
        return filter { seen.insert($0).inserted }
    }
}
