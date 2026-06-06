//
//  ComposerInputMetricsTests.swift
//  CueTests
//

import Foundation
import Testing
@testable import Cue

struct ComposerInputMetricsTests {
    private let singleLineHeight: CGFloat = 16

    @Test func stableLayoutWidthFallsBackWhenContentViewIsNotLaidOut() {
        #expect(ComposerInputMetrics.stableLayoutWidth(contentViewWidth: 0) == ComposerInputMetrics.fallbackLayoutWidth)
        #expect(ComposerInputMetrics.stableLayoutWidth(contentViewWidth: 40) == ComposerInputMetrics.fallbackLayoutWidth)
    }

    @Test func stableLayoutWidthUsesMeasuredWidthWhenNearExpectedSize() {
        #expect(ComposerInputMetrics.stableLayoutWidth(contentViewWidth: 332) == 332)
    }

    @Test func resolvedLineTierExpandsWhenHeightCrossesExpandThreshold() {
        let tier = ComposerInputMetrics.resolvedLineTier(
            isEmpty: false,
            hasExplicitNewline: false,
            lineFragmentCount: 1,
            usedHeight: singleLineHeight * 1.06,
            singleLineHeight: singleLineHeight,
            currentVisibleLineCount: 1
        )

        #expect(tier == ComposerInputMetrics.expandedVisibleLineCount)
    }

    @Test func resolvedLineTierStaysExpandedInsideHysteresisBand() {
        let tier = ComposerInputMetrics.resolvedLineTier(
            isEmpty: false,
            hasExplicitNewline: false,
            lineFragmentCount: 1,
            usedHeight: singleLineHeight * 1.0,
            singleLineHeight: singleLineHeight,
            currentVisibleLineCount: 2
        )

        #expect(tier == ComposerInputMetrics.expandedVisibleLineCount)
    }

    @Test func resolvedLineTierCollapsesOnlyBelowCollapseThreshold() {
        let tier = ComposerInputMetrics.resolvedLineTier(
            isEmpty: false,
            hasExplicitNewline: false,
            lineFragmentCount: 1,
            usedHeight: singleLineHeight * 0.94,
            singleLineHeight: singleLineHeight,
            currentVisibleLineCount: 2
        )

        #expect(tier == ComposerInputMetrics.compactVisibleLineCount)
    }

    @Test func resolvedLineTierExpandsForExplicitNewline() {
        let tier = ComposerInputMetrics.resolvedLineTier(
            isEmpty: false,
            hasExplicitNewline: true,
            lineFragmentCount: 1,
            usedHeight: singleLineHeight * 0.5,
            singleLineHeight: singleLineHeight,
            currentVisibleLineCount: 1
        )

        #expect(tier == ComposerInputMetrics.expandedVisibleLineCount)
    }

    @Test func resolvedLineTierExpandsForMultipleLineFragments() {
        let tier = ComposerInputMetrics.resolvedLineTier(
            isEmpty: false,
            hasExplicitNewline: false,
            lineFragmentCount: 2,
            usedHeight: singleLineHeight * 0.5,
            singleLineHeight: singleLineHeight,
            currentVisibleLineCount: 1
        )

        #expect(tier == ComposerInputMetrics.expandedVisibleLineCount)
    }
}
