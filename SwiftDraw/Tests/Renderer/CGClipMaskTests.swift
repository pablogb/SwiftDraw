//
//  CGClipMaskTests.swift
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

/// Pixel checks of clip paths and masks through the CoreGraphics renderer (SVG 1.1 §14.3.5, §14.4).
/// Every drawing is 16×16 on white, with a red element whose clip or mask leaves only some columns red.
final class CGClipMaskTests: XCTestCase {

    func testClipPathUnitsObjectBoundingBox() throws {
        // bbox (0,0,16,16): clip to x in 8...16
        let colors = try render(#"""
            <clipPath id="c" clipPathUnits="objectBoundingBox"><rect x="0.5" width="0.5" height="1" /></clipPath>
            <rect width="16" height="16" fill="red" clip-path="url(#c)" />
            """#)
        XCTAssertEqual(colors(4), .white)
        XCTAssertEqual(colors(12), .red)
    }

    func testClipRuleFromClipPathContents() throws {
        // outer 0...16, hole 4...12; evenodd on the path cuts the hole
        let colors = try render(#"""
            <clipPath id="c"><path clip-rule="evenodd" d="M0 0h16v16h-16z M4 0h8v16h-8z" /></clipPath>
            <rect width="16" height="16" fill="red" clip-path="url(#c)" />
            """#)
        XCTAssertEqual(colors(2), .red)
        XCTAssertEqual(colors(8), .white)
        XCTAssertEqual(colors(14), .red)
    }

    func testMixedClipRulesUnion() throws {
        let colors = try render(#"""
            <clipPath id="c">
              <rect width="4" height="16" clip-rule="evenodd" />
              <rect x="12" width="4" height="16" />
            </clipPath>
            <rect width="16" height="16" fill="red" clip-path="url(#c)" />
            """#)
        XCTAssertEqual(colors(2), .red)
        XCTAssertEqual(colors(8), .white)
        XCTAssertEqual(colors(14), .red)
    }

    func testUseInsideClipPath() throws {
        let colors = try render(#"""
            <defs><rect id="r" width="4" height="16" /></defs>
            <clipPath id="c"><use xlink:href="#r" x="8" /></clipPath>
            <rect width="16" height="16" fill="red" clip-path="url(#c)" />
            """#)
        XCTAssertEqual(colors(4), .white)
        XCTAssertEqual(colors(10), .red)
        XCTAssertEqual(colors(14), .white)
    }

    func testClipPathOnClipPath() throws {
        let colors = try render(#"""
            <clipPath id="inner"><rect x="4" width="12" height="16" /></clipPath>
            <clipPath id="c" clip-path="url(#inner)"><rect width="10" height="16" /></clipPath>
            <rect width="16" height="16" fill="red" clip-path="url(#c)" />
            """#)
        XCTAssertEqual(colors(2), .white)
        XCTAssertEqual(colors(6), .red)
        XCTAssertEqual(colors(12), .white)
    }

    func testMaskContentUnitsObjectBoundingBox() throws {
        let colors = try render(#"""
            <mask id="m" maskContentUnits="objectBoundingBox"><rect width="0.5" height="1" fill="white" /></mask>
            <rect x="8" width="8" height="16" fill="red" mask="url(#m)" />
            """#)
        XCTAssertEqual(colors(4), .white)
        XCTAssertEqual(colors(10), .red)
        XCTAssertEqual(colors(14), .white)
    }

    func testMaskRegionClipsMask() throws {
        let colors = try render(#"""
            <mask id="m" x="0" y="0" width="0.25" height="1"><rect width="16" height="16" fill="white" /></mask>
            <rect width="16" height="16" fill="red" mask="url(#m)" />
            """#)
        XCTAssertEqual(colors(2), .red)
        XCTAssertEqual(colors(8), .white)
    }

    func testMaskZeroRegionHidesElement() throws {
        let colors = try render(#"""
            <mask id="m" width="0"><rect width="16" height="16" fill="white" /></mask>
            <rect width="16" height="16" fill="red" mask="url(#m)" />
            """#)
        XCTAssertEqual(colors(2), .white)
        XCTAssertEqual(colors(8), .white)
        XCTAssertEqual(colors(14), .white)
    }

    func testFilterWithMaskTypeClip() throws {
        // mixed clip-rules make the clip a mask. A 2-px red bar blurred with σ = 3 spreads to a faint pink,
        // so its pixels are no longer solid red; with the filter ignored they would be
        let colors = try render(#"""
            <filter id="f" x="-2" y="0" width="5" height="1"><feGaussianBlur stdDeviation="3" /></filter>
            <clipPath id="c">
              <rect width="6" height="16" clip-rule="evenodd" />
              <rect x="10" width="6" height="16" />
            </clipPath>
            <rect x="1" width="2" height="16" fill="red" filter="url(#f)" clip-path="url(#c)" />
            """#)
        XCTAssertNotEqual(colors(1), .red)
        XCTAssertNotEqual(colors(2), .red)
        XCTAssertEqual(colors(8), .white)
        XCTAssertEqual(colors(13), .white)
    }

    func testClipPathWithoutShapesClipsEverything() throws {
        let colors = try render(#"""
            <clipPath id="c"><rect width="0" height="0" /></clipPath>
            <clipPath id="empty" />
            <rect width="16" height="16" fill="red" clip-path="url(#c)" />
            <rect width="16" height="16" fill="red" clip-path="url(#empty)" />
            """#)
        XCTAssertEqual(colors(2), .white)
        XCTAssertEqual(colors(8), .white)
        XCTAssertEqual(colors(13), .white)
    }

    // MARK: - PDF: masks clip vector contents to an image of the mask

    func testOverlappingEvenOddClipInPDF() throws {
        // resvg masking/clipPath/overlapped-shapes-with-evenodd: each circle keeps its own rule
        let pixel = try renderPDF(#"""
            <clipPath id="c" clip-rule="evenodd">
              <circle cx="8" cy="5" r="3"/><circle cx="5" cy="10" r="3"/><circle cx="11" cy="10" r="3"/>
            </clipPath>
            <rect width="16" height="16" fill="red" clip-path="url(#c)" />
            """#)
        XCTAssertEqual(pixel(8, 5), .red)
        XCTAssertEqual(pixel(8, 8), .red)
        XCTAssertEqual(pixel(1, 1), .white)
        XCTAssertEqual(pixel(14, 2), .white)
    }

    func testMixedClipRulesInPDF() throws {
        let pixel = try renderPDF(#"""
            <clipPath id="c">
              <path d="M1 1 H15 V15 H1 Z M5 5 H11 V11 H5 Z" clip-rule="evenodd"/>
              <circle cx="8" cy="8" r="1.5" clip-rule="nonzero"/>
            </clipPath>
            <rect width="16" height="16" fill="red" clip-path="url(#c)" />
            """#)
        XCTAssertEqual(pixel(2, 8), .red)
        XCTAssertEqual(pixel(6, 6), .white)
        XCTAssertEqual(pixel(8, 8), .red)
        XCTAssertEqual(pixel(0, 0), .white)
    }

    func testMaskElementInPDF() throws {
        let pixel = try renderPDF(#"""
            <mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="16" height="16">
              <rect width="8" height="16" fill="white"/>
            </mask>
            <rect width="16" height="16" fill="red" mask="url(#m)" />
            """#)
        XCTAssertEqual(pixel(3, 8), .red)
        XCTAssertEqual(pixel(12, 8), .white)
    }

    func testClipPathOnClipPathStaysVectorInPDF() throws {
        let body = #"""
            <clipPath id="outer"><rect width="12" height="12"/></clipPath>
            <clipPath id="c" clip-path="url(#outer)"><circle cx="8" cy="8" r="6"/></clipPath>
            <rect width="16" height="16" fill="red" clip-path="url(#c)" />
            """#
        let pixel = try renderPDF(body)
        XCTAssertEqual(pixel(6, 6), .red)
        XCTAssertEqual(pixel(13, 8), .white)
        XCTAssertEqual(pixel(8, 13), .white)
        // two clips: no image in the page
        let page = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: try makePDF(body) as CFData)!)?.page(at: 1))
        var resources: CGPDFDictionaryRef?
        var xObjects: CGPDFDictionaryRef?
        if let dictionary = page.dictionary, CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources {
            CGPDFDictionaryGetDictionary(resources, "XObject", &xObjects)
        }
        XCTAssertNil(xObjects)
    }

    func testMaskImageCoversOnlyWhatTheMaskDraws() throws {
        // a 4 pt mask on a 1000 pt page: rasterized around the mask, not the page
        let svg = try XCTUnwrap(SVG(xml: #"""
        <svg xmlns="http://www.w3.org/2000/svg" width="1000" height="1000">
            <mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="1000" height="1000"><rect x="500" y="500" width="4" height="4" fill="white"/></mask>
            <rect width="1000" height="1000" fill="red" mask="url(#m)" />
        </svg>
        """#))
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let ctx = try XCTUnwrap(CGContext(consumer: try XCTUnwrap(CGDataConsumer(data: data as CFMutableData)), mediaBox: &box, nil))
        ctx.beginPDFPage(nil)
        let renderer = CGRenderer(context: ctx)
        renderer.perform(svg.commands)
        ctx.endPDFPage()
        ctx.closePDF()
        // the coarse probe, then about 4 × 4 pt at 300 ppi, not the 16 million pixels of the page
        let spent = renderer.filterLayers.spentPasses - CGRenderer.maskProbePixels
        XCTAssertGreaterThan(spent, 4 * 4 * 17)
        XCTAssertLessThan(spent, 40 * 40 * 18)
    }

    func testSoftMaskCompositesTheGroupOnceInPDF() throws {
        // a red square under a blue band, faded by a gradient: half way, the band hides the red under it
        let color = try renderPDFColor(#"""
            <linearGradient id="fade" x1="0" x2="1"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#000"/></linearGradient>
            <mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="16" height="16"><rect width="16" height="16" fill="url(#fade)"/></mask>
            <g mask="url(#m)"><rect width="16" height="16" fill="#f00"/><rect y="4" width="16" height="8" fill="#00f"/></g>
            """#)
        // through the mask one shape at a time, the red showed: (128, 64, 192). CoreGraphics' reader
        // composites the group in Generic RGB: about (138, 160, 250) where (128, 128, 255) is exact
        let band = color(8, 8)
        XCTAssertLessThan(Int(band.red) - Int(band.green), 16)
        XCTAssertGreaterThan(band.blue, 200)
        let red = color(8, 2)
        XCTAssertGreaterThan(red.red, 200)
        XCTAssertGreaterThan(Int(red.red) - Int(red.green), 60)
    }

    func testMaskImageCoversOnlyTheMaskedContents() throws {
        // a page-sized mask on a 6 pt square: rasterized around the square, not the page
        let svg = try XCTUnwrap(SVG(xml: #"""
        <svg xmlns="http://www.w3.org/2000/svg" width="1000" height="1000">
            <mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="1000" height="1000"><rect width="1000" height="1000" fill="white"/></mask>
            <rect x="500" y="500" width="6" height="6" fill="red" mask="url(#m)" />
        </svg>
        """#))
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let ctx = try XCTUnwrap(CGContext(consumer: try XCTUnwrap(CGDataConsumer(data: data as CFMutableData)), mediaBox: &box, nil))
        ctx.beginPDFPage(nil)
        let renderer = CGRenderer(context: ctx)
        renderer.perform(svg.commands)
        ctx.endPDFPage()
        ctx.closePDF()
        // a probe and an image of 6 pt at 300 ppi, 25 × 25 pixels each
        XCTAssertGreaterThanOrEqual(renderer.filterLayers.spentPasses, 2 * 25 * 25)
        XCTAssertLessThan(renderer.filterLayers.spentPasses, 2 * 30 * 30)
    }

    func testMaskedFilteredContentsKeepWhatTheFilterDrawsBeyondThem() throws {
        // a masked layer's own filter is drawn first: an offset (or a blur's spread) lands outside its contents
        let colors = try render(#"""
            <mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="16" height="16"><rect width="16" height="16" fill="white"/></mask>
            <filter id="f" filterUnits="userSpaceOnUse" x="0" y="0" width="16" height="16"><feOffset dx="6"/></filter>
            <rect x="2" y="2" width="4" height="12" fill="red" filter="url(#f)" mask="url(#m)" />
            """#)
        XCTAssertEqual(colors(10), .red)
        XCTAssertEqual(colors(4), .white)
    }

    func testMaskedStrokeIsKeptWhereTheFillIsNot() throws {
        // the transparency layer covers the contents with their stroke
        let colors = try render(#"""
            <mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="16" height="16"><rect width="16" height="16" fill="white"/></mask>
            <rect x="5" y="5" width="6" height="6" fill="red" stroke="red" stroke-width="6" mask="url(#m)" />
            """#)
        XCTAssertEqual(colors(3), .red)
        XCTAssertEqual(colors(12), .red)
        XCTAssertEqual(colors(0), .white)
    }

    func testMaskedZeroLengthSubpathsKeepTheirCaps() throws {
        // `M x y Z` draws only its square caps, at x = 3 and 13; the layer is drawn within what it covers
        let colors = try render(#"""
            <mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="16" height="16"><rect width="16" height="16" fill="white"/></mask>
            <g mask="url(#m)"><path d="M3 8 Z M13 8 Z" stroke="red" stroke-width="4" stroke-linecap="square"/><rect x="7" y="7" width="2" height="2" fill="red"/></g>
            """#)
        XCTAssertEqual(colors(2), .red)
        XCTAssertEqual(colors(8), .red)
        XCTAssertEqual(colors(14), .red)
        XCTAssertEqual(colors(6), .white)
    }

    enum Pixel: Equatable {
        case red
        case white
        case other
    }

    /// The PDF drawn on white at 4 px per point; the colour at the centre of point (x, y), y down.
    func renderPDFColor(_ body: String) throws -> (Int, Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let page = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: try makePDF(body) as CFData)!)?.page(at: 1))
        let canvas = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 64 * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        canvas.setFillColor(.white)
        canvas.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        canvas.scaleBy(x: 4, y: 4)
        canvas.drawPDFPage(page)
        let data = Array(UnsafeBufferPointer(start: try XCTUnwrap(canvas.data).assumingMemoryBound(to: UInt8.self), count: 64 * 64 * 4))
        return { x, y in
            let i = (y * 4 + 2) * 64 * 4 + (x * 4 + 2) * 4
            return (data[i], data[i + 1], data[i + 2])
        }
    }

    func makePDF(_ body: String) throws -> Data {
        let svg = try XCTUnwrap(SVG(xml: """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="16" height="16">
            \(body)
        </svg>
        """))
        return try svg.pdfData()
    }

    /// The PDF drawn on white at 4 px per point; `pixel(x, y)` samples the centre of point (x, y), y down.
    func renderPDF(_ body: String) throws -> (Int, Int) -> Pixel {
        let page = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: try makePDF(body) as CFData)!)?.page(at: 1))
        let canvas = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 64 * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        canvas.setFillColor(.white)
        canvas.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        canvas.scaleBy(x: 4, y: 4)
        canvas.drawPDFPage(page)
        let data = Array(UnsafeBufferPointer(start: try XCTUnwrap(canvas.data).assumingMemoryBound(to: UInt8.self), count: 64 * 64 * 4))
        return { x, y in
            let i = (y * 4 + 2) * 64 * 4 + (x * 4 + 2) * 4
            let (r, g, b) = (data[i], data[i + 1], data[i + 2])
            if r > 230, g < 25, b < 25 { return .red }
            if r > 230, g > 230, b > 230 { return .white }
            return .other
        }
    }

    func render(_ body: String) throws -> (Int) -> Pixel {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="16" height="16">
            <rect width="16" height="16" fill="white" />
            \(body)
        </svg>
        """
        let svg = try XCTUnwrap(SVG(xml: xml))
        let image = svg.rasterize(with: CGSize(width: 16, height: 16), scale: 1)
        let canvas = NSBitmapImageRep(pixelsWide: 16, pixelsHigh: 16)
        canvas.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
        canvas.unlockFocus()

        return { i in
            guard let color = canvas.colorAt(x: i, y: 8)?.usingColorSpace(.deviceRGB) else { return .other }
            let (r, g, b) = (color.redComponent, color.greenComponent, color.blueComponent)
            if r > 0.9, g < 0.1, b < 0.1 { return .red }
            if r > 0.9, g > 0.9, b > 0.9 { return .white }
            return .other
        }
    }
}

#endif
