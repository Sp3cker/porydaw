// ---------------------------------------------------------- TrackHeaderRow

#include "ui/songview/trackheaderrow.h"

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

namespace {

struct RowPaintStyle {
    QColor base;
    QColor overlay;
    QColor backdrop;
    const QFont *titleFont;
    const QFontMetrics *titleMetrics;
    QColor titleColor;
    QColor subtitleColor;
    qreal overBudgetMix;
    bool useSelectedTitleOffset;
};

RowPaintStyle resolvePaintStyle(bool primary, bool inScope, bool overBudget,
                                const QPalette &palette, const QFont &normalTitleFont,
                                const QFont &boldTitleFont, const QFontMetrics &normalTitleMetrics,
                                const QFontMetrics &boldTitleMetrics)
{
    const QColor defaultBackdrop = palette.color(QPalette::Window);
    QColor opaqueDefaultBase = defaultBackdrop;
    opaqueDefaultBase.setAlpha(255);
    RowPaintStyle style{
        .base = opaqueDefaultBase,
        .overlay = {},
        .backdrop = defaultBackdrop,
        .titleFont = &normalTitleFont,
        .titleMetrics = &normalTitleMetrics,
        .titleColor = themes::color(themes::Role::song_view_primary_text),
        .subtitleColor = themes::color(themes::Role::song_view_secondary_text),
        .overBudgetMix = 0.6,
        .useSelectedTitleOffset = false,
    };

    if (primary) {
        style.backdrop = themes::color(themes::Role::song_view_track_header_selection);
        style.base = style.backdrop;
        style.base.setAlpha(255);
        style.titleFont = &boldTitleFont;
        style.titleMetrics = &boldTitleMetrics;
        style.titleColor = themes::color(themes::Role::song_view_track_header_selection_text);
        style.subtitleColor = style.titleColor;
        style.overBudgetMix = 0.35;
        style.useSelectedTitleOffset = true;
    } else if (inScope) {
        style.overlay = trackHeaderAlsoSelectedColor();
        style.backdrop = style.overlay;
    }

    if (overBudget) {
        style.titleColor = mixTowardOklab(style.titleColor, style.backdrop, style.overBudgetMix);
        style.subtitleColor =
            mixTowardOklab(style.subtitleColor, style.backdrop, style.overBudgetMix);
    }
    return style;
}

} // namespace

int TrackHeaderRow::resolvedHeight()
{
    // The row stride: defined here so the panel's overlay geometry and the
    // rows can never disagree.
    return lyt::fontPx(4.0);
}

