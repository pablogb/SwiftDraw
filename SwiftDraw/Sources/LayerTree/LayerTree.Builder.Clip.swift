//
//  LayerTree.Builder.Clip.swift
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

import SwiftDrawDOM
import Foundation

extension LayerTree.Builder {

    /// What an element's `clip-path` resolves to (SVG 1.1 §14.3.5).
    enum Clip {
        /// A union of shapes sharing one clip-rule, applied with a single `setClip`.
        case shapes([LayerTree.ClipShape], LayerTree.FillRule)
        /// Such a union clipped again by the `clip-path` of the `<clipPath>` itself: a second clip, still vector.
        indirect case intersection([LayerTree.ClipShape], LayerTree.FillRule, Clip)
        /// Geometry one clipping path cannot express (text, mixed clip-rules, a `clip-path` on the
        /// `<clipPath>` itself): drawn opaque white and applied as an alpha mask.
        case mask(LayerTree.Layer)

        /// The layers `apply` places around the clipped layer.
        var wrappers: Int {
            guard case .intersection(_, _, let nested) = self else { return 0 }
            return 1 + nested.wrappers
        }
    }

    /// A shape or text inside a `<clipPath>`, with the transform from its own coordinates to the
    /// clip path's content coordinates and the clip-rule it resolves to.
    struct ClipMember {
        var element: DOM.GraphicsElement
        var transform: LayerTree.Transform.Matrix
        var rule: LayerTree.FillRule
        /// A `clip-path` on the member itself (SVG 1.1 §14.3.5): it clips the member before the union.
        var clipID: String?
    }

    func makeClip(for element: DOM.GraphicsElement) -> Clip? {
        let attributes = DOM.presentationAttributes(for: element, styles: svg.styles)
        guard let clipID = attributes.clipPath?.fragmentID else { return nil }
        return makeClip(id: clipID, bounds: { makeBoundingBox(for: element) })
    }

    /// `bounds` is the bounding box of the referencing element, evaluated only for objectBoundingBox units.
    /// Resolved once per clip path and box; each element it clips pays for drawing its members again,
    /// and past the document-wide budget is clipped away.
    func makeClip(id: String, bounds: () -> LayerTree.Rect?) -> Clip? {
        // within a clip path being resolved, a cycle or the nesting cap depends on the path taken there
        guard activeClips.count == 0 else { return resolveClip(id: id, bounds: bounds) }
        // the box is part of the key when resolving the clip path (or one it uses) measured the element
        var measured = resolved.clipsMeasuringBounds.contains(id)
        var box = measured ? bounds() : nil
        var key: [AnyHashable] = measured ? [id, box] : [id]
        let resolution = resolved.clips[key] ?? {
            resolved.clipCost = 0
            let clip = resolveClip(id: id, bounds: {
                if !measured {
                    measured = true
                    box = bounds()
                }
                return box
            })
            if measured {
                resolved.clipsMeasuringBounds.insert(id)
                key = [id, box]
            }
            return (clip, resolved.clipCost)
        }()
        resolved.clips[key] = resolution
        guard resolution.clip != nil, references.spend(resolution.cost) else {
            return resolution.clip.map { _ in .shapes([.empty], .nonzero) }
        }
        return resolution.clip
    }

