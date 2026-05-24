import Foundation
import Security

enum CodeSigningDiagnostics {
    enum Status: Equatable {
        case signed(teamID: String)
        case unsigned
    }

    static func status(forBundleAt bundlePath: String) -> Status {
        status(for: URL(fileURLWithPath: bundlePath))
    }

    static func status(for bundleURL: URL) -> Status {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return .unsigned
        }

        guard let info = copySigningInformation(from: staticCode) else {
            return .unsigned
        }

        if let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String, !teamID.isEmpty {
            return .signed(teamID: teamID)
        }

        return .unsigned
    }

    static func fingerprint(forBundleAt bundlePath: String) -> String {
        let bundleURL = URL(fileURLWithPath: bundlePath)
        let dylibURL = bundleURL.appendingPathComponent("Contents/MacOS/Cue.debug.dylib")
        if FileManager.default.fileExists(atPath: dylibURL.path),
           let dylibFingerprint = uniqueIdentifier(for: dylibURL) {
            return normalizedFingerprint("dylib:\(dylibFingerprint)")
        }

        return normalizedFingerprint(uniqueIdentifier(for: bundleURL) ?? bundlePath)
    }

    /// Canonical form for comparing fingerprints stored before/after the Security-framework migration.
    /// Legacy values used full `codesign` lines (e.g. `CDHash=a1b2…`); current values use raw CDHash hex.
    static func normalizedFingerprint(_ fingerprint: String) -> String {
        if fingerprint.hasPrefix("dylib:") {
            let hash = normalizeHashComponent(String(fingerprint.dropFirst("dylib:".count)))
            return "dylib:\(hash)"
        }

        return normalizeHashComponent(fingerprint)
    }

    static func fingerprintsMatch(_ lhs: String, _ rhs: String) -> Bool {
        normalizedFingerprint(lhs) == normalizedFingerprint(rhs)
    }

    private static func normalizeHashComponent(_ component: String) -> String {
        if component.hasPrefix("CDHash=") {
            return String(component.dropFirst("CDHash=".count))
        }

        return component
    }

    private static func uniqueIdentifier(for url: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode,
              let info = copySigningInformation(from: staticCode) else {
            return nil
        }

        if let unique = info[kSecCodeInfoUnique as String] as? Data {
            return unique.map { String(format: "%02hhx", $0) }.joined()
        }

        return nil
    }

    private static func copySigningInformation(from staticCode: SecStaticCode) -> [String: Any]? {
        var signingInfo: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &signingInfo) == errSecSuccess,
              let info = signingInfo as? [String: Any] else {
            return nil
        }

        return info
    }
}
