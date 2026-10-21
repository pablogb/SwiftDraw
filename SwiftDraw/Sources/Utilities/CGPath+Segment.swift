//
//  CGPath+Segment.swift
//  SwiftDraw
//
//  Created by Simon Whitty on 10/3/17.
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

#if canImport(CoreGraphics)
import CoreText
import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

extension CGPath {
    func doApply(action: @escaping (CGPathElement)->()) {
        var action = action
        withUnsafeMutablePointer(to: &action) { action in
            apply(info: action) {
                let action = $0!.bindMemory(to: ((CGPathElement)->()).self, capacity: 1).pointee
                action($1.pointee)
            }
        }
    }
}

extension CGPath {
    enum Segment: Equatable {
        case move(CGPoint)
        case line(CGPoint)
        case quad(CGPoint, CGPoint)
        case cubic(CGPoint, CGPoint, CGPoint)
        case close
    }

    func segments() -> [Segment] {
        var segments = [Segment]()
        self.doApply {
            let p = $0
            switch (p.type) {
            case .moveToPoint:
                segments.append(Segment.move(p.points[0]))
            case .addLineToPoint:
                segments.append(Segment.line(p.points[0]))
            case .addQuadCurveToPoint:
                segments.append(Segment.quad(p.points[0], p.points[1]))
            case .addCurveToPoint:
                segments.append(Segment.cubic(p.points[0], p.points[1], p.points[2]))
            case .closeSubpath:
                segments.append(Segment.close)
            @unknown default:
                ()
            }
        }
        return segments
    }
}

extension CGPath {

    func makePath() -> LayerTree.Path {
        let s = segments()
        return LayerTree.Path(
            s.map(Self.makeSegment)
        )
    }

    static func makeSegment(for segment: Segment) -> LayerTree.Path.Segment {
        switch segment {
        case .move(let point):
            return .move(to: .init(point))
        case .line(let point):
            return .line(to: .init(point))
        case .cubic(let control1, let control2, let point):
            return .cubic(to: .init(point), control1: .init(control1), control2: .init(control2))
        case .close:
            return .close
        case .quad(let control1, let point):
            return .cubic(to: .init(point), control1: .init(control1), control2: .init(control1))
        }
    }
}

private extension LayerTree.Point {
    init(_ p: CGPoint) {
        self.init(LayerTree.Float(p.x),
                  LayerTree.Float((p.y)))
    }
}

extension CGPath {

    /// About what CoreGraphics' antialiasing rasteriser spends filling or clipping to this path under the
    /// linear part of `transform`, in nanoseconds. It keeps the edges crossing the scanline sorted, and
    /// inserting an edge or swapping two that cross walks that list: measured at 4–8 ns per edge in the list,
    /// so a 30 KB scribble (edges crossing each other) takes 13 s and 1000 glyphs in a pixel row 2 s, where a
    /// page of text takes 0.15 s.
    func rasterCost(transform: CGAffineTransform) -> Int {
        Self.fillCost(of: rasterEdges(transform: transform))
    }

    static func fillCost(of edges: RasterEdges) -> Int {
        nanoseconds(8 * (edges.inserts + edges.crossings * edges.inserts / Double(max(1, edges.count))))
    }

    /// About what stroking this path `width` device pixels wide costs, in nanoseconds; `scale` is the
    /// transform's. Up to about 1.5 px a stroke costs 0.5–2.5 ns per edge in the list as each is inserted,
    /// growing with its length in pixels; wider, CoreGraphics strokes each edge on its own: measured at
    /// 3 µs per edge (1000 random walks of 500 steps, 4 px wide: 1.4 s), and up to 40 ns per edge in the
    /// list (a 30 KB scribble: 0.2 s; a page of text at 300 ppi: 1.9 s).
    static func strokeCost(of edges: RasterEdges, width: CGFloat, scale: CGFloat) -> Int {
        guard width > 1.5 else {
            return nanoseconds(0.6 * max(1, Double(scale)) * edges.inserts)
        }
        return nanoseconds(max(3000 * Double(edges.count), 40 * edges.inserts))
    }

    private static func nanoseconds(_ cost: Double) -> Int {
        cost < Double(Int.max / 2) ? Int(cost) : Int.max / 2
    }

    typealias RasterEdges = (count: Int, inserts: Double, crossings: Double)