    private func resolveClip(id: String, bounds: () -> LayerTree.Rect?) -> Clip? {
        guard let clip = resolved.clipPath(id: id, in: svg.defs) else { return nil }

        // a clip path that (indirectly) clips itself is ignored; the active set is not counted
        // against the document-wide reference budget, so any number of elements may share a clip.
        // Each nested clip-path costs native stack, so nesting stops at ActiveClipSet.maxDepth.
        guard activeClips.count < ActiveClipSet.maxDepth,
              activeClips.insert(id).inserted else { return nil }
        defer { activeClips.remove(id) }

        var units = LayerTree.Transform.Matrix.identity
        if clip.clipPathUnits == .objectBoundingBox {
            // the bounding box of text is unknown here: keep the element unclipped rather than lose content
            guard let bounds = bounds() else { return nil }
            // an empty bounding box clips everything away
            guard bounds.width > 0, bounds.height > 0 else { return .shapes([.empty], .nonzero) }
            units = LayerTree.Transform.Matrix(a: bounds.width, b: 0, c: 0, d: bounds.height,
                                               tx: bounds.x, ty: bounds.y)
        }

        // the <clipPath>'s own cascade (attributes < CSS rules < style=""), done by the parser
        let own = clip.cascaded
        let transform = own.transform ?? []
        // the bounding box mapping comes first, then the <clipPath>'s transform in user units
        // (as Blink, Gecko and resvg do: clipTransform × translate(bbox) × scale(bbox))
        let space = units.concatenated(Self.createTransforms(from: transform).toMatrix())
        let rule = own.clipRule ?? .nonzero
        // `visibility` is inherited: a hidden <clipPath> hides its children unless they say `visible`
        let visibility = own.visibility ?? .visible
        let members = clip.childElements.flatMap { makeClipMembers(for: $0, inheriting: rule, visibility: visibility) }
        resolved.clipCost += members.reduce(0) { $0 + ReferenceGuard.cost(of: $1.element) }
        let nested = own.clipPath?.fragmentID

        let shapes = members.compactMap { member -> LayerTree.ClipShape? in
            guard let shape = Self.makeShape(from: member.element) else { return nil }
            return LayerTree.ClipShape(shape: shape, transform: member.transform.concatenated(space))
        }
        let rules = Set(members.map(\.rule))

        // one clipping path keeps each child's own clip-rule only where no two children meet: under
        // evenodd, overlapping children would cut holes in each other
        let nestedClip = nested.flatMap { makeClip(id: $0, bounds: bounds) }
        if shapes.count == members.count, rules.count <= 1, members.allSatisfy({ $0.clipID == nil }),
           rules.first != .evenodd || areApart(members) {
            // a clip path without any shape clips everything away
            let union = shapes.isEmpty ? [LayerTree.ClipShape.empty] : shapes
            switch nestedClip {
            case nil:
                return .shapes(union, rules.first ?? .nonzero)
            case .shapes?, .intersection?:
                return .intersection(union, rules.first ?? .nonzero, nestedClip!)
            case .mask?:
                break
            }
        }

        let content = LayerTree.Layer()
        if space != .identity {
            content.transform = [.matrix(space)]
        }
        for member in members {
            content.appendContents(.layer(makeClipMaskLayer(for: member)))
        }

        let region = LayerTree.Layer()
        let placed = nestedClip.map { apply($0, to: region) } ?? region
        region.appendContents(.layer(content))

        let mask = LayerTree.Layer()
        mask.appendContents(.layer(placed))
        return .mask(mask)
    }

    /// Whether no two members' bounding boxes meet; a clip path with many children is not compared.
    private func areApart(_ members: [ClipMember]) -> Bool {
        guard members.count <= 32 else { return false }
        let boxes = members.compactMap { member in
            makeBoundingBox(for: member.element).map { $0.applying(member.transform) }
        }
        guard boxes.count == members.count else { return false }
        for (i, a) in boxes.enumerated() {
            for b in boxes[(i + 1)...]
            where a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height {
                return false
            }
        }
        return true
    }

