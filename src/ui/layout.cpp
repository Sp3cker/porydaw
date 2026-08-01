#include "layout.h"

#include <QAbstractItemView>
#include <QApplication>
#include <QComboBox>
#include <QCursor>
#include <QEvent>
#include <QFontMetrics>
#include <QFrame>
#include <QLayout>
#include <QPainter>
#include <QPalette>
#include <QScrollBar>
#include <QStyle>
#include <QStyleOptionComboBox>
#include <QtGlobal>

#include <algorithm>
#include <array>
#include <optional>

namespace layout {
namespace {

// Concrete pixel dimensions derived once from typography's captured base font
// pixel size.
// The stylesheet builders consume these values so control geometry and spacing
// remain proportional to the platform-scaled application font.
struct FontScaledGeometry {
    int border;
    int zero;
    int half;
    int one;
    int two;
    int comboDropDownLane;
    int comboDropDownWidth;
    int listPositionIndicatorMinimumLength;
    int indicatorExtent;
    int groupBoxTitleBand;
};

constexpr auto TRACK_HEADER_WIDTH_SCALE = 17.5;
constexpr auto PIANO_KEYBOARD_WIDTH_SCALE = 13.0 / 3.0;
constexpr auto AUTOMATION_ROW_DEFAULT_HEIGHT_SCALE = 4.0;
constexpr auto AUTOMATION_ROW_MINIMUM_HEIGHT_SCALE = 7.0 / 3.0;
constexpr auto AUTOMATION_ROW_MAXIMUM_HEIGHT_SCALE = 32.0 / 3.0;
constexpr auto AUTOMATION_ROW_WHEEL_INCREMENT_SCALE = 1.0 / 3.0;
constexpr auto ADD_AUTOMATION_LANE_STRIP_HEIGHT_SCALE = 5.0 / 3.0;
constexpr auto EDITOR_DRAWER_RESIZE_HANDLE_HEIGHT_SCALE = 1.0 / 3.0;
constexpr auto MINIMUM_VISIBLE_PIANO_ROLL_HEIGHT_SCALE = 10.0;
constexpr auto AUTOMATION_POINT_HIT_RADIUS_SCALE = 7.0 / 12.0;
constexpr auto AUTOMATION_NEUTRAL_SNAP_RADIUS_SCALE = 2.0 / 3.0;
constexpr auto AUTOMATION_DELETE_TIME_RADIUS_SCALE = 0.75;
constexpr auto AUTOMATION_POINT_DETAIL_THRESHOLD_SCALE = 2.0;
constexpr auto AUTOMATION_HOVER_PAINT_PADDING_SCALE = 1.0 / 6.0;
constexpr auto VELOCITY_DENSITY_THRESHOLD_D1_SCALE = 6.0;
constexpr auto VELOCITY_DENSITY_THRESHOLD_D2_SCALE = 25.0 / 3.0;
constexpr auto VELOCITY_DENSITY_THRESHOLD_D3_SCALE = 12.0;
constexpr auto VELOCITY_DENSITY_THRESHOLD_D4_SCALE = 24.0;
constexpr auto VELOCITY_START_NODE_HIT_RADIUS_SCALE = 0.5;
constexpr auto VELOCITY_NODE_PAINT_RADIUS_SCALE = 7.0 / 24.0;
constexpr auto VELOCITY_SELECTED_NODE_RING_RADIUS_SCALE = 3.0 / 8.0;
constexpr auto VELOCITY_NODE_OUTLINE_DIP_WIDTH_SCALE = 1.0 / 12.0;
constexpr auto VELOCITY_SELECTED_NODE_RING_DIP_WIDTH_SCALE = 1.0 / 6.0;
constexpr auto VELOCITY_STEM_DIP_WIDTH_SCALE = 1.0 / 6.0;
constexpr auto VELOCITY_SELECTED_STEM_DIP_WIDTH_SCALE = 1.0 / 4.0;
constexpr auto VELOCITY_DURATION_LINE_VERTICAL_RADIUS_SCALE = 1.0 / 3.0;
constexpr auto VELOCITY_DURATION_LINE_HORIZONTAL_SLOP_SCALE = 1.0 / 6.0;
constexpr auto VELOCITY_RELATIVE_DRAG_ACTIVATION_DISTANCE_SCALE = 1.0 / 12.0;
constexpr auto EDITOR_DEFAULT_PIXELS_PER_BEAT_SCALE = 8.0 / 3.0;
constexpr auto VOICE_PICKER_DIALOG_WIDTH_SCALE = 30.0;
constexpr auto VOICE_PICKER_DIALOG_HEIGHT_SCALE = 110.0 / 3.0;
constexpr auto TRACK_HEADER_BUTTON_EXTENT_SCALE = 1.5;
constexpr auto TRACK_HEADER_ROW_HEIGHT_SCALE = 4.0;
constexpr auto TRACK_HEADER_BUTTON_COLUMN_WIDTH_SCALE = 2.0;
constexpr auto TRACK_HEADER_VOICE_LINE_LEFT_SCALE = 5.0 / 6.0;
constexpr auto TRACK_HEADER_VOICE_LINE_TOP_SCALE = 11.0 / 6.0;
constexpr auto TRACK_HEADER_VOICE_LINE_RIGHT_SCALE = 3.0;
constexpr auto TRACK_HEADER_VOICE_LINE_HEIGHT_SCALE = 4.0 / 3.0;
constexpr auto TRACK_HEADER_RENAME_EDITOR_LEFT_SCALE = 0.5;
constexpr auto TRACK_HEADER_RENAME_EDITOR_TOP_SCALE = 1.0 / 6.0;
constexpr auto TRACK_HEADER_RENAME_EDITOR_RIGHT_SCALE = 8.0 / 3.0;
constexpr auto TRACK_HEADER_RENAME_EDITOR_HEIGHT_SCALE = 5.0 / 3.0;
constexpr auto TIMELINE_MINIMUM_PIXELS_PER_BEAT_SCALE = 1.0 / 3.0;
constexpr auto TIMELINE_MAXIMUM_PIXELS_PER_BEAT_SCALE = 160.0 / 3.0;
constexpr auto PIANO_ROLL_MINIMUM_KEY_HEIGHT_SCALE = 1.0 / 3.0;
constexpr auto PIANO_ROLL_MAXIMUM_KEY_HEIGHT_SCALE = 8.0 / 3.0;
constexpr auto VELOCITY_HANDLE_MINIMUM_KEY_HEIGHT_SCALE = 1.0;
constexpr auto AUTOMATION_GRID_MINIMUM_CELL_WIDTH_SCALE = 4.0 / 3.0;
constexpr auto VELOCITY_HANDLE_TALL_NOTE_THRESHOLD_SCALE = 5.0 / 3.0;
constexpr auto VELOCITY_HANDLE_BAR_THICKNESS_SCALE = 1.0 / 6.0;
constexpr auto VELOCITY_HANDLE_INSET_SCALE = 1.0 / 6.0;
constexpr auto SELECTION_RING_DIP_WIDTH_SCALE = 1.0 / 8.0;
constexpr auto TIMELINE_DETAIL_MINIMUM_PIXELS_PER_BEAT_SCALE = 5.0 / 6.0;
constexpr auto GRID_LINE_STROKE_WIDTH_SCALE = 1.0 / 6.0;
constexpr auto TIME_RULER_MINIMUM_FONT_PIXEL_SIZE_SCALE = 1.0 / 12.0;
constexpr auto TIME_RULER_LETTER_SPACING_SCALE = -1.0 / 24.0;
constexpr auto TIME_RULER_BEAT_LABEL_ZOOM_FACTOR = 3.0;
constexpr auto MIDI_CURSOR_EXTENT_SCALE = 2.0;
constexpr auto PIANO_ROLL_NOTE_MINIMUM_WIDTH_SCALE = 1.0 / 6.0;
constexpr auto PIANO_ROLL_NOTE_MINIMUM_HEIGHT_SCALE = 1.0 / 6.0;
constexpr auto PIANO_ROLL_NOTE_EDGE_GRIP_REACH_SCALE = 0.25;
constexpr auto PIANO_ROLL_NOTE_MOVE_ZONE_MINIMUM_WIDTH_SCALE = 0.5;
constexpr auto NOTE_BORDER_DASH_LENGTH_SCALE = 1.0 / 3.0;
constexpr auto NOTE_BORDER_DASH_GAP_SCALE = 1.0 / 6.0;
constexpr auto KEYBOARD_HOVER_CHIP_FONT_PIXEL_SIZE_SCALE = 5.0 / 6.0;
constexpr auto KEYBOARD_HOVER_CHIP_HORIZONTAL_PADDING_SCALE = 2.0 / 3.0;
constexpr auto KEYBOARD_HOVER_CHIP_VERTICAL_PADDING_SCALE = 1.0 / 6.0;
constexpr auto KEYBOARD_HOVER_CHIP_RIGHT_INSET_SCALE = 1.0 / 6.0;
constexpr auto VELOCITY_LABEL_FIT_ALLOWANCE_SCALE = 1.0 / 3.0;
constexpr auto KEYBOARD_HOVER_CHIP_CORNER_RADIUS_SCALE = 0.25;
constexpr auto PIANO_KEYBOARD_LABEL_RIGHT_INSET_SCALE = 0.25;
constexpr auto OTHER_EVENT_HIT_SLOP_SCALE = 1.0 / 3.0;
constexpr auto OTHER_EVENT_MARKER_HALF_WIDTH_SCALE = 1.0 / 3.0;
constexpr auto OTHER_EVENT_MARKER_HALF_HEIGHT_SCALE = 5.0 / 12.0;
constexpr auto TRACK_HEADER_TEXT_LEFT_SCALE = 5.0 / 6.0;
constexpr auto TRACK_HEADER_REORDER_INDICATOR_HEIGHT_SCALE = 0.25;
constexpr auto PIANO_ROLL_INITIAL_VIEWPORT_HEIGHT_SCALE = 50.0 / 3.0;
constexpr auto TIMELINE_REVEAL_VIEWPORT_FRACTION = 1.0 / 3.0;
constexpr auto TIMELINE_VIEWPORT_MINIMUM_WIDTH_SCALE = 25.0 / 6.0;
constexpr auto TIMELINE_CONTENT_TAIL_WIDTH_SCALE = 25.0 / 3.0;

// Space tokens use their enum ordinal as the lookup key:
// token -> font-relative multiplier -> startup-resolved pixel value. Keeping
// the resolved pixels in ResolvedLayout makes space() a hot-path array lookup.
constexpr auto SPACE_MULTIPLIERS = std::array{0.0, 0.125, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0};
using ResolvedSpaces = std::array<int, SPACE_MULTIPLIERS.size()>;
// Pin every current public token to its positional multiplier. These checks
// fail if the existing enum order or table length changes independently.
static_assert(static_cast<std::size_t>(Space::Zero) == 0);
static_assert(static_cast<std::size_t>(Space::Half) == 1);
static_assert(static_cast<std::size_t>(Space::One) == 2);
static_assert(static_cast<std::size_t>(Space::Two) == 3);
static_assert(static_cast<std::size_t>(Space::Three) == 4);
static_assert(static_cast<std::size_t>(Space::Four) == 5);
static_assert(static_cast<std::size_t>(Space::Six) == 6);
static_assert(static_cast<std::size_t>(Space::Eight) + 1 == SPACE_MULTIPLIERS.size());

// Qt has one application stylesheet and one application event-filter chain.
// Retaining the pair makes repeated startup harmless while rejecting a second
// scale or QApplication that would otherwise split process-wide layout state.
struct ResolvedLayout {
    QApplication *application;
    int baseFontPx;
    ResolvedSpaces spaces;
    EditorGeometry editor;
    QString geometry;
};

std::optional<ResolvedLayout> resolvedLayout;

int resolve(double baseFontPx, double multiplier)
{
    Q_ASSERT(baseFontPx > 0.0);
    Q_ASSERT(multiplier >= 0.0);
    if (multiplier == 0.0)
        return 0;
    return qMax(1, qRound(baseFontPx * multiplier));
}

QString pixels(int value)
{
    return QString::number(value) + QStringLiteral("px");
}

std::size_t spaceIndex(Space token)
{
    const auto index = static_cast<std::size_t>(token);
    Q_ASSERT(index < SPACE_MULTIPLIERS.size());
    return index;
}

ResolvedSpaces resolveSpaces(int baseFontPx)
{
    // Rounding and minimum-size clamping happen once during initialization, not
    // in the paint and widget-layout paths that repeatedly call space().
    auto spaces = ResolvedSpaces{};
    std::transform(SPACE_MULTIPLIERS.cbegin(), SPACE_MULTIPLIERS.cend(), spaces.begin(),
                   [baseFontPx](double multiplier) { return resolve(baseFontPx, multiplier); });
    return spaces;
}

int resolvedSpace(const ResolvedSpaces &spaces, Space token)
{
    return spaces[spaceIndex(token)];
}

EditorGeometry resolveEditorGeometry(int baseFontPx)
{
    const auto trackHeaderWidth = resolve(baseFontPx, TRACK_HEADER_WIDTH_SCALE);
    const auto pianoKeyboardWidth = resolve(baseFontPx, PIANO_KEYBOARD_WIDTH_SCALE);
    const auto automationRowDefaultHeight =
        resolve(baseFontPx, AUTOMATION_ROW_DEFAULT_HEIGHT_SCALE);
    const auto automationRowMinimumHeight =
        resolve(baseFontPx, AUTOMATION_ROW_MINIMUM_HEIGHT_SCALE);
    const auto automationRowMaximumHeight =
        resolve(baseFontPx, AUTOMATION_ROW_MAXIMUM_HEIGHT_SCALE);
    const auto automationRowWheelIncrement =
        resolve(baseFontPx, AUTOMATION_ROW_WHEEL_INCREMENT_SCALE);
    const auto addAutomationLaneStripHeight =
        resolve(baseFontPx, ADD_AUTOMATION_LANE_STRIP_HEIGHT_SCALE);
    const auto editorDrawerResizeHandleHeight =
        resolve(baseFontPx, EDITOR_DRAWER_RESIZE_HANDLE_HEIGHT_SCALE);
    const auto minimumVisiblePianoRollHeight =
        resolve(baseFontPx, MINIMUM_VISIBLE_PIANO_ROLL_HEIGHT_SCALE);
    const auto automationPointHitRadius = resolve(baseFontPx, AUTOMATION_POINT_HIT_RADIUS_SCALE);
    const auto automationNeutralSnapRadius =
        resolve(baseFontPx, AUTOMATION_NEUTRAL_SNAP_RADIUS_SCALE);
    const auto automationDeleteTimeRadius =
        resolve(baseFontPx, AUTOMATION_DELETE_TIME_RADIUS_SCALE);
    const auto automationPointDetailThreshold =
        resolve(baseFontPx, AUTOMATION_POINT_DETAIL_THRESHOLD_SCALE);
    const auto automationHoverPaintPadding =
        resolve(baseFontPx, AUTOMATION_HOVER_PAINT_PADDING_SCALE);
    const auto velocityDensityThresholdD1 =
        resolve(baseFontPx, VELOCITY_DENSITY_THRESHOLD_D1_SCALE);
    const auto velocityDensityThresholdD2 =
        resolve(baseFontPx, VELOCITY_DENSITY_THRESHOLD_D2_SCALE);
    const auto velocityDensityThresholdD3 =
        resolve(baseFontPx, VELOCITY_DENSITY_THRESHOLD_D3_SCALE);
    const auto velocityDensityThresholdD4 =
        resolve(baseFontPx, VELOCITY_DENSITY_THRESHOLD_D4_SCALE);
    const auto velocityStartNodeHitRadius =
        resolve(baseFontPx, VELOCITY_START_NODE_HIT_RADIUS_SCALE);
    const auto velocityNodePaintRadius = baseFontPx * VELOCITY_NODE_PAINT_RADIUS_SCALE;
    const auto velocitySelectedNodeRingRadius =
        baseFontPx * VELOCITY_SELECTED_NODE_RING_RADIUS_SCALE;
    const auto velocityNodeOutlineDipWidth = baseFontPx * VELOCITY_NODE_OUTLINE_DIP_WIDTH_SCALE;
    const auto velocitySelectedNodeRingDipWidth =
        baseFontPx * VELOCITY_SELECTED_NODE_RING_DIP_WIDTH_SCALE;
    const auto velocityStemDipWidth = baseFontPx * VELOCITY_STEM_DIP_WIDTH_SCALE;
    const auto velocitySelectedStemDipWidth = baseFontPx * VELOCITY_SELECTED_STEM_DIP_WIDTH_SCALE;
    const auto velocityDurationLineVerticalRadius =
        resolve(baseFontPx, VELOCITY_DURATION_LINE_VERTICAL_RADIUS_SCALE);
    const auto velocityDurationLineHorizontalSlop =
        resolve(baseFontPx, VELOCITY_DURATION_LINE_HORIZONTAL_SLOP_SCALE);
    const auto velocityRelativeDragActivationDistance =
        resolve(baseFontPx, VELOCITY_RELATIVE_DRAG_ACTIVATION_DISTANCE_SCALE);
    const auto editorDefaultPixelsPerBeat =
        resolve(baseFontPx, EDITOR_DEFAULT_PIXELS_PER_BEAT_SCALE);
    const auto voicePickerDialogWidth = resolve(baseFontPx, VOICE_PICKER_DIALOG_WIDTH_SCALE);
    const auto voicePickerDialogHeight = resolve(baseFontPx, VOICE_PICKER_DIALOG_HEIGHT_SCALE);
    const auto trackHeaderButtonExtent = resolve(baseFontPx, TRACK_HEADER_BUTTON_EXTENT_SCALE);
    const auto trackHeaderRowHeight = resolve(baseFontPx, TRACK_HEADER_ROW_HEIGHT_SCALE);
    const auto trackHeaderButtonColumnWidth =
        resolve(baseFontPx, TRACK_HEADER_BUTTON_COLUMN_WIDTH_SCALE);
    const auto trackHeaderVoiceLineLeft = resolve(baseFontPx, TRACK_HEADER_VOICE_LINE_LEFT_SCALE);
    const auto trackHeaderVoiceLineTop = resolve(baseFontPx, TRACK_HEADER_VOICE_LINE_TOP_SCALE);
    const auto trackHeaderVoiceLineRight = resolve(baseFontPx, TRACK_HEADER_VOICE_LINE_RIGHT_SCALE);
    const auto trackHeaderVoiceLineHeight =
        resolve(baseFontPx, TRACK_HEADER_VOICE_LINE_HEIGHT_SCALE);
    const auto trackHeaderRenameEditorLeft =
        resolve(baseFontPx, TRACK_HEADER_RENAME_EDITOR_LEFT_SCALE);
    const auto trackHeaderRenameEditorTop =
        resolve(baseFontPx, TRACK_HEADER_RENAME_EDITOR_TOP_SCALE);
    const auto trackHeaderRenameEditorRight =
        resolve(baseFontPx, TRACK_HEADER_RENAME_EDITOR_RIGHT_SCALE);
    const auto trackHeaderRenameEditorHeight =
        resolve(baseFontPx, TRACK_HEADER_RENAME_EDITOR_HEIGHT_SCALE);
    const auto timelineMinimumPixelsPerBeat =
        resolve(baseFontPx, TIMELINE_MINIMUM_PIXELS_PER_BEAT_SCALE);
    const auto timelineMaximumPixelsPerBeat =
        resolve(baseFontPx, TIMELINE_MAXIMUM_PIXELS_PER_BEAT_SCALE);
    const auto pianoRollMinimumKeyHeight = resolve(baseFontPx, PIANO_ROLL_MINIMUM_KEY_HEIGHT_SCALE);
    const auto pianoRollMaximumKeyHeight = resolve(baseFontPx, PIANO_ROLL_MAXIMUM_KEY_HEIGHT_SCALE);
    const auto velocityHandleMinimumKeyHeight =
        resolve(baseFontPx, VELOCITY_HANDLE_MINIMUM_KEY_HEIGHT_SCALE);
    const auto automationGridMinimumCellWidth =
        resolve(baseFontPx, AUTOMATION_GRID_MINIMUM_CELL_WIDTH_SCALE);
    const auto velocityHandleTallNoteThreshold =
        resolve(baseFontPx, VELOCITY_HANDLE_TALL_NOTE_THRESHOLD_SCALE);
    const auto velocityHandleBarThickness =
        resolve(baseFontPx, VELOCITY_HANDLE_BAR_THICKNESS_SCALE);
    const auto velocityHandleInset = resolve(baseFontPx, VELOCITY_HANDLE_INSET_SCALE);
    const auto selectionRingDipWidth = baseFontPx * SELECTION_RING_DIP_WIDTH_SCALE;
    const auto timelineDetailMinimumPixelsPerBeat =
        resolve(baseFontPx, TIMELINE_DETAIL_MINIMUM_PIXELS_PER_BEAT_SCALE);
    const auto gridLineStrokeWidth = resolve(baseFontPx, GRID_LINE_STROKE_WIDTH_SCALE);
    const auto timeRulerMinimumFontPixelSize =
        resolve(baseFontPx, TIME_RULER_MINIMUM_FONT_PIXEL_SIZE_SCALE);
    const auto timeRulerLetterSpacing = baseFontPx * TIME_RULER_LETTER_SPACING_SCALE;
    const auto timeRulerBeatLabelZoomFactor = TIME_RULER_BEAT_LABEL_ZOOM_FACTOR;
    const auto midiCursorExtent = resolve(baseFontPx, MIDI_CURSOR_EXTENT_SCALE);
    const auto pianoRollNoteMinimumWidth = resolve(baseFontPx, PIANO_ROLL_NOTE_MINIMUM_WIDTH_SCALE);
    const auto pianoRollNoteMinimumHeight =
        resolve(baseFontPx, PIANO_ROLL_NOTE_MINIMUM_HEIGHT_SCALE);
    const auto pianoRollNoteEdgeGripReach = baseFontPx * PIANO_ROLL_NOTE_EDGE_GRIP_REACH_SCALE;
    const auto pianoRollNoteMoveZoneMinimumWidth =
        baseFontPx * PIANO_ROLL_NOTE_MOVE_ZONE_MINIMUM_WIDTH_SCALE;
    const auto noteBorderDashLength = resolve(baseFontPx, NOTE_BORDER_DASH_LENGTH_SCALE);
    const auto noteBorderDashGap = resolve(baseFontPx, NOTE_BORDER_DASH_GAP_SCALE);
    const auto keyboardHoverChipFontPixelSize =
        resolve(baseFontPx, KEYBOARD_HOVER_CHIP_FONT_PIXEL_SIZE_SCALE);
    const auto keyboardHoverChipHorizontalPadding =
        resolve(baseFontPx, KEYBOARD_HOVER_CHIP_HORIZONTAL_PADDING_SCALE);
    const auto keyboardHoverChipVerticalPadding =
        resolve(baseFontPx, KEYBOARD_HOVER_CHIP_VERTICAL_PADDING_SCALE);
    const auto keyboardHoverChipRightInset =
        resolve(baseFontPx, KEYBOARD_HOVER_CHIP_RIGHT_INSET_SCALE);
    const auto velocityLabelFitAllowance = resolve(baseFontPx, VELOCITY_LABEL_FIT_ALLOWANCE_SCALE);
    const auto keyboardHoverChipCornerRadius =
        resolve(baseFontPx, KEYBOARD_HOVER_CHIP_CORNER_RADIUS_SCALE);
    const auto pianoKeyboardLabelRightInset =
        resolve(baseFontPx, PIANO_KEYBOARD_LABEL_RIGHT_INSET_SCALE);
    const auto otherEventHitSlop = resolve(baseFontPx, OTHER_EVENT_HIT_SLOP_SCALE);
    const auto otherEventMarkerHalfWidth = resolve(baseFontPx, OTHER_EVENT_MARKER_HALF_WIDTH_SCALE);
    const auto otherEventMarkerHalfHeight =
        resolve(baseFontPx, OTHER_EVENT_MARKER_HALF_HEIGHT_SCALE);
    const auto trackHeaderTextLeft = resolve(baseFontPx, TRACK_HEADER_TEXT_LEFT_SCALE);
    const auto trackHeaderReorderIndicatorHeight =
        resolve(baseFontPx, TRACK_HEADER_REORDER_INDICATOR_HEIGHT_SCALE);
    const auto pianoRollInitialViewportHeight =
        resolve(baseFontPx, PIANO_ROLL_INITIAL_VIEWPORT_HEIGHT_SCALE);
    const auto timelineRevealViewportFraction = TIMELINE_REVEAL_VIEWPORT_FRACTION;
    const auto timelineViewportMinimumWidth =
        resolve(baseFontPx, TIMELINE_VIEWPORT_MINIMUM_WIDTH_SCALE);
    const auto timelineContentTailWidth = resolve(baseFontPx, TIMELINE_CONTENT_TAIL_WIDTH_SCALE);
    return {
        trackHeaderWidth,
        pianoKeyboardWidth,
        automationRowDefaultHeight,
        automationRowMinimumHeight,
        automationRowMaximumHeight,
        automationRowWheelIncrement,
        addAutomationLaneStripHeight,
        editorDrawerResizeHandleHeight,
        minimumVisiblePianoRollHeight,
        automationPointHitRadius,
        automationNeutralSnapRadius,
        automationDeleteTimeRadius,
        automationPointDetailThreshold,
        automationHoverPaintPadding,
        velocityDensityThresholdD1,
        velocityDensityThresholdD2,
        velocityDensityThresholdD3,
        velocityDensityThresholdD4,
        velocityStartNodeHitRadius,
        velocityNodePaintRadius,
        velocitySelectedNodeRingRadius,
        velocityNodeOutlineDipWidth,
        velocitySelectedNodeRingDipWidth,
        velocityStemDipWidth,
        velocitySelectedStemDipWidth,
        velocityDurationLineVerticalRadius,
        velocityDurationLineHorizontalSlop,
        velocityRelativeDragActivationDistance,
        trackHeaderWidth + pianoKeyboardWidth,
        editorDefaultPixelsPerBeat,
        voicePickerDialogWidth,
        voicePickerDialogHeight,
        trackHeaderButtonExtent,
        trackHeaderRowHeight,
        trackHeaderButtonColumnWidth,
        trackHeaderVoiceLineLeft,
        trackHeaderVoiceLineTop,
        trackHeaderVoiceLineRight,
        trackHeaderVoiceLineHeight,
        trackHeaderRenameEditorLeft,
        trackHeaderRenameEditorTop,
        trackHeaderRenameEditorRight,
        trackHeaderRenameEditorHeight,
        timelineMinimumPixelsPerBeat,
        timelineMaximumPixelsPerBeat,
        pianoRollMinimumKeyHeight,
        pianoRollMaximumKeyHeight,
        velocityHandleMinimumKeyHeight,
        automationGridMinimumCellWidth,
        velocityHandleTallNoteThreshold,
        velocityHandleBarThickness,
        velocityHandleInset,
        selectionRingDipWidth,
        timelineDetailMinimumPixelsPerBeat,
        gridLineStrokeWidth,
        timeRulerMinimumFontPixelSize,
        timeRulerLetterSpacing,
        timeRulerBeatLabelZoomFactor,
        midiCursorExtent,
        pianoRollNoteMinimumWidth,
        pianoRollNoteMinimumHeight,
        pianoRollNoteEdgeGripReach,
        pianoRollNoteMoveZoneMinimumWidth,
        noteBorderDashLength,
        noteBorderDashGap,
        keyboardHoverChipFontPixelSize,
        keyboardHoverChipHorizontalPadding,
        keyboardHoverChipVerticalPadding,
        keyboardHoverChipRightInset,
        velocityLabelFitAllowance,
        keyboardHoverChipCornerRadius,
        pianoKeyboardLabelRightInset,
        otherEventHitSlop,
        otherEventMarkerHalfWidth,
        otherEventMarkerHalfHeight,
        trackHeaderTextLeft,
        trackHeaderReorderIndicatorHeight,
        pianoRollInitialViewportHeight,
        timelineRevealViewportFraction,
        timelineViewportMinimumWidth,
        timelineContentTailWidth,
    };
}

FontScaledGeometry resolveGeometry(int baseFontPx, const ResolvedSpaces &spaces)
{
    const auto comboDropDownLane = resolve(baseFontPx, 1.25);
    return {
        singlePixel(),
        resolvedSpace(spaces, Space::Zero),
        resolvedSpace(spaces, Space::Half),
        resolvedSpace(spaces, Space::One),
        resolvedSpace(spaces, Space::Two),
        comboDropDownLane,
        qMax(singlePixel(), comboDropDownLane - 2 * singlePixel()),
        resolvedSpace(spaces, Space::Eight),
        resolve(baseFontPx, 0.9),
        resolve(baseFontPx, 1.2),
    };
}

QString commonGeometryStyleSheet(const FontScaledGeometry &geometry)
{
    return QStringLiteral("QPushButton,QToolButton,QTabBar::tab,QAbstractSpinBox,"
                          "QLineEdit,QTextEdit,QPlainTextEdit,QCheckBox,QRadioButton,"
                          "QGroupBox,QMenu,QToolTip,QAbstractItemView,QScrollBar,"
                          "QScrollBar::handle,QSplitter::handle,"
                          "QFrame#vgSamplePickerPopup{"
                          "border:%1 solid transparent;border-radius:%2;}"
                          "QHeaderView::section{border:0;}"
                          "QPushButton{padding:%5 %6;}"
                          "QMenu::item{padding-left:%3;padding-right:%3;}"
                          "QMenu::item{padding-top:%4;padding-bottom:%4;}"
                          "QCheckBox::indicator,QRadioButton::indicator,"
                          "QAbstractSpinBox::up-button,QAbstractSpinBox::down-button{"
                          "border:%1 solid transparent;border-radius:%2;}")
        .arg(pixels(geometry.border), pixels(geometry.zero), pixels(geometry.two),
             pixels(geometry.one), pixels(singlePixel()), pixels(geometry.two + singlePixel()));
}

QString comboBoxGeometryStyleSheet(const FontScaledGeometry &geometry)
{
    // Popup width is measured from content and live Qt style metrics by the
    // private Layout popup filter; do not fix the dropdown width here.
    return QStringLiteral("QComboBox{border:%1 solid transparent;border-radius:%5;"
                          "padding:%3 %4 %3 %5;}"
                          "QComboBox QLineEdit{background-color:transparent;"
                          "border:%2;padding:%2;}"
                          "QComboBox::drop-down{subcontrol-origin:border;"
                          "subcontrol-position:top right;width:%6;"
                          "border:%1 solid transparent;border-radius:%2;}"
                          "QComboBox QAbstractItemView{border:%1 solid transparent;"
                          "border-radius:%2;padding:%2;}"
                          "QComboBox QAbstractItemView::item{padding:%3 %5;}")
        .arg(pixels(geometry.border), pixels(geometry.zero), pixels(geometry.half),
             pixels(geometry.comboDropDownLane), pixels(geometry.one),
             pixels(geometry.comboDropDownWidth));
}

QString tabGeometryStyleSheet(const FontScaledGeometry &geometry)
{
    // Vertical tab metrics must stay in step with chromeRowHeight(); only the
    // horizontal padding is free to breathe.
    return QStringLiteral("QTabBar::tab{margin-top:%1;padding:%1 %2;}")
        .arg(pixels(geometry.half), pixels(geometry.two));
}

// The stylesheet renderer drops the native style's built-in breathing room
// and subcontrol art the moment a widget family is themed. These rules give
// every styled family back font-derived padding, correctly shaped check and
// radio indicators, a reserved group-box title band, and a full spin-button
// lane (whose arrow glyphs the theme sheet supplies as generated images).
QString comfortGeometryStyleSheet(const FontScaledGeometry &geometry)
{
    auto sheet =
        QStringLiteral("QMenuBar::item{padding:%1 %2;}"
                       "QMenu{padding:%3 0px;}"
                       "QMenu::separator{height:%4;margin:%3 %2;}"
                       "QToolTip{padding:%3 %1;}"
                       "QLineEdit,QTextEdit,QPlainTextEdit,QAbstractSpinBox{padding:%3 %1;}"
                       "QLineEdit,QTextEdit,QPlainTextEdit{border-radius:%1;}"
                       "QLineEdit QToolButton{border:0;border-radius:0;padding:0;}"
                       "QAbstractSpinBox{border-radius:%1;}"
                       "QAbstractSpinBox QLineEdit{border:0;padding:0;}"
                       "QHeaderView::section{padding:%3 %1;}")
            .arg(pixels(geometry.one), pixels(geometry.two), pixels(geometry.half),
                 pixels(geometry.border));
    sheet += QStringLiteral("QCheckBox,QRadioButton{spacing:%1;}"
                            "QCheckBox::indicator,QRadioButton::indicator{width:%2;height:%2;}"
                            "QRadioButton::indicator{border-radius:%3;}")
                 .arg(pixels(geometry.one), pixels(geometry.indicatorExtent),
                      pixels((geometry.indicatorExtent + 2 * geometry.border) / 2));
    // Checkable menu items share the checkbox indicator; every item indents
    // past the indicator column so labels align whether checkable or not.
    sheet +=
        QStringLiteral("QMenu::item{padding-left:%1;}"
                       "QMenu::indicator{width:%2;height:%2;left:%3;"
                       "subcontrol-origin:border;subcontrol-position:left center;"
                       "border:%4 solid transparent;}")
            .arg(pixels(geometry.indicatorExtent + 2 * geometry.one + 2 * geometry.border),
                 pixels(geometry.indicatorExtent), pixels(geometry.one), pixels(geometry.border));
    sheet +=
        QStringLiteral("QGroupBox{margin-top:%1;padding-top:%2;}"
                       "QGroupBox::title{subcontrol-origin:margin;"
                       "subcontrol-position:top left;left:%3;padding:0 %2;}")
            .arg(pixels(geometry.groupBoxTitleBand), pixels(geometry.half), pixels(geometry.one));
    // No ::up-arrow/::down-arrow rules on purpose: with none present the
    // stylesheet renderer draws the base style's arrow primitive in the
    // theme's foreground, exactly like the combo drop-down arrow.
    sheet += QStringLiteral("QAbstractSpinBox{padding-right:%1;}"
                            "QAbstractSpinBox::up-button{subcontrol-origin:border;"
                            "subcontrol-position:top right;width:%1;}"
                            "QAbstractSpinBox::down-button{subcontrol-origin:border;"
                            "subcontrol-position:bottom right;width:%1;}")
                 .arg(pixels(geometry.comboDropDownLane));
    return sheet;
}

QString listPositionIndicatorGeometryStyleSheet(const FontScaledGeometry &geometry)
{
    return QStringLiteral("QScrollBar#listPositionIndicator:vertical{width:%1;margin:%2;"
                          "padding:%2;border-width:%2;}"
                          "QScrollBar#listPositionIndicator::handle:vertical{"
                          "min-height:%3;border-width:%2;}"
                          "QScrollBar#listPositionIndicator::add-line:vertical,"
                          "QScrollBar#listPositionIndicator::sub-line:vertical{"
                          "height:%2;border-width:%2;}"
                          "QScrollBar#listPositionIndicator::up-arrow:vertical,"
                          "QScrollBar#listPositionIndicator::down-arrow:vertical{"
                          "width:%2;height:%2;}")
        .arg(pixels(geometry.two), pixels(geometry.zero),
             pixels(geometry.listPositionIndicatorMinimumLength));
}

QString toolbarGeometryStyleSheet(const FontScaledGeometry &geometry)
{
    // A real (transparent at rest) border lets the theme sheet surface the
    // pressed-state outline; the small radius softens the hover/checked fills.
    return QStringLiteral("QToolBar#transportToolbar QToolButton{"
                          "border:%1 solid transparent;border-radius:%2;"
                          "padding:%2;}")
        .arg(pixels(geometry.border), pixels(geometry.half));
}

QString buildGeometryStyleSheet(int baseFontPx, const ResolvedSpaces &spaces)
{
    const auto geometry = resolveGeometry(baseFontPx, spaces);
    return commonGeometryStyleSheet(geometry) + comboBoxGeometryStyleSheet(geometry) +
           tabGeometryStyleSheet(geometry) + comfortGeometryStyleSheet(geometry) +
           listPositionIndicatorGeometryStyleSheet(geometry) + toolbarGeometryStyleSheet(geometry);
}

QComboBox *comboForPopup(QAbstractItemView &view)
{
    for (auto *parent = view.parent(); parent; parent = parent->parent()) {
        if (auto *combo = qobject_cast<QComboBox *>(parent))
            return combo;
    }
    return nullptr;
}

// Begin at the closed-control width so opening a popup may only make the popup
// wider. Model and style metrics stay live because either may change at
// runtime.
int popupContentWidth(const QComboBox &combo)
{
    const auto *view = combo.view();
    const auto *model = view->model();
    auto width = combo.width();
    for (auto row = 0; row < model->rowCount(view->rootIndex()); ++row) {
        const auto index = model->index(row, 0, view->rootIndex());
        width = std::max(width, view->sizeHintForIndex(index).width());
    }
    const auto *style = combo.style();
    const auto checkmarkWidth = style->pixelMetric(QStyle::PM_IndicatorWidth, nullptr, &combo);
    const auto focusMargin = style->pixelMetric(QStyle::PM_FocusFrameHMargin, nullptr, &combo);
    const auto margins = view->contentsMargins();
    return width + checkmarkWidth + 2 * focusMargin + margins.left() + margins.right() +
           2 * view->frameWidth();
}

// Qt styles wrap ComboBox views in platform-specific popup frames. Flatten each
// layer here so Layout's item padding is not compounded by native containers.
void flattenPopup(QComboBox &combo)
{
    auto *view = combo.view();
    view->setFrameShape(QFrame::NoFrame);
    view->setContentsMargins(0, 0, 0, 0);

    auto *popup = view->window();
    if (!popup || popup == combo.window())
        return;
    if (auto *frame = qobject_cast<QFrame *>(popup)) {
        frame->setFrameShape(QFrame::NoFrame);
        frame->setLineWidth(0);
        frame->setMidLineWidth(0);
    }
    popup->setContentsMargins(0, 0, 0, 0);
    if (auto *layout = popup->layout()) {
        layout->setContentsMargins(0, 0, 0, 0);
        layout->setSpacing(0);
    }
    auto palette = popup->palette();
    palette.setColor(QPalette::Window, view->palette().color(QPalette::Base));
    popup->setPalette(palette);
    popup->setAutoFillBackground(true);
}

// Set minimum widths only on the view/window; resizing the QComboBox here would
// make opening the popup permanently alter its closed layout.
void resizePopup(QComboBox &combo)
{
    auto *view = combo.view();
    const auto contentWidth = popupContentWidth(combo);
    view->setMinimumWidth(contentWidth);
    auto *popup = view->window();
    if (!popup || popup == combo.window())
        return;
    const auto margins = popup->contentsMargins();
    const auto popupWidth = contentWidth + margins.left() + margins.right();
    popup->setMinimumWidth(popupWidth);
    if (popup->width() < popupWidth)
        popup->resize(popupWidth, popup->height());
}

// Some styles add visible popup siblings such as scrollers. Only fill the whole
// container when the item view is the sole visible popup content.
void fillPopupContainer(QComboBox &combo)
{
    auto *view = combo.view();
    auto *popup = view->window();
    if (!popup || popup == combo.window())
        return;
    for (auto *child : popup->children()) {
        auto *sibling = qobject_cast<QWidget *>(child);
        if (sibling && sibling != view && sibling->isVisible())
            return;
    }
    if (auto *layout = popup->layout())
        layout->activate();
    view->setGeometry(popup->contentsRect());
}

void paintComboBox(QComboBox &combo)
{
    QStyleOptionComboBox option;
    option.initFrom(&combo);
    option.editable = combo.isEditable();
    option.frame = combo.hasFrame();
    option.currentIcon = combo.itemIcon(combo.currentIndex());
    option.currentText = combo.currentText();
    option.iconSize = combo.iconSize();
    option.subControls = QStyle::SC_All;
    const auto arrowRect = combo.style()->subControlRect(QStyle::CC_ComboBox, &option,
                                                         QStyle::SC_ComboBoxArrow, &combo);
    const auto arrowHovered = option.state & QStyle::State_MouseOver &&
                              arrowRect.contains(combo.mapFromGlobal(QCursor::pos()));
    if (arrowHovered)
        option.activeSubControls = QStyle::SC_ComboBoxArrow;
    if (combo.view()->isVisible()) {
        option.activeSubControls = QStyle::SC_ComboBoxArrow;
        option.state |= QStyle::State_On;
    }
    QPainter painter(&combo);
    combo.style()->drawComplexControl(QStyle::CC_ComboBox, &option, &painter, &combo);
    if (!combo.isEditable())
        combo.style()->drawControl(QStyle::CE_ComboBoxLabel, &option, &painter, &combo);
    const auto center = arrowRect.center() + QPoint(1, 0);
    const auto halfWidth = qMax(2, arrowRect.width() / 4);
    const auto halfHeight = qMax(1, halfWidth / 2);
    const QPoint points[] = {
        {center.x() - halfWidth, center.y() - halfHeight},
        {center.x() + halfWidth, center.y() - halfHeight},
        {center.x(), center.y() + halfHeight},
    };
    const auto colorGroup = combo.isEnabled() ? QPalette::Active : QPalette::Disabled;
    painter.setPen(Qt::NoPen);
    painter.setBrush(combo.palette().color(colorGroup, QPalette::ButtonText));
    painter.drawPolygon(points, 3);
}

// QEvent::Show is late enough for the popup's live model, style, and wrapper
// window to exist. Always return false so Qt still performs the actual show.
class PopupSizingFilter final : public QObject
{
  public:
    explicit PopupSizingFilter(QObject *parent) : QObject(parent) {}

    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (event->type() == QEvent::Paint) {
            if (auto *combo = qobject_cast<QComboBox *>(watched)) {
                paintComboBox(*combo);
                return true;
            }
            return false;
        }
        if (event->type() != QEvent::Show)
            return false;
        auto *view = qobject_cast<QAbstractItemView *>(watched);
        if (!view)
            return false;
        if (auto *combo = comboForPopup(*view)) {
            flattenPopup(*combo);
            resizePopup(*combo);
            fillPopupContainer(*combo);
        }
        return false;
    }
};

const ResolvedLayout &currentLayout()
{
    Q_ASSERT(resolvedLayout);
    return *resolvedLayout;
}

} // namespace

