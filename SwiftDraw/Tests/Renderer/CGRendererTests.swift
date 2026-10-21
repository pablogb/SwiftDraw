//
//  CGRendererTests.swift
//  SwiftDraw
//
//  Created by Simon Whitty on 18/12/18.
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

@testable import SwiftDrawDOM
@testable import SwiftDraw

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
import CoreGraphics
import XCTest

final class CGRendererTests: XCTestCase {
  
  func testTilingByAnEmptyOrTinySizeDrawsNoTiles() throws {
    // the tile count was converted with Int(): infinite or past Int.max, it trapped
    let svg = try XCTUnwrap(SVG(xml: #"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10"/></svg>"#))
    let ctx = try XCTUnwrap(CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.draw(svg.sized(CGSize(width: 1e-300, height: 1e-300)), in: CGRect(x: 0, y: 0, width: 10, height: 10), byTiling: true)
    ctx.draw(svg.sized(.zero), in: CGRect(x: 0, y: 0, width: 10, height: 10), byTiling: true)
    ctx.draw(svg, in: CGRect(x: 0, y: 0, width: 10, height: 10), capInsets: (1, 1, 1, 1e-300), byTiling: true)
  }

  func testDrawsRect() {
    let renderer = ImageRenderer(pixelsWide: 2, pixelsHigh: 2)
    
    renderer.renderer.setFill(color: .red)
    renderer.renderer.fill(path: CGPath.rect(), rule: .evenOdd)
    
    XCTAssertEqual(renderer.getColor(x: 0, y: 0), .red)
    XCTAssertEqual(renderer.getColor(x: 1, y: 1), .red)
  }
  
  func testLineDashLeavesGaps() {
    let renderer = ImageRenderer(pixelsWide: 20, pixelsHigh: 4)
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: 2))
    path.addLine(to: CGPoint(x: 20, y: 2))

    renderer.renderer.setStroke(color: .red)
    renderer.renderer.setLine(width: 4)
    renderer.renderer.setLineDash(phase: 0, lengths: [5, 5])
    renderer.renderer.stroke(path: path)

    XCTAssertEqual(renderer.getColor(x: 2, y: 2), .red)
    XCTAssertNotEqual(renderer.getColor(x: 7, y: 2), .red)
    XCTAssertEqual(renderer.getColor(x: 12, y: 2), .red)
  }

  func testRepeatGradientRepeats() throws {
    // red→blue every 10 units: pad would leave x ≥ 10 blue, repeat restarts red at x = 10 and 20
    func redness(_ spread: String, x: Int) throws -> CGFloat {
      let renderer = ImageRenderer(pixelsWide: 40, pixelsHigh: 4)
      let svg = try DOM.SVG.parse(xml: """
      <svg xmlns="http://www.w3.org/2000/svg" width="40" height="4">
        <defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" x2="10" spreadMethod="\(spread)">
          <stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/>
        </linearGradient></defs>
        <rect width="40" height="4" fill="url(#g)"/>
      </svg>
      """)
      let layer = LayerTree.Builder(svg: svg).makeLayer()
      let generator = LayerTree.CommandGenerator(provider: CGProvider(), size: LayerTree.Size(40, 4), options: .default)
      renderer.renderer.perform(generator.renderCommands(for: layer, colorConverter: .default))
      let color = try XCTUnwrap(renderer.getColor(x: x, y: 2)?.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil))
      let c = try XCTUnwrap(color.components)
      return c[0] - c[2]
    }
    XCTAssertGreaterThan(try redness("repeat", x: 1), 0.5)
    XCTAssertGreaterThan(try redness("repeat", x: 21), 0.5)
    XCTAssertLessThan(try redness("pad", x: 21), -0.5)
    // reflect: x = 11 mirrors x = 9 (blue)
    XCTAssertLessThan(try redness("reflect", x: 11), -0.5)
    XCTAssertGreaterThan(try redness("reflect", x: 19), 0.5)
  }

