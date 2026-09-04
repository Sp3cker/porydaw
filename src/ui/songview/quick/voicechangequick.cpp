#include "ui/editordrawer/voicechangearea/voicechangearea.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <span>
#include <vector>

#include <QFontMetrics>

#include "core/miditimeline.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/timecamera.h"
#include "ui/theme/themeruntime.h"
#include "ui/theme/trackidentitycolors.h"

namespace lyt = ::layout;
using Space = lyt::Space;

namespace {

constexpr quint64 kVoiceTitleTextKey = std::numeric_limits<quint64>::max();
constexpr quint64 kVoiceSummaryTextKey = kVoiceTitleTextKey - 1;
constexpr quint64 kVoiceReadoutTextKey = kVoiceTitleTextKey - 2;

QRectF heldSpanRect(uint64_t beginTick, uint64_t endTick, const songview::TimeCamera &camera,
                    const QRectF &plot)
{
    const qreal left = std::max<qreal>(0.0, camera.contentX(double(beginTick)));
    const qreal right = std::min<qreal>(plot.width(), camera.contentX(double(endTick)));
    if (right <= left)
        return {};
    return QRectF(left, 0.0, right - left, plot.height());
}

void appendText(std::vector<songview::TimelineQuickTextModel::Record> &records, quint64 ordinal,
                const QRectF &rect, const QString &text, const QColor &color, const QFont &font,
                Qt::Alignment horizontalAlignment, Qt::Alignment verticalAlignment)
{
    if (rect.width() <= 0.0 || rect.height() <= 0.0)
        return;
    records.push_back({{songview::TimelineQuickTextKeyKind::VoiceChanges, {}, ordinal},
                       rect,
                       text,
                       color,
                       font,
                       horizontalAlignment,
                       verticalAlignment});
}

} // namespace