    /// The shapes and text a `<clipPath>` child contributes: a `<use>` contributes the shape or text
    /// it references directly; any other element is ignored (SVG 1.1 §14.3.5).
    func makeClipMembers(for element: DOM.GraphicsElement, inheriting rule: LayerTree.FillRule,
                         visibility inherited: DOM.Visibility = .visible) -> [ClipMember] {
        let attributes = DOM.presentationAttributes(for: element, styles: svg.styles)
        let visibility = attributes.visibility ?? inherited
        // SVG 1.1 §14.3.5: children with `display="none"` or hidden `visibility` do not contribute to the clip
        guard attributes.display != DOM.DisplayMode.none, visibility == .visible else { return [] }
        let transform = Self.createTransforms(from: attributes.transform ?? []).toMatrix()
        let rule = attributes.clipRule ?? rule

        if let use = element as? DOM.Use {
            guard let id = use.href.fragmentID,
                  let referenced = svg.firstGraphicsElement(with: id),
                  !(referenced is DOM.Use) else { return [] }
            let translate = LayerTree.Transform.translate(tx: use.x ?? 0, ty: use.y ?? 0).toMatrix()
            return makeClipMembers(for: referenced, inheriting: rule, visibility: visibility).map {
                var member = $0
                member.transform = member.transform.concatenated(translate).concatenated(transform)
                return member
            }
        } else if Self.makeShape(from: element) != nil || element is DOM.Text {
            return [ClipMember(element: element, transform: transform, rule: rule,
                               clipID: attributes.clipPath?.fragmentID)]
        }
        return []
    }

    func makeClipMaskLayer(for member: ClipMember) -> LayerTree.Layer {
        let l = LayerTree.Layer()
        if member.transform != .identity {
            l.transform = [.matrix(member.transform)]
        }
        if let shape = Self.makeShape(from: member.element) {
            var state = State()
            state.fill = .color(.keyword(.white))
            state.fillRule = member.rule
            l.appendContents(makeShapeContents(from: shape, with: state))
            return applyMemberClip(of: member, to: l)
        } else if let text = member.element as? DOM.Text {
            let state = createState(for: text, inheriting: State())
            if case .text(let string, let point, var attributes) = makeTextContents(from: text, with: state) {
                attributes.color = .white
                l.appendContents(.text(string, point, attributes))
            }
            return applyMemberClip(of: member, to: l)
        }
        return l
    }

    /// A `clip-path` on a `<clipPath>` child clips that child only, in the child's user space.
    private func applyMemberClip(of member: ClipMember, to layer: LayerTree.Layer) -> LayerTree.Layer {
        guard let id = member.clipID,
              let clip = makeClip(id: id, bounds: { makeBoundingBox(for: member.element) }) else { return layer }
        return apply(clip, to: layer)
    }

    /// Clips `layer`; returns the layer to place where `layer` was: `layer` itself, or for an intersection
    /// the layers holding it, each adding a clip, the outermost taking over `layer`'s transform.
    @discardableResult
    func apply(_ clip: Clip, to layer: LayerTree.Layer) -> LayerTree.Layer {
        switch clip {
        case let .shapes(shapes, rule):
            layer.clip = shapes
            layer.clipRule = rule
            return layer
        case let .intersection(shapes, rule, nested):
            layer.clip = shapes
            layer.clipRule = rule
            let outer = LayerTree.Layer()
            outer.transform = layer.transform
            layer.transform = []
            outer.appendContents(.layer(layer))
            return apply(nested, to: outer)
        case let .mask(mask):
            guard let existing = layer.mask else {
                layer.mask = mask
                layer.maskIsClip = true
                return layer
            }
            // a mask and a clip together: the clip masks the mask's own contents
            let inner = LayerTree.Layer()
            inner.mask = mask
            existing.contents.forEach(inner.appendContents)
            let combined = LayerTree.Layer()
            combined.appendContents(.layer(inner))
            layer.mask = combined
            return layer
        }
    }