  func testRadialReflectGradientMirrors() throws {
    // red at the centre, blue at r = 10, mirrored back to red at r = 20 (pad stays blue)
    func redness(_ spread: String, x: Int) throws -> CGFloat {
      let renderer = ImageRenderer(pixelsWide: 40, pixelsHigh: 40)
      let svg = try DOM.SVG.parse(xml: """
      <svg xmlns="http://www.w3.org/2000/svg" width="40" height="40">
        <defs><radialGradient id="g" gradientUnits="userSpaceOnUse" cx="20" cy="20" r="10" spreadMethod="\(spread)">
          <stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/>
        </radialGradient></defs>
        <rect width="40" height="40" fill="url(#g)"/>
      </svg>
      """)
      let layer = LayerTree.Builder(svg: svg).makeLayer()
      let generator = LayerTree.CommandGenerator(provider: CGProvider(), size: LayerTree.Size(40, 40), options: .default)
      renderer.renderer.perform(generator.renderCommands(for: layer, colorConverter: .default))
      let color = try XCTUnwrap(renderer.getColor(x: x, y: 20)?.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil))
      let c = try XCTUnwrap(color.components)
      return c[0] - c[2]
    }
    XCTAssertGreaterThan(try redness("reflect", x: 20), 0.5)
    XCTAssertLessThan(try redness("reflect", x: 30), -0.5)
    XCTAssertGreaterThan(try redness("reflect", x: 39), 0.5)
    XCTAssertLessThan(try redness("pad", x: 39), -0.5)
  }

  func testPreserveAspectRatioLetterboxesViewBox() throws {
    // 100x100 viewBox in a 200x100 viewport: xMidYMid meet centres it, leaving 50px bands either side
    let dom = try DOM.SVG.parse(xml: """
    <svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" viewBox="0 0 100 100">
    <rect width="100" height="100" fill="red"/></svg>
    """)
    let svg = SVG(dom: dom, options: .default)
    let renderer = ImageRenderer(pixelsWide: 200, pixelsHigh: 100)
    renderer.renderer.perform(svg.commands)

    XCTAssertTrue(renderer.isSVGRed(x: 100, y: 50))
    XCTAssertTrue(renderer.isSVGRed(x: 55, y: 50))
    XCTAssertFalse(renderer.isSVGRed(x: 45, y: 50))
    XCTAssertFalse(renderer.isSVGRed(x: 155, y: 50))
  }

  func testPreserveAspectRatioSliceFillsViewport() throws {
    let dom = try DOM.SVG.parse(xml: """
    <svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" viewBox="0 0 100 100" preserveAspectRatio="xMinYMin slice">
    <rect width="100" height="100" fill="red"/></svg>
    """)
    let svg = SVG(dom: dom, options: .default)
    let renderer = ImageRenderer(pixelsWide: 200, pixelsHigh: 100)
    renderer.renderer.perform(svg.commands)

    XCTAssertTrue(renderer.isSVGRed(x: 5, y: 5))
    XCTAssertTrue(renderer.isSVGRed(x: 195, y: 95))
  }

  func testRootSliceDoesNotBleedOutsideItsViewport() throws {
    // drawn into a larger context, the overflow of a sliced viewBox is clipped to the 200x100 viewport
    let dom = try DOM.SVG.parse(xml: """
    <svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" viewBox="0 0 100 100" preserveAspectRatio="xMinYMin slice">
    <rect x="-50" y="-50" width="300" height="300" fill="red"/></svg>
    """)
    let svg = SVG(dom: dom, options: .default)
    let renderer = ImageRenderer(pixelsWide: 300, pixelsHigh: 200)
    renderer.renderer.perform(svg.commands)

    // the context is not flipped, so the 200x100 viewport is the bottom half of the 300x200 bitmap (rows 100...199)
    XCTAssertTrue(renderer.isSVGRed(x: 100, y: 150))
    XCTAssertFalse(renderer.isSVGRed(x: 250, y: 150))
    XCTAssertFalse(renderer.isSVGRed(x: 100, y: 50))
  }

  func testAlphaClips() {
    let renderer = ImageRenderer(pixelsWide: 2, pixelsHigh: 2)
    
    renderer.renderer.setFill(color: .red)
    renderer.renderer.fill(path: CGPath.rect(), rule: .evenOdd)
    
    XCTAssertEqual(renderer.getColor(x: 0, y: 0), .red)
    XCTAssertEqual(renderer.getColor(x: 1, y: 1), .red)
  }

  /// Twenty copies of a 300-segment scribble stroked 4 px wide, side by side, each in a 100 px square:
  /// which of them drew, with the drawing's budget at 64 × 100 000 (each stroke is estimated at 0.9 ms;
  /// copies may spend half).
  func renderScribbles(asCopies: Bool) throws -> (Int) -> Bool {
    let scribble = CGPathSegmentTests.scribble(segments: 300)
    let bitmap = try XCTUnwrap(CGContext(data: nil, width: 2_000, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    var commands: [RendererCommand<CGTypes>] = [.setStroke(color: CGColor(gray: 0, alpha: 1)), .setLine(width: 4),
                                                .setFill(color: CGColor(gray: 0, alpha: 1))]
    for copy in 0..<20 {
      let place: [RendererCommand<CGTypes>] = [.pushState, .translate(tx: CGFloat(copy) * 100, ty: 0), .stroke(scribble), .popState]
      commands += asCopies ? [.pushCopy] + place + [.popCopy] : place
    }
    CGRenderer(context: bitmap, maxFilterLayerPixels: 100_000).perform(commands)
    let data = try XCTUnwrap(bitmap.data).assumingMemoryBound(to: UInt8.self)
    return { copy in
      (0..<100).contains { y in (copy * 100..<copy * 100 + 100).contains { x in data[y * bitmap.bytesPerRow + x * 4 + 3] != 0 } }
    }
  }

  func testWideStrokesOfTheDocumentAreAllDrawn() throws {
    let isDrawn = try renderScribbles(asCopies: false)
    XCTAssertTrue((0..<20).allSatisfy(isDrawn))
  }

  func testWideStrokesOfCopiesPastTheBudgetAreNotDrawn() throws {
    // the first is the document's own; each later one is charged its edges and pixels
    let isDrawn = try renderScribbles(asCopies: true)
    XCTAssertTrue((0..<4).allSatisfy(isDrawn))
    XCTAssertFalse((4..<20).contains(where: isDrawn))
  }

  /// Translucent 100 × 100 px squares, each the whole bitmap: `count` of the document's own, or 100 copies as
  /// nested <use>s. The alpha they add up to, with the drawing's budget at 64 × 10 000 (copies may spend half),
  /// drawn into the bitmap or into a PDF page of 100 × 100 points then drawn into it.
  func renderTranslucentSquares(_ fill: String, count: Int? = nil, pdf: Bool = false) throws -> UInt8 {
    let square = ##"<rect width="100" height="100" fill="\##(fill)" fill-opacity="0.01"/>"##
    let body = count.map { String(repeating: square, count: $0) }
      ?? ##"<defs>\##(square.replacingOccurrences(of: "<rect", with: ##"<rect id="r""##))<g id="ten">"## +
        String(repeating: ##"<use href="#r"/>"##, count: 10) + "</g></defs>" + String(repeating: ##"<use href="#ten"/>"##, count: 10)
    let svg = try XCTUnwrap(SVG(xml: """
    <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
    <defs><linearGradient id="g"><stop offset="0" stop-color="black"/><stop offset="1" stop-color="black"/></linearGradient></defs>
    \(body)
    </svg>
    """))
    let bitmap = try XCTUnwrap(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    if pdf {
      let data = NSMutableData()
      var box = CGRect(x: 0, y: 0, width: 100, height: 100)
      let context = try XCTUnwrap(CGContext(consumer: try XCTUnwrap(CGDataConsumer(data: data as CFMutableData)), mediaBox: &box, nil))
      context.beginPDFPage(nil)
      CGRenderer(context: context, maxFilterLayerPixels: 10_000).perform(svg.commands)
      context.endPDFPage()
      context.closePDF()
      bitmap.drawPDFPage(try XCTUnwrap(CGPDFDocument(try XCTUnwrap(CGDataProvider(data: data as CFData)))?.page(at: 1)))
    } else {
      CGRenderer(context: bitmap, maxFilterLayerPixels: 10_000).perform(svg.commands)
    }
    return try XCTUnwrap(bitmap.data).assumingMemoryBound(to: UInt8.self)[50 * bitmap.bytesPerRow + 50 * 4 + 3]
  }

  func testCopiesOfLargeAreasAreChargedTheirPixels() throws {
    // filled at 2.5 ns a pixel, 12 copies are charged after the first, the document's own; gradients
    // (7 ns a pixel) are all charged: 4 copies. The document's own squares are not
    XCTAssertEqual(try renderTranslucentSquares("black"), try renderTranslucentSquares("black", count: 13))
    XCTAssertEqual(try renderTranslucentSquares("url(#g)"), try renderTranslucentSquares("url(#g)", count: 4))
    XCTAssertGreaterThan(try renderTranslucentSquares("black", count: 100), try renderTranslucentSquares("black", count: 99))
    // a PDF holds what its reader draws at a pixel per point
    XCTAssertEqual(try renderTranslucentSquares("black", pdf: true), try renderTranslucentSquares("black", count: 13, pdf: true))
  }

  func testLineWidthIsRestoredWithTheGraphicsState() throws {
    // the optimizer drops a width the restored state holds: what copies' strokes are charged follows CoreGraphics
    let bitmap = try XCTUnwrap(CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let renderer = CGRenderer(context: bitmap)
    renderer.perform([.setLine(width: 2), .pushState, .setLine(width: 9), .popState])
    XCTAssertEqual(renderer.filterLayers.lineWidth, 2)
    renderer.perform([.pushTransparencyLayer, .setLine(width: 9), .popTransparencyLayer])
    XCTAssertEqual(renderer.filterLayers.lineWidth, 2)
  }

  func testImageIsShownAsItsEXIFOrientationSays() throws {
    // 40 × 20, red left and blue right, tagged 6 (turned a quarter clockwise): shown 20 × 40, red on top,
    // as a 20 × 40 image red on top and untagged is
    func jpeg(width: Int, height: Int, red: CGRect, orientation: Int) throws -> String {
      let image = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
      image.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
      image.fill(CGRect(x: 0, y: 0, width: width, height: height))
      image.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
      image.fill(red)
      let data = NSMutableData()
      let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
      CGImageDestinationAddImage(destination, try XCTUnwrap(image.makeImage()),
                                 [kCGImagePropertyOrientation: orientation, kCGImageDestinationLossyCompressionQuality: 1] as CFDictionary)
      XCTAssertTrue(CGImageDestinationFinalize(destination))
      return (data as Data).base64EncodedString()
    }
    let turned = try jpeg(width: 40, height: 20, red: CGRect(x: 0, y: 0, width: 20, height: 20), orientation: 6)
    let upright = try jpeg(width: 20, height: 40, red: CGRect(x: 0, y: 20, width: 20, height: 20), orientation: 1)
    let source = try XCTUnwrap(CGProvider().createImage(from: LayerTree.Image(bitmap: .jpeg(try XCTUnwrap(Data(base64Encoded: turned))))))
    XCTAssertEqual(CGProvider().createSize(from: source), LayerTree.Size(20, 40))

    func draw(_ base64: String) throws -> [UInt8] {
      let svg = try XCTUnwrap(SVG(xml: """
      <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="20" height="40">
      <image width="20" height="40" xlink:href="data:image/jpeg;base64,\(base64)"/>
      </svg>
      """))
      let canvas = try XCTUnwrap(CGContext(data: nil, width: 20, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      canvas.draw(svg)
      let pixels = try XCTUnwrap(canvas.data).assumingMemoryBound(to: UInt8.self)
      return [(10, 5), (10, 35)].map { x, y in pixels[y * canvas.bytesPerRow + x * 4] }
    }
    let reds = try draw(turned)
    XCTAssertEqual(reds, try draw(upright))
    XCTAssertNotEqual(reds[0] > 128, reds[1] > 128)
  }

  func testLargeImageIsDecodedAtTheSizeItIsDrawn() throws {
    // 4000 × 2000 grey pixels drawn 100 × 50 points: 128 pixels wide in a bitmap, at least 300 ppi in a PDF
    let image = try XCTUnwrap(CGContext(data: nil, width: 4_000, height: 2_000, bitsPerComponent: 8, bytesPerRow: 0,
                                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
    image.setFillColor(gray: 0.5, alpha: 1)
    image.fill(CGRect(x: 0, y: 0, width: 4_000, height: 2_000))
    let png = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try XCTUnwrap(image.makeImage()), nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    let source = try XCTUnwrap(CGProvider().createImage(from: LayerTree.Image(bitmap: .png(png as Data))))
    XCTAssertEqual(CGProvider().createSize(from: source), LayerTree.Size(4_000, 2_000))

    let bitmap = try XCTUnwrap(CGContext(data: nil, width: 100, height: 50, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let drawn = CGRect(x: 0, y: 0, width: 100, height: 50)
    XCTAssertEqual(CGRenderer(context: bitmap).makeImage(source, drawnIn: drawn)?.width, 128)
    bitmap.scaleBy(x: 40, y: 40)
    XCTAssertEqual(CGRenderer(context: bitmap).makeImage(source, drawnIn: drawn)?.width, 4_000)

    let pdfData = NSMutableData()
    var box = drawn
    let pdf = try XCTUnwrap(CGContext(consumer: try XCTUnwrap(CGDataConsumer(data: pdfData as CFMutableData)), mediaBox: &box, nil))
    pdf.beginPDFPage(nil)
    XCTAssertEqual(CGRenderer(context: pdf).makeImage(source, drawnIn: drawn)?.width, 512)
    pdf.endPDFPage()
    pdf.closePDF()

    // drawn where it is placed
    let svg = try XCTUnwrap(SVG(xml: """
    <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="100" height="50">
    <image width="100" height="50" xlink:href="data:image/png;base64,\((png as Data).base64EncodedString())"/>
    </svg>
    """))
    let canvas = try XCTUnwrap(CGContext(data: nil, width: 100, height: 50, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    canvas.draw(svg)
    let pixels = try XCTUnwrap(canvas.data).assumingMemoryBound(to: UInt8.self)
    for (x, y) in [(1, 1), (50, 25), (98, 48)] {
      XCTAssertEqual(pixels[y * canvas.bytesPerRow + x * 4 + 3], 255)
      XCTAssertEqual(Int(pixels[y * canvas.bytesPerRow + x * 4]), 128, accuracy: 2)
    }
  }

  func testTextIsLaidOutOncePerStringAndPlace() {
    let generator = LayerTree.CommandGenerator(provider: CGProvider(), size: .init(100, 100), options: .default)
    let attributes = LayerTree.TextAttributes(color: .gray(white: 0, a: 1), font: [.name("Times")], size: 12,
                                              anchor: .start, baseline: .auto)
    let layer = LayerTree.Layer()
    layer.contents = [.text("Hello", .init(0, 10), attributes), .text("Hello", .init(0, 10), attributes)]
    let paths = generator.renderCommands(for: layer, colorConverter: .default).compactMap { command -> CGPath? in
      guard case .fill(let path, _) = command else { return nil }
      return path
    }
    XCTAssertEqual(paths.count, 2)
    XCTAssertTrue(paths[0] === paths[1])
  }
}

final class ImageRenderer {
  
  let renderer: CGRenderer
  private let bitmap: NSBitmapImageRep
  
  init(pixelsWide: Int, pixelsHigh: Int) {
    self.bitmap = NSBitmapImageRep(pixelsWide: pixelsWide,
                                   pixelsHigh: pixelsHigh)
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
    self.renderer = CGRenderer(context: context)
  }
  
  /// `.red` in this file is a test colour; an SVG `red` fill reads back as pure (1, 0, 0)
  func isSVGRed(x: Int, y: Int) -> Bool {
    guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
    return c.redComponent > 0.99 && c.greenComponent < 0.01 && c.blueComponent < 0.01 && c.alphaComponent > 0.99
  }

  func getColor(x: Int, y: Int) -> CGColor? {
    return bitmap.colorAt(x: x, y: y)?.cgColor
  }
}

private extension CGPath {
  
  static func rect(x: CGFloat = 0,
                   y: CGFloat = 0,
                   width: CGFloat = 2,
                   height: CGFloat = 2) -> CGPath {
    
    let rect = CGRect(x: x, y: y, width: width, height: height)
    return CGPath(rect: rect, transform: nil)
  }
}

private extension CGColor {
  
  static var red: CGColor {
    //return CGColor(red: 1.0, green: 0, blue: 0, alpha: 1.0)
    return NSColor(deviceRed: 0.0, green: 0, blue: 1.0, alpha: 1.0).cgColor
  }
}

#endif
