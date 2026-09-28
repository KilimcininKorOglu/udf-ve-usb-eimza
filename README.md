# USB E-imza & UDF

A native macOS, iOS and iPadOS application that signs documents with a USB smart
card holding a qualified electronic certificate, and reads, edits and writes UDF
documents. It bridges Turkish e-government sign-in portals to a local signing
service and produces CAdES and XAdES signatures.

![CI](https://github.com/KilimcininKorOglu/udf-ve-usb-eimza/actions/workflows/ci.yml/badge.svg)

## Screens

<p align="center">
  <a href="docs/screenshots/portals.png"><img src="docs/screenshots/portals.png" width="32%" alt="Portals" /></a>
  <a href="docs/screenshots/sign.png"><img src="docs/screenshots/sign.png" width="32%" alt="Document signing" /></a>
  <a href="docs/screenshots/editor.png"><img src="docs/screenshots/editor.png" width="32%" alt="UDF editor" /></a>
</p>
<p align="center">
  <sub>Portals &nbsp;·&nbsp; Document signing &nbsp;·&nbsp; UDF editor — click a screen for the full image</sub>
</p>

## Features

- **Sign-in portals.** A grouped list of government portals (UYAP, e-Devlet, UETS,
  PTT KEP) that open in an embedded WKWebView, with the card status shown live.
- **Document signing.** Pick a local file, choose a card certificate and a format,
  enter the PIN, and export the signed bytes as CAdES or XAdES.
- **UDF editor.** Open, edit and save UDF documents in a TextKit editor with a
  formatting toolbar; the reader and writer round-trip paragraphs, tables, images,
  fields, headers and footers without loss.
- **One codebase.** The same feature set runs on macOS, iOS and iPadOS.

## Architecture

The card private key never leaves the card. PIN verification and the RSA signature
are performed on the card through APDU commands (VERIFY, then PSO), and the raw
signature is embedded into the CMS (CAdES) or XML-DSig (XAdES) structure. Those
structures are built by hand with swift-asn1, so the same code runs on every
platform. Card access uses CryptoTokenKit on macOS, iOS and iPadOS with a USB-C
connected CCID reader.

A small loopback HTTP server on `127.0.0.1` exposes the signing endpoints. The app
injects a JavaScript shim into each government page that wraps `fetch` and
`EventSource` targeting the loopback port and routes them to the native host, so an
HTTPS page can reach the local service without a mixed-content block.

## Signature formats

- **CAdES-BES** — a CMS `SignedData` structure, verifiable with `openssl cms -verify`.
- **XAdES-BES** — XML-DSig plus `SignedProperties`, canonicalized with libxml2 and
  verifiable with `xmlsec1 --verify`.

## Requirements

- A qualified electronic certificate on a smart card and its PIN.
- A CCID-compliant USB smart card reader (for example ACR39U).
- A USB-C or Lightning-to-USB adapter for a phone or tablet.

## Project layout

| Path | Contents |
| --- | --- |
| `Sources/SignCore` | Platform-independent core: loopback server, router, CryptoTokenKit transport, PKCS#15 reader, CAdES and XAdES builders, UDF model, reader and writer. |
| `Sources/signbridged` | An executable that runs the signing service headlessly. |
| `App/Sources` | The SwiftUI app: portals, the document signer and the UDF editor. |
| `Tests/SignCoreTests` | Unit tests for the envelope, router, PKCS#15 parsing, and CAdES/XAdES output. |

## Build and test

```sh
swift build
swift test
```

Generate and build the app from `project.yml`:

```sh
xcodegen generate
xcodebuild -project SignBridgeApp.xcodeproj -scheme SignBridgeApp \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

CAdES verification uses `openssl`; XAdES verification uses `xmlsec1`
(`brew install xmlsec1`).

## Dependencies

swift-asn1, swift-certificates, swift-crypto and ZIPFoundation. The signature
structures are built with these libraries; the card key is never handed to them.
