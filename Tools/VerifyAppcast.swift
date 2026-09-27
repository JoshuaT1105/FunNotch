//
//  VerifyAppcast.swift
//  FunNotch
//
//  Checks every download in an appcast the way Sparkle will: fetches the
//  file the enclosure points at, compares its length, and verifies the EdDSA
//  signature against the public key the app ships with. Run through
//  Tools/verify-appcast.sh after every release.
//
//  This exists because the release workflow once rebuilt and re-uploaded the
//  dmgs after they had been signed. The files on GitHub stopped matching their
//  signatures, and every update failed with "The update is improperly signed"
//  for two releases before anyone noticed.
//
//      swift Tools/VerifyAppcast.swift <public-key> <appcast path or URL>
//

import CryptoKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let keyData = Data(base64Encoded: arguments[1]),
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
else {
    print("usage: VerifyAppcast.swift <base64 public key> <appcast path or URL>")
    exit(2)
}

/// Downloads with every cache bypassed. Sparkle asks the server for a fresh
/// feed, so a copy cached on this Mac from an earlier run would check the
/// wrong thing.
func fetch(_ url: URL) -> Data? {
    if url.isFileURL { return try? Data(contentsOf: url) }
    final class Box: @unchecked Sendable { var data: Data? }
    let box = Box()
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 120)
    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
    let done = DispatchSemaphore(value: 0)
    URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, _ in
        if (response as? HTTPURLResponse)?.statusCode == 200 { box.data = data }
        done.signal()
    }.resume()
    done.wait()
    return box.data
}

let source = arguments[2]
let feedURL = source.hasPrefix("http") ? URL(string: source)! : URL(fileURLWithPath: source)
guard let feed = fetch(feedURL),
      let document = try? XMLDocument(data: feed)
else {
    print("could not read the appcast at \(source)")
    exit(1)
}

let items = (try? document.nodes(forXPath: "//item")) ?? []
var failures = 0

for case let item as XMLElement in items {
    let version = (try? item.nodes(forXPath: "*[local-name()='shortVersionString']").first?.stringValue) ?? "?"
    guard let enclosure = item.elements(forName: "enclosure").first,
          let address = enclosure.attribute(forName: "url")?.stringValue,
          let url = URL(string: address)
    else {
        print("\(version): no enclosure")
        failures += 1
        continue
    }
    let declaredLength = Int(enclosure.attribute(forName: "length")?.stringValue ?? "") ?? -1
    let signature = enclosure.attributes?
        .first { $0.localName == "edSignature" }?
        .stringValue
        .flatMap { Data(base64Encoded: $0) }

    guard let file = fetch(url) else {
        print("\(version): could not download \(address)")
        failures += 1
        continue
    }
    let lengthOK = file.count == declaredLength
    let signatureOK = signature.map { publicKey.isValidSignature($0, for: file) } ?? false
    let verdict = lengthOK && signatureOK ? "OK" : "BROKEN — Sparkle will refuse this update"
    print("\(version): \(file.count) bytes (appcast says \(declaredLength)), "
        + "signature \(signatureOK ? "valid" : "INVALID") — \(verdict)")
    if !(lengthOK && signatureOK) { failures += 1 }
}

if items.isEmpty {
    print("no items in the appcast")
    exit(1)
}
exit(failures == 0 ? 0 : 1)
