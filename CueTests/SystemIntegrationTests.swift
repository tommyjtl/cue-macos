//
//  SystemIntegrationTests.swift
//  CueTests
//

import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import Cue

struct SystemIntegrationTests {
    @Test func soundEffectsDefaultToEnabledWhenPreferenceMissing() {
        let defaults = UserDefaults.standard
        let key = AppPreferenceKeys.soundEffectsEnabledKey
        let previousValue = defaults.object(forKey: key)
        defaults.removeObject(forKey: key)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        #expect(AppPreferenceKeys.soundEffectsEnabled)
    }

    @Test func launchContextDetectsXcodeDebugBuild() {
        let path = "/Users/dev/Library/Developer/Xcode/DerivedData/Cue/Build/Products/Debug/Cue.app"
        #expect(PermissionManager.LaunchContext.current(for: path) == .xcodeDebug)
    }

    @Test func launchContextDetectsInstalledApp() {
        let path = "/Applications/Cue.app"
        #expect(PermissionManager.LaunchContext.current(for: path) == .installed)
    }

    @Test func launchContextDetectsArchiveBuild() {
        let path = "/Users/dev/build/Cue.xcarchive/Products/Applications/Cue.app"
        #expect(PermissionManager.LaunchContext.current(for: path) == .xcodeArchive)
    }

    @Test func crossAppAccessibilityProbeRequiresSuccessfulReadWhenOtherAppsExist() {
        #expect(AccessibilityClient.canQueryOtherApplicationsTree(probedOtherApp: false, queriedAnySuccessfully: false))
        #expect(AccessibilityClient.canQueryOtherApplicationsTree(probedOtherApp: true, queriedAnySuccessfully: true))
        #expect(!AccessibilityClient.canQueryOtherApplicationsTree(probedOtherApp: true, queriedAnySuccessfully: false))
    }

    @Test func resolveTrustedStatePrefersCachedGrant() {
        #expect(AccessibilityClient.resolveTrustedState(cachedTrusted: true, liveTrusted: false))
        #expect(AccessibilityClient.resolveTrustedState(cachedTrusted: true, liveTrusted: true))
        #expect(AccessibilityClient.resolveTrustedState(cachedTrusted: false, liveTrusted: true))
        #expect(!AccessibilityClient.resolveTrustedState(cachedTrusted: false, liveTrusted: false))
    }

    @Test func shouldAttachAfterSecondCopyWithinInterval() {
        let now: CFTimeInterval = 100

        let firstPress = ClipboardMonitor.shouldAttachAfterCopyKeyPress(lastCopyKeyDownAt: nil, now: now)
        #expect(firstPress.shouldAttach == false)
        #expect(firstPress.nextLastCopyKeyDownAt == now)

        let secondPress = ClipboardMonitor.shouldAttachAfterCopyKeyPress(
            lastCopyKeyDownAt: firstPress.nextLastCopyKeyDownAt,
            now: now + 0.2
        )
        #expect(secondPress.shouldAttach == true)
        #expect(secondPress.nextLastCopyKeyDownAt == nil)

        let tooLate = ClipboardMonitor.shouldAttachAfterCopyKeyPress(
            lastCopyKeyDownAt: now,
            now: now + 0.6,
            maxIntervalBetweenCopies: 0.5
        )
        #expect(tooLate.shouldAttach == false)
        #expect(tooLate.nextLastCopyKeyDownAt == now + 0.6)
    }

    @Test func clipboardMonitorReadStringRequiresNonEmptyPlainText() {
        #expect(ClipboardMonitor.readString(from: makePasteboard(string: "hello")) == "hello")
        #expect(ClipboardMonitor.readString(from: makePasteboard(string: "  \n")) == nil)

        let emptyPasteboard = NSPasteboard(name: NSPasteboard.Name("test.empty.\(UUID().uuidString)"))
        emptyPasteboard.clearContents()
        #expect(ClipboardMonitor.readString(from: emptyPasteboard) == nil)
    }

    private func makePasteboard(string: String) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString(string, forType: NSPasteboard.PasteboardType.string)
        return pasteboard
    }
    @Test func selectionRectFlipsYIntoScreenCaptureKitSpace() {
        let displayFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let rectInDisplaySpace = CGRect(x: 100, y: 200, width: 50, height: 60)

        let localRect = ScreenCaptureGeometry.selectionRectInDisplayLocalSpace(
            rectInDisplaySpace: rectInDisplaySpace,
            displayFrame: displayFrame
        )

        #expect(localRect.origin.x == 100)
        #expect(localRect.origin.y == 820)
        #expect(localRect.size.width == 50)
        #expect(localRect.size.height == 60)
    }

    @Test func selectionRectAdjustsForMenuBarOffset() {
        let screenFrame = CGRect(x: 0, y: 25, width: 1920, height: 1055)
        let cgDisplayBounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let selectionRect = CGRect(x: 10, y: 30, width: 100, height: 100)

        let adjusted = ScreenCaptureGeometry.selectionRectInDisplaySpace(
            selectionRect: selectionRect,
            screenFrame: screenFrame,
            cgDisplayBounds: cgDisplayBounds
        )

        #expect(adjusted.origin.x == 10)
        #expect(adjusted.origin.y == 5)
    }

    @Test func normalizedFingerprintAcceptsLegacyCodesignLine() {
        let hash = "a1d2c9997747aea3e57f222d7368eaf6110fd120"
        #expect(CodeSigningDiagnostics.normalizedFingerprint("CDHash=\(hash)") == hash)
        #expect(CodeSigningDiagnostics.normalizedFingerprint("dylib:CDHash=\(hash)") == "dylib:\(hash)")
    }

    @Test func fingerprintsMatchAcrossLegacyAndCurrentFormats() {
        let hash = "a1d2c9997747aea3e57f222d7368eaf6110fd120"
        #expect(CodeSigningDiagnostics.fingerprintsMatch("CDHash=\(hash)", hash))
        #expect(CodeSigningDiagnostics.fingerprintsMatch("dylib:CDHash=\(hash)", "dylib:\(hash)"))
        #expect(!CodeSigningDiagnostics.fingerprintsMatch(hash, "0000000000000000000000000000000000000000"))
    }

    @Test func matchDisplayPrefersExplicitDisplayID() {
        let displays = [
            ScreenCaptureGeometry.DisplayInfo(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            ScreenCaptureGeometry.DisplayInfo(displayID: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        ]
        let selection = CGRect(x: 2000, y: 400, width: 100, height: 100)

        let matched = ScreenCaptureGeometry.matchDisplay(
            selectionRect: selection,
            preferredDisplayID: 1,
            displays: displays
        )

        #expect(matched?.displayID == 1)
    }
}
