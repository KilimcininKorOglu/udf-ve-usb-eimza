import Foundation

/// Parses a `.udf` document (or its `content.xml`) into a `UDFDocument`.
public enum UDFReader {
    /// Reads a full `.udf` archive.
    public static func read(udf: Data) throws -> UDFDocument {
        let xml = try UDFArchive.contentXML(from: udf)
        return try parse(contentXML: xml)
    }

    /// Parses the `content.xml` bytes into a document.
    public static func parse(contentXML: Data) throws -> UDFDocument {
        let delegate = RawNodeBuilder()
        let parser = XMLParser(data: contentXML)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse(), let root = delegate.root, root.name == "template" else {
            throw UDFError.malformedXML(delegate.errorMessage ?? "template kökü yok")
        }
        return map(template: root)
    }

    // MARK: Mapping

    private static func map(template: RawNode) -> UDFDocument {
        var document = UDFDocument()
        document.formatID = template.attributes.value("format_id") ?? "1.7"
        for child in template.children {
            switch child.name {
            case "content":
                document.text = child.cdata
            case "properties":
                document.pageFormat = child.children.first { $0.name == "pageFormat" }?.attributes ?? []
            case "styles":
                document.styles = child.children.filter { $0.name == "style" }
                    .map { UDFStyle(
                        name: $0.attributes.value("name") ?? "",
                        attributes: $0.attributes.filter { $0.name != "name" }
                    ) }
            case "elements":
                document.elements = child.children.compactMap(mapElement)
            default:
                break
            }
        }
        return document
    }

    private static func mapElement(_ node: RawNode) -> UDFElement? {
        switch node.name {
        case "paragraph":
            return .paragraph(UDFParagraph(attributes: node.attributes, runs: runs(of: node)))
        case "table":
            return .table(mapTable(node))
        case "image":
            return .image(UDFImage(attributes: node.attributes))
        case "field":
            return .field(UDFField(attributes: node.attributes, runs: runs(of: node)))
        case "space":
            return .space(run(node))
        default:
            return nil
        }
    }

    private static func mapTable(_ node: RawNode) -> UDFTable {
        let rows = node.children.filter { $0.name == "row" }.map { rowNode in
            UDFRow(
                attributes: rowNode.attributes,
                cells: rowNode.children.filter { $0.name == "cell" }.map { cellNode in
                    UDFCell(attributes: cellNode.attributes, elements: cellNode.children.compactMap(mapElement))
                }
            )
        }
        return UDFTable(attributes: node.attributes, rows: rows)
    }

    private static func runs(of node: RawNode) -> [UDFContentRun] {
        node.children.filter { $0.name == "content" }.map(run)
    }

    private static func run(_ node: RawNode) -> UDFContentRun {
        let extra = node.attributes.filter { $0.name != "startOffset" && $0.name != "length" }
        return UDFContentRun(
            startOffset: Int(node.attributes.value("startOffset") ?? "0") ?? 0,
            length: Int(node.attributes.value("length") ?? "0") ?? 0,
            attributes: extra
        )
    }
}

/// Builds a generic node tree from an XML stream, sorting attributes by name
/// for deterministic output.
private final class RawNode {
    let name: String
    let attributes: [UDFAttribute]
    var cdata: String = ""
    var children: [RawNode] = []

    init(name: String, attributes: [UDFAttribute]) {
        self.name = name
        self.attributes = attributes
    }
}

private final class RawNodeBuilder: NSObject, XMLParserDelegate {
    var root: RawNode?
    var errorMessage: String?
    private var stack: [RawNode] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        let attributes = attributeDict.keys.sorted().map { UDFAttribute($0, attributeDict[$0] ?? "") }
        let node = RawNode(name: elementName, attributes: attributes)
        stack.last?.children.append(node)
        if root == nil { root = node }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.cdata += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        stack.last?.cdata += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if !stack.isEmpty { stack.removeLast() }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        errorMessage = parseError.localizedDescription
    }
}