    /// The region outside which a `<mask>` is zero (SVG 1.1 §14.4): nil when it cannot be resolved
    /// (an objectBoundingBox region on an element whose bounding box is unknown).
    func makeMaskRegion(for mask: DOM.Mask, bounds: LayerTree.Rect?) -> LayerTree.Rect? {
        let x = mask.x ?? .percentage(-10)
        let y = mask.y ?? .percentage(-10)
        let width = mask.width ?? .percentage(120)
        let height = mask.height ?? .percentage(120)

        switch mask.maskUnits ?? .objectBoundingBox {
        case .objectBoundingBox:
            guard let bounds else { return nil }
            func fraction(_ length: DOM.DashLength) -> LayerTree.Float {
                switch length {
                case .absolute(let value): return value
                case .percentage(let value): return value / 100
                }
            }
            return LayerTree.Rect(x: bounds.x + fraction(x) * bounds.width,
                                  y: bounds.y + fraction(y) * bounds.height,
                                  width: fraction(width) * bounds.width,
                                  height: fraction(height) * bounds.height)
        case .userSpaceOnUse:
            let viewport = svg.viewBox.map { LayerTree.Size($0.width, $0.height) }
                ?? LayerTree.Size(LayerTree.Float(svg.width), LayerTree.Float(svg.height))
            func length(_ length: DOM.DashLength, _ reference: LayerTree.Float) -> LayerTree.Float {
                switch length {
                case .absolute(let value): return value
                case .percentage(let value): return value / 100 * reference
                }
            }
            return LayerTree.Rect(x: length(x, viewport.width),
                                  y: length(y, viewport.height),
                                  width: length(width, viewport.width),
                                  height: length(height, viewport.height))
        }
    }

    /// The object bounding box of an element in its own user space: the fill geometry of its shapes,
    /// without stroke (SVG 1.1 §7.11). Nil when unknown: text, or a container holding text, since
    /// a box measured without it would cut the text away.
    func makeBoundingBox(for element: DOM.GraphicsElement) -> LayerTree.Rect? {
        var visited = Set<String>()
        switch makeBounds(for: element, depth: 0, visited: &visited) {
        case .known(let rect): return rect
        case .empty, .unknown: return nil
        }
    }

    enum Bounds {
        case known(LayerTree.Rect)
        /// no geometry (an empty group, a move-only path): ignored by the enclosing container
        case empty
        /// geometry this platform-independent builder cannot measure (text)
        case unknown
    }

    /// Measurement keeps its own visited set, depth cap and step budget: it never spends the
    /// document-wide reference budget that `<use>`, masks and patterns share.
    private func makeBounds(for element: DOM.GraphicsElement, depth: Int, visited: inout Set<String>) -> Bounds {
        guard depth < 32, measurement.spend() else { return .unknown }

        if let shape = Self.makeShape(from: element) {
            return Bounds(shape.path.bounds)
        } else if let image = element as? DOM.Image {
            guard let width = image.width, let height = image.height else { return .unknown }
            return Bounds(LayerTree.Rect(x: image.x ?? 0, y: image.y ?? 0, width: width, height: height))
        } else if let use = element as? DOM.Use {
            guard let id = use.href.fragmentID,
                  let referenced = svg.firstGraphicsElement(with: id) else { return .empty }
            guard visited.insert(id).inserted else { return .empty }
            defer { visited.remove(id) }
            let referencedBounds = makeBounds(for: referenced, depth: depth + 1, visited: &visited)
            guard case .known(let bounds) = referencedBounds else { return referencedBounds }
            let transform = Self.createTransforms(from: DOM.presentationAttributes(for: referenced, styles: svg.styles).transform ?? []).toMatrix()
                .concatenated(LayerTree.Transform.translate(tx: use.x ?? 0, ty: use.y ?? 0).toMatrix())
            return Bounds(bounds.applying(transform))
        } else if let container = element as? any ContainerElement {
            var result: LayerTree.Rect?
            for child in container.childElements {
                let childAttributes = DOM.presentationAttributes(for: child, styles: svg.styles)
                guard childAttributes.display != DOM.DisplayMode.none else { continue }
                switch makeBounds(for: child, depth: depth + 1, visited: &visited) {
                case .unknown:
                    return .unknown
                case .empty:
                    continue
                case .known(let bounds):
                    let transform: LayerTree.Transform.Matrix
                    if let svg = child as? DOM.SVG {
                        transform = Self.makeTransform(x: svg.x, y: svg.y, viewBox: svg.viewBox,
                                                       width: svg.width, height: svg.height).toMatrix()
                    } else {
                        transform = Self.createTransforms(from: childAttributes.transform ?? []).toMatrix()
                    }
                    guard case .known(let childBounds) = Bounds(bounds.applying(transform)) else { continue }
                    let union = result.map { $0.union(childBounds) } ?? childBounds
                    // a union reaching infinity (1e308 + 1e308) carries no usable geometry
                    guard case .known(let checked) = Bounds(union) else { continue }
                    result = checked
                }
            }
            return result.map(Bounds.known) ?? .empty
        } else if element is DOM.Text {
            return .unknown
        }
        return .empty
    }
}

