//
//  CGPatternTests.swift
//  SwiftDraw
//
//  Created by Misoservices on 8/10/26.
//  Copyright 2026 Simon Whitty
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


@testable import SwiftDraw

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
import XCTest

/// Pixel checks of `<pattern>` through the CoreGraphics renderer (SVG 1.1 §13.3).
/// Every drawing is 16×16 and uses full-height (or full-width) stripes, so only one axis matters.
final class CGPatternTests: XCTestCase {

    func testPatternXOffsetsTiles() throws {
        // tiles at x = 4 + 8k, red in the first half of each tile
        let colors = try render(pattern: #"<pattern id="p" x="4" width="8" height="16" patternUnits="userSpaceOnUse">\#(stripe)</pattern>"#)
        XCTAssertEqual(colors(1), .white)
        XCTAssertEqual(colors(5), .red)
        XCTAssertEqual(colors(9), .white)
        XCTAssertEqual(colors(13), .red)
    }

    func testPatternYOffsetsTiles() throws {
        // horizontal stripes: tiles at y = 4 + 8k, red in the top half of each tile
        let colors = try render(pattern: #"<pattern id="p" y="4" width="16" height="8" patternUnits="userSpaceOnUse"><rect width="16" height="4" fill="red" /></pattern>"#, column: true)
        XCTAssertEqual(colors(1), .white)
        XCTAssertEqual(colors(5), .red)
        XCTAssertEqual(colors(9), .white)
        XCTAssertEqual(colors(13), .red)
    }

    func testPatternTransformMovesTiles() throws {
        let colors = try render(pattern: #"<pattern id="p" width="8" height="16" patternUnits="userSpaceOnUse" patternTransform="translate(2, 0)">\#(stripe)</pattern>"#)
        XCTAssertEqual(colors(1), .white)
        XCTAssertEqual(colors(3), .red)
        XCTAssertEqual(colors(7), .white)
        XCTAssertEqual(colors(11), .red)
    }

    func testPatternHrefInheritsAttributesAndContent() throws {
        let colors = try render(pattern: #"""
            <pattern id="base" x="4" width="8" height="16" patternUnits="userSpaceOnUse">\#(stripe)</pattern>
            <pattern id="p" xlink:href="#base" patternTransform="translate(-2, 0)" />
            """#)
        XCTAssertEqual(colors(1), .white)
        XCTAssertEqual(colors(3), .red)
        XCTAssertEqual(colors(7), .white)
        XCTAssertEqual(colors(11), .red)
    }

    func testPatternUnitsDefaultToObjectBoundingBox() throws {
        // width 0.5 of the 16 wide bounding box: tiles of 8
        let colors = try render(pattern: #"<pattern id="p" width="0.5" height="1">\#(stripe)</pattern>"#)
        XCTAssertEqual(colors(1), .red)
        XCTAssertEqual(colors(5), .white)
        XCTAssertEqual(colors(9), .red)
        XCTAssertEqual(colors(13), .white)
    }

    func testPatternViewBoxScalesContent() throws {
        // viewBox 0 0 8 16 into a 16×16 tile: meet scale 1, content centred at x = 4
        let colors = try render(pattern: #"<pattern id="p" width="16" height="16" viewBox="0 0 8 16" patternUnits="userSpaceOnUse">\#(stripe)</pattern>"#)
        XCTAssertEqual(colors(1), .white)
        XCTAssertEqual(colors(5), .red)
        XCTAssertEqual(colors(9), .white)
    }

    func testPatternWithoutSizePaintsNothingAndKeepsDocument() throws {
        let colors = try render(pattern: #"<pattern id="p">\#(stripe)</pattern>"#)
        XCTAssertEqual(colors(1), .white)
        XCTAssertEqual(colors(5), .white)
    }
}

extension CGPatternTests {

    // As an app page: CoreGraphics contexts the caller has flipped and placed 8 px down before drawing.
    // Tiles at y = 4 + 8k, red in the top half of each, so rows 8 + 4...8 and 8 + 12...16 are red.

    func testPatternInAFlippedAndTranslatedBitmap() throws {
        let colors = try renderPlaced(pdf: false)
        XCTAssertEqual(colors(9), .white)
        XCTAssertEqual(colors(13), .red)
        XCTAssertEqual(colors(17), .white)
        XCTAssertEqual(colors(21), .red)
    }

    func testPatternInAFlippedAndTranslatedPDF() throws {
        let colors = try renderPlaced(pdf: true)
        XCTAssertEqual(colors(9), .white)
        XCTAssertEqual(colors(13), .red)
        XCTAssertEqual(colors(17), .white)
        XCTAssertEqual(colors(21), .red)
    }

    /// Samples column 8 of a 16×24 drawing, rows from the top.
    func renderPlaced(pdf: Bool) throws -> (Int) -> Pixel {
        let svg = try XCTUnwrap(SVG(xml: """
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16">
            <defs><pattern id="p" y="4" width="16" height="8" patternUnits="userSpaceOnUse"><rect width="16" height="4" fill="red" /></pattern></defs>
            <rect width="16" height="16" fill="url(#p)" />
        </svg>
        """))
        func place(_ ctx: CGContext) {
            ctx.translateBy(x: 0, y: 24)
            ctx.scaleBy(x: 1, y: -1)
            ctx.translateBy(x: 0, y: 8)
            ctx.draw(svg)
        }
        let canvas = try XCTUnwrap(CGContext(data: nil, width: 16, height: 24, bitsPerComponent: 8, bytesPerRow: 16 * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        canvas.setFillColor(.white)
        canvas.fill(CGRect(x: 0, y: 0, width: 16, height: 24))
        if pdf {
            let data = NSMutableData()
            var box = CGRect(x: 0, y: 0, width: 16, height: 24)
            let ctx = try XCTUnwrap(CGContext(consumer: try XCTUnwrap(CGDataConsumer(data: data as CFMutableData)), mediaBox: &box, nil))
            ctx.beginPDFPage(nil)
            place(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            canvas.drawPDFPage(try XCTUnwrap(CGPDFDocument(CGDataProvider(data: data as CFData)!)?.page(at: 1)))
        } else {
            place(canvas)
        }
        let bytes = Array(UnsafeBufferPointer(start: try XCTUnwrap(canvas.data).assumingMemoryBound(to: UInt8.self), count: 16 * 24 * 4))
        return { row in
            let i = (row * 16 + 8) * 4
            if bytes[i] > 230, bytes[i + 1] < 25, bytes[i + 2] < 25 { return .red }
            if bytes[i] > 230, bytes[i + 1] > 230, bytes[i + 2] > 230 { return .white }
            return .other
        }
    }
}

extension CGPatternTests {

    // As the app draws a page: a flipped, layer-backed view translates by an inset, then draws the page.
    final class PageView: NSView {
        let svg: SVG
        let inset: CGPoint

        init(svg: SVG, inset: CGPoint, scale: CGFloat) {
            self.svg = svg
            self.inset = inset
            super.init(frame: CGRect(x: 0, y: 0, width: (svg.size.width + 2 * inset.x) * scale,
                                     height: (svg.size.height + 2 * inset.y) * scale))
            wantsLayer = true
            scaleUnitSquare(to: NSSize(width: scale, height: scale))
        }

        required init?(coder: NSCoder) { nil }

        override var isFlipped: Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.translateBy(x: inset.x, y: inset.y)
            context.draw(svg, in: CGRect(origin: .zero, size: svg.size))
        }
    }

    @MainActor
    func testPatternInAFlippedViewMatchesABitmapAtEachScale() throws {
        // tiles of 10 × 8 from (3, 5), red top left and blue bottom right of each: placement, scale and
        // orientation all show
        let svg = try XCTUnwrap(SVG(xml: """
        <svg xmlns="http://www.w3.org/2000/svg" width="40" height="40">
            <defs><pattern id="p" x="3" y="5" width="10" height="8" patternUnits="userSpaceOnUse">
                <rect width="5" height="3" fill="red" /><rect x="5" y="4" width="5" height="4" fill="blue" />
            </pattern></defs>
            <rect x="2" y="2" width="36" height="36" fill="url(#p)" />
        </svg>
        """))
        for scale in [1, 2] as [CGFloat] {
            let view = PageView(svg: svg, inset: CGPoint(x: 7, y: 9), scale: scale)
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)

            // the same page in a plain bitmap, placed as the view places it
            let width = rep.pixelsWide
            let height = rep.pixelsHigh
            let pixelsPerPoint = CGFloat(width) / view.bounds.width
            let bitmap = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            bitmap.translateBy(x: 0, y: CGFloat(height))
            bitmap.scaleBy(x: pixelsPerPoint, y: -pixelsPerPoint)
            bitmap.translateBy(x: 7, y: 9)
            bitmap.draw(svg, in: CGRect(origin: .zero, size: svg.size))
            let bytes = try XCTUnwrap(bitmap.data).assumingMemoryBound(to: UInt8.self)

            var mismatches = 0
            for y in 0..<height {
                for x in 0..<width {
                    let expected = Pixel(bytes + y * bitmap.bytesPerRow + x * 4)
                    let color = try XCTUnwrap(rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    let actual = Pixel(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent, alpha: color.alphaComponent)
                    if expected != actual { mismatches += 1 }
                }
            }
            XCTAssertEqual(mismatches, 0, "scale \(scale)")
        }
    }
}

extension CGPatternTests {

    func testPatternCellIsGeneratedOnceForEveryShapeItFills() throws {
        // a bounding-box pattern: every shape has its own tile, all drawn from one set of commands
        let rects = (0..<50).map { ##"<rect x="\##($0 * 3)" width="\##($0 + 1)" height="\##(2 * $0 + 1)" fill="url(#p)"/>"## }.joined()
        let svg = try XCTUnwrap(SVG(xml: """
        <svg xmlns="http://www.w3.org/2000/svg" width="200" height="200">
            <defs><pattern id="p" width="0.5" height="0.5"><rect width="1" height="1" fill="red"/></pattern></defs>
            \(rects)
        </svg>
        """))
        let patterns = svg.commands.compactMap { command -> CGTransformingPattern? in
            guard case .setFillPattern(let pattern) = command else { return nil }
            return pattern
        }
        XCTAssertEqual(patterns.count, 50)
        let storage = patterns.map { $0.contents.withUnsafeBufferPointer { $0.baseAddress } }
        XCTAssertEqual(Set(storage).count, 1)
    }

    /// Twenty 10 × 10 squares in a row, each under its own transform, filled with a pattern red on its left half.
    func renderSquaresUnderTransforms(maxFilterLayerPixels: Int, current: Bool) throws -> (Int) -> CGFloat {
        let squares = (0..<20).map { ##"<rect width="10" height="10" fill="url(#p)" transform="translate(\##($0 * 10) 0)"/>"## }.joined()
        let svg = try XCTUnwrap(SVG(xml: """
        <svg xmlns="http://www.w3.org/2000/svg" width="200" height="10">
            <defs><pattern id="p" width="10" height="10" patternUnits="userSpaceOnUse"><rect width="5" height="10" fill="red"/></pattern></defs>
            \(squares)
        </svg>
        """))
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 200, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.translateBy(x: 0, y: 10)
        bitmap.scaleBy(x: 1, y: -1)
        let previous = NSGraphicsContext.current
        if current {
            NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: true)
        }
        CGRenderer(context: bitmap, maxFilterLayerPixels: maxFilterLayerPixels).perform(svg.commands)
        NSGraphicsContext.current = previous
        let bytes = try XCTUnwrap(bitmap.data).assumingMemoryBound(to: UInt8.self)
        let row = (0..<200).map { x in CGFloat(bytes[5 * bitmap.bytesPerRow + x * 4 + 3]) / 255 }
        return { x in row[x] }
    }

    func testPatternCellsPastTheDrawingsBudgetPaintTheirAverageColour() throws {
        // a new CGPattern per square, each cell 2 commands and 100 pixels: 900 of a budget of 64 × 100
        let alpha = try renderSquaresUnderTransforms(maxFilterLayerPixels: 100, current: false)
        XCTAssertEqual(alpha(2), 1, accuracy: 0.01)
        XCTAssertEqual(alpha(7), 0, accuracy: 0.01)
        XCTAssertEqual(alpha(192), 0.5, accuracy: 0.02)
        XCTAssertEqual(alpha(197), 0.5, accuracy: 0.02)
    }

    func testPatternCellsTiledPastTheDrawingsBudgetPaintTheirAverageColour() throws {
        // where AppKit draws, the cells are tiled by hand: one per square, 6 commands each
        let alpha = try renderSquaresUnderTransforms(maxFilterLayerPixels: 100, current: true)
        XCTAssertEqual(alpha(2), 1, accuracy: 0.01)
        XCTAssertEqual(alpha(7), 0, accuracy: 0.01)
        XCTAssertEqual(alpha(192), 0.5, accuracy: 0.02)
        XCTAssertEqual(alpha(197), 0.5, accuracy: 0.02)
        // and all tiled within a full budget
        let full = try renderSquaresUnderTransforms(maxFilterLayerPixels: CGRenderer.defaultMaxFilterLayerPixels, current: true)
        XCTAssertEqual(full(192), 1, accuracy: 0.01)
        XCTAssertEqual(full(197), 0, accuracy: 0.01)
    }
}

extension CGPatternTests.Pixel {
    // premultiplied RGBA bytes, opaque colours only
    init(_ p: UnsafePointer<UInt8>) {
        self.init(red: CGFloat(p[0]) / 255, green: CGFloat(p[1]) / 255, blue: CGFloat(p[2]) / 255, alpha: CGFloat(p[3]) / 255)
    }

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        // loose: a view's colours are matched to the display's space and read back converted
        guard alpha > 0.9 else { self = .other; return }
        if red > 0.8, green < 0.3, blue < 0.3 { self = .red }
        else if red < 0.3, green < 0.3, blue > 0.8 { self = .blue }
        else { self = .other }
    }
}

extension CGPatternTests {

    enum Pixel: Equatable {
        case red
        case blue
        case white
        case other
    }

    var stripe: String { #"<rect width="4" height="16" fill="red" />"# }

    /// Samples the middle row, or the middle column when `column` is true.
    func render(pattern: String, column: Bool = false) throws -> (Int) -> Pixel {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="16" height="16">
            <defs>\(pattern)</defs>
            <rect width="16" height="16" fill="white" />
            <rect width="16" height="16" fill="url(#p)" />
        </svg>
        """
        let svg = try XCTUnwrap(SVG(xml: xml))
        let image = svg.rasterize(with: CGSize(width: 16, height: 16), scale: 1)
        let canvas = NSBitmapImageRep(pixelsWide: 16, pixelsHigh: 16)
        canvas.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
        canvas.unlockFocus()

        return { i in
            guard let color = canvas.colorAt(x: column ? 8 : i, y: column ? i : 8)?.usingColorSpace(.deviceRGB) else { return .other }
            let (r, g, b) = (color.redComponent, color.greenComponent, color.blueComponent)
            if r > 0.9, g < 0.1, b < 0.1 { return .red }
            if r > 0.9, g > 0.9, b > 0.9 { return .white }
            return .other
        }
    }
}

#endif
