//
//  LayerTree.Builder.ReferenceCycleTests.swift
//  SwiftDraw
//  Created by Simon Whitty on 21/11/18.
//  Copyright 2020 WhileLoop Pty Ltd. All rights reserved.
//
//  Distributed under the permissive zlib license
//  Get the latest version from here:
//
//  https://github.com/swhitty/SwiftDraw
//
//  This software is provided 'as-is', without any express or implied
//  warranty.  In no event will the authors be held liable for any damages
//  arising from the use of this software.
//
//  Permission is granted to anyone to use this software for any purpose,
//  including commercial applications, and to alter it and redistribute it
//  freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//  claim that you wrote the original software. If you use this software
//  in a product, an acknowledgment in the product documentation would be
//  appreciated but is not required.
//
//  2. Altered source versions must be plainly marked as such, and must not be
//  misrepresented as being the original software.
//
//  3. This notice may not be removed or altered from any source distribution.

import SwiftDrawDOM
import XCTest
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import SwiftDraw

final class LayerTreeBuilderReferenceCycleTests: XCTestCase {

    private struct Stats {
        var layers = 0
        var shapes = 0
        var maskedLayers = 0
        var patternFills = 0
        var texts = 0
        var nesting = 0
    }

    private func makeSVG(_ body: String) throws -> DOM.SVG {
        try DOM.SVG.parse(xml: """
        <svg width="100" height="100" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
        \(body)
        </svg>
        """)
    }

    private func stats(_ body: String) throws -> Stats {
        let layer = LayerTree.Builder(svg: try makeSVG(body)).makeLayer()
        return Self.stats(of: layer)
    }

    private static func stats(of layer: LayerTree.Layer) -> Stats {
        var stats = Stats()
        collect(layer, depth: 1, into: &stats)
        return stats
    }

    private static func collect(_ layer: LayerTree.Layer, depth: Int, into stats: inout Stats) {
        stats.layers += 1
        stats.nesting = max(stats.nesting, depth)
        if let mask = layer.mask {
            stats.maskedLayers += 1
            collect(mask, depth: depth + 1, into: &stats)
        }
        collect(layer.contents, depth: depth + 1, into: &stats)
    }

    private static func collect(_ contents: [LayerTree.Layer.Contents], depth: Int, into stats: inout Stats) {
        for content in contents {
            switch content {
            case .layer(let l):
                collect(l, depth: depth, into: &stats)
            case .shape(_, _, let fill):
                stats.shapes += 1
                if case .pattern(let pattern) = fill.fill {
                    stats.patternFills += 1
                    collect(pattern.contents, depth: depth + 1, into: &stats)
                }
            case .text:
                stats.texts += 1
            case .image:
                break
            }
        }
    }

    /// `<g id="g0"><use href="#g1"/></g> ... <g id="g<count>"><rect/></g>`
    private static func chain(count: Int) -> String {
        var svg = ""
        for i in 0..<count {
            svg += ##"<g id="g\##(i)"><use xlink:href="#g\##(i + 1)"/></g>"##
        }
        svg += ##"<g id="g\##(count)"><rect width="10" height="10"/></g>"##
        return svg
    }

    // MARK: - <use> cycles

