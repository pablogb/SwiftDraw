//
//  Renderer.CoreGraphics.swift
//  SwiftDraw
//
//  Created by Simon Whitty on 4/6/17.
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
//

#if canImport(CoreGraphics)
import Foundation
import CoreText
import Accelerate
import ImageIO
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

import SwiftDrawDOM

struct CGTypes: RendererTypes, Sendable {
    typealias Float = CGFloat
    typealias Point = CGPoint
    typealias Size = CGSize
    typealias Rect = CGRect
    typealias Color = CGColor
    typealias Gradient = CGGradient
    typealias Path = CGPath
    typealias Pattern = CGTransformingPattern
    typealias Transform = CGAffineTransform
    typealias BlendMode = CGBlendMode
    typealias FillRule = CGPathFillRule
    typealias LineCap = CGLineCap
    typealias LineJoin = CGLineJoin
    // decoded when drawn, at the size drawn when it is large
    typealias Image = CGImageSource
}

struct CGTransformingPattern: Hashable {

    var bounds: CGRect
    var contents: [RendererCommand<CGTypes>]
    /// patternTransform: pattern space to the user space of the filled element
    var transform: CGAffineTransform

    init(bounds: CGRect, contents: [RendererCommand<CGTypes>], transform: CGAffineTransform = .identity) {
        self.bounds = bounds
        self.contents = contents
        self.transform = transform
    }

    // the contents are compared, not hashed: fills of one pattern share them, and equal arrays sharing
    // storage compare at once
    func hash(into hasher: inout Hasher) {
        for value in [bounds.minX, bounds.minY, bounds.width, bounds.height,
                      transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty] {
            hasher.combine(value)
        }
        hasher.combine(contents.count)
    }
}

struct CGProvider: RendererTypeProvider {
  
    typealias Types = CGTypes

    func createFloat(from float: LayerTree.Float) -> CGFloat {
        return CGFloat(float)
    }

    func createPoint(from point: LayerTree.Point) -> CGPoint {
        return CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))
    }

    func createSize(from size: LayerTree.Size) -> CGSize {
        return CGSize(width: CGFloat(size.width), height: CGFloat(size.height))
    }

    func createRect(from rect: LayerTree.Rect) -> CGRect {
        return CGRect(x: CGFloat(rect.x),
                      y: CGFloat(rect.y),
                      width: CGFloat(rect.width),
                      height: CGFloat(rect.height))
    }

    func createColor(from color: LayerTree.Color) -> CGColor {
        switch color {
        case .none: return createSRGB(r: 0, g: 0, b: 0, a: 0)
        case let .rgba(r, g, b, a, .srgb):
            return createSRGB(r: CGFloat(r),
                              g: CGFloat(g),
                              b: CGFloat(b),
                              a: CGFloat(a))
        case let .rgba(r, g, b, a, .p3):
            return createP3(r: CGFloat(r),
                            g: CGFloat(g),
                            b: CGFloat(b),
                            a: CGFloat(a))
        case .gray(white: let w, a: let a):
            return createColor(w: CGFloat(w), a: CGFloat(a))
        }
    }

    private func createColorSpace(for colorSpace: LayerTree.ColorSpace) -> CGColorSpace {
        switch colorSpace {
        case .srgb:
            return CGColorSpaceCreateDeviceRGB()
        case .p3:
            return CGColorSpace(name: CGColorSpace.displayP3)!
        }
    }

    func createGradient(from gradient: LayerTree.Gradient) -> CGGradient {
        let colors = gradient.stops.map { createColor(from: $0.color) } as CFArray
        var points = gradient.stops.map { createFloat(from: $0.offset) }

        return CGGradient(colorsSpace: createColorSpace(for: gradient.colorSpace),
                          colors: colors,
                          locations: &points)!
    }

    private func createSRGB(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) -> CGColor {
        return CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                       components: [r, g, b, a])!
    }

    private func createP3(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) -> CGColor {
        return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
                       components: [r, g, b, a])!
    }

    private func createColor(w: CGFloat, a: CGFloat) -> CGColor {
        return CGColor(colorSpace: CGColorSpaceCreateExtendedGray(),
                       components: [w, a])!
    }

    func createBlendMode(from mode: LayerTree.BlendMode) -> CGBlendMode {
        switch mode {
        case .normal: return .normal
        case .copy: return .copy
        case .sourceIn: return .sourceIn
        case .destinationIn: return .destinationIn
        }
    }
    func createTransform(from transform: LayerTree.Transform.Matrix) -> CGAffineTransform {
        return CGAffineTransform(a: CGFloat(transform.a),
                                 b: CGFloat(transform.b),
                                 c: CGFloat(transform.c),
                                 d: CGFloat(transform.d),
                                 tx: CGFloat(transform.tx),
                                 ty: CGFloat(transform.ty))
    }

    func createPath(from shape: LayerTree.Shape) -> CGPath {
        switch shape {
        case .line(let points):
            let path = CGMutablePath()
            path.addLines(between: points.map{ createPoint(from: $0) })
            return path
        case .rect(let frame, let radii):
            return CGPath(roundedRect: createRect(from: frame),
                          cornerWidth: createFloat(from: radii.width),
                          cornerHeight: createFloat(from: radii.height),
                          transform: nil)
        case .ellipse(let frame):
            return CGPath(ellipseIn: createRect(from: frame), transform: nil)
        case .polygon(let points):
            let path = CGMutablePath()
            path.addLines(between: points.map{ createPoint(from: $0) })
            path.closeSubpath()
            return path
        case .path(let path):
            return createPath(from: path)
        }
    }

    private func createPath(from path: LayerTree.Path) -> CGPath {
        let cgPath = CGMutablePath()
        for s in path.segments {
            switch s {
            case .move(let p):
                cgPath.move(to: createPoint(from: p))
            case .line(let p):
                cgPath.addLine(to: createPoint(from: p))
            case .cubic(let p, let cp1, let cp2):
                cgPath.addCurve(to: createPoint(from: p),
                                control1: createPoint(from: cp1),
                                control2: createPoint(from: cp2))
            case .close:
                cgPath.closeSubpath()
            }
        }
        return cgPath
    }

    func createPath(from subPaths: [CGPath]) -> CGPath {
        let cgPath = CGMutablePath()

        for path in subPaths {
            cgPath.addPath(path)
        }

        return cgPath
    }

    func createPath(from text: String, at origin: LayerTree.Point, with attributes: LayerTree.TextAttributes) -> Types.Path? {
        let font = CGProvider.createCTFont(for: attributes.font, size: attributes.size)
        guard let path = text.toPath(font: font) else { return nil }
        var transform = CGAffineTransform(translationX: createFloat(from: origin.x), y: createFloat(from: origin.y))
        return path.copy(using: &transform)
    }

    private static func createCTFont(for font: LayerTree.TextAttributes.Font, size: CGFloat) -> CTFont? {
        switch font {
        case .truetype(let data):
            guard let provider = CGDataProvider(data: data as CFData),
                  let cgFont = CGFont(provider) else { return nil }
            return CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
        case .name(let name):
            let ctFont = CTFontCreateWithName(name as CFString, size, nil)
            let postScriptName = CTFontCopyPostScriptName(ctFont) as String
            if postScriptName.caseInsensitiveCompare(name) == .orderedSame
                || CTFontCopyFamilyName(ctFont) as String == name {
                return ctFont
            }
            return nil
        }
    }

    static func createCTFont(for fonts: [LayerTree.TextAttributes.Font], size: Float) -> CTFont {
        let cgSize = CGFloat(size)
        let fallback = CTFontCreateWithName("Times" as CFString, cgSize, nil)
        let ctFonts = fonts.compactMap { createCTFont(for: $0, size: cgSize) }
        guard let primary = ctFonts.first else { return fallback }
        guard ctFonts.count > 1 else { return primary }
        let descriptors = ctFonts.dropFirst().map { CTFontCopyFontDescriptor($0) }
        let cascade = CTFontDescriptorCreateWithAttributes(
            [kCTFontCascadeListAttribute: descriptors] as CFDictionary
        )
        return CTFontCreateCopyWithAttributes(primary, cgSize, nil, cascade)
    }

    func createPattern(from pattern: LayerTree.Pattern, contents: [RendererCommand<Types>]) -> CGTransformingPattern {
        let bounds = createRect(from: pattern.frame)
        return CGTransformingPattern(bounds: bounds,
                                     contents: contents,
                                     transform: createTransform(from: pattern.transform))
    }

    func createFillRule(from rule: LayerTree.FillRule) -> CGPathFillRule {
        switch rule {
        case .nonzero:
            return .winding
        case .evenodd:
            return .evenOdd
        }
    }

    func createLineCap(from cap: LayerTree.LineCap) -> CGLineCap {
        switch cap {
        case .butt: return .butt
        case .round: return .round
        case .square: return .square
        }
    }

    func createLineJoin(from join: LayerTree.LineJoin) -> CGLineJoin {
        switch join {
        case .bevel: return .bevel
        case .round: return .round
        case .miter: return .miter
        }
    }

    func createImage(from image: LayerTree.Image) -> CGImageSource? {
        let data: Data
        switch image.bitmap {
        case .jpeg(let d), .png(let d):
            data = d
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              source.pixelSize != nil else { return nil }
        return source
    }

    func createSize(from image: CGImageSource) -> LayerTree.Size {
        let size = image.pixelSize ?? (0, 0)
        return LayerTree.Size(LayerTree.Float(size.width), LayerTree.Float(size.height))
    }

    func getBounds(from shape: LayerTree.Shape) -> LayerTree.Rect {
        let bounds = createPath(from: shape).boundingBoxOfPath
        return LayerTree.Rect(x: LayerTree.Float(bounds.origin.x),
                              y: LayerTree.Float(bounds.origin.y),
                              width: LayerTree.Float(bounds.width),
                              height: LayerTree.Float(bounds.height))
    }
}

