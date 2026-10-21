//
//  CGPath+SegmentTests.swift
//  SwiftDraw
//
//  Created by Simon Whitty on 20/11/18.
//  Copyright 2020 Simon Whitty
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
//

import XCTest
@testable import SwiftDraw
#if canImport(CoreGraphics)
import CoreGraphics

final class CGPathSegmentTests: XCTestCase {

  func testSegments() {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: 0))
    path.addLine(to: CGPoint(x: 0, y: 100))
    path.addQuadCurve(to: CGPoint(x: 100, y: 100),
                      control: CGPoint(x: 50, y: 50))
    path.addCurve(to: CGPoint(x: 200, y: 100),
                  control1: CGPoint(x: 100, y: 50),
                  control2: CGPoint(x: 200, y: 150))
    path.closeSubpath()

    XCTAssertEqual(path.segments(),
                   [.move(CGPoint(x: 0, y: 0)),
                    .line(CGPoint(x: 0, y: 100)),
                    .quad(CGPoint(x: 50, y: 50), CGPoint(x: 100, y: 100)),
                    .cubic(CGPoint(x: 100, y: 50), CGPoint(x: 200, y: 150), CGPoint(x: 200, y: 100)),
                    .close])
  }

  func testString() {
    let font = CTFontCreateWithName("Helvetica" as CFString, 10.0, nil)
    let path = "_".toPath(font: font)!

    let segments = path.segments()
    XCTAssertEqual(segments.count, 5)
    guard case .move(_) = segments[0] else { XCTFail("expected move"); return }
    guard case .line(_) = segments[1] else { XCTFail("expected line"); return }
    guard case .line(_) = segments[2] else { XCTFail("expected line"); return }
    guard case .line(_) = segments[3] else { XCTFail("expected line"); return }
    XCTAssertEqual(segments[4], .close)
  }

  func testStringGlyphsArePlacedOnTheBaseline() {
    let font = CTFontCreateWithName("Helvetica" as CFString, 10.0, nil)
    func glyphBounds(_ name: String) -> CGRect {
      CTFontGetBoundingRectsForGlyphs(font, .default, [CTFontGetGlyphWithName(font, name as CFString)], nil, 1)
    }
    let bounds = "a_".toPath(font: font)!.boundingBox
    // flipped to y down, the baseline at 0: "a" rises above it, "_" hangs below
    XCTAssertEqual(bounds.minX, glyphBounds("a").minX, accuracy: 0.01)
    XCTAssertEqual(bounds.minY, -glyphBounds("a").maxY, accuracy: 0.01)
    XCTAssertEqual(bounds.maxY, -glyphBounds("underscore").minY, accuracy: 0.01)
  }

  func testLongStringIsBuiltInLinearTime() {
    // 40 000 glyphs: appending each with a transform cost the whole path so far (about 100 s)
    nonisolated(unsafe) let font = CTFontCreateWithName("Helvetica" as CFString, 10.0, nil)
    nonisolated(unsafe) var path: CGPath?
    let done = DispatchSemaphore(value: 0)
    Thread {
      path = String(repeating: "a&", count: 20_000).toPath(font: font)
      done.signal()
    }.start()
    XCTAssertEqual(done.wait(timeout: .now() + 20), .success)
    XCTAssertGreaterThan(path?.boundingBox.width ?? 0, 20_000 * 10)
  }

  /// `segments` lines between pseudo-random points within `size`
  static func scribble(segments: Int, size: CGFloat = 100) -> CGPath {
    var seed: UInt64 = 1
    func next() -> CGFloat {
      seed = seed &* 6364136223846793005 &+ 1442695040888963407
      return CGFloat(seed >> 33) / CGFloat(1 << 31) * size
    }
    let path = CGMutablePath()
    path.move(to: .zero)
    for _ in 0..<segments {
      path.addLine(to: CGPoint(x: next(), y: next()))
    }
    return path
  }

  func testRasterCostCountsCrossingsAndCrowdedRows() {
    // measured: 1.7 s, 2.1 s and 0.15 s to fill on a bitmap
    let scribble = Self.scribble(segments: 2_000)
    XCTAssertGreaterThan(scribble.rasterCost(transform: .identity), 1_000_000_000)
    let tinyText = String(repeating: "W", count: 1_000).toPath(font: CTFontCreateWithName("Times" as CFString, 1, nil))!
    XCTAssertGreaterThan(tinyText.rasterCost(transform: .identity), 1_000_000_000)
    let line = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 2)
      .toPath(font: CTFontCreateWithName("Times" as CFString, 12, nil))!
    let page = CGMutablePath()
    for row in 0..<50 {
      page.addPath(line, transform: CGAffineTransform(translationX: 0, y: CGFloat(row) * 14))
    }
    XCTAssertLessThan(page.rasterCost(transform: .identity), 400_000_000)

    // cost does not depend on scale or position, but on which way the rows run
    let scaled = CGAffineTransform(a: 4, b: 0, c: 0, d: 4, tx: 100, ty: 100)
    XCTAssertEqual(scribble.rasterCost(transform: scaled), scribble.rasterCost(transform: .identity))
    // a few edges cost nothing worth counting
    XCTAssertEqual(Self.scribble(segments: 10).rasterCost(transform: .identity), 0)
  }
}

#endif
