import Foundation
import SwiftASN1

/// Reads certificates from a PKCS#15 card by following the object directory
/// files and parsing the certificate elementary files they reference.
public struct Pkcs15Reader: Sendable {
    /// EF.ODF, the object directory file, holds pointers to the other DFs.
    public static let efODF: UInt16 = 0x5031
    /// EF.DIR is an alternate discovery file present on some cards.
    public static let efDIR: UInt16 = 0x2F00

    private let maxFileLength = 0x8000
    private let session: any CardSession

    public init(session: any CardSession) {
        self.session = session
    }

    /// Reads the DER bytes of every certificate the card exposes.
    public func certificates() async throws -> [Data] {
        try await session.selectExpectingSuccess(ApduRecipes.selectMasterFile())
        let odf = try await readEF(Self.efODF)
        let candidatePaths = Pkcs15Reader.extractPaths(fromDER: odf)

        var seenDER: [Data] = []
        var visited = Set<UInt16>()
        for fid in candidatePaths where !visited.contains(fid) {
            visited.insert(fid)
            guard let content = try? await readEF(fid) else { continue }
            if (try? Certificate15.isCertificate(content)) == true {
                seenDER.append(content)
            } else {
                try await collectNested(content, into: &seenDER, visited: &visited)
            }
        }
        return seenDER
    }

    private func collectNested(_ content: Data, into out: inout [Data], visited: inout Set<UInt16>) async throws {
        for fid in Pkcs15Reader.extractPaths(fromDER: content) where !visited.contains(fid) {
            visited.insert(fid)
            guard let nested = try? await readEF(fid) else { continue }
            if (try? Certificate15.isCertificate(nested)) == true {
                out.append(nested)
            }
        }
    }

    /// Selects an EF and reads its whole content over READ BINARY chunks.
    func readEF(_ fid: UInt16) async throws -> Data {
        try await session.selectExpectingSuccess(ApduRecipes.selectFileID(fid))
        var out = Data()
        var offset: UInt16 = 0
        while out.count < maxFileLength {
            let response = try await session.transmit(ApduRecipes.readBinary(offset: offset, length: 0x00))
            if response.statusWord == 0x6B00 || response.data.isEmpty { break }
            guard response.isSuccess || response.sw1 == 0x6C else {
                throw CardError.apduFailed(response.statusWord)
            }
            out.append(response.data)
            if response.data.count < 256 { break }
            offset = offset &+ UInt16(response.data.count)
        }
        return out
    }

    /// Collects 2-byte file identifiers from OCTET STRING nodes in a DER blob.
    static func extractPaths(fromDER der: Data) -> [UInt16] {
        guard let root = try? DER.parse([UInt8](der)) else { return [] }
        var out: [UInt16] = []
        walk(root, into: &out)
        return out
    }

    private static func walk(_ node: ASN1Node, into out: inout [UInt16]) {
        switch node.content {
        case .primitive(let bytes):
            if node.identifier == .octetString, bytes.count == 2 {
                out.append((UInt16(bytes[bytes.startIndex]) << 8) | UInt16(bytes[bytes.startIndex + 1]))
            }
        case .constructed(let children):
            for child in children { walk(child, into: &out) }
        }
    }
}

/// Minimal check that a DER blob is an X.509 certificate: a SEQUENCE whose
/// first element is itself a SEQUENCE (the tbsCertificate).
enum Certificate15 {
    static func isCertificate(_ der: Data) throws -> Bool {
        let root = try DER.parse([UInt8](der))
        guard root.identifier == .sequence, case .constructed(let top) = root.content else {
            return false
        }
        var iterator = top.makeIterator()
        guard let first = iterator.next() else { return false }
        return first.identifier == .sequence
    }
}

extension CardSession {
    /// Sends a command and throws unless the card answers 9000.
    func selectExpectingSuccess(_ apdu: Data) async throws {
        let response = try await transmit(apdu)
        guard response.isSuccess else {
            if response.statusWord == 0x6A82 { throw CardError.fileNotFound }
            throw CardError.apduFailed(response.statusWord)
        }
    }
}