extension CGImageSource {
    // the first image's, read from its header
    var pixelSize: (width: Int, height: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(self, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        return (width, height)
    }
}

struct CGRenderer: Renderer {
    typealias Types = CGTypes

    private let rootContext: CGContext
    // asked once: CoreGraphics logs an error each time a PDF context is asked for its bits per pixel
    private let rootIsVector: Bool
    private let rootTilesPatterns: Bool
    let filterLayers: CGFilterLayerStack
    let maxFilterLayerPixels: Int

    // drawing goes into the innermost offscreen filter layer, if any
    var ctx: CGContext { filterLayers.context ?? rootContext }

    // PDF and other vector contexts write paths out; bitmaps, offscreens included, rasterise them
    var isVector: Bool { filterLayers.context == nil && rootIsVector }

    // CGPattern matrices map to the context's base space, which CoreGraphics does not expose. PDF contexts and
    // bitmaps made with CoreGraphics, such as offscreen filter layers, have the identity: the CTM holds any
    // flip or placement by the caller. The base AppKit and UIKit set for a view or image is not known (nor
    // what the caller did since): there patterns are drawn through an offscreen bitmap.
    var tilesPatterns: Bool { filterLayers.context == nil && rootTilesPatterns }

    init(context: CGContext, maxFilterLayerPixels: Int = CGRenderer.defaultMaxFilterLayerPixels) {
        self.init(context: context, maxFilterLayerPixels: maxFilterLayerPixels, drawing: nil)
    }

    // pattern cells and masks are drawn by renderers of their own, within the budget of the drawing
    private init(context: CGContext, maxFilterLayerPixels: Int, drawing: CGFilterLayerStack?) {
        self.rootContext = context
        self.rootIsVector = context.bitsPerPixel == 0
        self.rootTilesPatterns = !rootIsVector && context.isCurrentGraphicsContext
        self.filterLayers = CGFilterLayerStack(drawing: drawing, keepsPatterns: rootTilesPatterns)
        self.maxFilterLayerPixels = maxFilterLayerPixels
    }

    func pushState() {
        ctx.saveGState()
        filterLayers.saveState()
    }

    func popState() {
        ctx.restoreGState()
        filterLayers.restoreState()
    }

    // ending a transparency layer restores the graphics state it began with. A copy's layer past the
    // drawing's budget is empty, and so is what the copy draws next
    func pushTransparencyLayer() {
        if filterLayers.copies > 0, !canDrawCopy(covering: ctx.boundingBoxOfClipPath, perPixel: CGRenderer.layerPixelCost) {
            ctx.clip(to: .zero)
        }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        filterLayers.saveState()
    }

    func popTransparencyLayer() {
        ctx.endTransparencyLayer()
        filterLayers.restoreState()
    }

    func concatenate(transform: CGAffineTransform) {
        ctx.concatenate(transform)
    }

    func translate(tx: CGFloat, ty: CGFloat) {
        ctx.translateBy(x: tx, y: ty)
    }

    func rotate(angle: CGFloat) {
        ctx.rotate(by: angle)
    }

    func scale(sx: CGFloat, sy: CGFloat) {
        ctx.scaleBy(x: sx, y: sy)
    }

    func setFill(color: CGColor) {
        if rootTilesPatterns {
            filterLayers.tiledPattern = nil
        }
        ctx.setFillColor(color)
    }

    func setFill(pattern: CGTransformingPattern) {
        guard !tilesPatterns else {
            filterLayers.tiledPattern = pattern
            return
        }
        // the pattern matrix maps to the base space, the identity here
        guard let cgPattern = makePattern(pattern, matrix: pattern.transform.concatenating(ctx.ctm)) else {
            ctx.setFillColor(makeAverageColor(of: pattern))
            return
        }
        var alpha: CGFloat = 1.0
        ctx.setFillColorSpace(CGColorSpace(patternBaseSpace: nil)!)
        ctx.setFillPattern(cgPattern, colorComponents: &alpha)
    }

