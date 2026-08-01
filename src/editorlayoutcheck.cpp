#include "ui/layout.h"

#include <QApplication>
#include <QtGlobal>

#include <array>
#include <cmath>
#include <cstdio>

namespace {

class Reporter
{
  public:
    void check(bool condition, const char *value, const char *invariant)
    {
        if (condition)
            return;
        std::fprintf(stderr, "editor-layout-check: FAIL: %s: %s\n", value, invariant);
        ++m_failures;
    }

    int finish(int valueCount) const
    {
        std::printf(m_failures == 0 ? "editor-layout-check: PASS (%d values)\n"
                                    : "editor-layout-check: FAIL (%d values)\n",
                    valueCount);
        return m_failures == 0 ? 0 : 1;
    }

  private:
    int m_failures = 0;
};

struct FontScaledValue {
    const char *id;
    int resolved;
    double factor;
    int at12;
    int at16;
};

int resolveFontFactor(int baseFontPx, double factor)
{
    return qMax(1, qRound(baseFontPx * factor));
}

void checkFontScaled(Reporter &reporter, const FontScaledValue &value, int baseFontPx)
{
    reporter.check(value.at12 == resolveFontFactor(12, value.factor), value.id,
                   "default does not use qRound then qMax");
    reporter.check(value.at16 == resolveFontFactor(16, value.factor), value.id,
                   "alternate scale does not use qRound then qMax");
    reporter.check(value.resolved == (baseFontPx == 12 ? value.at12 : value.at16), value.id,
                   "accessor has the wrong resolved value");
}

int runCheck(QApplication &application, int baseFontPx)
{
    const auto initialized = layout::initialize(application, baseFontPx);
    Reporter reporter;
    reporter.check(initialized, "layout initialization",
                   "did not accept the requested clean-process scale");
    if (!initialized)
        return reporter.finish(0);

    const auto values = std::array{
        FontScaledValue{"track-header width", layout::editorGeometry().trackHeaderWidth, 17.5, 210,
                        280},
        FontScaledValue{"piano-keyboard width", layout::editorGeometry().pianoKeyboardWidth,
                        13.0 / 3.0, 52, 69},
        FontScaledValue{"editor default pixels per beat",
                        layout::editorGeometry().editorDefaultPixelsPerBeat, 8.0 / 3.0, 32, 43},
        FontScaledValue{"voice picker dialog width",
                        layout::editorGeometry().voicePickerDialogWidth, 30.0, 360, 480},
        FontScaledValue{"voice picker dialog height",
                        layout::editorGeometry().voicePickerDialogHeight, 110.0 / 3.0, 440, 587},
        FontScaledValue{"track-header button extent",
                        layout::editorGeometry().trackHeaderButtonExtent, 1.5, 18, 24},
        FontScaledValue{"track-header row height", layout::editorGeometry().trackHeaderRowHeight,
                        4.0, 48, 64},
        FontScaledValue{"track-header button column width",
                        layout::editorGeometry().trackHeaderButtonColumnWidth, 2.0, 24, 32},
        FontScaledValue{"track-header voice-line left",
                        layout::editorGeometry().trackHeaderVoiceLineLeft, 5.0 / 6.0, 10, 13},
        FontScaledValue{"track-header voice-line top",
                        layout::editorGeometry().trackHeaderVoiceLineTop, 11.0 / 6.0, 22, 29},
        FontScaledValue{"track-header voice-line right",
                        layout::editorGeometry().trackHeaderVoiceLineRight, 3.0, 36, 48},
        FontScaledValue{"track-header voice-line height",
                        layout::editorGeometry().trackHeaderVoiceLineHeight, 4.0 / 3.0, 16, 21},
        FontScaledValue{"track-header rename-editor left",
                        layout::editorGeometry().trackHeaderRenameEditorLeft, 0.5, 6, 8},
        FontScaledValue{"track-header rename-editor top",
                        layout::editorGeometry().trackHeaderRenameEditorTop, 1.0 / 6.0, 2, 3},
        FontScaledValue{"track-header rename-editor right",
                        layout::editorGeometry().trackHeaderRenameEditorRight, 8.0 / 3.0, 32, 43},
        FontScaledValue{"track-header rename-editor height",
                        layout::editorGeometry().trackHeaderRenameEditorHeight, 5.0 / 3.0, 20, 27},
        FontScaledValue{"timeline minimum pixels per beat",
                        layout::editorGeometry().timelineMinimumPixelsPerBeat, 1.0 / 3.0, 4, 5},
        FontScaledValue{"timeline maximum pixels per beat",
                        layout::editorGeometry().timelineMaximumPixelsPerBeat, 160.0 / 3.0, 640,
                        853},
        FontScaledValue{"piano-roll minimum key height",
                        layout::editorGeometry().pianoRollMinimumKeyHeight, 1.0 / 3.0, 4, 5},
        FontScaledValue{"piano-roll maximum key height",
                        layout::editorGeometry().pianoRollMaximumKeyHeight, 8.0 / 3.0, 32, 43},
        FontScaledValue{"velocity-handle minimum key height",
                        layout::editorGeometry().velocityHandleMinimumKeyHeight, 1.0, 12, 16},
        FontScaledValue{"automation grid minimum cell width",
                        layout::editorGeometry().automationGridMinimumCellWidth, 4.0 / 3.0, 16, 21},
        FontScaledValue{"velocity-handle tall-note threshold",
                        layout::editorGeometry().velocityHandleTallNoteThreshold, 5.0 / 3.0, 20,
                        27},
        FontScaledValue{"velocity-handle bar thickness",
                        layout::editorGeometry().velocityHandleBarThickness, 1.0 / 6.0, 2, 3},
        FontScaledValue{"velocity-handle inset", layout::editorGeometry().velocityHandleInset,
                        1.0 / 6.0, 2, 3},
        FontScaledValue{"timeline detail minimum pixels per beat",
                        layout::editorGeometry().timelineDetailMinimumPixelsPerBeat, 5.0 / 6.0, 10,
                        13},
        FontScaledValue{"grid-line stroke width", layout::editorGeometry().gridLineStrokeWidth,
                        1.0 / 6.0, 2, 3},
        FontScaledValue{"time-ruler minimum font pixel size",
                        layout::editorGeometry().timeRulerMinimumFontPixelSize, 1.0 / 12.0, 1, 1},
        FontScaledValue{"MIDI cursor extent", layout::editorGeometry().midiCursorExtent, 2.0, 24,
                        32},
        FontScaledValue{"piano-roll note minimum width",
                        layout::editorGeometry().pianoRollNoteMinimumWidth, 1.0 / 6.0, 2, 3},
        FontScaledValue{"piano-roll note minimum height",
                        layout::editorGeometry().pianoRollNoteMinimumHeight, 1.0 / 6.0, 2, 3},
        FontScaledValue{"note-border dash length", layout::editorGeometry().noteBorderDashLength,
                        1.0 / 3.0, 4, 5},
        FontScaledValue{"note-border dash gap", layout::editorGeometry().noteBorderDashGap,
                        1.0 / 6.0, 2, 3},
        FontScaledValue{"keyboard hover-chip font pixel size",
                        layout::editorGeometry().keyboardHoverChipFontPixelSize, 5.0 / 6.0, 10, 13},
        FontScaledValue{"keyboard hover-chip horizontal padding",
                        layout::editorGeometry().keyboardHoverChipHorizontalPadding, 2.0 / 3.0, 8,
                        11},
        FontScaledValue{"keyboard hover-chip vertical padding",
                        layout::editorGeometry().keyboardHoverChipVerticalPadding, 1.0 / 6.0, 2, 3},
        FontScaledValue{"keyboard hover-chip right inset",
                        layout::editorGeometry().keyboardHoverChipRightInset, 1.0 / 6.0, 2, 3},
        FontScaledValue{"velocity-label fit allowance",
                        layout::editorGeometry().velocityLabelFitAllowance, 1.0 / 3.0, 4, 5},
        FontScaledValue{"keyboard hover-chip corner radius",
                        layout::editorGeometry().keyboardHoverChipCornerRadius, 0.25, 3, 4},
        FontScaledValue{"piano-keyboard label right inset",
                        layout::editorGeometry().pianoKeyboardLabelRightInset, 0.25, 3, 4},
        FontScaledValue{"other-event hit slop", layout::editorGeometry().otherEventHitSlop,
                        1.0 / 3.0, 4, 5},
        FontScaledValue{"other-event marker half width",
                        layout::editorGeometry().otherEventMarkerHalfWidth, 1.0 / 3.0, 4, 5},
        FontScaledValue{"other-event marker half height",
                        layout::editorGeometry().otherEventMarkerHalfHeight, 5.0 / 12.0, 5, 7},
        FontScaledValue{"track-header text left", layout::editorGeometry().trackHeaderTextLeft,
                        5.0 / 6.0, 10, 13},
        FontScaledValue{"track-header reorder-indicator height",
                        layout::editorGeometry().trackHeaderReorderIndicatorHeight, 0.25, 3, 4},
        FontScaledValue{"piano-roll initial viewport height",
                        layout::editorGeometry().pianoRollInitialViewportHeight, 50.0 / 3.0, 200,
                        267},
        FontScaledValue{"timeline viewport minimum width",
                        layout::editorGeometry().timelineViewportMinimumWidth, 25.0 / 6.0, 50, 67},
        FontScaledValue{"timeline content-tail width",
                        layout::editorGeometry().timelineContentTailWidth, 25.0 / 3.0, 100, 133},
        FontScaledValue{"drawer resize-handle height",
                        layout::editorGeometry().editorDrawerResizeHandleHeight, 1.0 / 3.0, 4, 5},
        FontScaledValue{"minimum visible piano-roll height",
                        layout::editorGeometry().minimumVisiblePianoRollHeight, 10.0, 120, 160},
        FontScaledValue{"automation default row height",
                        layout::editorGeometry().automationRowDefaultHeight, 4.0, 48, 64},
        FontScaledValue{"automation minimum row height",
                        layout::editorGeometry().automationRowMinimumHeight, 7.0 / 3.0, 28, 37},
        FontScaledValue{"automation maximum row height",
                        layout::editorGeometry().automationRowMaximumHeight, 32.0 / 3.0, 128, 171},
        FontScaledValue{"automation row wheel increment",
                        layout::editorGeometry().automationRowWheelIncrement, 1.0 / 3.0, 4, 5},
        FontScaledValue{"add-automation-lane strip height",
                        layout::editorGeometry().addAutomationLaneStripHeight, 5.0 / 3.0, 20, 27},
        FontScaledValue{"automation point-hit radius",
                        layout::editorGeometry().automationPointHitRadius, 7.0 / 12.0, 7, 9},
        FontScaledValue{"automation neutral-snap radius",
                        layout::editorGeometry().automationNeutralSnapRadius, 2.0 / 3.0, 8, 11},
        FontScaledValue{"automation delete-time radius",
                        layout::editorGeometry().automationDeleteTimeRadius, 0.75, 9, 12},
        FontScaledValue{"automation point-detail threshold",
                        layout::editorGeometry().automationPointDetailThreshold, 2.0, 24, 32},
        FontScaledValue{"continuous-axis density threshold D1",
                        layout::editorGeometry().velocityDensityThresholdD1, 6.0, 72, 96},
        FontScaledValue{"continuous-axis density threshold D2",
                        layout::editorGeometry().velocityDensityThresholdD2, 25.0 / 3.0, 100, 133},
        FontScaledValue{"continuous-axis density threshold D3",
                        layout::editorGeometry().velocityDensityThresholdD3, 12.0, 144, 192},
        FontScaledValue{"continuous-axis density threshold D4",
                        layout::editorGeometry().velocityDensityThresholdD4, 24.0, 288, 384},
        FontScaledValue{"velocity start-node hit radius",
                        layout::editorGeometry().velocityStartNodeHitRadius, 0.5, 6, 8},
        FontScaledValue{"velocity duration-line vertical radius",
                        layout::editorGeometry().velocityDurationLineVerticalRadius, 1.0 / 3.0, 4,
                        5},
        FontScaledValue{"velocity duration-line horizontal slop",
                        layout::editorGeometry().velocityDurationLineHorizontalSlop, 1.0 / 6.0, 2,
                        3},
        FontScaledValue{"velocity relative-drag activation distance",
                        layout::editorGeometry().velocityRelativeDragActivationDistance, 1.0 / 12.0,
                        1, 1},
    };
    reporter.check(values.size() == 67, "editor layout inventory",
                   "does not cover every assigned semantic value");
    for (const auto &value : values)
        checkFontScaled(reporter, value, baseFontPx);
    reporter.check(resolveFontFactor(18, 7.0 / 12.0) == 11, "automation point-hit radius",
                   "does not preserve 7/12 rounding at the 18px half-pixel boundary");
    reporter.check(resolveFontFactor(18, 1.0 / 12.0) == 2,
                   "velocity relative-drag activation distance",
                   "does not preserve 1/12 rounding at the 18px half-pixel boundary");
    const auto expectedSelectionRingDipWidth = baseFontPx == 12 ? 1.5 : 2.0;
    const auto expectedTimeRulerLetterSpacing = baseFontPx == 12 ? -0.5 : -2.0 / 3.0;
    const auto expectedTimeRulerBeatLabelZoomFactor = 3.0;
    const auto expectedPianoRollNoteEdgeGripReach = baseFontPx == 12 ? 3.0 : 4.0;
    const auto expectedPianoRollNoteMoveZoneMinimumWidth = baseFontPx == 12 ? 6.0 : 8.0;
    const double expectedVelocityNodePaintRadius = baseFontPx == 12 ? 3.5 : 14.0 / 3.0;
    const double expectedVelocitySelectedNodeRingRadius = baseFontPx == 12 ? 4.5 : 6.0;
    const double expectedVelocityNodeOutlineDipWidth = baseFontPx == 12 ? 1.0 : 4.0 / 3.0;
    const double expectedVelocitySelectedNodeRingDipWidth = baseFontPx == 12 ? 2.0 : 8.0 / 3.0;
    const double expectedVelocityStemDipWidth = baseFontPx == 12 ? 2.0 : 8.0 / 3.0;
    const double expectedVelocitySelectedStemDipWidth = baseFontPx == 12 ? 3.0 : 4.0;
    reporter.check(std::abs(layout::editorGeometry().velocityNodePaintRadius -
                            expectedVelocityNodePaintRadius) < 0.000001 &&
                       std::abs(layout::editorGeometry().velocitySelectedNodeRingRadius -
                                expectedVelocitySelectedNodeRingRadius) < 0.000001 &&
                       std::abs(layout::editorGeometry().velocityNodeOutlineDipWidth -
                                expectedVelocityNodeOutlineDipWidth) < 0.000001 &&
                       std::abs(layout::editorGeometry().velocitySelectedNodeRingDipWidth -
                                expectedVelocitySelectedNodeRingDipWidth) < 0.000001 &&
                       std::abs(layout::editorGeometry().velocityStemDipWidth -
                                expectedVelocityStemDipWidth) < 0.000001 &&
                       std::abs(layout::editorGeometry().velocitySelectedStemDipWidth -
                                expectedVelocitySelectedStemDipWidth) < 0.000001,
                   "velocity-node paint metrics",
                   "do not preserve the 12px and 16px visual scale contract");
    reporter.check(std::abs(layout::editorGeometry().selectionRingDipWidth -
                            expectedSelectionRingDipWidth) < 0.000001,
                   "selection-ring DIP width", "does not resolve at the requested font scale");
    reporter.check(std::abs(layout::editorGeometry().timeRulerLetterSpacing -
                            expectedTimeRulerLetterSpacing) < 0.000001,
                   "time-ruler letter spacing", "does not resolve at the requested font scale");
    reporter.check(std::abs(layout::editorGeometry().timelineRevealViewportFraction - 1.0 / 3.0) <
                       0.000001,
                   "timeline reveal viewport fraction", "is not an invariant resolved ratio");
    reporter.check(std::abs(layout::editorGeometry().timeRulerBeatLabelZoomFactor -
                            expectedTimeRulerBeatLabelZoomFactor) < 0.000001,
                   "time-ruler beat-label zoom factor", "is not an invariant resolved ratio");
    reporter.check(std::abs(layout::editorGeometry().pianoRollNoteEdgeGripReach -
                            expectedPianoRollNoteEdgeGripReach) < 0.000001,
                   "piano-roll note edge-grip reach",
                   "does not resolve at the requested font scale");
    reporter.check(std::abs(layout::editorGeometry().pianoRollNoteMoveZoneMinimumWidth -
                            expectedPianoRollNoteMoveZoneMinimumWidth) < 0.000001,
                   "piano-roll note move-zone minimum width",
                   "does not resolve at the requested font scale");
    reporter.check(layout::space(layout::Space::Zero) == 0, "Space::Zero",
                   "is not invariant at zero");
    reporter.check(layout::singlePixel() == 1, "singlePixel",
                   "is not invariant at one physical pixel");

    const auto headerWidth = layout::editorGeometry().trackHeaderWidth;
    const auto keyboardWidth = layout::editorGeometry().pianoKeyboardWidth;
    const auto defaultRowHeight = layout::editorGeometry().automationRowDefaultHeight;
    const auto addLaneStripHeight = layout::editorGeometry().addAutomationLaneStripHeight;
    const auto expectedPlotOrigin = baseFontPx == 12 ? 262 : 349;
    const auto expectedFirstTabWidth = baseFontPx == 12 ? 105 : 140;
    const auto expectedMinimumDrawerHeight = baseFontPx == 12 ? 68 : 91;
    reporter.check(layout::editorGeometry().plotOrigin == headerWidth + keyboardWidth,
                   "plot origin", "does not derive from the resolved gutter widths");
    reporter.check(layout::editorGeometry().plotOrigin == expectedPlotOrigin, "plot origin",
                   "has the wrong resolved value");

    const auto firstTabWidth = headerWidth / 2;
    const auto secondTabWidth = headerWidth - firstTabWidth;
    reporter.check(firstTabWidth + secondTabWidth == headerWidth, "drawer tab partition",
                   "does not partition the resolved header width");
    reporter.check(firstTabWidth == expectedFirstTabWidth, "drawer first tab width",
                   "does not use the integer half");
    reporter.check(secondTabWidth == expectedFirstTabWidth, "drawer second tab width",
                   "does not use the header remainder");
    constexpr auto ODD_HEADER_WIDTH = 211;
    reporter.check(ODD_HEADER_WIDTH / 2 == 105, "odd drawer first tab width",
                   "does not use integer division");
    reporter.check(ODD_HEADER_WIDTH - ODD_HEADER_WIDTH / 2 == 106, "odd drawer second tab width",
                   "does not use the header remainder");

    reporter.check(defaultRowHeight + addLaneStripHeight == expectedMinimumDrawerHeight,
                   "minimum open drawer height",
                   "does not derive from the resolved row and add-lane heights");
    return reporter.finish(int(values.size()) + 11);
}

} // namespace

int main(int argc, char *argv[])
{
    QApplication application(argc, argv);
    const auto arguments = application.arguments();
    if (arguments.size() != 3 || arguments.at(1) != QStringLiteral("--base-font-px"))
        return 2;
    if (arguments.at(2) == QStringLiteral("12"))
        return runCheck(application, 12);
    if (arguments.at(2) == QStringLiteral("16"))
        return runCheck(application, 16);
    return 2;
}
