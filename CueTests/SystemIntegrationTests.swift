//
//  SystemIntegrationTests.swift
//  CueTests
//

import Testing
@testable import Cue

struct SystemIntegrationTests {
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
}
