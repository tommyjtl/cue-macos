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

    @Test func shouldAttachAfterSecondPasteboardChangeWithinInterval() {
        let now: CFTimeInterval = 100

        let firstCopy = ClipboardMonitor.shouldAttachAfterPasteboardChange(
            firstCopyChangeCount: nil,
            firstCopyAt: nil,
            newChangeCount: 100,
            now: now
        )
        #expect(firstCopy.shouldAttach == false)
        #expect(firstCopy.nextFirstCopyChangeCount == 100)
        #expect(firstCopy.nextFirstCopyAt == now)

        let secondCopy = ClipboardMonitor.shouldAttachAfterPasteboardChange(
            firstCopyChangeCount: firstCopy.nextFirstCopyChangeCount,
            firstCopyAt: firstCopy.nextFirstCopyAt,
            newChangeCount: 101,
            now: now + 0.2
        )
        #expect(secondCopy.shouldAttach == true)
        #expect(secondCopy.nextFirstCopyChangeCount == nil)
        #expect(secondCopy.nextFirstCopyAt == nil)

        let tooLate = ClipboardMonitor.shouldAttachAfterPasteboardChange(
            firstCopyChangeCount: 200,
            firstCopyAt: now,
            newChangeCount: 201,
            now: now + 0.6,
            maxIntervalBetweenCopies: 0.5
        )
        #expect(tooLate.shouldAttach == false)
        #expect(tooLate.nextFirstCopyChangeCount == 201)
        #expect(tooLate.nextFirstCopyAt == now + 0.6)
    }

    @Test func composerEditShortcutMatchesStandardEditCommands() {
        #expect(ComposerEditShortcut.selector(for: makeKeyEvent(characters: "c", modifiers: [.command])) == #selector(NSText.copy(_:)))
        #expect(ComposerEditShortcut.selector(for: makeKeyEvent(characters: "v", modifiers: [.command])) == #selector(NSText.paste(_:)))
        #expect(ComposerEditShortcut.selector(for: makeKeyEvent(characters: "z", modifiers: [.command])) == Selector(("undo:")))
        #expect(ComposerEditShortcut.selector(for: makeKeyEvent(characters: "z", modifiers: [.command, .shift])) == Selector(("redo:")))
    }

    @Test func composerEditShortcutIgnoresModifiedEditCommands() {
        #expect(ComposerEditShortcut.selector(for: makeKeyEvent(characters: "c", modifiers: [.command, .option])) == nil)
        #expect(ComposerEditShortcut.selector(for: makeKeyEvent(characters: "v", modifiers: [.command, .option])) == nil)
        #expect(ComposerEditShortcut.selector(for: makeKeyEvent(characters: "z", modifiers: [.command, .control])) == nil)
        #expect(ComposerEditShortcut.selector(for: makeKeyEvent(characters: "z", modifiers: [.command, .option, .shift])) == nil)
    }

    @Test func isCopyKeyDownMatchesCharacterEvenWithDifferentKeyCode() {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "c",
            charactersIgnoringModifiers: "c",
            isARepeat: false,
            keyCode: 99
        )

        #expect(event != nil)
        #expect(ClipboardMonitor.isCopyKeyDown(event!))
    }

    @Test func isEscapeKeyEventIgnoresCapsLockModifier() {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.capsLock],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 53
        )

        #expect(event != nil)
        #expect(ContextStackWindowController.isEscapeKeyEvent(event!))
    }

    @Test func clipboardMonitorReadStringRequiresNonEmptyPlainText() {
        #expect(ClipboardMonitor.readString(from: makePasteboard(string: "hello")) == "hello")
        #expect(ClipboardMonitor.readString(from: makePasteboard(string: "  \n")) == nil)

        let emptyPasteboard = NSPasteboard(name: NSPasteboard.Name("test.empty.\(UUID().uuidString)"))
        emptyPasteboard.clearContents()
        #expect(ClipboardMonitor.readString(from: emptyPasteboard) == nil)
    }

    @Test func clipboardMonitorReadStringAcceptsPublicPlainTextType() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test.plain.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("plain-text payload", forType: NSPasteboard.PasteboardType("public.plain-text"))

        #expect(ClipboardMonitor.readString(from: pasteboard) == "plain-text payload")
    }

    @Test func diagnosePasteboardDescribesUnreadableTypes() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test.types.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setData(Data([0x01, 0x02]), forType: NSPasteboard.PasteboardType("com.example.binary"))

        let diagnostic = ClipboardMonitor.diagnosePasteboard(pasteboard)
        #expect(diagnostic.plainTextPreview == nil)
        #expect(diagnostic.readFailureReason == "no supported plain-text type")
        #expect(diagnostic.typeLabels.contains("com.example.binary"))
    }

    private func makeKeyEvent(characters: String, modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: 0
        )!
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