    // CoreGraphics draws the cell once per CGPattern, in a bitmap into a tile of its device size: shapes filled
    // alike share one, and each new one is charged. Nil past the drawing's budget.
    private func makePattern(_ pattern: CGTransformingPattern, matrix: CGAffineTransform) -> CGPattern? {
        let key: [AnyHashable] = [pattern, matrix.a, matrix.b, matrix.c, matrix.d, matrix.tx, matrix.ty]
        if let cgPattern = filterLayers.patterns[key] {
            return cgPattern
        }
        let tile = isVector ? 0 : abs(matrix.a * matrix.d - matrix.b * matrix.c) * pattern.bounds.width * pattern.bounds.height
        guard spend(cost: Double(pattern.contents.count * CGRenderer.patternCommandCost) + tile) else { return nil }
        let maxPixels = maxFilterLayerPixels
        let drawing = filterLayers
        let cgPattern = CGPattern.make(bounds: pattern.bounds,
                                       matrix: matrix,
                                       step: pattern.bounds.size,
                                       tiling: .constantSpacingMinimalDistortion,
                                       isColored: true,
                                       draw: { CGRenderer(context: $0, maxFilterLayerPixels: maxPixels, drawing: drawing).perform(pattern.contents) })
        filterLayers.patterns[key] = cgPattern
        return cgPattern
    }

    // Where AppKit or UIKit draws, a CGPattern placed in device space fills an offscreen bitmap over what of
    // the path is visible, a band of rows at a time, drawn back pixel for pixel through the path's clip.
    // Past the drawing's budget, the cell's average colour.
    private func fill(path: CGPath, rule: CGPathFillRule, tiling pattern: CGTransformingPattern) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.addPath(path)
        ctx.clip(using: rule)
        let toDevice = ctx.userSpaceToDeviceSpaceTransform
        let visible = ctx.boundingBoxOfClipPath
        guard !visible.isNull, !visible.isEmpty, !visible.isInfinite else { return }
        let device = visible.applying(toDevice).integral
        guard [device.minX, device.minY, device.width, device.height].allSatisfy(\.isFinite),
              device.width >= 1, device.height >= 1 else { return }
        let width = Int(device.width)
        let rows = max(1, min(Int(device.height), CGRenderer.maxPatternBandPixels / width))
        guard let cgPattern = makePattern(pattern, matrix: pattern.transform.concatenating(toDevice)),
              let band = CGContext.makeFilterLayer(width: width, height: rows, colorSpace: ctx.colorSpace) else {
            ctx.setFillColor(makeAverageColor(of: pattern))
            ctx.fill(visible)
            return
        }
        var alpha: CGFloat = 1.0
        band.setFillColorSpace(CGColorSpace(patternBaseSpace: nil)!)
        band.setFillPattern(cgPattern, colorComponents: &alpha)
        ctx.concatenate(toDevice.inverted())
        ctx.interpolationQuality = .none
        let bandRect = CGRect(x: 0, y: 0, width: width, height: rows)
        for y in stride(from: device.minY, to: device.maxY, by: CGFloat(rows)) {
            band.clear(bandRect)
            // the band's pixels are device pixels offset by its origin
            band.setPatternPhase(CGSize(width: -device.minX, height: -y))
            band.fill(bandRect)
            if let image = band.makeImage() {
                ctx.draw(image, in: CGRect(x: device.minX, y: y, width: CGFloat(width), height: CGFloat(rows)))
            }
        }
    }

