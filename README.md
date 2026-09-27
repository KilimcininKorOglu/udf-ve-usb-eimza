# USB E-imza & UDF

A native application for macOS, iOS and iPadOS that signs documents with a USB
smart card (qualified electronic certificate) and edits UDF documents. It bridges
Turkish e-government sign-in portals to a local signing service and produces CAdES
and XAdES signatures.

## Components

- **SignCore** — platform-independent core: a loopback HTTP server, the request
  router, the CryptoTokenKit card transport, PKCS#15 reading, the CAdES and XAdES
  builders, and the UDF reader, writer and model.
- **signbridged** — an executable that runs the signing service headlessly.
- **SignBridgeApp** — the SwiftUI app (portals in a WKWebView, a document signer
  and a TextKit UDF editor), generated with XcodeGen.

## Architecture

The card private key never leaves the card. The card computes the RSA signature
through APDU commands (PIN verification with VERIFY, the signature with PSO), and
the raw signature is embedded into the CMS (CAdES) or XML-DSig (XAdES) structure,
built by hand with swift-asn1 so the same code runs on every platform. Card access
uses CryptoTokenKit on macOS, iOS and iPadOS with a USB-C connected CCID reader.

The app injects a small JavaScript shim into the government pages that wraps
`fetch` and `EventSource` targeting the loopback port and routes them to the native
host, so an HTTPS page can reach the local signing service.

## Requirements

- A qualified electronic certificate on a smart card and its PIN.
- A CCID-compliant USB smart card reader (for example ACR39U).
- A USB-C or Lightning-to-USB adapter for a phone or tablet.

## Build and test

```sh
swift build
swift test
```

The app project is generated from `project.yml`:

```sh
xcodegen generate
xcodebuild -project SignBridgeApp.xcodeproj -scheme SignBridgeApp \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

## Signatures

- **CAdES-BES**: a CMS SignedData structure, verifiable with `openssl cms -verify`.
- **XAdES-BES**: XML-DSig plus SignedProperties, canonicalized with libxml2 and
  verifiable with `xmlsec1 --verify`.

## Dependencies

swift-asn1, swift-certificates, swift-crypto and ZIPFoundation. The signature
structures are built with these libraries; the card key is never handed to them.
