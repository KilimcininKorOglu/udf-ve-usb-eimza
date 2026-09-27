import Foundation

/// Builders for the ISO/IEC 7816-4 commands used to read a PKCS#15 card and
/// compute a signature. Each returns the raw command APDU bytes.
public enum ApduRecipes {
    // MARK: File selection

    /// SELECT by 2-byte file identifier under the current DF.
    public static func selectFileID(_ fid: UInt16, expectFCP: Bool = true) -> Data {
        let p2: UInt8 = expectFCP ? 0x00 : 0x0C
        return apdu(cla: 0x00, ins: 0xA4, p1: 0x02, p2: p2,
                    data: Data([UInt8(fid >> 8), UInt8(fid & 0xFF)]))
    }

    /// SELECT the master file (3F00).
    public static func selectMasterFile() -> Data {
        apdu(cla: 0x00, ins: 0xA4, p1: 0x00, p2: 0x00, data: Data([0x3F, 0x00]))
    }

    /// SELECT a DF by application identifier.
    public static func selectAID(_ aid: Data) -> Data {
        apdu(cla: 0x00, ins: 0xA4, p1: 0x04, p2: 0x00, data: aid)
    }

    // MARK: Reading

    /// READ BINARY at the given offset for `length` bytes (0 = up to 256).
    public static func readBinary(offset: UInt16, length: UInt8) -> Data {
        Data([0x00, 0xB0, UInt8(offset >> 8), UInt8(offset & 0xFF), length])
    }

    /// GET RESPONSE for `length` bytes.
    public static func getResponse(length: UInt8) -> Data {
        Data([0x00, 0xC0, 0x00, 0x00, length])
    }

    // MARK: Authentication

    /// VERIFY the PIN in the given reference slot.
    public static func verifyPIN(_ pin: Data, reference: UInt8 = 0x00) -> Data {
        apdu(cla: 0x00, ins: 0x20, p1: 0x00, p2: reference, data: pin)
    }

    // MARK: Signing

    /// MANAGE SECURITY ENVIRONMENT: set the key and algorithm for signing.
    public static func mseSetDigitalSignature(keyReference: UInt8, algorithm: UInt8) -> Data {
        let body = Data([0x80, 0x01, algorithm, 0x84, 0x01, keyReference])
        return apdu(cla: 0x00, ins: 0x22, p1: 0x41, p2: 0xB6, data: body)
    }

    /// PERFORM SECURITY OPERATION: compute digital signature over `hash`.
    public static func computeSignature(_ hash: Data) -> Data {
        apdu(cla: 0x00, ins: 0x2A, p1: 0x9E, p2: 0x9A, data: hash, expectResponse: true)
    }

    // MARK: Assembly

    /// Assembles a short-form APDU with an Lc data field and optional Le.
    static func apdu(
        cla: UInt8, ins: UInt8, p1: UInt8, p2: UInt8,
        data: Data, expectResponse: Bool = false
    ) -> Data {
        var out = Data([cla, ins, p1, p2])
        if !data.isEmpty {
            out.append(UInt8(data.count))
            out.append(data)
        }
        if expectResponse {
            out.append(0x00)
        }
        return out
    }
}
