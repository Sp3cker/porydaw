#pragma once

#include <QFont>
#include <QString>
#include <QtCore/QRect>
#include <QtGlobal>

class QApplication;
class QScrollBar;

namespace layout {

enum class Space {
    Zero,
    Half,
    One,
    Two,
    Three,
    Four,
    Six,
    Eight,
};

/// Vertical placement of a measured text block within available bounds.
enum class VerticalAlignment {
    Top,
    Center,
    Bottom,
};

/// Absolute line boxes produced by TwoLineTextLayout::align().
/// Both preserve the supplied bounds' horizontal position and width.
struct TwoLineTextBoxes {
    QRect primary;
    QRect secondary;
};

/// Geometry for a primary line that may change font and a secondary line.
class TwoLineTextLayout
{
  public:
    /// Total outer height of both line boxes and their intervening gap.
    int height() const;
    /// Aligns the complete block vertically within bounds.
    TwoLineTextBoxes align(const QRect &bounds, VerticalAlignment verticalAlignment) const;

  private:
    friend TwoLineTextLayout twoLineText(const QFont &, const QFont &, const QFont &, Space);
    TwoLineTextLayout(const QFont &primary, const QFont &alternatePrimary, const QFont &secondary,
                      Space gap);

    int m_primaryHeight;
    int m_secondaryHeight;
    int m_gap;
};

/// Reserves the primary line using the taller of primary and alternatePrimary,
/// so callers can change font for hover/selection without moving either line.
/// The secondary font determines the second line; gap is a layout-space token.
TwoLineTextLayout twoLineText(const QFont &primary, const QFont &alternatePrimary,
                              const QFont &secondary, Space gap);
/// Resolves and installs the one application-wide geometry stylesheet from
/// typography's captured base font pixel size. Repeating the same
/// application/base pair is idempotent; invalid or conflicting calls fail
/// without changing established geometry. Must run before stateful queries and
/// application widgets exist.
bool initialize(QApplication &application, int baseFontPx);
/// Resolves a named spacing token after successful initialization.
int space(Space token);
/// Resolves a dimensionless multiplier after successful initialization.
int fontPx(double multiplier);
/// Returns the initialization-independent logical-pixel application hairline.
int singlePixel();
/// Resolved editor geometry, initialized by initialize().
struct EditorGeometry {
    int trackHeaderWidth;
    int pianoKeyboardWidth;
    int automationRowDefaultHeight;
    int automationRowMinimumHeight;
    int automationRowMaximumHeight;
    int automationRowWheelIncrement;
    int addAutomationLaneStripHeight;
    int editorDrawerResizeHandleHeight;
    int minimumVisiblePianoRollHeight;
    int automationPointHitRadius;
    int automationNeutralSnapRadius;
    int automationDeleteTimeRadius;
    int automationPointDetailThreshold;
    int automationHoverPaintPadding;
    int velocityDensityThresholdD1;
    int velocityDensityThresholdD2;
    int velocityDensityThresholdD3;
    int velocityDensityThresholdD4;
    int velocityStartNodeHitRadius;
    double velocityNodePaintRadius;
    double velocitySelectedNodeRingRadius;
    double velocityNodeOutlineDipWidth;
    double velocitySelectedNodeRingDipWidth;
    double velocityStemDipWidth;
    double velocitySelectedStemDipWidth;
    int velocityDurationLineVerticalRadius;
    int velocityDurationLineHorizontalSlop;
    int velocityRelativeDragActivationDistance;
    int plotOrigin;
    int editorDefaultPixelsPerBeat;
    int voicePickerDialogWidth;
    int voicePickerDialogHeight;
    int trackHeaderButtonExtent;
    int trackHeaderRowHeight;
    int trackHeaderButtonColumnWidth;
    int trackHeaderVoiceLineLeft;
    int trackHeaderVoiceLineTop;
    int trackHeaderVoiceLineRight;
    int trackHeaderVoiceLineHeight;
    int trackHeaderRenameEditorLeft;
    int trackHeaderRenameEditorTop;
    int trackHeaderRenameEditorRight;
    int trackHeaderRenameEditorHeight;
    int timelineMinimumPixelsPerBeat;
    int timelineMaximumPixelsPerBeat;
    int pianoRollMinimumKeyHeight;
    int pianoRollMaximumKeyHeight;
    int velocityHandleMinimumKeyHeight;
    int automationGridMinimumCellWidth;
    int velocityHandleTallNoteThreshold;
    int velocityHandleBarThickness;
    int velocityHandleInset;
    double selectionRingDipWidth;
    int timelineDetailMinimumPixelsPerBeat;
    int gridLineStrokeWidth;
    int timeRulerMinimumFontPixelSize;
    double timeRulerLetterSpacing;
    double timeRulerBeatLabelZoomFactor;
    int midiCursorExtent;
    int pianoRollNoteMinimumWidth;
    int pianoRollNoteMinimumHeight;
    double pianoRollNoteEdgeGripReach;
    double pianoRollNoteMoveZoneMinimumWidth;
    int noteBorderDashLength;
    int noteBorderDashGap;
    int keyboardHoverChipFontPixelSize;
    int keyboardHoverChipHorizontalPadding;
    int keyboardHoverChipVerticalPadding;
    int keyboardHoverChipRightInset;
    int velocityLabelFitAllowance;
    int keyboardHoverChipCornerRadius;
    int pianoKeyboardLabelRightInset;
    int otherEventHitSlop;
    int otherEventMarkerHalfWidth;
    int otherEventMarkerHalfHeight;
    int trackHeaderTextLeft;
    int trackHeaderReorderIndicatorHeight;
    int pianoRollInitialViewportHeight;
    double timelineRevealViewportFraction;
    int timelineViewportMinimumWidth;
    int timelineContentTailWidth;
};
/// Returns the resolved editor geometry after successful initialization.
const EditorGeometry &editorGeometry();
/// Computes parameterized velocity-handle hit padding.
qreal velocityHandlePointerHitPadding(qreal noteHeight, qreal physicalPixel);
/// Computes the shared dock-title and tab-row outer height.
int chromeRowHeight(const QFont &applicationFont, int iconExtent);
/// Returns cached geometry followed by color rules without installing either.
QString composeStyleSheet(const QString &colorStyleSheet);
/// Keeps list scrolling and drag navigation while showing only its handle.
void configureListPositionIndicator(QScrollBar &scrollBar);

} // namespace layout