    // The colour a pattern's cell averages to, drawn at 16 × 16 pixels once per cell contents
    private func makeAverageColor(of pattern: CGTransformingPattern) -> CGColor {
        let key = CGTransformingPattern(bounds: .zero, contents: pattern.contents)
        if let color = filterLayers.root.averageColors[key] {
            return color
        }
        var color = CGColor(gray: 0, alpha: 0)
        let size = 16
        let cell = pattern.bounds
        if cell.width > 0, cell.height > 0,
           let context = CGContext.makeFilterLayer(width: size, height: size, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)),
           let data = context.data {
            context.scaleBy(x: CGFloat(size) / cell.width, y: CGFloat(size) / cell.height)
            context.translateBy(x: -cell.minX, y: -cell.minY)
            CGRenderer(context: context, maxFilterLayerPixels: maxFilterLayerPixels, drawing: filterLayers).perform(pattern.contents)
            let bytes = data.assumingMemoryBound(to: UInt8.self)
            var sum = [CGFloat](repeating: 0, count: 4)
            for row in 0..<size {
                for column in 0..<size {
                    for channel in 0..<4 {
                        sum[channel] += CGFloat(bytes[row * context.bytesPerRow + column * 4 + channel])
                    }
                }
            }
            if sum[3] > 0, let space = context.colorSpace {
                // premultiplied sums: the colour is their ratio to alpha
                color = CGColor(colorSpace: space, components: [sum[0] / sum[3], sum[1] / sum[3], sum[2] / sum[3],
                                                                sum[3] / CGFloat(size * size * 255)]) ?? color
            }
        }
        filterLayers.root.averageColors[key] = color
        return color
    }

    func setStroke(color: CGColor) {
        ctx.setStrokeColor(color)
    }

    func setLine(width: CGFloat) {
        filterLayers.lineWidth = width
        ctx.setLineWidth(width)
    }

    func setLine(cap: CGLineCap) {
        ctx.setLineCap(cap)
    }

    func setLine(join: CGLineJoin) {
        ctx.setLineJoin(join)
    }

    func setLine(miterLimit: CGFloat) {
        ctx.setMiterLimit(miterLimit)
    }

    func setLineDash(phase: CGFloat, lengths: [CGFloat]) {
        ctx.setLineDash(phase: phase, lengths: lengths)
    }

    func setClip(path: CGPath, rule: CGPathFillRule) {
        guard filterLayers.copies == 0 || canDrawCopy(of: path, cost: fillCost(of: path)) else {
            ctx.clip(to: .zero)
            return
        }
        ctx.addPath(path)
        ctx.clip(using: rule)
    }

    func setAlpha(_ alpha: CGFloat) {
        ctx.setAlpha(alpha)
    }

    func setBlend(mode: CGBlendMode) {
        ctx.setBlendMode(mode)
    }

    func stroke(path: CGPath) {
        guard filterLayers.copies == 0 || canDrawCopy(of: path, stroked: true, covering: strokeBounds(of: path),
                                                     perPixel: CGRenderer.fillPixelCost, cost: strokeCost(of: path)) else { return }
        ctx.addPath(path)
        ctx.strokePath()
    }

    func clipStrokeOutline(path: CGPath) {
        ctx.addPath(path)
        ctx.replacePathWithStrokedPath()
        // the outline is made here: its cost is not kept
        if filterLayers.copies > 0, let outline = ctx.path, !spend(outline.rasterCost(transform: ctx.ctm), within: 2) {
            ctx.beginPath()
            ctx.clip(to: .zero)
            return
        }
        ctx.clip()
    }

    func fill(path: CGPath, rule: CGPathFillRule) {
        guard filterLayers.copies == 0 || canDrawCopy(of: path, covering: path.boundingBoxOfPath,
                                                     perPixel: CGRenderer.fillPixelCost, cost: fillCost(of: path)) else { return }
        if tilesPatterns, let pattern = filterLayers.tiledPattern {
            fill(path: path, rule: rule, tiling: pattern)
            return
        }
        ctx.addPath(path)
        ctx.fillPath(using: rule)
    }

    func pushCopy() {
        filterLayers.copies += 1
    }

    func popCopy() {
        filterLayers.copies -= 1
    }

    // A copy multiplies what the document draws. The first draw of a path or image within copies is the
    // document's own; each later one pays for the device pixels it covers within the clip, at `perPixel`
    // nanoseconds, and `cost` more, within half the drawing's budget (building the copies took time already).
    // False, charging nothing, past it. A vector context's device pixels are points: what its reader draws
    // at a pixel per point.
    private func canDrawCopy(of object: AnyObject? = nil, stroked: Bool = false, covering rect: CGRect = .null,
                             perPixel: Double = 0, cost: @autoclosure () -> Int = 0) -> Bool {
        if let object {
            let id = ObjectIdentifier(object)
            if stroked ? filterLayers.stroked.insert(id).inserted : filterLayers.filled.insert(id).inserted {
                return true
            }
        }
        let visible = rect.intersection(ctx.boundingBoxOfClipPath)
        let t = ctx.userSpaceToDeviceSpaceTransform
        let pixels = visible.isNull ? 0 : abs(t.a * t.d - t.b * t.c) * visible.width * visible.height
        return spend(cost: perPixel * Double(pixels) + Double(cost()), within: 2)
    }

    private func fillCost(of path: CGPath) -> Int {
        CGPath.fillCost(of: filterLayers.rasterEdges(of: path, transform: ctx.ctm))
    }

    private func strokeCost(of path: CGPath) -> Int {
        let t = ctx.ctm
        let scale = abs(t.a * t.d - t.b * t.c).squareRoot()
        return CGPath.strokeCost(of: filterLayers.rasterEdges(of: path, transform: t),
                                 width: filterLayers.lineWidth * scale, scale: scale)
    }

    // what a stroke can cover: the path grown by its width on each side, for miters and square caps
    private func strokeBounds(of path: CGPath) -> CGRect {
        let width = filterLayers.lineWidth
        return path.boundingBoxOfPath.insetBy(dx: -width, dy: -width)
    }

    func draw(image: CGImageSource, in rect: CGRect) {
      guard filterLayers.copies == 0 || canDrawCopy(of: image, covering: rect, perPixel: CGRenderer.imagePixelCost),
            let decoded = makeImage(image, drawnIn: rect) else { return }
      pushState()
      translate(tx: rect.minX, ty: rect.maxY)
      scale(sx: 1, sy: -1)
      pushState()
      ctx.draw(decoded, in: CGRect(origin: .zero, size: rect.size))
      popState()
      popState()
    }

    // ImageIO keeps what it decodes in the source. An image with more pixels than a floor and four times what
    // the device has where it is drawn (300 ppi in vector contexts) is decoded at that size, rounded up to a
    // power of two so that nearby sizes share it: a large image costs what it draws, not what it holds.
    func makeImage(_ source: CGImageSource, drawnIn rect: CGRect) -> CGImage? {
        guard let (width, height) = source.pixelSize else { return nil }
        let device = rect.applying(ctx.userSpaceToDeviceSpaceTransform)
        let scale = isVector ? CGRenderer.vectorOversample : 1
        let side = max(device.width, device.height) * scale
        let needed = Double(device.width * device.height * scale * scale)
        guard side.isFinite else { return nil }
        guard Double(width) * Double(height) > max(Double(CGRenderer.minDecodedPixels), 4 * needed) else {
            return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary)
        }
        let maxSide = 1 << Int(log2(max(1, Double(side))).rounded(.up))
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                               kCGImageSourceThumbnailMaxPixelSize: maxSide,
                                                               kCGImageSourceShouldCache: true,
                                                               kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    func draw(linear gradient: CGGradient, from start: CGPoint, to end: CGPoint) {
        guard filterLayers.copies == 0 || canDrawCopy(covering: ctx.boundingBoxOfClipPath, perPixel: CGRenderer.gradientPixelCost) else { return }
        ctx.drawLinearGradient(gradient,
                               start: start,
                               end: end,
                               options: [.drawsAfterEndLocation, .drawsBeforeStartLocation]
        )
    }

    func draw(radial gradient: CGGradient, startCenter: CGPoint, startRadius: CGFloat, endCenter: CGPoint, endRadius: CGFloat) {
        guard filterLayers.copies == 0 || canDrawCopy(covering: ctx.boundingBoxOfClipPath, perPixel: CGRenderer.gradientPixelCost) else { return }
        ctx.drawRadialGradient(gradient,
                               startCenter: startCenter,
                               startRadius: startRadius,
                               endCenter: endCenter,
                               endRadius: endRadius,
                               options: [.drawsAfterEndLocation, .drawsBeforeStartLocation]
        )
    }

    // The following commands are drawn into a bitmap covering the filter region in device pixels,
    // intersected with the visible clip grown by how far the filter moves pixels (blur extent, offsets).
    // The result is composited back clipped to the region. Over maxFilterLayerPixels the bitmap is rendered
    // at a reduced scale (deviations and offsets scaled to match) and drawn back up, so large exports stay
    // filtered without unbounded allocations. SD2's blur chains are blurred in place; other filters evaluate
    // their primitive tree (SD12), which keeps several bitmaps alive: the budget is shared between them.
    func pushFilterLayer(_ filter: LayerTree.FilterLayer) {
        let parent = ctx
        let region = CGRect(x: CGFloat(filter.region.x),
                            y: CGFloat(filter.region.y),
                            width: CGFloat(filter.region.width),
                            height: CGFloat(filter.region.height))
        let toDevice = parent.userSpaceToDeviceSpaceTransform
        let isBlurChain = filter.isBlurChain
        let deviations = isBlurChain ? filter.effects.compactMap { $0.deviceStdDeviation(toDevice) } : []
        let visible = parent.boundingBoxOfClipPath

        parent.saveGState()
        // the offscreen starts from a fresh graphics state, as the command optimizer expects
        filterLayers.saveState()
        filterLayers.resetState()
        parent.clip(to: region)

        // empty clip: draw nothing and allocate nothing
        guard !visible.isNull, !visible.isEmpty else {
            parent.clip(to: .zero)
            filterLayers.entries.append(CGFilterLayer())
            return
        }

        // blurs too small to change a pixel (every box size 1) are a pass-through:
        // draw straight into the parent, clipped to the region
        let oversample = isVector ? CGRenderer.vectorOversample : 1
        if isBlurChain && !deviations.contains(where: { CGContext.isVisibleBlur($0, scale: oversample) }) {
            filterLayers.entries.append(CGFilterLayer())
            return
        }

        var deviceRect = region.applying(toDevice)
        if !visible.isInfinite {
            let spread = filter.deviceSpread(toDevice)
            deviceRect = deviceRect.intersection(visible.applying(toDevice).insetBy(dx: -spread.width, dy: -spread.height))
        }

        // the offscreen itself, plus the bitmaps of the primitive tree, within what the offscreens alive
        // and the drawing so far leave: too little left draws the layer unfiltered
        let bitmaps = isBlurChain ? 1 : filter.peakBitmapCount + 1
        let maxPixels = makeMaxPixels(passes: filter.passes) / bitmaps
        guard isAffordable(deviceRect, oversample: oversample, maxPixels: maxPixels) else {
            filterLayers.entries.append(CGFilterLayer())
            return
        }

        // PDF and other vector contexts: filtered groups are rasterized at 300 ppi
        guard var layer = CGFilterLayer.make(deviceRect: deviceRect,
                                             deviations: deviations,
                                             maxPixels: maxPixels,
                                             oversample: oversample,
                                             colorSpace: parent.colorSpace) else {
            // empty clip or region: draw nothing and allocate nothing
            parent.clip(to: .zero)
            filterLayers.entries.append(CGFilterLayer())
            return
        }
        filterLayers.spend(layer.pixels * filter.passes)
        if !isBlurChain {
            layer.filter = filter
            layer.toDevice = toDevice
        }

        layer.offscreen?.concatenate(toDevice)
        // input outside the region is excluded (it matters under rotation or skew); the edge is anti-aliased
        // once, by the parent clip at composite time
        layer.offscreen?.setShouldAntialias(false)
        layer.offscreen?.clip(to: region)
        layer.offscreen?.setShouldAntialias(true)
        filterLayers.entries.append(layer)
    }

    func popFilterLayer() {
        guard let layer = filterLayers.entries.popLast() else { return }
        let parent = ctx

        if let offscreen = layer.offscreen {
            if let filter = layer.filter {
                offscreen.applyFilter(filter, toPixels: layer.pixelTransform, spend: { spend($0) })
            } else {
                for deviation in layer.deviations {
                    offscreen.applyGaussianBlur(CGSize(width: deviation.width * layer.scale,
                                                       height: deviation.height * layer.scale))
                }
            }
            if let image = offscreen.makeImage() {
                let size = CGSize(width: CGFloat(image.width) / layer.scale,
                                  height: CGFloat(image.height) / layer.scale)
                parent.saveGState()
                parent.concatenate(parent.userSpaceToDeviceSpaceTransform.inverted())
                if layer.scale == 1 {
                    parent.interpolationQuality = .none
                }
                parent.draw(image, in: CGRect(origin: layer.deviceRect.origin, size: size))
                parent.restoreGState()
            }
        }

        // removes the region clip set by pushFilterLayer
        parent.restoreGState()
        filterLayers.restoreState()
    }

    // PDF and other vector contexts cannot express masks: the contents stay vector, clipped to the
    // mask drawn as an image at 300 ppi where they draw. Through a soft mask they are composited as one
    // group, so shapes do not show through those above them; a mask of whole pixels (and edges) applies
    // to each shape alike, and keeps them out of a group, which CoreGraphics' PDF reader composites in
    // Generic RGB (shifting saturated sRGB colours). Bitmaps draw the contents into a transparency layer
    // covering what they draw.
    func pushMask(_ mask: [RendererCommand<CGTypes>], bounds: CGRect?) {
        let parent = ctx
        let toDevice = parent.userSpaceToDeviceSpaceTransform
        guard isVector else {
            // whole device pixels around the contents: their edges are not antialiased twice
            if let bounds, !bounds.isNull, !bounds.isInfinite {
                parent.concatenate(toDevice.inverted())
                parent.clip(to: bounds.applying(toDevice).insetBy(dx: -1, dy: -1).integral)
                parent.concatenate(toDevice)
            }
            pushTransparencyLayer()
            return
        }
        parent.saveGState()
        filterLayers.saveState()
        var isSoft = false
        defer {
            filterLayers.maskGroups.append(isSoft)
            if isSoft {
                parent.beginTransparencyLayer(auxiliaryInfo: nil)
            }
        }
        let visible = bounds.map { parent.boundingBoxOfClipPath.intersection($0) } ?? parent.boundingBoxOfClipPath
        guard !visible.isNull, !visible.isEmpty else { return }
        // an unknown extent, or too little left of the budget: drawn unmasked
        guard !visible.isInfinite,
              let (image, rect, soft) = makeMaskImage(mask, toDevice: toDevice, deviceRect: visible.applying(toDevice)) else { return }
        guard let image else {
            parent.clip(to: .zero)
            return
        }
        parent.concatenate(toDevice.inverted())
        parent.clip(to: rect, mask: image)
        parent.concatenate(toDevice)
        isSoft = soft
    }

    func popMask(_ composite: [RendererCommand<CGTypes>]) {
        guard isVector else {
            perform(composite)
            popTransparencyLayer()
            return
        }
        if filterLayers.maskGroups.popLast() == true {
            ctx.endTransparencyLayer()
        }
        ctx.restoreGState()
        filterLayers.restoreState()
    }

    // The alpha the mask draws, as a DeviceGray image (clip(to:mask:) takes its gray as alpha), its rect
    // in device space, and whether it is soft: more pixels between 0 and 1 than two outlines of the image.
    // A coarse pass finds where it draws, so a small mask on a large page stays small. nil when the budget
    // cannot afford it; a nil image when the mask draws nothing.
    private func makeMaskImage(_ mask: [RendererCommand<CGTypes>], toDevice: CGAffineTransform,
                               deviceRect: CGRect) -> (image: CGImage?, rect: CGRect, isSoft: Bool)? {
        let probe = min(CGRenderer.maskProbePixels, makeMaxPixels(passes: 1))
        guard probe > 0,
              let coarse = drawMask(mask, toDevice: toDevice, deviceRect: deviceRect,
                                    maxPixels: probe, oversample: CGRenderer.vectorOversample) else { return nil }
        filterLayers.spend(coarse.context.width * coarse.context.height)
        guard let drawn = coarse.drawnRect else { return (nil, .zero, false) }
        let rect = drawn.intersection(deviceRect)
        let maxPixels = makeMaxPixels(passes: 1)
        guard isAffordable(rect, oversample: CGRenderer.vectorOversample, maxPixels: maxPixels),
              let fine = drawMask(mask, toDevice: toDevice, deviceRect: rect,
                                  maxPixels: maxPixels, oversample: CGRenderer.vectorOversample) else { return nil }
        filterLayers.spend(fine.context.width * fine.context.height)
        guard let data = fine.context.data,
              let provider = CGDataProvider(data: Data(bytes: data, count: fine.context.bytesPerRow * fine.context.height) as CFData) else { return nil }
        let image = CGImage(width: fine.context.width, height: fine.context.height,
                            bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: fine.context.bytesPerRow,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        var partial = 0
        for row in 0..<fine.context.height {
            let line = bytes + row * fine.context.bytesPerRow
            for column in 0..<fine.context.width where line[column] != 0 && line[column] != 255 {
                partial += 1
            }
        }
        return (image, fine.rect, partial > 4 * (fine.context.width + fine.context.height))
    }

    // the mask drawn into an alpha-only bitmap covering deviceRect
    private func drawMask(_ mask: [RendererCommand<CGTypes>], toDevice: CGAffineTransform, deviceRect: CGRect,
                          maxPixels: Int, oversample: CGFloat) -> (context: CGContext, rect: CGRect, drawnRect: CGRect?)? {
        guard !deviceRect.isNull, !deviceRect.isInfinite,
              [deviceRect.minX, deviceRect.minY, deviceRect.width, deviceRect.height].allSatisfy(\.isFinite) else { return nil }
        let rect = deviceRect.integral
        guard rect.width >= 1, rect.height >= 1, rect.width.isFinite, rect.height.isFinite else { return nil }
        let scale = CGFilterLayer.makeScale(size: rect.size, maxPixels: maxPixels, oversample: oversample)
        let width = max(1, Int((rect.width * scale).rounded(.up)))
        let height = max(1, Int((rect.height * scale).rounded(.up)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
              let data = context.data else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -rect.minX, y: -rect.minY)
        context.concatenate(toDevice)
        // as in a transparency layer composited destination-in: the last mask drawn over a pixel wins
        context.setBlendMode(.copy)
        CGRenderer(context: context, maxFilterLayerPixels: maxFilterLayerPixels, drawing: filterLayers).perform(mask)

        // the drawn pixels, one pixel wider on each side for what antialiasing left below one level
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for row in 0..<height {
            let line = bytes + row * context.bytesPerRow
            for column in 0..<width where line[column] != 0 {
                minX = min(minX, column)
                maxX = max(maxX, column)
                minY = min(minY, row)
                maxY = max(maxY, row)
            }
        }
        let size = CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale)
        guard maxX >= 0 else { return (context, CGRect(origin: rect.origin, size: size), nil) }
        // rows run from the top of the rect down
        let drawn = CGRect(x: rect.minX + CGFloat(minX - 1) / scale,
                           y: rect.minY + CGFloat(height - maxY - 2) / scale,
                           width: CGFloat(maxX - minX + 3) / scale,
                           height: CGFloat(maxY - minY + 3) / scale)
        return (context, CGRect(origin: rect.origin, size: size), drawn)
    }

    // Pixels a bitmap of `passes` passes may have: what the offscreens alive and the drawing's rasterising
    // so far leave
    private func makeMaxPixels(passes: Int) -> Int {
        min(maxFilterLayerPixels - filterLayers.livePixels,
            (maxFilterLayerPixels * CGRenderer.drawBudgetLayers - filterLayers.spentPasses) / max(1, passes))
    }

    // Charges `cost` to the drawing's budget; false, charging nothing, when what is left of the first
    // 1 / `share` of it cannot pay it
    private func spend(_ cost: Int, within share: Int = 1) -> Bool {
        guard cost > 0 else { return true }
        guard cost <= maxFilterLayerPixels * CGRenderer.drawBudgetLayers / share - filterLayers.spentPasses else { return false }
        filterLayers.spend(cost)
        return true
    }

    private func spend(cost: Double, within share: Int = 1) -> Bool {
        cost.isFinite && cost < Double(Int.max / 2) && spend(Int(cost), within: share)
    }

    // Whether a bitmap within maxPixels is worth drawing: all of the rect, or at least a floor of pixels
    private func isAffordable(_ deviceRect: CGRect, oversample: CGFloat, maxPixels: Int) -> Bool {
        let needed = deviceRect.width * deviceRect.height * oversample * oversample
        let floor = CGFloat(maxFilterLayerPixels / CGRenderer.minFilterLayerFraction)
        return maxPixels > 0 && CGFloat(maxPixels) >= min(needed.isNaN ? floor : needed, floor)
    }

    static let defaultMaxFilterLayerPixels = 16_777_216
    // A drawing's budget for what it multiplies, in units of about a nanosecond: this many passes over a
    // full-budget layer, about 1 s. A pass over a pixel (drawing it, a box blur, a flood) costs 0.3–1 ns; filter
    // primitives also pay for the pixels they work out one by one, pattern cells for their commands, and copies
    // for their pixels and paths. The document's own shapes, text and images are not charged.
    static let drawBudgetLayers = 64
    // below this fraction of the budget a layer that needs more is not rasterised
    static let minFilterLayerFraction = 256
    static let maxDeviceSpread: CGFloat = 100_000
    static let vectorOversample: CGFloat = 300.0 / 72
    static let maskProbePixels = 65_536
    // a pattern cell's command, drawn or written out: measured at 0.3 µs in bitmaps and 0.4 µs in PDF
    static let patternCommandCost = 400
    // the most pixels of a band an offscreen pattern fill draws at once
    static let maxPatternBandPixels = 1 << 22
    // images up to this many pixels are decoded whole (16 MB at 4 bytes a pixel)
    static let minDecodedPixels = 1 << 22
    // nanoseconds per device pixel a copy pays, measured on a 1600 × 1200 bitmap: a translucent fill or
    // stroke 2.3, a gradient 5–7, a transformed image 6, a transparency layer 7
    static let fillPixelCost = 2.5
    static let gradientPixelCost = 7.0
    static let imagePixelCost = 6.0
    static let layerPixelCost = 7.0
}

