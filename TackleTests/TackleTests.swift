//
//  TackleTests.swift
//  TackleTests
//
//  Created by Utkarsh Upadhyay on 21/09/26.
//

import Testing
@testable import Tackle

@Suite("SortIndex")
struct SortIndexTests {

    @Test("An empty section starts at the gap")
    func emptySection() {
        #expect(SortIndex.between(above: nil, below: nil) == 1024)
    }

    @Test("Moving to the top sits a gap above the first row")
    func top() {
        #expect(SortIndex.between(above: nil, below: 1024) == 0)
        #expect(SortIndex.between(above: nil, below: 512) == -512)
    }

    @Test("Moving to the bottom sits a gap below the last row")
    func bottom() {
        #expect(SortIndex.between(above: 1024, below: nil) == 2048)
    }

    @Test("Moving between two rows takes the midpoint")
    func middle() {
        #expect(SortIndex.between(above: 1024, below: 2048) == 1536)
        #expect(SortIndex.between(above: 0, below: 1) == 0.5)
    }

    @Test("Repeated splits between the same pair stay ordered")
    func repeatedSplits() {
        var above = 1024.0
        let below = 2048.0

        for _ in 0..<10 {
            let index = SortIndex.between(above: above, below: below)
            #expect(index > above && index < below)
            above = index
        }
    }
}
