import Foundation

/// An ordered XML attribute, preserved for faithful round-tripping.
public struct UDFAttribute: Equatable, Sendable {
    public var name: String
    public var value: String

    public init(_ name: String, _ value: String) {
        self.name = name
        self.value = value
    }
}

public extension Array where Element == UDFAttribute {
    /// The value of the first attribute with the given name.
    func value(_ name: String) -> String? {
        first { $0.name == name }?.value
    }
}

/// A parsed UDF document: the flat text plus the styles and the element tree
/// that map ranges of that text to paragraphs, tables, images and fields.
public struct UDFDocument: Equatable, Sendable {
    public var formatID: String
    public var text: String
    public var pageFormat: [UDFAttribute]
    public var styles: [UDFStyle]
    public var elements: [UDFElement]

    public init(
        formatID: String = "1.7",
        text: String = "",
        pageFormat: [UDFAttribute] = [],
        styles: [UDFStyle] = [],
        elements: [UDFElement] = []
    ) {
        self.formatID = formatID
        self.text = text
        self.pageFormat = pageFormat
        self.styles = styles
        self.elements = elements
    }
}

/// A named style: a font family, size and flags referenced by a resolver.
public struct UDFStyle: Equatable, Sendable {
    public var name: String
    public var attributes: [UDFAttribute]

    public init(name: String, attributes: [UDFAttribute]) {
        self.name = name
        self.attributes = attributes
    }
}

/// A run pointing at a range of the document text, with optional inline style.
public struct UDFContentRun: Equatable, Sendable {
    public var startOffset: Int
    public var length: Int
    public var attributes: [UDFAttribute]

    public init(startOffset: Int, length: Int, attributes: [UDFAttribute] = []) {
        self.startOffset = startOffset
        self.length = length
        self.attributes = attributes
    }
}

/// A top-level or nested UDF element.
public indirect enum UDFElement: Equatable, Sendable {
    case paragraph(UDFParagraph)
    case table(UDFTable)
    case image(UDFImage)
    case field(UDFField)
    case space(UDFContentRun)
    /// Any element the typed mapping does not recognise, preserved verbatim so
    /// the document round-trips without losing content such as headers.
    case raw(UDFRawElement)
}

/// A verbatim element the typed mapping does not model. Keeps the tag name,
/// attributes, character data and nested elements so the writer can re-emit it.
public struct UDFRawElement: Equatable, Sendable {
    public var name: String
    public var attributes: [UDFAttribute]
    public var cdata: String
    public var children: [UDFRawElement]

    public init(name: String, attributes: [UDFAttribute] = [], cdata: String = "", children: [UDFRawElement] = []) {
        self.name = name
        self.attributes = attributes
        self.cdata = cdata
        self.children = children
    }
}

public struct UDFParagraph: Equatable, Sendable {
    public var attributes: [UDFAttribute]
    public var inlines: [UDFInline]

    public init(attributes: [UDFAttribute] = [], inlines: [UDFInline] = []) {
        self.attributes = attributes
        self.inlines = inlines
    }

    /// Convenience initialiser for the common all-text-run paragraph.
    public init(attributes: [UDFAttribute] = [], runs: [UDFContentRun]) {
        self.attributes = attributes
        self.inlines = runs.map { .content($0) }
    }

    /// The text runs among the inlines, in order (content, field and space
    /// all point at a range of the document text).
    public var textRuns: [UDFContentRun] {
        inlines.compactMap { inline in
            switch inline {
            case .content(let run), .field(let run), .space(let run): return run
            case .image, .raw: return nil
            }
        }
    }
}

/// One inline item inside a paragraph, kept in document order. Content, field
/// and space each point at a range of the flat text; an image is standalone;
/// raw keeps any other inline element verbatim.
public enum UDFInline: Equatable, Sendable {
    case content(UDFContentRun)
    case field(UDFContentRun)
    case space(UDFContentRun)
    case image(UDFRawElement)
    case raw(UDFRawElement)
}

public struct UDFTable: Equatable, Sendable {
    public var attributes: [UDFAttribute]
    public var rows: [UDFRow]

    public init(attributes: [UDFAttribute] = [], rows: [UDFRow] = []) {
        self.attributes = attributes
        self.rows = rows
    }
}

public struct UDFRow: Equatable, Sendable {
    public var attributes: [UDFAttribute]
    public var cells: [UDFCell]

    public init(attributes: [UDFAttribute] = [], cells: [UDFCell] = []) {
        self.attributes = attributes
        self.cells = cells
    }
}

public struct UDFCell: Equatable, Sendable {
    public var attributes: [UDFAttribute]
    public var elements: [UDFElement]

    public init(attributes: [UDFAttribute] = [], elements: [UDFElement] = []) {
        self.attributes = attributes
        self.elements = elements
    }
}

public struct UDFImage: Equatable, Sendable {
    public var attributes: [UDFAttribute]

    public init(attributes: [UDFAttribute] = []) {
        self.attributes = attributes
    }
}

public struct UDFField: Equatable, Sendable {
    public var attributes: [UDFAttribute]
    public var runs: [UDFContentRun]

    public init(attributes: [UDFAttribute] = [], runs: [UDFContentRun] = []) {
        self.attributes = attributes
        self.runs = runs
    }
}