final class CGFilterLayerStack {
    var entries = [CGFilterLayer]() {
        didSet { context = entries.last(where: { $0.offscreen != nil })?.offscreen }
    }
    // the innermost offscreen, kept as entries change: every command draws into it
    private(set) var context: CGContext?
    // the drawing a pattern cell or mask is drawn for: its offscreens stay alive and its budget is shared
    let drawing: CGFilterLayerStack?
    private var spent = 0
    // the patterns made in this context, by pattern and matrix
    var patterns = [[AnyHashable]: CGPattern]()
    // for each PDF mask pushed, whether its contents are drawn as one group
    var maskGroups = [Bool]()
    // what each pattern cell's contents average to, for the whole drawing
    var averageColors = [CGTransformingPattern: CGColor]()

    // What the renderer keeps beside CoreGraphics' graphics state, saved and restored with it: the command
    // optimizer drops a setting the restored state already holds. The pattern following fills draw offscreen,
    // where CGPatterns would be misplaced, is only kept where AppKit or UIKit draws.
    var lineWidth: CGFloat = 1
    var tiledPattern: CGTransformingPattern?
    private var savedWidths = [CGFloat]()
    private var savedPatterns = [CGTransformingPattern?]()
    private let keepsPatterns: Bool
    // how many copies the commands drawn are within, and the paths and images drawn in them so far
    var copies = 0
    var filled = Set<ObjectIdentifier>()
    var stroked = Set<ObjectIdentifier>()