void VoiceChangeArea::rebuildQuickScene(songview::TimelineQuickScene &scene)
{
    using namespace songview;
    constexpr std::array layers = {
        TimelineQuickLayer::VoiceChangesGutterChrome, TimelineQuickLayer::VoiceChangesChrome,
        TimelineQuickLayer::VoiceChangesGrid,         TimelineQuickLayer::VoiceChangesSpans,
        TimelineQuickLayer::VoiceChangesMarkers,      TimelineQuickLayer::VoiceChangesTransient,
        TimelineQuickLayer::VoiceChangesHover,
    };
    for (const TimelineQuickLayer layer : layers)
        timeline_quick::resetLayer(scene, layer);
    scene.setVoiceChangesGutterTextRecords({});
    scene.setVoiceChangesTextRecords({});
    scene.setVoiceChangesHoverTextRecords({});

    const QRectF sceneBounds = bounds();
    const QRectF plot(QPointF(), sceneBounds.size());
    const QRectF gutter = gutterRect();
    if (plot.width() <= 0.0 || plot.height() <= 0.0)
        return;

    const QColor background = themes::color(themes::Role::song_view_piano_roll_background);
    constexpr TimelineQuickLayer gutterChromeLayer = TimelineQuickLayer::VoiceChangesGutterChrome;
    constexpr TimelineQuickLayer chromeLayer = TimelineQuickLayer::VoiceChangesChrome;
    if (gutter.width() > 0.0) {
        timeline_quick::addRect(scene, gutterChromeLayer, gutter, background, gutter);
        timeline_quick::addHorizontalLine(scene, gutterChromeLayer, gutter.left(), gutter.right(),
                                          gutter.bottom(), lyt::singlePixel(),
                                          themes::color(themes::Role::song_view_separator), gutter);
    }
    timeline_quick::addRect(scene, chromeLayer, plot, background, plot);
    timeline_quick::addHorizontalLine(scene, chromeLayer, plot.left(), plot.right(), plot.bottom(),
                                      lyt::singlePixel(),
                                      themes::color(themes::Role::song_view_separator), plot);

    std::vector<TimelineQuickTextModel::Record> gutterTextRecords;
    const int gutterMargin = lyt::space(Space::Zero);
    const QRect gutterTextBounds(gutterMargin, 0,
                                 std::max(0, qRound(gutter.width()) - 2 * gutterMargin),
                                 qRound(gutter.height()));
    const lyt::TwoLineTextBoxes textBoxes =
        m_textLayout.align(gutterTextBounds, lyt::VerticalAlignment::Center);
    const QColor primaryText = themes::color(themes::Role::song_view_primary_text);
    const QColor secondaryText = themes::color(themes::Role::song_view_secondary_text);
    appendText(gutterTextRecords, kVoiceTitleTextKey, QRectF(textBoxes.primary), tr("Voice"),
               primaryText, m_titleFont, Qt::AlignLeft, Qt::AlignVCenter);

    SongDocument *document = m_owner.document();
    if (document && m_engineTrack >= 0) {
        const int changeCount = int(m_voicePoints.size());
        if (m_changeCount != changeCount) {
            m_secondary = changeCount
                              ? tr("%n change(s) · double-click to edit", nullptr, changeCount)
                              : tr("no voice set · double-click to add");
            m_changeCount = changeCount;
        }
        appendText(gutterTextRecords, kVoiceSummaryTextKey, QRectF(textBoxes.secondary),
                   m_secondary, secondaryText, m_captionFont, Qt::AlignLeft, Qt::AlignVCenter);
    }
    scene.setVoiceChangesGutterTextRecords(gutterTextRecords);

    std::vector<TimelineQuickTextModel::Record> plotTextRecords;
    const QRect plotRect = plot.toRect();
    if (!document) {
        appendText(plotTextRecords, kVoiceReadoutTextKey, plot, tr("Voice changes are read-only"),
                   secondaryText, m_captionFont, Qt::AlignCenter, Qt::AlignVCenter);
        scene.setVoiceChangesTextRecords(plotTextRecords);
        return;
    }

    const MidiTimeline *timeline = m_owner.timeline();
    if (!timeline || m_engineTrack < 0 || m_engineTrack >= 16) {
        appendText(plotTextRecords, kVoiceReadoutTextKey, plot, tr("No track selected"),
                   secondaryText, m_captionFont, Qt::AlignCenter, Qt::AlignVCenter);
        scene.setVoiceChangesTextRecords(plotTextRecords);
        return;
    }
    if (plotRect.width() <= 0 || plotRect.height() <= 0) {
        scene.setVoiceChangesTextRecords(plotTextRecords);
        return;
    }

    const int track = m_engineTrack;
    const qreal dpr = devicePixelRatio();
    const bool previewing = voiceDragActive();
    if (previewing) {
        m_previewEntries.clear();
        m_previewEntries.reserve(m_voicePoints.size());
        for (const DocLanePoint &point : m_voicePoints) {
            const bool dragged = m_voiceDrag->point.smfTrack == point.smfTrack &&
                                 m_voiceDrag->point.index == point.index;
            m_previewEntries.push_back(
                {dragged ? m_voiceDrag->previewTick : point.tick, point.value});
        }
        std::stable_sort(m_previewEntries.begin(), m_previewEntries.end(),
                         [](const VoicePaintEntry &left, const VoicePaintEntry &right) {
                             return left.tick < right.tick;
                         });
    }
    const std::size_t paintEntryCount = previewing ? m_previewEntries.size() : m_voicePoints.size();
    const auto paintEntryAt = [this, previewing](std::size_t index) {
        if (previewing)
            return m_previewEntries[index];
        const DocLanePoint &point = m_voicePoints[index];
        return VoicePaintEntry{point.tick, point.value};
    };

    timeline_quick::composeBandedGrid(scene, TimelineQuickLayer::VoiceChangesGrid, m_owner, plot, 0,
                                      dpr);
    const QColor trackColor =
        themes::trackIdentityColor(std::size_t(track % themes::trackIdentityColorCount));
    QColor heldColor = trackColor;
    heldColor.setAlpha(18);
    int program = timeline->tracks[track].firstProgram;
    uint64_t spanStart = 0;
    for (std::size_t index = 0; index < paintEntryCount; ++index) {
        const VoicePaintEntry entry = paintEntryAt(index);
        if (program >= 0 && entry.tick > spanStart) {
            timeline_quick::addRect(scene, TimelineQuickLayer::VoiceChangesSpans,
                                    heldSpanRect(spanStart, entry.tick, m_camera, plot), heldColor,
                                    plot);
        }
        program = entry.program;
        spanStart = entry.tick;
    }
    if (program >= 0 && timeline->lengthTicks > spanStart) {
        timeline_quick::addRect(scene, TimelineQuickLayer::VoiceChangesSpans,
                                heldSpanRect(spanStart, timeline->lengthTicks, m_camera, plot),
                                heldColor, plot);
    }

    static const QString noVoiceText = tr("No voice");
    const double contextTick =
        m_live.playback.playing ? m_live.playback.playheadTick : m_live.editCursorTick;
    const int contextSlot = voiceSlotAt(uint64_t(std::round(std::max(0.0, contextTick))));
    const QString &contextText = contextSlot >= 0 && contextSlot < VOICEGROUP_SIZE
                                     ? paintTextFor(contextSlot).label
                                     : noVoiceText;
    appendText(plotTextRecords, kVoiceReadoutTextKey,
               plot.adjusted(lyt::space(Space::One), lyt::space(Space::Zero),
                             -lyt::space(Space::One), -lyt::space(Space::Zero)),
               contextText, secondaryText, m_captionFont, Qt::AlignRight, Qt::AlignVCenter);

    const qreal pad = lyt::space(Space::One);
    const qreal gap = std::max<qreal>(m_geometry.hoverPaintPadding, lyt::space(Space::One));
    const QFontMetricsF &fontMetrics = m_captionMetrics;
    const qreal labelHeight = fontMetrics.height();
    const qreal centerY = plot.center().y() - labelHeight / 2.0;
    const qreal stairStep =
        std::min<qreal>(lyt::space(Space::Four), (plot.height() - labelHeight - 2 * pad) / 2.0);
    const bool canStair = stairStep > 1.0;
    m_labelLayouts.resize(paintEntryCount);
    qreal lastXEnd = -std::numeric_limits<qreal>::infinity();
    bool stairUp = true;
    for (std::size_t index = 0; index < paintEntryCount; ++index) {
        const VoicePaintEntry entry = paintEntryAt(index);
        VoiceLabelLayout &labelLayout = m_labelLayouts[index];
        labelLayout.elidedText.clear();
        const QString &sourceText = paintTextFor(entry.program).label;
        labelLayout.text = sourceText.isEmpty() ? &noVoiceText : &sourceText;
        const qreal labelX = m_camera.displayX(double(entry.tick), 0.0, dpr) + pad;
        const qreal maxWidth = std::max<qreal>(0.0, plot.right() - labelX);
        if (fontMetrics.horizontalAdvance(*labelLayout.text) > maxWidth && maxWidth > 0.0) {
            labelLayout.elidedText = fontMetrics.elidedText(*labelLayout.text, Qt::ElideRight,
                                                            int(std::floor(maxWidth)));
            labelLayout.text = &labelLayout.elidedText;
        }
        const qreal labelWidth =
            std::min<qreal>(fontMetrics.horizontalAdvance(*labelLayout.text), maxWidth);
        labelLayout.offscreen =
            labelX + labelWidth < plot.left() || labelX > plot.right() || labelWidth <= 0.0;
        qreal labelY = centerY;
        if (!labelLayout.offscreen) {
            const bool close = labelX < lastXEnd + gap;
            if (close && canStair) {
                stairUp = !stairUp;
                labelY = stairUp ? centerY - stairStep : centerY + stairStep;
            }
            labelY = std::clamp(labelY, plot.top() + pad, plot.bottom() - labelHeight - pad);
            lastXEnd = labelX + labelWidth + gap;
        }
        labelLayout.rect = QRectF(labelX, labelY, labelWidth, labelHeight);
    }
    const qreal markerWidth = lyt::singlePixel() + lyt::singlePixel();
    for (const VoiceLabelLayout &markerLabel : m_labelLayouts) {
        const qreal markerX = markerLabel.rect.left() - pad;
        timeline_quick::addVerticalLine(scene, TimelineQuickLayer::VoiceChangesMarkers, markerX,
                                        plot.top() + pad, plot.bottom() - pad, markerWidth,
                                        trackColor, plot);
    }
    for (std::size_t index = 0; index < m_labelLayouts.size(); ++index) {
        const VoiceLabelLayout &labelLayout = m_labelLayouts[index];
        if (!labelLayout.offscreen && labelLayout.text) {
            appendText(plotTextRecords, index, labelLayout.rect, *labelLayout.text, primaryText,
                       m_captionFont, Qt::AlignLeft, Qt::AlignVCenter);
        }
    }
    scene.setVoiceChangesTextRecords(plotTextRecords);
}

void VoiceChangeArea::rebuildQuickHover(songview::TimelineQuickScene &scene)
{
    using namespace songview;
    constexpr TimelineQuickLayer hoverLayer = TimelineQuickLayer::VoiceChangesHover;
    timeline_quick::resetLayer(scene, hoverLayer);
    scene.setVoiceChangesHoverTextRecords(std::span<const TimelineQuickTextModel::Record>{});

    const QRectF plot(plotRect());
    if (!m_hoverActive || plot.width() <= 0.0 || plot.height() <= 0.0 || !m_owner.document() ||
        !m_owner.timeline() || m_engineTrack < 0 || m_engineTrack >= 16) {
        return;
    }
    if (m_hoverLabel.isEmpty())
        return;
    const TimelineQuickTextModel::Record label = {
        {TimelineQuickTextKeyKind::VoiceChangesHover, {}, 0},
        m_hoverLabelRect,
        m_hoverLabel,
        themes::color(themes::Role::song_view_primary_text),
        m_hoverLabelFont,
        Qt::AlignLeft,
        Qt::AlignVCenter};
    scene.setVoiceChangesHoverTextRecords(
        std::span<const TimelineQuickTextModel::Record>(&label, 1));
}