// Validate before the idempotence check: initialize(application, 0) must never
// report success merely because a valid layout was established earlier.
bool initialize(QApplication &application, int baseFontPx)
{
    if (baseFontPx <= 0)
        return false;
    if (resolvedLayout) {
        const auto &resolved = *resolvedLayout;
        return resolved.application == &application && resolved.baseFontPx == baseFontPx;
    }
    // Resolve the complete spacing scale before publishing process-wide state.
    // The stylesheet and later space() calls then consume the same pixel values.
    const auto spaces = resolveSpaces(baseFontPx);
    const auto editor = resolveEditorGeometry(baseFontPx);
    resolvedLayout = ResolvedLayout{&application, baseFontPx, spaces, editor,
                                    buildGeometryStyleSheet(baseFontPx, spaces)};
    application.setStyleSheet(resolvedLayout->geometry);
    // QApplication owns the filter. The initialization guard above ensures only
    // one filter is installed for the process-wide Layout state.
    application.installEventFilter(new PopupSizingFilter(&application));
    return true;
}

int space(Space token)
{
    const auto &resolved = currentLayout();
    return resolvedSpace(resolved.spaces, token);
}

int fontPx(double multiplier)
{
    return resolve(currentLayout().baseFontPx, multiplier);
}

int singlePixel()
{
    return 1;
}