    func saveState() {
        savedWidths.append(lineWidth)
        if keepsPatterns {
            savedPatterns.append(tiledPattern)
        }
    }

    func restoreState() {
        lineWidth = savedWidths.popLast() ?? 1
        if keepsPatterns {
            tiledPattern = savedPatterns.popLast() ?? nil
        }
    }

    func resetState() {
        lineWidth = 1
        tiledPattern = nil
    }

    var root: CGFilterLayerStack {
        drawing?.root ?? self
    }

    init(drawing: CGFilterLayerStack? = nil, keepsPatterns: Bool = false) {
        self.drawing = drawing
        self.keepsPatterns = keepsPatterns
    }

    var livePixels: Int {
        entries.reduce(drawing?.livePixels ?? 0) { $0 + $1.pixels }
    }

    // passes over pixels rasterised so far in the drawing: filter layers and masks
    var spentPasses: Int {
        drawing?.spentPasses ?? spent
    }

    func spend(_ passes: Int) {
        if let drawing {
            drawing.spend(passes)
        } else {
            spent += passes
        }
    }

    // the edges of each path drawn, under the last linear transform it was drawn with; the path is kept so
    // its identity is not reused
    private var rasterEdges = [ObjectIdentifier: (path: CGPath, transform: CGAffineTransform, edges: CGPath.RasterEdges)]()