TrackHeaderRow::Geometry TrackHeaderRow::Geometry::resolve()
{
    return {lyt::fontPx(1.5),       resolvedHeight(),        lyt::fontPx(2.0),
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
    setAttribute(Qt::WA_OpaquePaintEvent);
    rebuildFontCache();
    const auto buttonExtent = m_geometry.trackHeaderButtonExtent;
    setFixedHeight(m_geometry.trackHeaderRowHeight);
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
    // Checked before connect, so construction re-emits nothing; rows
    // retained across a rebuild re-check via resyncSong.
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

// True when the track index is at or beyond the project's in-game
// allocation (SongDocument::trackBudget). Warning-only: the track stays
// audible and editable.
bool TrackHeaderRow::exceedsProjectTrackBudget() const
{
    const SongDocument *doc = m_sv->document();
    return doc && m_track >= doc->trackBudget();
}

QString TrackHeaderRow::fallbackTrackName() const
{
    return SongView::tr("Track %1").arg(m_track + 1);
}
TrackHeaderRow::SelectionState TrackHeaderRow::selectionState() const
{
    const auto &selectionModel = m_sv->selectionModel();
    if (selectionModel.primaryTrack() == m_track)
        return SelectionState::Primary;
    if (selectionModel.resolvedTrackScope(usedTrackMask(m_sv->timeline())) & (1u << m_track))
        return SelectionState::InScope;
    return SelectionState::None;
}

QRect TrackHeaderRow::textColumnRect() const
{
    const int left = lyt::space(Space::One);
    const int right = width() - m_geometry.trackHeaderButtonExtent - lyt::space(Space::One);
    // The full parent-painted gutter covers title centering offsets and
    // antialiasing without reaching the activity column, button column,
    // or bottom separator.
    return QRect(left, lyt::space(Space::Zero), right - left, height() - lyt::singlePixel());
}

void TrackHeaderRow::updateVisibleTitleCenteringCache(const QString &visibleTitle)
{
    if (visibleTitle == m_centeredTitle)
        return;
    m_centeredTitle = visibleTitle;
    m_selectedTitleOffset =
        typography::glyphCenteringOffset(m_normalTitleFont, m_boldTitleFont, visibleTitle);
}

void TrackHeaderRow::paintEvent(QPaintEvent *event)
{
    const MidiTimeline *timeline = m_sv->timeline();
    const SelectionState selection = selectionState();

    const RowPaintStyle style = resolvePaintStyle(
        selection == SelectionState::Primary, selection == SelectionState::InScope,
        exceedsProjectTrackBudget(), palette(), m_normalTitleFont, m_boldTitleFont,
        m_normalTitleMetrics, m_boldTitleMetrics);
    QString name = timeline ? timeline->tracks[m_track].name : QString();
    if (name.isEmpty())
        name = fallbackTrackName();
    const QRect textPaintRect = textColumnRect();
    const int textW = width() - m_geometry.trackHeaderButtonColumnWidth -
                      m_geometry.trackHeaderTextLeft - lyt::space(Space::One);
    const QRect textBounds(m_geometry.trackHeaderTextLeft, lyt::space(Space::Zero), textW,
                           height() - lyt::singlePixel());
    const auto title = QStringLiteral("%1 · %2").arg(m_track + 1).arg(name);
    const auto visibleTitle = style.titleMetrics->elidedText(title, Qt::ElideRight, textW);
    const auto textBoxes = m_textLayout->align(textBounds, ::layout::VerticalAlignment::Center);
    updateVisibleTitleCenteringCache(visibleTitle);
    const QPointF titleOffset = style.useSelectedTitleOffset ? m_selectedTitleOffset : QPointF{};
    const auto titleBox = QRectF(textBoxes.primary).translated(titleOffset);
    const int shownProgram = m_sv->currentProgram(m_track);
    const QString subtitle = m_sv->instrumentLabel(m_track);

    QPainter p(this);
    p.fillRect(rect(), style.base);
    if (style.overlay.isValid())
        p.fillRect(rect(), style.overlay);
    if (event->region().contains(rect()))
        m_paintedSelection = selection;
    p.setPen(QPen(themes::color(themes::Role::song_view_separator), lyt::singlePixel()));
    p.drawLine(lyt::space(Space::Zero), height() - lyt::singlePixel(), width(),
               height() - lyt::singlePixel());
    p.setFont(*style.titleFont);
    p.setPen(style.titleColor);
    p.drawText(titleBox, Qt::AlignLeft | Qt::AlignVCenter, visibleTitle);
    p.setFont(m_subtitleFont);
    p.setPen(style.subtitleColor);
    p.drawText(textBoxes.secondary, Qt::AlignLeft | Qt::AlignVCenter,
               m_subtitleMetrics.elidedText(subtitle, Qt::ElideRight, textW));
    if (event->region().contains(textPaintRect))
        m_shownProgram = shownProgram;
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
    // The native Quick window overlaps the header column. Mouse presses reach
    // this QWidget, but the platform context-menu event is retargeted to the
    // Quick window, so open the native menu while this row still owns the press.
    if (event->button() == Qt::RightButton) {
        showContextMenu(event->globalPosition().toPoint());
        return;
    }
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
// commitTrackRename — it rebuilds the header panel, which would cancel
// this editor mid-signal.
// The voice line follows the song's program changes as the playhead (or
// edit cursor) moves; repaint only when the shown program flips.
void TrackHeaderRow::syncVoice()
{
    if (m_shownProgram == m_sv->currentProgram(m_track))
        return;
    update(textColumnRect());
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
    m_editor->setPlaceholderText(fallbackTrackName());
    m_editor->setGeometry(editorRect());
    m_editor->show();
    m_editor->setFocus();
    m_editor->selectAll();
}

// Reaper-style commit for gestures that will rebuild the panel: header
// rows take no focus, so pressing one never gives the editor a
// focus-out — without this, the rebuild's cancel would silently drop
// the typed name.
void TrackHeaderRow::commitOpenRename()
{
    finishRename(true, false);
}

// Rebuild-time cancel: the typed name is dropped, never committed;
// m_finishing blocks the editingFinished the focus-out emits.
void TrackHeaderRow::cancelRename()
{
    if (!m_editor)
        return;
    const bool restoreFocus = m_editor->hasFocus();
    m_finishing = true;
    m_editor->hide();
    m_editor->setObjectName(QString());
    m_editor->deleteLater();
    m_editor = nullptr;
    m_finishing = false;
    if (restoreFocus)
        m_sv->focusContent();
}

void TrackHeaderRow::resyncSong()
{
    const SelectionState selection = selectionState();
    cancelRename();
    m_dragArmed = false;
    m_dragging = false;
    m_voiceClickArmed = false;
    m_shownProgram = -2;
    m_mute->setChecked(m_sv->trackMuted(m_track));
    m_solo->setChecked(m_sv->trackSoloed(m_track));
    updateToolTip();
    if (!m_paintedSelection || *m_paintedSelection != selection)
        update();
    else
        update(textColumnRect());
}

void TrackHeaderRow::mouseDoubleClickEvent(QMouseEvent *event)
{
    m_sv->selectTrack(m_track);
    // The voice line opens the voice picker (its single click already
    // revealed the voice in the dock); anywhere else renames. Queued:
    // the picked voice's edit rebuilds the header panel.
    if (voiceLineRect().contains(event->pos())) {
        m_sv->queueHeaderMutation([sv = m_sv, t = m_track] { sv->editTrackVoice(t); });
        return;
    }
    beginRename();
}

void TrackHeaderRow::contextMenuEvent(QContextMenuEvent *event)
{
    showContextMenu(event->globalPos());
}

void TrackHeaderRow::showContextMenu(const QPoint &globalPosition)
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

    connect(renameAction, &QAction::triggered, this, &TrackHeaderRow::beginRename);
    connect(showVoiceAction, &QAction::triggered, this,
            [this] { m_sv->revealTrackVoice(m_track); });
    // Queued: these edits rebuild the header panel.
    connect(voiceAction, &QAction::triggered, this, [this] {
        m_sv->queueHeaderMutation([sv = m_sv, t = m_track] { sv->editTrackVoice(t); });
    });
    connect(duplicateAction, &QAction::triggered, this, [this] {
        m_sv->queueHeaderMutation([sv = m_sv, t = m_track] { sv->duplicateTrack(t); });
    });
    connect(deleteAction, &QAction::triggered, this, [this] {
        m_sv->queueHeaderMutation([sv = m_sv, t = m_track] { sv->deleteTrack(t); });
    });

    menu.exec(globalPosition);
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
    if (m_editor)
        m_editor->setGeometry(editorRect());
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
