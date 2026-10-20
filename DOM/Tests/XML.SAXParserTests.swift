//
//  XML.SAXParserTests.swift
//  SwiftDraw
//
//  Created by Simon Whitty on 16/11/18.
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

import Foundation
import Testing
@testable import SwiftDrawDOM

@Suite("SAX Parser Tests")
struct SAXParserTests {

    @Test
    func missingFileThrows() {
        let missingFile = URL(fileURLWithPath: "/user/tmp/SWIFTDraw/SwiftDraw/missing")
        #expect(throws: (any Error).self) {
            _ = try XML.SAXParser.parse(contentsOf: missingFile)
        }
    }

    @Test
    func invalidXMLThrows() {
        let xml = "hi"
        #expect(throws: (any Error).self) {
            _ = try XML.SAXParser.parse(data: xml.data(using: .utf8)!)
        }
    }

    @Test
    func validSVGParses() throws {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
        </svg>
        """

        let root = try XML.SAXParser.parse(data: xml.data(using: .utf8)!)
        #expect(root.name == "svg")
        #expect(root.children.isEmpty)
    }

    #if canImport(Darwin)
    @Test
    func unexpectedElementsThrows() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
            </b>
        </svg>
        """

        #expect(throws: (any Error).self) {
            _ = try XML.SAXParser.parse(data: xml.data(using: .utf8)!)
        }
    }
    #endif

    @Test
    func unexpectedNamespaceElementsSkipped() throws {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
        <a xmlns="http://another.com" />
        <b />
        </svg>
        """
        let root = try XML.SAXParser.parse(data: xml.data(using: .utf8)!)
        #expect(root.name == "svg")
        #expect(root.children.count == 1)
        #expect(root.children[0].name == "b")
    }

    @Test
    func declaredSVGPrefixIsKept() throws {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:ns="http://www.w3.org/2000/svg" xmlns:s="http://www.w3.org/2000/svg">
        <ns:g><s:rect /></ns:g>
        <b />
        </svg>
        """
        let root = try XML.SAXParser.parse(data: xml.data(using: .utf8)!)
        #expect(root.children.map(\.name) == ["g", "b"])
        #expect(root.children[0].children.map(\.name) == ["rect"])
    }

    @Test
    func foreignNamespaceDropsSubtreeAndText() throws {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg"
             xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape"
             xmlns:sodipodi="http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd"
             xmlns:x="http://example.com/custom">
        <inkscape:foo><rect /><g>dropped</g></inkscape:foo>
        <sodipodi:namedview><circle /></sodipodi:namedview>
        <x:thing xmlns="http://example.com/other"><b /></x:thing>
        <text>kept</text>
        </svg>
        """
        let root = try XML.SAXParser.parse(data: xml.data(using: .utf8)!)
        #expect(root.children.map(\.name) == ["text"])
        #expect(root.children[0].innerText?.contains("kept") == true)
        #expect(root.innerText?.contains("dropped") != true)
    }

    @Test
    func entitiesAreJoinedIntoTheText() throws {
        let xml = "<svg xmlns=\"http://www.w3.org/2000/svg\"><desc>a" + String(repeating: "&lt;b", count: 10_000) + "</desc></svg>"
        let root = try XML.SAXParser.parse(data: Data(xml.utf8))
        #expect(root.children[0].innerText == "a" + String(repeating: "<b", count: 10_000))
    }

    @Test
    func elementsNestedTooDeepAreSkipped() throws {
        let depth = 5_000
        let xml = #"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">"#
            + String(repeating: #"<g><rect width="1" height="1"/>"#, count: depth - 1)
            + String(repeating: "</g>", count: depth - 1) + "</svg>"

        nonisolated(unsafe) var root: XML.Element?
        nonisolated(unsafe) var svg: DOM.SVG?
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            root = try? XML.SAXParser.parse(data: Data(xml.utf8))
            svg = try? DOM.SVG.parse(xml: xml)
            done.signal()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        #expect(done.wait(timeout: .now() + 60) == .success)

        var levels = 0
        var element = try #require(root)
        while true {
            levels += 1
            guard let g = element.children.first(where: { $0.name == "g" }) else { break }
            element = g
        }
        #expect(levels == XML.SAXParser.maxDepth)
        // the last level kept is a <g> without its children
        #expect(element.children.isEmpty)
        #expect(svg != nil)
    }
}
