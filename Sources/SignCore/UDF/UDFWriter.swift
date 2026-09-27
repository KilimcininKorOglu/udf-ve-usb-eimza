import Foundation

/// Serialises a `UDFDocument` back to `content.xml` and a `.udf` archive.
public enum UDFWriter {
    /// Builds the full `.udf` archive bytes.
    public static func write(_ document: UDFDocument, resources: [String: Data] = [:]) throws -> Data {
        let xml = contentXML(document)
        return try UDFArchive.makeUDF(contentXML: Data(xml.utf8), resources: resources)
    }

    /// Produces the `content.xml` string for a document.
    public static func contentXML(_ document: UDFDocument) -> String {
        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n\n"
        out += "<template format_id=\"\(escape(document.formatID))\" >\n"
        out += "<content><![CDATA[\(document.text)]]></content>"
        out += "<properties><pageFormat\(attributeString(document.pageFormat)) /></properties>"
        out += "<styles>"
        for style in document.styles {
            out += "<style name=\"\(escape(style.name))\"\(attributeString(style.attributes)) />"
        }
        out += "</styles>\n<elements >\n"
        for element in document.elements {
            out += elementXML(element)
        }
        out += "</elements>\n\n</template>\n"
        return out
    }

    // MARK: Elements

    private static func elementXML(_ element: UDFElement) -> String {
        switch element {
        case .paragraph(let paragraph):
            return "<paragraph\(attributeString(paragraph.attributes))>\(runsXML(paragraph.runs))</paragraph>\n"
        case .table(let table):
            return tableXML(table)
        case .image(let image):
            return "<image\(attributeString(image.attributes)) />\n"
        case .field(let field):
            return "<field\(attributeString(field.attributes))>\(runsXML(field.runs))</field>\n"
        case .space(let run):
            return "<space\(runAttributes(run)) />"
        case .raw(let raw):
            return rawXML(raw)
        }
    }

    private static func rawXML(_ raw: UDFRawElement) -> String {
        let attrs = attributeString(raw.attributes)
        if raw.cdata.isEmpty && raw.children.isEmpty {
            return "<\(raw.name)\(attrs) />"
        }
        let inner = escape(raw.cdata) + raw.children.map(rawXML).joined()
        return "<\(raw.name)\(attrs)>\(inner)</\(raw.name)>"
    }

    private static func tableXML(_ table: UDFTable) -> String {
        var out = "<table\(attributeString(table.attributes))>"
        for row in table.rows {
            out += "<row\(attributeString(row.attributes))>"
            for cell in row.cells {
                out += "<cell\(attributeString(cell.attributes))>"
                for element in cell.elements { out += elementXML(element) }
                out += "</cell>"
            }
            out += "</row>"
        }
        out += "</table>\n"
        return out
    }

    private static func runsXML(_ runs: [UDFContentRun]) -> String {
        runs.map { "<content\(runAttributes($0)) />" }.joined()
    }

    private static func runAttributes(_ run: UDFContentRun) -> String {
        " startOffset=\"\(run.startOffset)\" length=\"\(run.length)\"\(attributeString(run.attributes))"
    }

    // MARK: Attributes

    private static func attributeString(_ attributes: [UDFAttribute]) -> String {
        attributes.map { " \($0.name)=\"\(escape($0.value))\"" }.joined()
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