const EditorGeometry &editorGeometry()
{
    return currentLayout().editor;
}
qreal velocityHandlePointerHitPadding(qreal noteHeight, qreal physicalPixel)
{
    const auto physicalNoteHeight = qRound(noteHeight / physicalPixel);
    const auto paddingPixels = std::clamp(physicalNoteHeight / 6, 2, 4);
    return paddingPixels * physicalPixel;
}

TwoLineTextLayout::TwoLineTextLayout(const QFont &primary, const QFont &alternatePrimary,
                                     const QFont &secondary, Space gap)
    : m_primaryHeight(
          qMax(QFontMetrics(primary).lineSpacing(), QFontMetrics(alternatePrimary).lineSpacing()))
    , m_secondaryHeight(QFontMetrics(secondary).lineSpacing())
    , m_gap(space(gap))
{}

int TwoLineTextLayout::height() const
{
    return m_primaryHeight + m_gap + m_secondaryHeight;
}

TwoLineTextBoxes TwoLineTextLayout::align(const QRect &bounds,
                                          VerticalAlignment verticalAlignment) const
{
    auto top = bounds.top();
    switch (verticalAlignment) {
    case VerticalAlignment::Top:
        break;
    case VerticalAlignment::Center:
        top += (bounds.height() - height()) / 2;
        break;
    case VerticalAlignment::Bottom:
        top += bounds.height() - height();
        break;
    }

    return {
        QRect(bounds.left(), top, bounds.width(), m_primaryHeight),
        QRect(bounds.left(), top + m_primaryHeight + m_gap, bounds.width(), m_secondaryHeight),
    };
}

TwoLineTextLayout twoLineText(const QFont &primary, const QFont &alternatePrimary,
                              const QFont &secondary, Space gap)
{
    return TwoLineTextLayout(primary, alternatePrimary, secondary, gap);
}

int chromeRowHeight(const QFont &applicationFont, int iconExtent)
{
    return qMax(QFontMetrics(applicationFont).lineSpacing(), iconExtent) + 2 * space(Space::Half) +
           2 * singlePixel();
}

QString composeStyleSheet(const QString &colorStyleSheet)
{
    return currentLayout().geometry + colorStyleSheet;
}
// For a consistent scrollbar everywhere.
void configureListPositionIndicator(QScrollBar &scrollBar)
{
    scrollBar.setObjectName(QStringLiteral("listPositionIndicator"));
    scrollBar.style()->unpolish(&scrollBar);
    scrollBar.style()->polish(&scrollBar);
}

} // namespace layout