    func rasterEdges(of path: CGPath, transform t: CGAffineTransform) -> CGPath.RasterEdges {
        if let drawing {
            return drawing.rasterEdges(of: path, transform: t)
        }
        let linear = CGAffineTransform(a: t.a, b: t.b, c: t.c, d: t.d, tx: 0, ty: 0)
        if let cached = rasterEdges[ObjectIdentifier(path)], cached.transform == linear {
            return cached.edges
        }
        let edges = path.rasterEdges(transform: linear)
        rasterEdges[ObjectIdentifier(path)] = (path, linear, edges)
        return edges
    }
}

struct CGFilterLayer {
    // nil when contents are drawn directly into the parent context
    var offscreen: CGContext?
    var deviceRect: CGRect = .zero
    var deviations: [CGSize] = []
    // offscreen pixels per device pixel
    var scale: CGFloat = 1
    // a primitive tree to evaluate when popped, with the user space it was resolved in (SD12);
    // nil for blur chains, blurred in place by deviations
    var filter: LayerTree.FilterLayer?
    var toDevice: CGAffineTransform = .identity

    var pixels: Int {
        offscreen.map { $0.width * $0.height } ?? 0
    }

    // user space to offscreen pixels: x right, y down from the first row in memory
    var pixelTransform: CGAffineTransform {
        let height = CGFloat(offscreen?.height ?? 0)
        return toDevice
            .concatenating(CGAffineTransform(translationX: -deviceRect.minX, y: -deviceRect.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height))
    }

    // nil when the device rect is empty or not finite
    static func make(deviceRect: CGRect,
                     deviations: [CGSize],
                     maxPixels: Int,
                     oversample: CGFloat,
                     colorSpace: CGColorSpace?) -> CGFilterLayer? {
        guard !deviceRect.isNull, !deviceRect.isInfinite,
              deviceRect.minX.isFinite, deviceRect.minY.isFinite,
              deviceRect.width.isFinite, deviceRect.height.isFinite else { return nil }
        let rect = deviceRect.integral
        // integral can overflow a finite rect to an infinite width
        guard rect.width >= 1, rect.height >= 1, rect.width.isFinite, rect.height.isFinite else { return nil }

        let scale = makeScale(size: rect.size, maxPixels: maxPixels, oversample: oversample)
        let width = max(1, Int((rect.width * scale).rounded(.up)))
        let height = max(1, Int((rect.height * scale).rounded(.up)))
        guard let offscreen = CGContext.makeFilterLayer(width: width, height: height, colorSpace: colorSpace) else {
            return nil
        }

        offscreen.scaleBy(x: scale, y: scale)
        offscreen.translateBy(x: -rect.minX, y: -rect.minY)
        return CGFilterLayer(offscreen: offscreen, deviceRect: rect, deviations: deviations, scale: scale)
    }

    // largest scale ≤ oversample that keeps the bitmap within maxPixels and each side within maxSide
    static func makeScale(size: CGSize, maxPixels: Int, oversample: CGFloat) -> CGFloat {
        let maxSide = CGFloat(maxPixels).squareRoot() * 4
        let pixels = size.width * size.height
        var scale = oversample
        scale = min(scale, (CGFloat(maxPixels) / pixels).squareRoot())
        scale = min(scale, maxSide / size.width, maxSide / size.height)
        return scale
    }
}

private extension LayerTree.FilterLayer.Effect {

    // stdDeviation converted to device pixels along the device axes; nil when it does not blur.
    // Exact for scale and 90° rotations, an approximation under skew or other rotations.
    func deviceStdDeviation(_ toDevice: CGAffineTransform) -> CGSize? {
        guard case let .gaussianBlur(stdDeviation: x, stdDeviationY: y) = self else { return nil }
        let sx = CGFloat(x)
        let sy = CGFloat(y)
        let width = hypot(sx * toDevice.a, sy * toDevice.c)
        let height = hypot(sx * toDevice.b, sy * toDevice.d)
        let size = CGSize(width: width.isFinite ? width : 0, height: height.isFinite ? height : 0)
        return size.width > 0 || size.height > 0 ? size : nil
    }
}

private extension LayerTree.FilterLayer {

    // passes over the offscreen per draw: drawing it, three box blurs per blur, one per other
    // primitive and per merged input
    var passes: Int {
        primitives.reduce(1) { total, primitive in
            switch primitive.effect {
            case .gaussianBlur:
                return total + 3
            case .merge:
                return total + max(1, primitive.inputs.count)
            case .offset, .flood, .composite, .blend, .colorMatrix:
                return total + 1
            }
        }
    }