    func testUseOfOwnAncestorDrawsNoExtraCopy() throws {
        // rendered directly: the group draws once, the nested use is the error
        let s = try stats(##"<g id="a"><rect width="10" height="10"/><use xlink:href="#a"/></g>"##)
        XCTAssertEqual(s.shapes, 1)
    }

    func testUseOfItselfDrawsNothing() throws {
        let s = try stats(##"<use id="a" xlink:href="#a"/>"##)
        XCTAssertEqual(s.shapes, 0)
    }

    func testMutualCycleRenderedDirectlyDrawsEachGroupOnce() throws {
        let s = try stats(##"""
        <g id="a"><rect width="10" height="10"/><use xlink:href="#b"/></g>
        <g id="b"><rect width="10" height="10"/><use xlink:href="#a"/></g>
        """##)
        XCTAssertEqual(s.shapes, 2)
    }

    func testUseOfCyclicTargetDrawsNothing() throws {
        let s = try stats(##"""
        <defs><g id="a"><rect width="10" height="10"/><use xlink:href="#a"/></g></defs>
        <use xlink:href="#a"/>
        """##)
        XCTAssertEqual(s.shapes, 0)
    }

    func testIndirectCycleThroughTargetDrawsNothing() throws {
        let s = try stats(##"""
        <defs>
          <g id="x"><rect width="10" height="10"/><use xlink:href="#y"/></g>
          <g id="y"><rect width="10" height="10"/><use xlink:href="#x"/></g>
        </defs>
        <use xlink:href="#x"/>
        """##)
        XCTAssertEqual(s.shapes, 0)
    }

    // MARK: - valid references still draw

    func testDiamondDrawsSharedTargetTwice() throws {
        let s = try stats(##"""
        <defs>
          <rect id="d" width="10" height="10"/>
          <g id="b"><use xlink:href="#d"/></g>
          <g id="c"><use xlink:href="#d"/></g>
          <g id="a"><use xlink:href="#b"/><use xlink:href="#c"/></g>
        </defs>
        <use xlink:href="#a"/>
        """##)
        XCTAssertEqual(s.shapes, 2)
    }

    func testRepeatedSiblingUsesAreAllDrawn() throws {
        let s = try stats(##"""
        <defs><rect id="r" width="10" height="10"/></defs>
        <use xlink:href="#r"/><use xlink:href="#r"/><use xlink:href="#r"/>
        """##)
        XCTAssertEqual(s.shapes, 3)
    }

    func testChainUnderTheCapIsDrawnFully() throws {
        let s = try stats(##"<defs>\##(Self.chain(count: 5))</defs><use xlink:href="#g0"/>"##)
        XCTAssertEqual(s.shapes, 1)
    }

    // MARK: - caps

    func testLongChainStopsAtTheCapWithoutCrashing() throws {
        let s = try stats(##"<defs>\##(Self.chain(count: 100))</defs><use xlink:href="#g0"/>"##)
        XCTAssertEqual(s.shapes, 0)
        XCTAssertLessThanOrEqual(s.layers, 4 * LayerTree.Builder.ReferenceGuard.maxDepth + 8)
    }

    func testFanOutIsBoundedByTheElementBudget() throws {
        // 10 uses of 10 uses of 10 uses of 1000 rects: 1 000 000 copies
        var body = ##"<defs><g id="l0">"## + String(repeating: ##"<rect width="1" height="1"/>"##, count: 1_000) + "</g>"
        for i in 1...3 {
            body += ##"<g id="l\##(i)">"## + String(repeating: ##"<use xlink:href="#l\##(i - 1)"/>"##, count: 10) + "</g>"
        }
        body += ##"</defs><use xlink:href="#l3"/>"##
        let builder = LayerTree.Builder(svg: try makeSVG(body))
        let s = Self.stats(of: builder.makeLayer())
        let budget = LayerTree.Builder.ReferenceGuard.maxElements
        XCTAssertEqual(builder.references.elements, budget)
        // every element counted built at most one shape; then copying stopped
        XCTAssertLessThanOrEqual(s.shapes, budget)
        XCTAssertGreaterThan(s.shapes, budget * 9 / 10)
    }

    func testHeavyCopiesSpendTheBudgetByTheirSize() throws {
        // 10 000 copies of an 800-segment path: each costs 101 elements
        let path = ##"<path id="l0" d="M0 0"## + String(repeating: " L1 1", count: 800) + ##""/>"##
        var body = "<defs>" + path
        for i in 1...4 {
            body += ##"<g id="l\##(i)">"## + String(repeating: ##"<use xlink:href="#l\##(i - 1)"/>"##, count: 10) + "</g>"
        }
        body += ##"</defs><use xlink:href="#l4"/>"##
        let builder = LayerTree.Builder(svg: try makeSVG(body))
        let s = Self.stats(of: builder.makeLayer())
        let copies = LayerTree.Builder.ReferenceGuard.maxElements / 101
        XCTAssertLessThanOrEqual(s.shapes, copies)
        XCTAssertGreaterThan(s.shapes, copies * 9 / 10)
    }

    func testTextCopiesSpendTheBudgetByTheirLength() throws {
        // 1000 copies of 100 characters: each costs 1001 elements
        var body = ##"<defs><text id="l0">"## + String(repeating: "W", count: 100) + "</text>"
        for i in 1...3 {
            body += ##"<g id="l\##(i)">"## + String(repeating: ##"<use xlink:href="#l\##(i - 1)"/>"##, count: 10) + "</g>"
        }
        body += ##"</defs><use xlink:href="#l3"/>"##
        let s = try stats(body)
        let copies = LayerTree.Builder.ReferenceGuard.maxElements / 1001
        XCTAssertLessThanOrEqual(s.texts, copies)
        XCTAssertGreaterThan(s.texts, copies * 9 / 10)
    }

    func testManyUsesOfOneShapeAllDraw() throws {
        // text exported as glyph <use>s: 25 600 copies, far below the element budget
        let uses = String(repeating: ##"<use xlink:href="#d"/>"##, count: 25_600)
        let s = try stats(##"<defs><rect id="d" width="4" height="4"/></defs>\##(uses)"##)
        XCTAssertEqual(s.shapes, 25_600)
    }

    func testCapDepthFitsASmallSecondaryThreadStack() throws {
        // the deepest chain still drawn: each hop is a <use>, its reference and a group
        let hops = LayerTree.Builder.ReferenceGuard.maxDepth / (LayerTree.Builder.ReferenceGuard.referenceDepth + 2) - 1
        nonisolated(unsafe) let svg = try makeSVG(##"<defs>\##(Self.chain(count: hops))</defs><use xlink:href="#g0"/>"##)
        nonisolated(unsafe) var result = Stats()
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            result = Self.stats(of: LayerTree.Builder(svg: svg).makeLayer())
            done.signal()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        XCTAssertEqual(done.wait(timeout: .now() + 30), .success)
        XCTAssertEqual(result.shapes, 1)
    }

    // MARK: - depth, on the 512 KB stack of a secondary thread

    /// Builds, generates, draws into a bitmap and a PDF, and releases the tree on a 512 KB stack.
    private func drawOnSmallStack(_ body: String, file: StaticString = #filePath, line: UInt = #line) throws -> Stats {
        // parsed on this thread: deep nesting is the parser's to bound
        nonisolated(unsafe) let svg = try makeSVG(body)
        nonisolated(unsafe) var result = Stats()
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            let layer = LayerTree.Builder(svg: svg).makeLayer()
            result = Self.stats(of: layer)
            #if canImport(CoreGraphics)
            let generator = LayerTree.CommandGenerator(provider: CGProvider(), size: .init(100, 100), options: .default)
            let commands = generator.renderCommands(for: layer, colorConverter: .default)
            let bitmap = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            CGRenderer(context: bitmap).perform(commands)
            let data = NSMutableData()
            var box = CGRect(x: 0, y: 0, width: 100, height: 100)
            let pdf = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
            pdf.beginPDFPage(nil)
            CGRenderer(context: pdf).perform(commands)
            pdf.endPDFPage()
            pdf.closePDF()
            #endif
            done.signal()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        XCTAssertEqual(done.wait(timeout: .now() + 60), .success, file: file, line: line)
        return result
    }

    func testDeepGroupsStopAtTheDepthCap() throws {
        let s = try drawOnSmallStack(String(repeating: "<g>", count: 1_000) + ##"<rect width="10" height="10"/>"## + String(repeating: "</g>", count: 1_000))
        XCTAssertEqual(s.shapes, 0)
        XCTAssertLessThanOrEqual(s.nesting, LayerTree.Builder.ReferenceGuard.maxDepth + 1)
    }

    func testDeepSwitchesDrawTheirFirstChild() throws {
        let s = try drawOnSmallStack(String(repeating: "<switch>", count: 150) + ##"<rect width="10" height="10"/>"## + String(repeating: "</switch>", count: 150))
        XCTAssertEqual(s.shapes, 1)
    }

    func testDeepMaskChainFitsTheStack() throws {
        var body = "<defs>"
        for i in 0..<300 {
            body += ##"<mask id="m\##(i)"><rect width="100" height="100" fill="white" mask="url(#m\##(i + 1))"/></mask>"##
        }
        body += ##"<mask id="m300"><rect width="100" height="100" fill="white"/></mask></defs><rect width="80" height="80" mask="url(#m0)"/>"##
        let s = try drawOnSmallStack(body)
        // each mask level counts as a reference: the chain is cut long before 300
        XCTAssertLessThanOrEqual(s.maskedLayers, LayerTree.Builder.ReferenceGuard.maxDepth / LayerTree.Builder.ReferenceGuard.referenceDepth + 1)
        XCTAssertGreaterThan(s.maskedLayers, 1)
    }

    func testDeepPatternChainFitsTheStack() throws {
        var body = "<defs>"
        for i in 0..<300 {
            body += ##"<pattern id="p\##(i)" patternUnits="userSpaceOnUse" width="10" height="10"><rect width="9" height="9" fill="url(#p\##(i + 1))"/></pattern>"##
        }
        body += ##"<pattern id="p300" width="10" height="10"><rect width="5" height="5"/></pattern></defs><rect width="80" height="80" fill="url(#p0)"/>"##
        let s = try drawOnSmallStack(body)
        XCTAssertLessThanOrEqual(s.patternFills, LayerTree.Builder.ReferenceGuard.maxDepth / LayerTree.Builder.ReferenceGuard.referenceDepth + 1)
        XCTAssertGreaterThan(s.patternFills, 1)
    }

    func testGroupsBetweenUsesShareOneDepth() throws {
        // 20 groups per <use> hop: a capped depth per reference would allow 16 × 20 levels, one cap allows 200
        var body = "<defs>"
        for i in 0..<20 {
            body += ##"<g id="g\##(i)">"## + String(repeating: "<g>", count: 20) + ##"<use xlink:href="#g\##(i + 1)"/>"## + String(repeating: "</g>", count: 20) + "</g>"
        }
        body += ##"<g id="g20"><rect width="10" height="10"/></g></defs><use xlink:href="#g0"/>"##
        let s = try drawOnSmallStack(body)
        XCTAssertEqual(s.shapes, 0)
        XCTAssertLessThanOrEqual(s.nesting, LayerTree.Builder.ReferenceGuard.maxDepth + 1)
    }

    /// `<clipPath id="c0">` ... `<clipPath id="c<count - 1>">`, each clipped by the one before; `member` is each one's child
    private static func clipChain(count: Int, member: String = ##"<rect width="100" height="100"/>"##) -> String {
        var svg = ##"<clipPath id="c0">\##(member)</clipPath>"##
        for i in 1..<count {
            svg += ##"<clipPath id="c\##(i)" clip-path="url(#c\##(i - 1))">\##(member)</clipPath>"##
        }
        return svg
    }

    func testClipPathIntersectionsCountInTheDepth() throws {
        // each group is held by 15 layers intersecting the nested clip paths
        let groups = 190
        let body = "<defs>\(Self.clipChain(count: 16))</defs>"
            + String(repeating: ##"<g clip-path="url(#c15)">"##, count: groups) + ##"<rect width="10" height="10"/>"##
            + String(repeating: "</g>", count: groups)
        let s = try drawOnSmallStack(body)
        XCTAssertEqual(s.shapes, 0)
        XCTAssertLessThanOrEqual(s.nesting, LayerTree.Builder.ReferenceGuard.maxDepth + ActiveClipSet.maxDepth)
    }

    func testClipPathMasksInDeepGroupsFitTheStack() throws {
        // text makes every clip path of the chain a mask, hanging from each of 190 groups
        let groups = 190
        let body = "<defs>\(Self.clipChain(count: 16, member: "<text>Clip</text>"))</defs>"
            + String(repeating: ##"<g clip-path="url(#c15)">"##, count: groups) + ##"<rect width="10" height="10"/>"##
            + String(repeating: "</g>", count: groups)
        let s = try drawOnSmallStack(body)
        XCTAssertEqual(s.shapes, 1)
        XCTAssertEqual(s.maskedLayers, groups * 16)
    }

    func testPatternIsBuiltOncePerId() throws {
        let rects = String(repeating: ##"<rect width="10" height="10" fill="url(#p)"/>"##, count: 100)
        let svg = try makeSVG(##"""
        <pattern id="p" width="10" height="10" patternUnits="userSpaceOnUse">\##(String(repeating: ##"<rect width="1" height="1"/>"##, count: 10))</pattern>
        \##(rects)
        """##)
        let builder = LayerTree.Builder(svg: svg)
        let layer = builder.makeLayer()
        let patterns = layer.contents.compactMap { contents -> LayerTree.Pattern? in
            guard case .shape(_, _, let fill) = contents, case .pattern(let pattern) = fill.fill else { return nil }
            return pattern
        }
        XCTAssertEqual(patterns.count, 100)
        XCTAssertTrue(patterns.allSatisfy { $0 === patterns[0] })
        XCTAssertEqual(builder.references.elements, 10)
    }

    func testMaskReferencingItselfIsDroppedInsideTheMask() throws {
        let s = try stats(##"""
        <mask id="m"><rect width="10" height="10" mask="url(#m)"/></mask>
        <rect width="10" height="10" mask="url(#m)"/>
        """##)
        XCTAssertEqual(s.maskedLayers, 1)
    }

    func testPatternPaintedWithItselfIsDroppedInsideThePattern() throws {
        let s = try stats(##"""
        <pattern id="p" width="10" height="10" patternUnits="userSpaceOnUse">
          <rect width="5" height="5" fill="url(#p)"/>
        </pattern>
        <rect width="10" height="10" fill="url(#p)"/>
        """##)
        XCTAssertEqual(s.patternFills, 1)
    }

    func testPatternHrefCycleStillPaints() throws {
        let s = try stats(##"""
        <pattern id="a" xlink:href="#b" width="10" height="10" patternUnits="userSpaceOnUse"/>
        <pattern id="b" xlink:href="#a"><rect width="5" height="5"/></pattern>
        <rect width="10" height="10" fill="url(#a)"/>
        """##)
        XCTAssertEqual(s.patternFills, 1)
        XCTAssertEqual(s.shapes, 2) // the filled rect and the rect inherited from #b
    }

    func testPatternHrefChainStopsAtTheCap() throws {
        var body = ""
        for i in 0..<100 {
            body += ##"<pattern id="p\##(i)" xlink:href="#p\##(i + 1)" width="10" height="10" patternUnits="userSpaceOnUse"/>"##
        }
        body += ##"<pattern id="p100"><rect width="5" height="5"/></pattern><rect width="10" height="10" fill="url(#p0)"/>"##
        let s = try stats(body)
        // the content lives past the cap, so it is not inherited; the document still renders
        XCTAssertEqual(s.patternFills, 1)
        XCTAssertEqual(s.shapes, 1)
    }

    func testGradientHrefCycleDoesNotRecurse() throws {
        let s = try stats(##"""
        <linearGradient id="a" xlink:href="#b"/>
        <linearGradient id="b" xlink:href="#a"/>
        <rect width="10" height="10" fill="url(#a)"/>
        """##)
        XCTAssertEqual(s.shapes, 1)
    }
}
