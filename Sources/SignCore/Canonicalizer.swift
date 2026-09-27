import Foundation
import Clibxml2

/// Inclusive XML canonicalization (C14N 1.0) via libxml2.
public enum Canonicalizer {
    /// Canonicalizes a well-formed XML fragment and returns the C14N bytes.
    ///
    /// The fragment must declare, on its root element, every namespace it
    /// uses, so its standalone canonical form equals its in-context subtree
    /// canonical form.
    public static func canonicalize(_ xml: String) throws -> Data {
        let bytes = [UInt8](xml.utf8)
        guard let doc = bytes.withUnsafeBufferPointer({ buffer -> xmlDocPtr? in
            buffer.baseAddress?.withMemoryRebound(to: CChar.self, capacity: buffer.count) { chars in
                xmlReadMemory(chars, Int32(buffer.count), "fragment.xml", nil, Int32(XML_PARSE_NOBLANKS.rawValue))
            }
        }) else {
            throw CardError.parse("XML ayrıştırılamadı")
        }
        defer { xmlFreeDoc(doc) }

        var output: UnsafeMutablePointer<xmlChar>?
        let length = xmlC14NDocDumpMemory(doc, nil, 0, nil, 0, &output)
        guard length >= 0, let output else {
            throw CardError.parse("C14N başarısız")
        }
        defer { free(output) }
        return Data(bytes: output, count: Int(length))
    }
}
