// ---------------------------------------------------------- TrackHeaderRow

#include "ui/songview/trackheaderrow.h"

#include "ui/activity/trackactivitymeter.h"
#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/songview/trackheaderpanel.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"

#include <QAction>
#include <QApplication>
#include <QContextMenuEvent>
#include <QEvent>
#include <QFontMetrics>
#include <QHBoxLayout>
#include <QKeyEvent>
#include <QKeySequence>
#include <QLineEdit>
#include <QMenu>
#include <QMetaObject>
#include <QMouseEvent>
#include <QPaintEvent>
#include <QPainter>
#include <QPalette>
#include <QRectF>
#include <QResizeEvent>
#include <QToolButton>
#include <QVBoxLayout>

namespace lyt = ::layout;
using Space = lyt::Space;

namespace songview {
using namespace songview::detail;

TrackHeaderRow::Geometry TrackHeaderRow::Geometry::resolve()
{
    return {lyt::fontPx(1.5),       lyt::fontPx(4.0),        lyt::fontPx(2.0),
            lyt::fontPx(5.0 / 6.0), lyt::fontPx(11.0 / 6.0), lyt::fontPx(3.0),
            lyt::fontPx(4.0 / 3.0), lyt::fontPx(5.0 / 6.0),  lyt::fontPx(0.5),
            lyt::fontPx(1.0 / 6.0), lyt::fontPx(8.0 / 3.0),  lyt::fontPx(5.0 / 3.0)};
}

void TrackHeaderRow::rebuildFontCache()
{
    m_normalTitleFont = font();
    m_boldTitleFont = typography::bold(m_normalTitleFont);
    m_subtitleFont = typography::caption(m_normalTitleFont);
    m_normalTitleMetrics = QFontMetrics(m_normalTitleFont);
    m_boldTitleMetrics = QFontMetrics(m_boldTitleFont);
    m_subtitleMetrics = QFontMetrics(m_subtitleFont);
    m_textLayout.emplace(::layout::twoLineText(m_normalTitleFont, m_boldTitleFont, m_subtitleFont,
                                               ::layout::Space::Half));
    m_centeredTitle.clear();
    m_selectedTitleOffset = {};
}

void TrackHeaderRow::refreshGeometry()
{
    m_geometry = Geometry::resolve();
    rebuildFontCache();
    setFixedHeight(m_geometry.trackHeaderRowHeight);
    if (m_activityMeter)
        m_activityMeter->setGeometry(activityMeterRect());
    if (m_mute)
        m_mute->setFixedSize(m_geometry.trackHeaderButtonExtent,
                             m_geometry.trackHeaderButtonExtent);
    if (m_solo)
        m_solo->setFixedSize(m_geometry.trackHeaderButtonExtent,
                             m_geometry.trackHeaderButtonExtent);
    if (m_editor)
        m_editor->setGeometry(editorRect());
    update();
}

TrackHeaderRow::TrackHeaderRow(SongView *sv, int track, QWidget *parent)
    : QWidget(parent)
    , m_sv(sv)
    , m_track(track)
    , m_geometry(Geometry::resolve())
{
    rebuildFontCache();
    const auto buttonExtent = m_geometry.trackHeaderButtonExtent;
    setFixedHeight(m_geometry.trackHeaderRowHeight);
    m_activityMeter = new TrackActivityMeter(SongView::trackColor(m_track), this);
    m_activityMeter->setGeometry(activityMeterRect());
    setActivity(m_sv->m_trackActivity.intensity(m_track), m_sv->m_playing);
    auto *layout = new QHBoxLayout(this);
    layout->setContentsMargins(::layout::space(::layout::Space::Zero),
                               ::layout::space(::layout::Space::Zero),
                               ::layout::space(::layout::Space::One), ::layout::singlePixel());
    layout->addStretch();

    auto *buttons = new QVBoxLayout;
    buttons->setSpacing(::layout::space(::layout::Space::Zero));
    m_mute = new QToolButton(this);
    m_mute->setAutoRaise(false);
    m_mute->setText(QStringLiteral("M"));
    m_mute->setCheckable(true);
    m_mute->setFixedSize(buttonExtent, buttonExtent);
    m_mute->setObjectName(QStringLiteral("trackMuteButton"));
    // Headers are rebuilt on every document edit; keep the persistent
    // mute/solo state (checked before connect, so nothing re-emits).
    m_mute->setChecked(sv->trackMuted(track));
    connect(m_mute, &QToolButton::toggled, this,
            [this](bool on) { m_sv->setTrackMute(m_track, on); });
    m_solo = new QToolButton(this);
    m_solo->setAutoRaise(false);
    m_solo->setText(QStringLiteral("S"));
    m_solo->setCheckable(true);
    m_solo->setFixedSize(buttonExtent, buttonExtent);
    m_solo->setObjectName(QStringLiteral("trackSoloButton"));
    m_solo->setChecked(sv->trackSoloed(track));
    connect(m_solo, &QToolButton::toggled, this,
            [this](bool on) { m_sv->setTrackSolo(m_track, on); });
    // The keyboard toggles change the masks without a header rebuild;
    // follow them. Re-entry through toggled is safe: setTrackMute/Solo
    // no-op when the bit already matches.
    connect(sv, &SongView::muteMaskChanged, this,
            [this](uint32_t mask) { m_mute->setChecked(mask & (1u << m_track)); });
    connect(sv, &SongView::soloMaskChanged, this,
            [this](uint32_t mask) { m_solo->setChecked(mask & (1u << m_track)); });
    // Display-only binding hints, like the context menus'. Live: the
    // shortcuts dialog can rebind without a header rebuild.
    const auto retip = [this] {
        const auto &keys = keymap::Registry::instance();
        const auto hint = [&keys](const QString &id, const QString &name) {
            const QKeySequence seq = keys.bindings(id).value(0);
            return seq.isEmpty() ? name
                                 : QStringLiteral("%1 (%2)").arg(
                                       name, seq.toString(QKeySequence::NativeText));
        };
        m_mute->setToolTip(hint(QStringLiteral("roll.mute_tracks"), SongView::tr("Mute")));
        m_solo->setToolTip(hint(QStringLiteral("roll.solo_tracks"), SongView::tr("Solo")));
    };
    retip();
    connect(&keymap::Registry::instance(), &keymap::Registry::bindingsChanged, this, retip);
    buttons->addStretch();
    buttons->addWidget(m_mute);
    buttons->addStretch();
    buttons->addWidget(m_solo);
    buttons->addStretch();
    layout->addLayout(buttons);
    layout->setAlignment(buttons, Qt::AlignVCenter);
}

int TrackHeaderRow::track() const
{
    return m_track;
}

void TrackHeaderRow::setActivity(TrackActivityIntensity intensity, bool playing)
{
    m_activityMeter->setState({intensity, playing, 1.0f});
}

// True when the track index is at or beyond the project's in-game
// allocation (SongDocument::trackBudget). Warning-only: the track stays
// audible and editable.
bool TrackHeaderRow::exceedsProjectTrackBudget() const
{
    const SongDocument *doc = m_sv->document();
    return doc && m_track >= doc->trackBudget();
}

void TrackHeaderRow::paintEvent(QPaintEvent *)
{
    QPainter p(this);
    const auto &selectionModel = m_sv->selectionModel();
    const uint32_t usedTracks = usedTrackMask(m_sv->timeline());
    const bool selected = selectionModel.primaryTrack() == m_track;
    if (selected) {
        // The derived selection fill has the required lightness gap. Keep
        // it opaque so the visible header reaches that target.
        p.fillRect(rect(), themes::color(themes::Role::song_view_track_header_selection));
    } else if (selectionModel.resolvedTrackScope(usedTracks) & (1u << m_track)) {
        // Part of the multi-track scope (Ctrl/Shift+click), lighter than
        // the primary selection.
        p.fillRect(rect(), trackHeaderAlsoSelectedColor());
    }
    const bool overBudget = exceedsProjectTrackBudget();
    p.setPen(QPen(themes::color(themes::Role::song_view_separator), lyt::singlePixel()));
    p.drawLine(lyt::space(Space::Zero), height() - lyt::singlePixel(), width(),
               height() - lyt::singlePixel());

    const MidiTimeline *tl = m_sv->timeline();
    QString name = tl ? tl->tracks[m_track].name : QString();
    if (name.isEmpty())
        name = SongView::tr("Track %1").arg(m_track + 1);
    const auto textW = width() - m_geometry.trackHeaderButtonColumnWidth -
                       m_geometry.trackHeaderTextLeft - lyt::space(Space::One);
    const auto title = QStringLiteral("%1 · %2").arg(m_track + 1).arg(name);
    const QFont &titleFont = selected ? m_boldTitleFont : m_normalTitleFont;
    const QFontMetrics &titleMetrics = selected ? m_boldTitleMetrics : m_normalTitleMetrics;
    const auto visibleTitle = titleMetrics.elidedText(title, Qt::ElideRight, textW);
    const QColor backdrop = selected ? themes::color(themes::Role::song_view_track_header_selection)
                            : (selectionModel.resolvedTrackScope(usedTracks) & (1u << m_track))
                                ? trackHeaderAlsoSelectedColor()
                                : palette().color(QPalette::Window);
    // Tracks beyond the project budget recede to a gray warning but stay active.
    QColor titleColor = selected
                            ? themes::color(themes::Role::song_view_track_header_selection_text)
                            : themes::color(themes::Role::song_view_primary_text);
    QColor subtitleColor = selected
                               ? themes::color(themes::Role::song_view_track_header_selection_text)
                               : themes::color(themes::Role::song_view_secondary_text);
    if (overBudget) {
        titleColor = mixTowardOklab(titleColor, backdrop, selected ? 0.35 : 0.6);
        subtitleColor = mixTowardOklab(subtitleColor, backdrop, selected ? 0.35 : 0.6);
    }
    p.setFont(titleFont);
    p.setPen(titleColor);
    const auto &subtitleFont = m_subtitleFont;
    // The bottom pixel belongs to the separator, not the row's content.
    const auto textBounds = QRect(m_geometry.trackHeaderTextLeft, lyt::space(Space::Zero), textW,
                                  height() - lyt::singlePixel());
    const auto textBoxes = m_textLayout->align(textBounds, ::layout::VerticalAlignment::Center);
    // Bold and regular glyph bounds differ. Cache the selected-face offset
    // until the visible title or font changes.
    if (visibleTitle != m_centeredTitle) {
        m_centeredTitle = visibleTitle;
        m_selectedTitleOffset =
            typography::glyphCenteringOffset(m_normalTitleFont, m_boldTitleFont, visibleTitle);
    }
    const auto titleBox =
        QRectF(textBoxes.primary).translated(selected ? m_selectedTitleOffset : QPointF{});
    p.drawText(titleBox, Qt::AlignLeft | Qt::AlignVCenter, visibleTitle);

    p.setFont(subtitleFont);
    p.setPen(subtitleColor);
    m_shownProgram = m_sv->currentProgram(m_track);
    const QString subtitle = m_sv->instrumentLabel(m_track);
    p.drawText(textBoxes.secondary, Qt::AlignLeft | Qt::AlignVCenter,
               m_subtitleMetrics.elidedText(subtitle, Qt::ElideRight, textW));
}

// The painted voice line (paintEvent's instrument-label rect): a plain
// click here also reveals the voice in the voicegroup dock.
QRect TrackHeaderRow::voiceLineRect() const
{
    return QRect(m_geometry.trackHeaderVoiceLineLeft, m_geometry.trackHeaderVoiceLineTop,
                 width() - m_geometry.trackHeaderVoiceLineRight,
                 m_geometry.trackHeaderVoiceLineHeight);
}

void TrackHeaderRow::mousePressEvent(QMouseEvent *event)
{
    m_sv->trackHeaderClicked(m_track, event->modifiers());
    // A plain left press may become a reorder drag (the track's chunk
    // moves — AGB track order is chunk order).
    m_dragArmed = event->button() == Qt::LeftButton &&
                  !(event->modifiers() & (Qt::ControlModifier | Qt::ShiftModifier)) &&
                  m_sv->document();
    m_voiceClickArmed = event->button() == Qt::LeftButton &&
                        !(event->modifiers() & (Qt::ControlModifier | Qt::ShiftModifier)) &&
                        voiceLineRect().contains(event->pos());
    m_pressPos = event->pos();
}

// Inline rename: a line edit overlaid on the row's name line. Return
// commits, Escape cancels (both restore the roll's focus), focus-out
// commits Reaper-style. The document edit itself is queued by
// commitTrackRename — it rebuilds the header panel, which would delete
// this row and the editor mid-signal.
// The voice line follows the song's program changes as the playhead (or
// edit cursor) moves; repaint only when the shown program flips.
void TrackHeaderRow::syncVoice()
{
    if (m_shownProgram == m_sv->currentProgram(m_track))
        return;
    update();
    updateToolTip();
}

void TrackHeaderRow::updateToolTip()
{
    const MidiTimeline *tl = m_sv->timeline();
    if (!tl)
        return;
    QString tip = SongView::tr("%1 notes · %2")
                      .arg(tl->tracks[m_track].noteCount)
                      .arg(m_sv->instrumentLabel(m_track));
    if (exceedsProjectTrackBudget()) {
        tip += SongView::tr("\nPossibly incompatible in-game: this song's music player "
                            "only allocates %1 track(s) (sound/music_player_table.inc). "
                            "The track stays audible here.")
                   .arg(m_sv->document()->trackBudget());
    }
    if (m_sv->document()) {
        tip += SongView::tr("\nDouble-click to rename · right-click "
                            "to change voice, duplicate, or delete"
                            " · drag to reorder"
                            "\nClick the voice name to show it in the "
                            "voicegroup dock · double-click it to "
                            "change the voice");
    }
    setToolTip(tip);
}

void TrackHeaderRow::beginRename()
{
    SongDocument *doc = m_sv->document();
    if (!doc)
        return;
    if (!m_editor) {
        m_editor = new QLineEdit(this);
        m_editor->setObjectName(QStringLiteral("trackRenameEditor"));
        m_editor->installEventFilter(this);
        connect(m_editor, &QLineEdit::editingFinished, this, [this] { finishRename(true, false); });
    }
    m_editor->setText(doc->trackName(m_track));
    // What an empty name falls back to (mirrors the painted default).
    m_editor->setPlaceholderText(SongView::tr("Track %1").arg(m_track + 1));
    m_editor->setGeometry(editorRect());
    m_editor->show();
    m_editor->setFocus();
    m_editor->selectAll();
}

// Reaper-style commit for gestures that will rebuild the panel: header
// rows take no focus, so pressing one never gives the editor a
// focus-out — without this, the rebuild would destroy the editor and
// silently drop the typed name.
void TrackHeaderRow::commitOpenRename()
{
    finishRename(true, false);
}

void TrackHeaderRow::mouseDoubleClickEvent(QMouseEvent *event)
{
    m_sv->selectTrack(m_track);
    // The voice line opens the voice picker (its single click already
    // revealed the voice in the dock); anywhere else renames. Queued:
    // the picked voice's edit rebuilds the header panel, deleting this
    // row out from under its own event handler.
    if (voiceLineRect().contains(event->pos())) {
        QMetaObject::invokeMethod(
            m_sv, [sv = m_sv, t = m_track] { sv->editTrackVoice(t); }, Qt::QueuedConnection);
        return;
    }
    beginRename();
}

void TrackHeaderRow::contextMenuEvent(QContextMenuEvent *event)
{
    if (!m_sv->document())
        return;
    // A right-click with the left button still down is a mid-drag
    // cancel (mouseReleaseEvent), not a menu request.
    if (QApplication::mouseButtons() & Qt::LeftButton)
        return;
    m_sv->selectTrack(m_track);
    QMenu menu(this);
    QAction *voiceAction = menu.addAction(SongView::tr("Change voice..."));
    QAction *showVoiceAction = menu.addAction(SongView::tr("Show voice in voicegroup"));
    QAction *renameAction = menu.addAction(SongView::tr("Rename track..."));
    QAction *duplicateAction = menu.addAction(SongView::tr("Duplicate track"));
    duplicateAction->setEnabled(m_sv->document()->canAddTrack());
    QAction *deleteAction = menu.addAction(SongView::tr("Delete track"));
    QAction *chosen = menu.exec(event->globalPos());
    // Queued: these edits rebuild the header panel, which deletes this
    // row out from under its own event handler. (Rename just opens the
    // inline editor — no edit until it commits — so it's direct.)
    if (chosen == renameAction) {
        beginRename();
    } else if (chosen == showVoiceAction) {
        // No document edit — nothing rebuilds, so no queue needed.
        m_sv->revealTrackVoice(m_track);
    } else if (chosen == voiceAction) {
        QMetaObject::invokeMethod(
            m_sv, [sv = m_sv, t = m_track] { sv->editTrackVoice(t); }, Qt::QueuedConnection);
    } else if (chosen == duplicateAction) {
        QMetaObject::invokeMethod(
            m_sv, [sv = m_sv, t = m_track] { sv->duplicateTrack(t); }, Qt::QueuedConnection);
    } else if (chosen == deleteAction) {
        QMetaObject::invokeMethod(
            m_sv, [sv = m_sv, t = m_track] { sv->deleteTrack(t); }, Qt::QueuedConnection);
    }
}

bool TrackHeaderRow::eventFilter(QObject *watched, QEvent *event)
{
    if (watched == m_editor && event->type() == QEvent::KeyPress) {
        auto *keyEvent = static_cast<QKeyEvent *>(event);
        if (keyEvent->key() == Qt::Key_Escape) {
            finishRename(false, true);
            return true;
        }
        if (keyEvent->key() == Qt::Key_Return || keyEvent->key() == Qt::Key_Enter) {
            finishRename(true, true);
            return true;
        }
    }
    return QWidget::eventFilter(watched, event);
}

bool TrackHeaderRow::event(QEvent *event)
{
    const bool handled = QWidget::event(event);
    if (event->type() == QEvent::FontChange)
        refreshGeometry();
    return handled;
}

void TrackHeaderRow::resizeEvent(QResizeEvent *)
{
    // Rows are born 100px wide and only get their real width on the
    // deferred layout pass; an open editor must follow.
    if (m_activityMeter)
        m_activityMeter->setGeometry(activityMeterRect());
    if (m_editor)
        m_editor->setGeometry(editorRect());
}

QRect TrackHeaderRow::activityMeterRect() const
{
    return QRect(lyt::space(Space::Zero), lyt::space(Space::Zero), lyt::space(Space::One),
                 height() - lyt::singlePixel());
}

// The row's name line, clear of the color strip and the M/S column.
QRect TrackHeaderRow::editorRect() const
{
    return QRect(m_geometry.trackHeaderRenameEditorLeft, m_geometry.trackHeaderRenameEditorTop,
                 width() - m_geometry.trackHeaderRenameEditorRight,
                 m_geometry.trackHeaderRenameEditorHeight);
}

void TrackHeaderRow::finishRename(bool commit, bool restoreFocus)
{
    // isHidden, not isVisible: the guard must also hold when the view
    // itself isn't shown (offscreen harnesses). m_finishing blocks the
    // editingFinished that hide()'s focus-out re-emits.
    if (!m_editor || m_editor->isHidden() || m_finishing)
        return;
    m_finishing = true;
    const QString text = m_editor->text();
    m_editor->hide();
    m_finishing = false;
    if (restoreFocus)
        m_sv->focusContent();
    if (commit)
        m_sv->commitTrackRename(m_track, text);
}

void TrackHeaderRow::mouseMoveEvent(QMouseEvent *event)
{
    auto *panel = static_cast<TrackHeaderPanel *>(parentWidget());
    if (!m_dragging) {
        if (!m_dragArmed || !(event->buttons() & Qt::LeftButton) ||
            (event->pos() - m_pressPos).manhattanLength() < QApplication::startDragDistance())
            return;
        m_dragging = panel->beginRowDrag(m_track);
        if (!m_dragging)
            return;
    }
    panel->dragRowTo(mapTo(panel, event->pos()));
}

void TrackHeaderRow::mouseReleaseEvent(QMouseEvent *event)
{
    // Only a left release drops the row; any other button mid-drag is a
    // cancel gesture (matching the ruler's and roll's release handling).
    if (event->button() != Qt::LeftButton) {
        if (m_dragging) {
            m_dragging = false;
            m_dragArmed = false;
            static_cast<TrackHeaderPanel *>(parentWidget())->endRowDrag(false);
        }
        return;
    }
    m_dragArmed = false;
    const bool voiceClick = m_voiceClickArmed;
    m_voiceClickArmed = false;
    if (!m_dragging) {
        // A completed plain click on the voice line (not a drag, released
        // where it pressed) surfaces the track's voice in the dock.
        if (voiceClick && voiceLineRect().contains(event->pos()))
            m_sv->revealTrackVoice(m_track);
        return;
    }
    m_dragging = false;
    static_cast<TrackHeaderPanel *>(parentWidget())->endRowDrag(true);
}

} // namespace songview
