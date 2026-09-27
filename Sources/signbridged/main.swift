import Foundation
import SignCore

let router = Router(service: StubSigningService())
let server = LoopbackServer(router: router)

do {
    try server.start()
    print("signbridged \(SignBridgeInfo.version) dinliyor: 127.0.0.1:\(SignBridgeInfo.port)")
} catch {
    FileHandle.standardError.write(Data("başlatma hatası: \(error)\n".utf8))
    exit(1)
}

RunLoop.main.run()
