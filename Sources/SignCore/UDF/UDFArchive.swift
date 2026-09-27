import Foundation
import ZIPFoundation

/// Reads and writes the ZIP container of a `.udf` document.
///
/// A UDF file is a ZIP archive whose main entry is `content.xml`; binary
/// resources such as images may sit alongside it.
public enum UDFArchive {
    public static let contentEntry = "content.xml"

    /// Extracts one entry's bytes from a `.udf` archive.
    public static func entryData(_ name: String, in udf: Data) throws -> Data {
        let archive = try Archive(data: udf, accessMode: .read)
        guard let entry = archive[name] else {
            throw UDFError.missingEntry(name)
        }
        var output = Data()
        _ = try archive.extract(entry) { output.append($0) }
        return output
    }

    /// Reads the `content.xml` bytes from a `.udf` archive.
    public static func contentXML(from udf: Data) throws -> Data {
        try entryData(contentEntry, in: udf)
    }

    /// Builds a `.udf` archive from the content XML and optional named resources.
    public static func makeUDF(contentXML: Data, resources: [String: Data] = [:]) throws -> Data {
        let archive = try Archive(accessMode: .create)
        try addEntry(to: archive, name: contentEntry, data: contentXML)
        for (name, data) in resources {
            try addEntry(to: archive, name: name, data: data)
        }
        guard let data = archive.data else { throw UDFError.archiveFailed }
        return data
    }

    private static func addEntry(to archive: Archive, name: String, data: Data) throws {
        try archive.addEntry(
            with: name,
            type: .file,
            uncompressedSize: Int64(data.count),
            provider: { position, size in
                let start = Int(position)
                return data.subdata(in: start..<(start + size))
            }
        )
    }
}

/// Errors raised while reading or writing a UDF document.
public enum UDFError: Error, Equatable {
    case missingEntry(String)
    case archiveFailed
    case malformedXML(String)
}