    // How far the filter can move a pixel, in device pixels: three deviations per blur plus each offset.
    // Every path through the primitive tree is covered by the sum over all primitives.
    func deviceSpread(_ toDevice: CGAffineTransform) -> CGSize {
        var width: CGFloat = 0
        var height: CGFloat = 0
        for effect in effects {
            switch effect {
            case .gaussianBlur:
                if let deviation = effect.deviceStdDeviation(toDevice) {
                    width += 3 * deviation.width
                    height += 3 * deviation.height
                }
            case let .offset(dx: dx, dy: dy):
                let vector = CGSize(width: CGFloat(dx), height: CGFloat(dy)).applying(toDevice)
                width += abs(vector.width)
                height += abs(vector.height)
            case .flood, .composite, .merge, .blend, .colorMatrix:
                break
            }
        }
        return CGSize(width: width.isFinite ? min(width, CGRenderer.maxDeviceSpread) : CGRenderer.maxDeviceSpread,
                      height: height.isFinite ? min(height, CGRenderer.maxDeviceSpread) : CGRenderer.maxDeviceSpread)
    }
}

private extension CGContext {
    // the context AppKit or UIKit is drawing a view or image into
    var isCurrentGraphicsContext: Bool {
#if canImport(UIKit)
        UIGraphicsGetCurrentContext() === self
#elseif canImport(AppKit)
        NSGraphicsContext.current?.cgContext === self
#else
        false
#endif
    }
}

extension CGContext {

    static func makeFilterLayer(width: Int, height: Int, colorSpace: CGColorSpace?) -> CGContext? {
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let space = colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? sRGB
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info) ??
               CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB, bitmapInfo: info)
    }

    // Filter Effects 1 §9.16 / SVG 1.1 §15.17: three successive box blurs approximate the gaussian.
    // Box sizes must be odd for vImage, so an even size d becomes d+1, d-1, d+1 (near-identical variance).
    func applyGaussianBlur(_ deviation: CGSize) {
        guard let data else { return }
        Self.applyGaussianBlur(deviation, data: data, width: width, height: height, bytesPerRow: bytesPerRow)
    }

    static func applyGaussianBlur(_ deviation: CGSize, data: UnsafeMutableRawPointer, width: Int, height: Int, bytesPerRow: Int) {
        // a box wider than the image only spreads it further towards transparent: clamp per axis
        let sizesX = Self.boxSizes(for: deviation.width, limit: width | 1)
        let sizesY = Self.boxSizes(for: deviation.height, limit: height | 1)
        guard sizesX.contains(where: { $0 > 1 }) || sizesY.contains(where: { $0 > 1 }) else { return }

        let byteCount = bytesPerRow * height
        guard let temp = calloc(byteCount, 1) else { return }
        defer { free(temp) }

        var src = vImage_Buffer(data: data, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow)
        var dst = vImage_Buffer(data: temp, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow)
        var background: [UInt8] = [0, 0, 0, 0]
        for pass in 0..<3 {
            let error = vImageBoxConvolve_ARGB8888(&src, &dst, nil, 0, 0,
                                                   UInt32(sizesY[pass]), UInt32(sizesX[pass]),
                                                   &background, vImage_Flags(kvImageBackgroundColorFill))
            guard error == kvImageNoError else { return }
            swap(&src, &dst)
        }
        // after three passes the result is in the temporary buffer
        memcpy(data, src.data, byteCount)
    }

    // SD12: evaluates the primitive tree on the offscreen's pixels, SourceGraphic being what was drawn,
    // and leaves the result in their place; leaves them unfiltered when `spend` refuses a primitive's cost.
    func applyFilter(_ filter: LayerTree.FilterLayer, toPixels transform: CGAffineTransform,
                     spend: @escaping (Int) -> Bool = { _ in true }) {
        let width = self.width
        let height = self.height
        let bytesPerRow = self.bytesPerRow
        let colorSpace = self.colorSpace
        guard let data = self.data, width > 0, height > 0 else { return }
        let rowBytes = width * 4

        var pixels = [UInt8](repeating: 0, count: rowBytes * height)
        pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            for row in 0..<height {
                memcpy(base + row * rowBytes, data + row * bytesPerRow, rowBytes)
            }
        }

        let environment = LayerTree.FilterLayer.Environment(
            transform: LayerTree.Transform.Matrix(a: Float(transform.a), b: Float(transform.b),
                                                  c: Float(transform.c), d: Float(transform.d),
                                                  tx: Float(transform.tx), ty: Float(transform.ty)),
            blur: { bitmap, x, y in
                let w = bitmap.width
                let h = bitmap.height
                bitmap.pixels.withUnsafeMutableBytes { buffer in
                    guard let base = buffer.baseAddress else { return }
                    CGContext.applyGaussianBlur(CGSize(width: CGFloat(x), height: CGFloat(y)),
                                                data: base, width: w, height: h, bytesPerRow: w * 4)
                }
            },
            color: { CGContext.filterComponents(of: $0, colorSpace: colorSpace) },
            spend: spend
        )
        let result = filter.evaluate(source: FilterBitmap(width: width, height: height, pixels: pixels),
                                     environment: environment)

        result.pixels.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            for row in 0..<height {
                memcpy(data + row * bytesPerRow, base + row * rowBytes, rowBytes)
            }
        }
    }

    // The straight RGBA a fill of this colour leaves in a filter layer of the colour space:
    // floods are colour matched exactly like the shapes they are composited with.
    static func filterComponents(of color: LayerTree.Color, colorSpace: CGColorSpace?) -> SIMD4<Float> {
        guard let ctx = CGContext.makeFilterLayer(width: 1, height: 1, colorSpace: colorSpace),
              let data = ctx.data else {
            return FilterBitmap.components(of: color)
        }
        ctx.setFillColor(CGProvider().createColor(from: color))
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let pixel = data.assumingMemoryBound(to: UInt8.self)
        let alpha = Float(pixel[3])
        guard alpha > 0 else { return .zero }
        return SIMD4(Float(pixel[0]) / alpha, Float(pixel[1]) / alpha, Float(pixel[2]) / alpha, alpha / 255)
    }

    static func isVisibleBlur(_ deviation: CGSize, scale: CGFloat) -> Bool {
        boxSizes(for: deviation.width * scale) != [1, 1, 1] || boxSizes(for: deviation.height * scale) != [1, 1, 1]
    }

    // limit is odd: the largest box size worth applying
    static func boxSizes(for deviation: CGFloat, limit: Int = .max) -> [Int] {
        guard deviation.isFinite, deviation > 0 else { return [1, 1, 1] }
        let factor: CGFloat = 3 * (2 * CGFloat.pi).squareRoot() / 4
        let value = Swift.min(deviation * factor + 0.5, CGFloat(Swift.min(limit, 1 << 24)))
        let d = Int(value.rounded(.down))
        guard d > 1 else { return [1, 1, 1] }
        return d % 2 == 1 ? [d, d, d] : [d + 1, d - 1, d + 1]
    }
}

#endif