    /// The edges of the path under the linear part of `t`, how many were in the scanline's list as each was
    /// inserted, and how many cross: none worth counting below 16 edges. Curves count their control polygons;
    /// crossings come from a sample of edges, each tested against every edge beside it.
    func rasterEdges(transform t: CGAffineTransform) -> RasterEdges {
        // edges going down, horizontal ones left out as the rasteriser does
        var edges = [(x0: CGFloat, y0: CGFloat, x1: CGFloat, y1: CGFloat)]()
        var start = CGPoint.zero
        var last = CGPoint.zero
        func add(_ point: CGPoint) {
            let a = CGPoint(x: t.a * last.x + t.c * last.y, y: t.b * last.x + t.d * last.y)
            let b = CGPoint(x: t.a * point.x + t.c * point.y, y: t.b * point.x + t.d * point.y)
            if a.y < b.y {
                edges.append((a.x, a.y, b.x, b.y))
            } else if a.y > b.y {
                edges.append((b.x, b.y, a.x, a.y))
            }
            last = point
        }
        applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                start = points[0]
                last = points[0]
            case .addLineToPoint:
                add(points[0])
            case .addQuadCurveToPoint:
                add(points[0]); add(points[1])
            case .addCurveToPoint:
                add(points[0]); add(points[1]); add(points[2])
            case .closeSubpath:
                add(start)
            @unknown default:
                break
            }
        }
        let n = edges.count
        guard n >= 16, edges.allSatisfy({ $0.x0.isFinite && $0.x1.isFinite && $0.y0.isFinite && $0.y1.isFinite }) else { return (n, 0, 0) }

        // the edges in the list as each is inserted
        edges.sort { $0.y0 < $1.y0 }
        let ends = edges.map(\.y1).sorted()
        var inserts = 0.0
        var ended = 0
        for (index, edge) in edges.enumerated() {
            while ended < n && ends[ended] <= edge.y0 { ended += 1 }
            inserts += Double(index - ended)
        }

        // evenly spread samples, at most about max(65 536, 8n) edge tests in all
        let samples = max(1, min(n, max(1 << 16, 8 * n) / n))
        var crossings = 0
        for sample in 0..<samples {
            let index = (2 * sample + 1) * n / (2 * samples)
            let s = edges[index]
            var lower = 0
            var upper = n
            while lower < upper {
                let middle = (lower + upper) / 2
                if edges[middle].y0 < s.y1 { lower = middle + 1 } else { upper = middle }
            }
            for other in 0..<lower where other != index && edges[other].y1 > s.y0 {
                let f = edges[other]
                func side(_ ax: CGFloat, _ ay: CGFloat, _ bx: CGFloat, _ by: CGFloat, _ x: CGFloat, _ y: CGFloat) -> CGFloat {
                    (bx - ax) * (y - ay) - (by - ay) * (x - ax)
                }
                let s0 = side(s.x0, s.y0, s.x1, s.y1, f.x0, f.y0)
                let s1 = side(s.x0, s.y0, s.x1, s.y1, f.x1, f.y1)
                let f0 = side(f.x0, f.y0, f.x1, f.y1, s.x0, s.y0)
                let f1 = side(f.x0, f.y0, f.x1, f.y1, s.x1, s.y1)
                if s0 * s1 < 0 && f0 * f1 < 0 {
                    crossings += 1
                }
            }
        }
        return (n, inserts, Double(crossings) * Double(n) / Double(samples) / 2)
    }
}

extension String {

    func toLine(font: CTFont) -> CTLine {
        let attributes = [kCTFontAttributeName: font]
        let attString = CFAttributedStringCreate(nil, self as CFString, attributes as CFDictionary)!
        return CTLineCreateWithAttributedString(attString)
    }

    func toPath(font: CTFont) -> CGPath? {
        let line = toLine(font: font)
        let glyphRuns = CTLineGetGlyphRuns(line)

        var ascent = CGFloat(0)
        var descent = CGFloat(0)
        var leading = CGFloat(0)
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let baseline = ascent


        let path = CGMutablePath()

        for idx in 0..<CFArrayGetCount(glyphRuns) {
            let val = CFArrayGetValueAtIndex(glyphRuns, idx)
            let run = unsafeBitCast(val, to: CTRun.self)
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = resolveRunFont(attributes: attributes, fallback: font)

            for idx in 0..<CTRunGetGlyphCount(run) {
                let glyphRange = CFRange(location: idx, length: 1)
                var glyph: CGGlyph = 0
                var position: CGPoint = .zero
                CTRunGetGlyphs(run, glyphRange, &glyph)
                CTRunGetPositions(run, glyphRange, &position)
                // placed as it is made: appending with a transform costs the whole path so far
                var t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: position.x, ty: baseline)
                    .translatedBy(x: 0, y: baseline)
                if let glyphPath = CTFontCreatePathForGlyph(runFont, glyph, &t) {
                    path.addPath(glyphPath)
                }
            }
        }

        return path
    }

    // Use the font CoreText resolved for this run, else fall back to the requested font.
    private func resolveRunFont(attributes: NSDictionary, fallback: CTFont) -> CTFont {
        guard let value = attributes[kCTFontAttributeName] else {
            return fallback
        }
        // CoreFoundation type bridging: ensure it's a CTFont before use.
        if CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID() {
            return unsafeDowncast(value as AnyObject, to: CTFont.self)
        }
        return fallback
    }
}

#endif