extension LayerTree.Builder.Bounds {
    /// Non-finite or negative-sized bounds (a move-only path, NaN from 0 × inf) carry no geometry.
    init(_ rect: LayerTree.Rect) {
        let values = [rect.x, rect.y, rect.width, rect.height]
        guard values.allSatisfy(\.isFinite), rect.width >= 0, rect.height >= 0 else {
            self = .empty
            return
        }
        self = .known(rect)
    }
}

/// Ids of the clip paths being resolved, to drop cycles.
final class ActiveClipSet {
    static let maxDepth = 16
    private var ids = Set<String>()

    var count: Int { ids.count }

    func insert(_ id: String) -> (inserted: Bool, memberAfterInsert: String) {
        ids.insert(id)
    }

    func remove(_ id: String) {
        ids.remove(id)
    }
}

extension LayerTree.Builder {

    /// Bounds the elements visited measuring bounding boxes, document-wide: `visited` only cuts cycles,
    /// and non-cyclic `<use>` fan-out (4 uses per level) is exponential. Past the budget every box is
    /// unknown, so bbox clips and mask regions degrade to none rather than hide content.
    final class MeasurementBudget {
        static let maxSteps = 250_000
        private(set) var steps = 0

        func spend() -> Bool {
            guard steps < Self.maxSteps else { return false }
            steps += 1
            return true
        }
    }
}

extension LayerTree.ClipShape {
    /// A clip that nothing passes through.
    static var empty: Self {
        LayerTree.ClipShape(shape: .rect(within: .zero, radii: .zero), transform: .identity)
    }
}

extension LayerTree.Rect {

    func applying(_ matrix: LayerTree.Transform.Matrix) -> LayerTree.Rect {
        guard matrix != .identity else { return self }
        let points = [
            LayerTree.Point(x, y),
            LayerTree.Point(x + width, y),
            LayerTree.Point(x, y + height),
            LayerTree.Point(x + width, y + height)
        ].map(matrix.transform(point:))
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min()!, minY = ys.min()!
        return LayerTree.Rect(x: minX, y: minY, width: xs.max()! - minX, height: ys.max()! - minY)
    }

    func union(_ other: LayerTree.Rect) -> LayerTree.Rect {
        let minX = Swift.min(x, other.x)
        let minY = Swift.min(y, other.y)
        let maxX = Swift.max(x + width, other.x + other.width)
        let maxY = Swift.max(y + height, other.y + other.height)
        return LayerTree.Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Empty when the rects do not meet.
    func intersection(_ other: LayerTree.Rect) -> LayerTree.Rect {
        let minX = Swift.max(x, other.x)
        let minY = Swift.max(y, other.y)
        let maxX = Swift.min(x + width, other.x + other.width)
        let maxY = Swift.min(y + height, other.y + other.height)
        return LayerTree.Rect(x: minX, y: minY, width: Swift.max(0, maxX - minX), height: Swift.max(0, maxY - minY))
    }
}
