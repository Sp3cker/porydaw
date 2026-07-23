#include "songview.h"
#include "ui/songviewpianoroll.hpp"
#include "ui/songviewtimeruler.hpp"
#include "ui/songviewautomationarea.hpp"

#include <QApplication>
#include <QContextMenuEvent>
#include <QDialog>
#include <QDialogButtonBox>
#include <QFontMetrics>
#include <QHBoxLayout>
#include <QLabel>
#include <QLineEdit>
#include <QListWidget>
#include <QMenu>
#include <QMouseEvent>
#include <QPaintEvent>
#include <QPainter>
#include <QPainterPath>
#include <QResizeEvent>
#include <QScrollArea>
#include <QScrollBar>
#include <QSplitter>
#include <QStackedWidget>
#include <QToolButton>
#include <QToolTip>
#include <QVBoxLayout>
#include <algorithm>
#include <array>
#include <climits>
#include <cmath>
#include <functional>
#include <map>
#include <utility>

#include "core/mid2agbtables.h"
#include "core/songdocument.h"
#include "ui/eventlistview.h"

namespace songview {

namespace {

constexpr int kLanesAreaH = 150;
constexpr int kStripH = 24;
constexpr int kTrackRowH = 46;
constexpr double kMinPxPerBeat = 4.0;
constexpr double kMaxPxPerBeat = 640.0;
constexpr int kMinKeyHeight = 4;
constexpr int kMaxKeyHeight = 32;
constexpr int kVoiceAuditionKey = 60; // middle C, matching the voicegroup browser
constexpr int kVoiceAuditionVel = 112;



} // namespace


// ---------------------------------------------------------------- OtherStrip

class OtherStrip : public QWidget
{
public:
    explicit OtherStrip(SongView *sv)
        : QWidget(sv), m_sv(sv)
    {
        setFixedHeight(kStripH);
        setMouseTracking(true);
    }

protected:
    void paintEvent(QPaintEvent *) override
    {
        QPainter p(this);
        p.fillRect(rect(), palette().color(QPalette::Window).darker(104));
        p.setPen(palette().color(QPalette::Mid));
        p.drawLine(0, 0, width(), 0);

        const SongViewModel &model = m_sv->model();
        p.setPen(palette().color(QPalette::WindowText));
        p.drawText(QRect(8, 0, kGutterW - 16, height()), Qt::AlignVCenter,
                   SongView::tr("Other events (%1)").arg(model.strip.size()));
        if (!m_sv->timeline())
            return;

        const QRect area(kGutterW, 0, width() - kGutterW, height());
        p.setClipRect(area);
        time_ruler_detail::drawOverlays(p, m_sv, area, kGutterW, false);

        const int cy = height() / 2;
        for (const StripItem &item : model.strip) {
            const int x = kGutterW + m_sv->contentX(double(item.tick));
            if (x < area.left() - 4 || x > area.right() + 4)
                continue;
            QColor c = item.track >= 0 ? SongView::trackColor(item.track)
                                       : palette().color(QPalette::Mid);
            QPainterPath diamond;
            diamond.moveTo(x, cy - 5);
            diamond.lineTo(x + 4, cy);
            diamond.lineTo(x, cy + 5);
            diamond.lineTo(x - 4, cy);
            diamond.closeSubpath();
            p.fillPath(diamond, c);
        }
    }

    void mouseMoveEvent(QMouseEvent *event) override
    {
        const MidiTimeline *tl = m_sv->timeline();
        if (!tl || event->pos().x() < kGutterW) {
            QToolTip::hideText();
            return;
        }
        QStringList lines;
        for (const StripItem &item : m_sv->model().strip) {
            const int x = kGutterW + m_sv->contentX(double(item.tick));
            if (std::abs(x - event->pos().x()) > 4)
                continue;
            const double seconds = double(tl->sampleForTick(item.tick)) / tl->sampleRate;
            QString where = item.track >= 0
                                ? SongView::tr("Track %1").arg(item.track + 1)
                                : SongView::tr("File");
            lines << QStringLiteral("%1:%2 · %3 · %4")
                         .arg(int(seconds) / 60)
                         .arg(int(seconds) % 60, 2, 10, QLatin1Char('0'))
                         .arg(where, item.label);
            if (lines.size() >= 12) {
                lines << SongView::tr("…");
                break;
            }
        }
        if (lines.isEmpty())
            QToolTip::hideText();
        else
            QToolTip::showText(event->globalPosition().toPoint(),
                               lines.join(QStringLiteral("\n")), this);
    }

private:
    SongView *m_sv;
};

// ---------------------------------------------------------- VoicePickerDialog

// Modal instrument picker (SPEC §4.2): the voicegroup's 128 entries, the same
// list the import wizard's mapping combo renders. Press-and-hold auditions
// through the preview engine; double-click chooses.
class VoicePickerDialog : public QDialog
{
public:
    VoicePickerDialog(SongView *sv, const QString &title, int initialVoice,
                      std::function<void(int, int)> audition)
        : QDialog(sv), m_audition(std::move(audition))
    {
        setWindowTitle(title);
        resize(360, 440);
        auto *layout = new QVBoxLayout(this);
        m_list = new QListWidget(this);
        m_list->setUniformItemSizes(true);
        m_list->setToolTip(SongView::tr("Click and hold to audition (middle C)."));
        for (int v = 0; v < VOICEGROUP_SIZE; v++)
            m_list->addItem(QStringLiteral("%1  %2")
                                .arg(v, 3, 10, QLatin1Char('0'))
                                .arg(sv->voiceShortName(uint8_t(v))));
        m_list->setCurrentRow(std::clamp(initialVoice, 0, VOICEGROUP_SIZE - 1));
        m_list->scrollToItem(m_list->currentItem(), QAbstractItemView::PositionAtCenter);
        layout->addWidget(m_list, 1);

        auto *buttons =
            new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, this);
        connect(buttons, &QDialogButtonBox::accepted, this, &QDialog::accept);
        connect(buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);
        layout->addWidget(buttons);

        connect(m_list, &QListWidget::itemPressed, this, [this](QListWidgetItem *item) {
            releaseVoice();
            if (item) {
                m_sounding = m_list->row(item);
                m_audition(m_sounding, kVoiceAuditionVel);
            }
        });
        connect(m_list, &QListWidget::itemDoubleClicked, this, [this] { accept(); });
        m_list->viewport()->installEventFilter(this);
    }

    ~VoicePickerDialog() override { releaseVoice(); }

    int selectedVoice() const { return std::max(0, m_list->currentRow()); }

    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (watched == m_list->viewport() && event->type() == QEvent::MouseButtonRelease)
            releaseVoice();
        return QDialog::eventFilter(watched, event);
    }

private:
    void releaseVoice()
    {
        if (m_sounding < 0)
            return;
        m_audition(m_sounding, 0);
        m_sounding = -1;
    }

    QListWidget *m_list;
    std::function<void(int, int)> m_audition;
    int m_sounding = -1;
};

// ---------------------------------------------------------- TrackHeaderPanel

class TrackHeaderRow : public QWidget
{
public:
    TrackHeaderRow(SongView *sv, int track, QWidget *parent)
        : QWidget(parent), m_sv(sv), m_track(track)
    {
        setFixedHeight(kTrackRowH);
        auto *layout = new QHBoxLayout(this);
        layout->setContentsMargins(0, 2, 4, 2);
        layout->addStretch();

        auto *buttons = new QVBoxLayout;
        buttons->setSpacing(2);
        m_mute = new QToolButton(this);
        m_mute->setText(QStringLiteral("M"));
        m_mute->setCheckable(true);
        m_mute->setFixedSize(20, 18);
        m_mute->setToolTip(SongView::tr("Mute"));
        m_mute->setStyleSheet(
            QStringLiteral("QToolButton:checked { background: #d9534f; color: white; }"));
        // Headers are rebuilt on every document edit; keep the persistent
        // mute/solo state (checked before connect, so nothing re-emits).
        m_mute->setChecked(sv->trackMuted(track));
        connect(m_mute, &QToolButton::toggled, this,
                [this](bool on) { m_sv->setTrackMute(m_track, on); });
        m_solo = new QToolButton(this);
        m_solo->setText(QStringLiteral("S"));
        m_solo->setCheckable(true);
        m_solo->setFixedSize(20, 18);
        m_solo->setToolTip(SongView::tr("Solo"));
        m_solo->setStyleSheet(
            QStringLiteral("QToolButton:checked { background: #5cb85c; color: white; }"));
        m_solo->setChecked(sv->trackSoloed(track));
        connect(m_solo, &QToolButton::toggled, this,
                [this](bool on) { m_sv->setTrackSolo(m_track, on); });
        buttons->addWidget(m_mute);
        buttons->addWidget(m_solo);
        layout->addLayout(buttons);
    }

    int track() const { return m_track; }

protected:
    void paintEvent(QPaintEvent *) override
    {
        QPainter p(this);
        const bool selected = m_sv->selectedTrack() == m_track;
        if (selected) {
            QColor hl = palette().color(QPalette::Highlight);
            hl.setAlpha(50);
            p.fillRect(rect(), hl);
        } else if (m_sv->trackSelectionMask() & (1u << m_track)) {
            // Part of the multi-track scope (Ctrl/Shift+click), lighter than
            // the primary selection.
            QColor hl = palette().color(QPalette::Highlight);
            hl.setAlpha(22);
            p.fillRect(rect(), hl);
        }
        p.fillRect(QRect(0, 0, 4, height()), SongView::trackColor(m_track));
        p.setPen(palette().color(QPalette::Mid));
        p.drawLine(0, height() - 1, width(), height() - 1);

        const MidiTimeline *tl = m_sv->timeline();
        QString name = tl ? tl->tracks[m_track].name : QString();
        if (name.isEmpty())
            name = SongView::tr("Track %1").arg(m_track + 1);
        const int textW = width() - 36;
        QFont f = p.font();
        f.setBold(selected);
        p.setFont(f);
        p.setPen(palette().color(QPalette::WindowText));
        p.drawText(QRect(10, 4, textW, 16), Qt::AlignLeft | Qt::AlignVCenter,
                   fontMetrics().elidedText(
                       QStringLiteral("%1 · %2").arg(m_track + 1).arg(name),
                       Qt::ElideRight, textW));
        f.setBold(false);
        f.setPixelSize(std::max(9, f.pixelSize() > 0 ? f.pixelSize() - 2 : 10));
        p.setFont(f);
        p.setPen(palette().color(QPalette::PlaceholderText));
        m_shownProgram = m_sv->currentProgram(m_track);
        p.drawText(QRect(10, 22, textW, 16), Qt::AlignLeft | Qt::AlignVCenter,
                   QFontMetrics(f).elidedText(m_sv->instrumentLabel(m_track),
                                              Qt::ElideRight, textW));
    }

    // The painted voice line (paintEvent's instrument-label rect): a plain
    // click here also reveals the voice in the voicegroup dock.
    QRect voiceLineRect() const { return QRect(10, 22, width() - 36, 16); }

    void mousePressEvent(QMouseEvent *event) override
    {
        m_sv->trackHeaderClicked(m_track, event->modifiers());
        // A plain left press may become a reorder drag (the track's chunk
        // moves — AGB track order is chunk order).
        m_dragArmed = event->button() == Qt::LeftButton
            && !(event->modifiers() & (Qt::ControlModifier | Qt::ShiftModifier))
            && m_sv->document();
        m_voiceClickArmed = event->button() == Qt::LeftButton
            && !(event->modifiers() & (Qt::ControlModifier | Qt::ShiftModifier))
            && voiceLineRect().contains(event->pos());
        m_pressPos = event->pos();
    }

    // Defined below TrackHeaderPanel (they drive its drag state).
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;

public:
    // Inline rename: a line edit overlaid on the row's name line. Return
    // commits, Escape cancels (both restore the roll's focus), focus-out
    // commits Reaper-style. The document edit itself is queued by
    // commitTrackRename — it rebuilds the header panel, which would delete
    // this row and the editor mid-signal.
    // The voice line follows the song's program changes as the playhead (or
    // edit cursor) moves; repaint only when the shown program flips.
    void syncVoice()
    {
        if (m_shownProgram == m_sv->currentProgram(m_track))
            return;
        update();
        updateToolTip();
    }

    void updateToolTip()
    {
        const MidiTimeline *tl = m_sv->timeline();
        if (!tl)
            return;
        QString tip = SongView::tr("%1 notes · %2")
                          .arg(tl->tracks[m_track].noteCount)
                          .arg(m_sv->instrumentLabel(m_track));
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

    void beginRename()
    {
        SongDocument *doc = m_sv->document();
        if (!doc)
            return;
        if (!m_editor) {
            m_editor = new QLineEdit(this);
            m_editor->setObjectName(QStringLiteral("trackRenameEditor"));
            m_editor->installEventFilter(this);
            connect(m_editor, &QLineEdit::editingFinished, this,
                    [this] { finishRename(true, false); });
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
    void commitOpenRename() { finishRename(true, false); }

protected:
    void mouseDoubleClickEvent(QMouseEvent *event) override
    {
        m_sv->selectTrack(m_track);
        // The voice line opens the voice picker (its single click already
        // revealed the voice in the dock); anywhere else renames. Queued:
        // the picked voice's edit rebuilds the header panel, deleting this
        // row out from under its own event handler.
        if (voiceLineRect().contains(event->pos())) {
            QMetaObject::invokeMethod(
                m_sv, [sv = m_sv, t = m_track] { sv->editTrackVoice(t); },
                Qt::QueuedConnection);
            return;
        }
        beginRename();
    }

    void contextMenuEvent(QContextMenuEvent *event) override
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
        QAction *showVoiceAction =
            menu.addAction(SongView::tr("Show voice in voicegroup"));
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
                m_sv, [sv = m_sv, t = m_track] { sv->editTrackVoice(t); },
                Qt::QueuedConnection);
        } else if (chosen == duplicateAction) {
            QMetaObject::invokeMethod(
                m_sv, [sv = m_sv, t = m_track] { sv->duplicateTrack(t); },
                Qt::QueuedConnection);
        } else if (chosen == deleteAction) {
            QMetaObject::invokeMethod(
                m_sv, [sv = m_sv, t = m_track] { sv->deleteTrack(t); },
                Qt::QueuedConnection);
        }
    }

    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (watched == m_editor && event->type() == QEvent::KeyPress) {
            auto *keyEvent = static_cast<QKeyEvent *>(event);
            if (keyEvent->key() == Qt::Key_Escape) {
                finishRename(false, true);
                return true;
            }
            if (keyEvent->key() == Qt::Key_Return
                || keyEvent->key() == Qt::Key_Enter) {
                finishRename(true, true);
                return true;
            }
        }
        return QWidget::eventFilter(watched, event);
    }

    void resizeEvent(QResizeEvent *) override
    {
        // Rows are born 100px wide and only get their real width on the
        // deferred layout pass; an open editor must follow.
        if (m_editor)
            m_editor->setGeometry(editorRect());
    }

private:
    // The row's name line, clear of the color strip and the M/S column.
    QRect editorRect() const { return QRect(6, 2, width() - 32, 20); }

    void finishRename(bool commit, bool restoreFocus)
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

    SongView *m_sv;
    int m_track;
    QToolButton *m_mute;
    QToolButton *m_solo;
    QLineEdit *m_editor = nullptr;
    bool m_finishing = false;
    // Program painted on the voice line, for syncVoice's changed check
    // (-2 = never painted; distinct from -1, "no voice set").
    int m_shownProgram = -2;
    QPoint m_pressPos;
    bool m_dragArmed = false;
    bool m_dragging = false;
    bool m_voiceClickArmed = false;
};

class TrackHeaderPanel : public QWidget
{
public:
    explicit TrackHeaderPanel(SongView *sv)
        : QWidget(nullptr), m_sv(sv)
    {
        setObjectName(QStringLiteral("trackHeaderPanel"));
        m_layout = new QVBoxLayout(this);
        m_layout->setContentsMargins(0, 0, 0, 0);
        m_layout->setSpacing(0);
        m_layout->addStretch();
        // Reorder-drag drop indicator: a thin line floating over the rows at
        // the insertion point.
        m_indicator = new QWidget(this);
        m_indicator->setFixedHeight(3);
        m_indicator->setStyleSheet(QStringLiteral("background: palette(highlight);"));
        m_indicator->hide();
    }

    void rebuild()
    {
        // A document edit mid-drag rebuilds the rows, deleting the dragged
        // one out from under its own gesture; abandon the drag first.
        endRowDrag(false);
        qDeleteAll(m_rows);
        m_rows.clear();
        m_rowByTrack.clear();
        m_trackRows.clear();
        const MidiTimeline *tl = m_sv->timeline();
        if (tl) {
            for (int t = 0; t < 16; t++) {
                if (!tl->tracks[t].used)
                    continue;
                auto *row = new TrackHeaderRow(m_sv, t, this);
                row->setObjectName(QStringLiteral("trackHeaderRow%1").arg(t));
                m_rowByTrack[t] = row;
                row->updateToolTip();
                m_layout->insertWidget(m_layout->count() - 1, row);
                m_rows.push_back(row);
                m_trackRows.push_back(row);
            }
            SongDocument *doc = m_sv->document();
            if (doc && doc->canAddTrack()) {
                auto *add = new QToolButton(this);
                add->setText(SongView::tr("+ Add track"));
                add->setAutoRaise(true);
                add->setToolTip(SongView::tr("Add a track (picks its voice first)"));
                // Queued: the edit rebuilds this panel, deleting the button
                // out from under its own clicked handler.
                connect(add, &QToolButton::clicked, m_sv,
                        [sv = m_sv] { sv->addTrack(); }, Qt::QueuedConnection);
                m_layout->insertWidget(m_layout->count() - 1, add);
                m_rows.push_back(add);
            }
        }
    }

    void syncSelection()
    {
        for (QWidget *row : m_rows)
            row->update();
    }

    void beginRename(int track)
    {
        const auto it = m_rowByTrack.find(track);
        if (it != m_rowByTrack.end())
            it->second->beginRename();
    }

    // Called on every playhead/cursor move; each row repaints only when its
    // shown program actually changes.
    void syncVoices()
    {
        for (const auto &entry : m_rowByTrack)
            entry.second->syncVoice();
    }

    // --- header-row reorder drag (driven by TrackHeaderRow's mouse events;
    // the panel owns the state so a mid-drag rebuild can abandon it) ---

    bool beginRowDrag(int track)
    {
        if (m_dragFrom >= 0 || m_trackRows.size() < 2)
            return false;
        m_dragFrom = track;
        m_dropSlot = -1;
        QApplication::setOverrideCursor(Qt::ClosedHandCursor);
        return true;
    }

    void dragRowTo(QPoint pos)
    {
        if (m_dragFrom < 0)
            return;
        // Insertion slot: before the first row whose center is below the
        // cursor; past the last row otherwise.
        int slot = 0;
        for (const TrackHeaderRow *row : m_trackRows) {
            if (pos.y() > row->y() + row->height() / 2)
                slot++;
        }
        m_dropSlot = slot;
        const int y = slot < int(m_trackRows.size())
            ? m_trackRows[size_t(slot)]->y()
            : m_trackRows.back()->y() + m_trackRows.back()->height();
        m_indicator->setGeometry(0, y - 1, width(), 3);
        m_indicator->raise();
        m_indicator->show();
    }

    void endRowDrag(bool commit)
    {
        if (m_dragFrom < 0)
            return;
        const int from = m_dragFrom;
        const int slot = m_dropSlot;
        m_dragFrom = -1;
        m_dropSlot = -1;
        m_indicator->hide();
        QApplication::restoreOverrideCursor();
        if (!commit || slot < 0)
            return;
        int fromIdx = -1;
        for (size_t i = 0; i < m_trackRows.size(); i++) {
            if (m_trackRows[i]->track() == from)
                fromIdx = int(i);
        }
        // The slots adjacent to the dragged row leave it where it was.
        if (fromIdx < 0 || slot == fromIdx || slot == fromIdx + 1)
            return;
        const int target = m_trackRows[size_t(slot > fromIdx ? slot - 1 : slot)]->track();
        // The move's rebuild would destroy an open rename editor without a
        // focus-out (rows take no focus): commit it Reaper-style first. Its
        // queued commit runs before the queued move below, and renameTrack
        // renumbers nothing, so both captured track numbers stay valid.
        for (const auto &entry : m_rowByTrack)
            entry.second->commitOpenRename();
        // Queued: the edit rebuilds this panel, deleting the dragged row out
        // from under its own mouse-release handler.
        QMetaObject::invokeMethod(
            m_sv, [sv = m_sv, from, target] { sv->moveTrack(from, target); },
            Qt::QueuedConnection);
    }

private:
    SongView *m_sv;
    QVBoxLayout *m_layout;
    std::vector<QWidget *> m_rows;
    std::map<int, TrackHeaderRow *> m_rowByTrack;
    std::vector<TrackHeaderRow *> m_trackRows;
    QWidget *m_indicator = nullptr;
    int m_dragFrom = -1; // dragged engine track; -1 = no drag live
    int m_dropSlot = -1; // insertion slot the indicator marks
};

// The drag handlers live below TrackHeaderPanel because they drive it.

void TrackHeaderRow::mouseMoveEvent(QMouseEvent *event)
{
    auto *panel = static_cast<TrackHeaderPanel *>(parentWidget());
    if (!m_dragging) {
        if (!m_dragArmed || !(event->buttons() & Qt::LeftButton)
            || (event->pos() - m_pressPos).manhattanLength()
                < QApplication::startDragDistance())
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

// ------------------------------------------------------------------ SongView

using namespace songview;

// Vertical bar/beat grid lines inside rect, with zoom-adaptive sub-beat
// lines at the snap grid's positions fading lighter per subdivision level.
void SongView::drawGrid(QPainter &p, const QRect &rect, int origin) const
{
    if (!timeline())
        return;
    enum class GridLineBatch : size_t {
        SubdivisionLevel1,
        SubdivisionLevel2,
        SubdivisionLevel3,
        Beat,
        Bar,
        Count,
    };
    constexpr auto batchCount = static_cast<size_t>(GridLineBatch::Count);
    const auto t0 = std::max(0.0, tickAtContentX(rect.left() - origin));
    const auto t1 = tickAtContentX(rect.right() - origin) + 1;
    const auto drawBeats = pxPerBeat() >= 10.0;
    const auto barColor = palette().color(QPalette::Mid);
    auto beatColor = barColor;
    beatColor.setAlpha(70);
    auto lineBatches = std::array<QVector<QLine>, batchCount>{};
    time_ruler_detail::forEachSubGridLine(this, t0, t1, [&](uint64_t tick, int level) {
        const auto batch = static_cast<GridLineBatch>(level - 1);
        const auto batchIndex = static_cast<size_t>(batch);
        const auto x = origin + contentX(double(tick));
        lineBatches[batchIndex].append(
            QLine(x, rect.top(), x, rect.bottom()));
    });
    forEachGridLine(uint64_t(t0), uint64_t(t1),
                    [&](uint64_t tick, bool isBar, int) {
                        if (!isBar && !drawBeats)
                            return;
                        const auto batch = isBar ? GridLineBatch::Bar
                                                 : GridLineBatch::Beat;
                        const auto batchIndex = static_cast<size_t>(batch);
                        const auto x = origin + contentX(double(tick));
                        lineBatches[batchIndex].append(
                            QLine(x, rect.top(), x, rect.bottom()));
                    });
    const auto colors = std::array{m_subGridColors[0], m_subGridColors[1],
                                   m_subGridColors[2], beatColor, barColor};
    for (auto batchIndex = size_t{0}; batchIndex < lineBatches.size();
         ++batchIndex) {
        if (lineBatches[batchIndex].isEmpty())
            continue;
        p.setPen(colors[batchIndex]);
        p.drawLines(lineBatches[batchIndex]);
    }
}

SongView::SongView(QWidget *parent)
    : QWidget(parent)
{
    const auto lineColor = palette().color(QPalette::Mid);
    m_subGridColors[0] = lineColor;
    m_subGridColors[0].setAlpha(48);
    m_subGridColors[1] = lineColor;
    m_subGridColors[1].setAlpha(34);
    m_subGridColors[2] = lineColor;
    m_subGridColors[2].setAlpha(22);
    auto *vbox = new QVBoxLayout(this);
    vbox->setContentsMargins(0, 0, 0, 0);
    vbox->setSpacing(0);

    m_ruler = new TimeRuler(this);
    vbox->addWidget(m_ruler);

    // Roll (with headers) above, automation lanes below, split by a
    // draggable boundary; kLanesAreaH is only the initial lanes height.
    m_splitter = new QSplitter(Qt::Vertical, this);
    m_splitter->setChildrenCollapsible(false);
    auto *rollPane = new QWidget(m_splitter);
    auto *mid = new QHBoxLayout(rollPane);
    mid->setContentsMargins(0, 0, 0, 0);
    mid->setSpacing(0);
    auto *headerScroll = new QScrollArea(this);
    headerScroll->setFixedWidth(kHeaderW);
    headerScroll->setFrameShape(QFrame::NoFrame);
    headerScroll->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    headerScroll->setWidgetResizable(true);
    // The roll owns keyboard editing (delete, copy/paste); the scroll areas
    // must not steal its focus on click (QAbstractScrollArea defaults to
    // StrongFocus, which broke shortcuts right after a track switch).
    headerScroll->setFocusPolicy(Qt::NoFocus);
    m_headers = new TrackHeaderPanel(this);
    headerScroll->setWidget(m_headers);
    mid->addWidget(headerScroll);
    // The note grid and the raw event list share the roll's slot; the
    // headers, ruler, and lanes stay up whichever page is current.
    m_rollStack = new QStackedWidget(this);
    auto *rollPage = new QWidget(m_rollStack);
    auto *rollBox = new QHBoxLayout(rollPage);
    rollBox->setContentsMargins(0, 0, 0, 0);
    rollBox->setSpacing(0);
    m_roll = new PianoRoll(this);
    rollBox->addWidget(m_roll, 1);
    m_vbar = new QScrollBar(Qt::Vertical, this);
    rollBox->addWidget(m_vbar);
    m_rollStack->addWidget(rollPage);
    m_events = new EventListView(this);
    m_rollStack->addWidget(m_events);
    mid->addWidget(m_rollStack, 1);
    m_splitter->addWidget(rollPane);

    m_lanesScroll = new QScrollArea(this);
    m_lanesScroll->setFrameShape(QFrame::NoFrame);
    m_lanesScroll->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    m_lanesScroll->setWidgetResizable(true);
    m_lanesScroll->setFocusPolicy(Qt::NoFocus);
    m_lanes = new AutomationArea(this, m_lanesScroll);
    m_lanesScroll->setMinimumHeight(m_lanes->minimumSizeHint().height());
    m_lanesScroll->setWidget(m_lanes);
    m_splitter->addWidget(m_lanesScroll);
    m_splitter->setStretchFactor(0, 1);
    m_splitter->setStretchFactor(1, 0);
    vbox->addWidget(m_splitter, 1);

    m_strip = new OtherStrip(this);
    vbox->addWidget(m_strip);

    m_hbar = new QScrollBar(Qt::Horizontal, this);
    auto *hbarRow = new QHBoxLayout;
    hbarRow->addSpacing(kGutterW);
    hbarRow->addWidget(m_hbar);
    vbox->addLayout(hbarRow);

    connect(m_hbar, &QScrollBar::valueChanged, this, [this](int v) {
        if (m_scrollPx != v) {
            m_scrollPx = v;
            refreshTimelineViews();
        }
    });
    connect(m_vbar, &QScrollBar::valueChanged, this, [this](int v) {
        if (m_scrollY != v) {
            m_scrollY = v;
            m_roll->refresh();
        }
    });
}

void SongView::setSong(const MidiTimeline *timeline, const LoadedVoiceGroup *voicegroup)
{
    m_timeline = timeline;
    m_voicegroup = voicegroup;
    m_model = timeline ? buildSongViewModel(*timeline) : SongViewModel();
    m_emptyLanes.clear();
    m_selection.clear();
    m_timeSel = TimeSelection();
    m_clip = Clip();
    m_muteMask = 0;
    m_soloMask = 0;
    emit muteMaskChanged(0);
    emit soloMaskChanged(0);
    m_playheadTick = 0.0;
    m_editCursorTick = 0;
    m_playing = false;
    m_scrollPx = 0;
    m_events->setPlayheadTick(-1.0, false); // another song's ticks are stale
    // Lane heights and the snap grid are per-song view state; back to
    // defaults until a sidecar (applyViewState) says otherwise.
    m_lanes->setViewHeights(0, {});
    m_gridFeel = GridFeel::Straight;
    m_gridMinDenom = 0;
    m_snapToGrid = true;
    m_ruler->syncGridControls();

    m_selectedTrack = 0;
    if (timeline) {
        for (int t = 0; t < 16; t++) {
            if (timeline->tracks[t].used) {
                m_selectedTrack = t;
                break;
            }
        }
    }
    m_trackSelMask = 1u << m_selectedTrack;

    rebuildAfterSongChange();
}

void SongView::rebuildAfterSongChange()
{
    if (m_timeline) {
        // Default zoom: 32 px per beat, scrolled so the notes' pitch range
        // is centered in the roll.
        m_pxPerTick = 32.0 / double(m_timeline->ticksPerBeat);
        const int midKey = m_model.minNoteKey <= m_model.maxNoteKey
                               ? (m_model.minNoteKey + m_model.maxNoteKey) / 2
                               : 60;
        m_scrollY = std::max(0, (127 - midKey) * m_keyHeight
                                    - std::max(200, m_roll->height()) / 2);
    } else {
        m_pxPerTick = 1.0;
        m_scrollY = 0;
    }
    m_headers->rebuild();
    m_lanes->rebuildRows();
    updateScrollbars();
    refreshTimelineViews();
}

void SongView::updateSong(const MidiTimeline *timeline)
{
    m_timeline = timeline;
    m_model = timeline ? buildSongViewModel(*timeline) : SongViewModel();
    mergeEmptyLanes();

    if (timeline && !timeline->tracks[m_selectedTrack].used) {
        // The edited track disappeared (e.g. undo of its only events).
        m_selectedTrack = 0;
        for (int t = 0; t < 16; t++) {
            if (timeline->tracks[t].used) {
                m_selectedTrack = t;
                break;
            }
        }
    }

    // Keep only selection ids that still resolve to a note.
    std::vector<NoteId> keep;
    for (const NoteId &id : m_selection) {
        for (const ViewNote &note : m_model.notes) {
            if (note.track == m_selectedTrack && note.startTick == id.tick
                && note.key == id.key) {
                keep.push_back(id);
                break;
            }
        }
    }
    m_selection = std::move(keep);

    m_headers->rebuild();
    m_lanes->rebuildRows();
    updateScrollbars();
    refreshTimelineViews();
}

void SongView::setDocument(SongDocument *document)
{
    if (m_document != document) {
        if (m_document)
            disconnect(m_document, &SongDocument::trackMoved, this, nullptr);
        if (document)
            connect(document, &SongDocument::trackMoved, this,
                    &SongView::onTrackMoved);
    }
    m_document = document;
    m_selection.clear();
    m_headers->rebuild();   // the "+ Add track" button follows editability
    m_lanes->rebuildRows(); // the "+ Add lane" strip follows editability
    m_events->setDocument(document);
}

bool SongView::eventListVisible() const
{
    return m_rollStack->currentIndex() == 1;
}

void SongView::setEventListVisible(bool visible)
{
    if (eventListVisible() == visible)
        return;
    m_rollStack->setCurrentIndex(visible ? 1 : 0);
    if (visible) {
        // The list skips refreshes while its page is hidden; catch up now.
        m_events->refresh();
        m_events->syncTrackSelection();
    }
    focusContent();
    emit eventListVisibilityChanged(visible);
}

void SongView::focusContent()
{
    if (eventListVisible())
        m_events->setFocus();
    else
        m_roll->setFocus();
}

void SongView::addEmptyLane(int track, uint8_t cc)
{
    if (track < 0 || track > 15 || !m_timeline)
        return;
    const std::pair<int, uint8_t> key(track, cc);
    if (std::find(m_emptyLanes.begin(), m_emptyLanes.end(), key) == m_emptyLanes.end())
        m_emptyLanes.push_back(key);
    mergeEmptyLanes();
    m_lanes->rebuildRows();
}

void SongView::removeEmptyLane(int track, uint8_t cc)
{
    m_emptyLanes.erase(std::remove(m_emptyLanes.begin(), m_emptyLanes.end(),
                                   std::pair<int, uint8_t>(track, cc)),
                       m_emptyLanes.end());
    for (auto it = m_model.lanes.begin(); it != m_model.lanes.end(); ++it) {
        if (it->track == track && it->cc == cc && it->points.empty()) {
            m_model.lanes.erase(it);
            break;
        }
    }
    m_lanes->rebuildRows();
}

void SongView::mergeEmptyLanes()
{
    bool added = false;
    for (const std::pair<int, uint8_t> &key : m_emptyLanes) {
        if (m_model.findLane(key.first, key.second))
            continue;
        AutoLane lane;
        lane.track = uint8_t(key.first);
        lane.cc = key.second;
        if (key.second == LANE_CC_BEND) {
            lane.lane = M4aLane::PitchBend;
            lane.name = m4aLaneName(M4aLane::PitchBend);
        } else {
            const M4aCcInfo info = m4aClassifyCc(key.second);
            lane.lane = info.lane;
            lane.name = QString::fromLatin1(info.display);
        }
        m_model.lanes.push_back(std::move(lane));
        added = true;
    }
    if (added) {
        // Same order buildSongViewModel establishes.
        std::stable_sort(m_model.lanes.begin(), m_model.lanes.end(),
                         [](const AutoLane &a, const AutoLane &b) {
                             if (a.track != b.track)
                                 return a.track < b.track;
                             return a.cc < b.cc;
                         });
    }
}

SongView::ViewState SongView::viewState() const
{
    ViewState state;
    if (!m_timeline)
        return state;
    state.valid = true;
    state.pxPerBeat = m_pxPerTick * double(m_timeline->ticksPerBeat);
    state.keyHeight = m_keyHeight;
    state.scrollPx = m_scrollPx;
    state.scrollY = m_scrollY;
    state.selectedTrack = m_selectedTrack;
    state.editCursorTick = m_editCursorTick;
    state.laneHeight = m_lanes->laneHeight();
    state.laneHeights = m_lanes->rowHeightOverrides();
    state.splitterSizes = m_splitter->sizes();
    state.emptyLanes = m_emptyLanes;
    state.gridMinDenom = m_gridMinDenom;
    state.gridTriplet = m_gridFeel == GridFeel::Triplet;
    state.eventList = eventListVisible();
    return state;
}

void SongView::applyViewState(const ViewState &state)
{
    if (!state.valid || !m_timeline)
        return;
    const double tpb = double(m_timeline->ticksPerBeat);
    m_pxPerTick = std::clamp(state.pxPerBeat, kMinPxPerBeat, kMaxPxPerBeat) / tpb;
    m_keyHeight = std::clamp(state.keyHeight, kMinKeyHeight, kMaxKeyHeight);
    setGridMinDenom(state.gridMinDenom); // setter validates the denominator
    setGridFeel(state.gridTriplet ? GridFeel::Triplet : GridFeel::Straight);
    m_editCursorTick = std::min<uint64_t>(state.editCursorTick, m_timeline->lengthTicks);
    for (const std::pair<int, uint8_t> &lane : state.emptyLanes)
        if (lane.first >= 0 && lane.first < 16
            && std::find(m_emptyLanes.begin(), m_emptyLanes.end(), lane)
                   == m_emptyLanes.end())
            m_emptyLanes.push_back(lane);
    mergeEmptyLanes();
    m_lanes->setViewHeights(state.laneHeight, state.laneHeights);
    if (state.selectedTrack >= 0 && state.selectedTrack < 16
        && m_timeline->tracks[state.selectedTrack].used)
        selectTrack(state.selectedTrack);
    if (state.splitterSizes.size() == 2 && state.splitterSizes[0] > 0
        && state.splitterSizes[1] > 0) {
        // Real sizes exist; skip resizeEvent's default split.
        m_splitInit = true;
        m_splitter->setSizes(state.splitterSizes);
    }
    m_lanes->rebuildRows();
    updateScrollbars();
    setHScroll(std::max(0, state.scrollPx));
    m_vbar->setValue(std::max(0, state.scrollY));
    setEventListVisible(state.eventList);
    refreshTimelineViews();
}

void SongView::setVoicegroup(const LoadedVoiceGroup *voicegroup)
{
    m_voicegroup = voicegroup;
    m_headers->rebuild();
    refreshTimelineViews();
}

void SongView::setGridFeel(GridFeel feel)
{
    if (m_gridFeel == feel)
        return;
    m_gridFeel = feel;
    m_ruler->syncGridControls();
    refreshTimelineViews();
}

void SongView::setGridMinDenom(int denom)
{
    if (denom != 4 && denom != 8 && denom != 16 && denom != 32)
        denom = 0;
    if (m_gridMinDenom == denom)
        return;
    m_gridMinDenom = denom;
    m_ruler->syncGridControls();
    refreshTimelineViews();
}
void SongView::setSnapToGrid(bool enabled)
{
    if (m_snapToGrid == enabled)
        return;
    m_snapToGrid = enabled;
    m_ruler->syncGridControls();
    announce(enabled ? tr("Snap to grid enabled")
                     : tr("Snap to grid disabled"));
}


SongView::GridSeg SongView::gridSegAt(uint64_t tick) const
{
    GridSeg seg;
    if (!m_timeline)
        return seg;
    const uint64_t tpb = std::max<uint32_t>(1, m_timeline->ticksPerBeat);
    seg.beatTicks = tpb;
    for (const TimeSigPoint &ts : m_timeline->timeSigs) { // tick-sorted
        if (ts.tick > tick) {
            seg.next = ts.tick;
            break;
        }
        // Same-tick duplicates overwrite: the last at a tick wins, matching
        // forEachGridLine.
        seg.start = ts.tick;
        seg.beatTicks = std::max<uint64_t>(
            1, (uint64_t(tpb) * 4) >> std::min<int>(ts.denomPow2, 63));
    }
    return seg;
}

uint64_t SongView::gridTicksAt(uint64_t tick) const
{
    if (!m_timeline)
        return 24;
    return gridTicksIn(gridSegAt(tick));
}

uint64_t SongView::gridTicksIn(const GridSeg &seg) const
{
    const uint64_t clock = m_document ? m_document->ticksPerClock() : 1;
    // Finest visible subdivision at least ~8 px wide from the feel's ladder
    // (divisions per beat), floored at the mid2agb clock grid and at the
    // user's minimum note value. The floor is one division per beat of the
    // governing signature (1/4 = the beat); triplet feel fits three notes
    // where straight fits two, so the same denominator allows 3/2 the
    // divisions.
    static constexpr uint64_t kStraight[] = {32, 16, 8, 4, 2, 1};
    static constexpr uint64_t kTriplet[] = {48, 24, 12, 6, 3, 1};
    const bool triplet = m_gridFeel == GridFeel::Triplet;
    const uint64_t maxDiv = m_gridMinDenom == 0
        ? UINT64_MAX
        : std::max<uint64_t>(1, uint64_t(m_gridMinDenom) * (triplet ? 3 : 2) / 8);
    const double pxPerSegBeat = m_pxPerTick * double(seg.beatTicks);
    for (uint64_t div : triplet ? kTriplet : kStraight) {
        if (div > maxDiv)
            continue;
        if (pxPerSegBeat / double(div) >= 8.0)
            return std::max(std::max<uint64_t>(1, seg.beatTicks / div), clock);
    }
    return std::max(seg.beatTicks, clock);
}

uint64_t SongView::fineGridTicks() const
{
    return m_document ? std::max<uint32_t>(1, m_document->ticksPerClock())
                      : gridTicksAt(0);
}

uint64_t SongView::snapTick(double tick, bool fine) const
{
    tick = std::max(0.0, tick);
    if (!m_snapToGrid)
        return uint64_t(std::llround(tick));
    if (fine) {
        // The clock grid is the document's absolute resolution; it does not
        // restart at time-signature changes.
        const double g = double(fineGridTicks());
        return uint64_t(std::round(tick / g) * g);
    }
    const GridSeg seg = gridSegAt(uint64_t(tick));
    const uint64_t g = std::max<uint64_t>(1, gridTicksIn(seg));
    const uint64_t k = uint64_t((tick - double(seg.start)) / double(g));
    const uint64_t lo = seg.start + k * g;
    // The next signature's tick is itself a grid position (the grid
    // restarts there), so the upper candidate never crosses it.
    const uint64_t hi = std::min(lo + g, seg.next);
    return tick - double(lo) <= double(hi) - tick ? lo : hi;
}

uint64_t SongView::snapTickDown(double tick) const
{
    tick = std::max(0.0, tick);
    if (!m_snapToGrid)
        return uint64_t(std::floor(tick));
    const GridSeg seg = gridSegAt(uint64_t(tick));
    const uint64_t g = std::max<uint64_t>(1, gridTicksIn(seg));
    return seg.start + uint64_t((tick - double(seg.start)) / double(g)) * g;
}

uint64_t SongView::snapTickUp(double tick) const
{
    tick = std::max(0.0, tick);
    if (!m_snapToGrid)
        return uint64_t(std::ceil(tick));
    const GridSeg seg = gridSegAt(uint64_t(tick));
    const uint64_t g = std::max<uint64_t>(1, gridTicksIn(seg));
    const uint64_t lo =
        seg.start + uint64_t((tick - double(seg.start)) / double(g)) * g;
    if (double(lo) >= tick)
        return lo;
    // The next signature's tick is itself a grid position (the grid
    // restarts there), so the upper candidate never crosses it.
    return std::min(lo + g, seg.next);
}

bool SongView::isSelected(const ViewNote &note) const
{
    if (note.track != m_selectedTrack)
        return false;
    const NoteId id{note.startTick, note.key};
    return std::find(m_selection.begin(), m_selection.end(), id) != m_selection.end();
}

void SongView::setSelection(std::vector<NoteId> ids)
{
    m_selection = std::move(ids);
    // The two selection kinds are mutually exclusive, so Ctrl+C is never
    // ambiguous.
    if (!m_selection.empty() && m_timeSel.active())
        clearTimeSelection();
    m_roll->refresh();
}

void SongView::clearSelection()
{
    if (!m_selection.empty()) {
        m_selection.clear();
        m_roll->refresh();
    }
}

void SongView::setTimeSelection(const TimeSelection &sel)
{
    m_timeSel = sel;
    if (m_timeSel.active() && !m_selection.empty())
        m_selection.clear();
    refreshTimelineViews();
}

void SongView::clearTimeSelection()
{
    m_timeSel = TimeSelection();
    refreshTimelineViews();
}

bool SongView::timeSelectionCoversTrack(int track) const
{
    if (!m_timeSel.active() || track < 0 || track > 15)
        return false;
    if (m_timeSel.scope == TimeSelection::Lanes)
        return false;
    // Track scope is live: it always mirrors the header selection.
    return trackSelectionMask() & (1u << track);
}

bool SongView::timeSelectionCoversRow(int track, uint8_t cc) const
{
    if (!m_timeSel.active())
        return false;
    if (m_timeSel.scope == TimeSelection::Lanes)
        return std::find(m_timeSel.lanes.begin(), m_timeSel.lanes.end(),
                         std::pair<int, uint8_t>(track, cc))
            != m_timeSel.lanes.end();
    // Track scopes cover the track's CC/voice rows, never the global tempo.
    if (cc == DOC_CC_TEMPO)
        return false;
    return timeSelectionCoversTrack(track);
}

void SongView::announceTimeSelection()
{
    if (!m_timeSel.active() || !m_timeline)
        return;
    const double beats = double(m_timeSel.endTick - m_timeSel.startTick)
                         / double(std::max<uint32_t>(1, m_timeline->ticksPerBeat));
    QString scope;
    if (m_timeSel.scope == TimeSelection::Lanes) {
        scope = tr("%n lane(s)", nullptr, int(m_timeSel.lanes.size()));
    } else {
        const uint32_t mask = trackSelectionMask();
        int n = 0;
        for (int t = 0; t < 16; t++)
            n += (mask >> t) & 1;
        scope = tr("%n track(s)", nullptr, n);
    }
    emit statusMessage(tr("Time selection: %1 beats · %2 · Ctrl+C/X copies, "
                          "Del clears, Ctrl+V pastes at the edit cursor")
                           .arg(beats, 0, 'g', 4)
                           .arg(scope));
}

std::vector<int> SongView::timeSelectionTracks() const
{
    std::vector<int> tracks;
    if (!m_timeline || !m_document)
        return tracks;
    const uint32_t mask = trackSelectionMask();
    for (int t = 0; t < 16; t++) {
        if (!m_timeline->tracks[t].used || !(mask & (1u << t)))
            continue;
        if (m_document->smfTrackFor(t) < 0)
            continue;
        tracks.push_back(t);
    }
    return tracks;
}

std::vector<uint8_t> SongView::trackCcs(int track) const
{
    std::vector<uint8_t> ccs;
    for (const AutoLane &lane : m_model.lanes)
        if (lane.track == track)
            ccs.push_back(lane.cc); // LANE_CC_BEND == DOC_CC_BEND
    ccs.push_back(DOC_CC_VOICE);
    return ccs;
}

void SongView::copyTimeSelection()
{
    if (!m_document || !m_timeSel.active())
        return;
    const uint64_t s = m_timeSel.startTick;
    const uint64_t e = m_timeSel.endTick;
    Clip clip;
    clip.span = e - s;
    int noteCount = 0;
    int pointCount = 0;
    const auto copyLanePoints = [&](int track, uint8_t cc) {
        ClipLane lane{track, cc, {}};
        const int query = track < 0 ? m_selectedTrack : track;
        for (const DocLanePoint &pt : m_document->lanePoints(query, cc)) {
            if (pt.tick >= s && pt.tick < e)
                lane.points.push_back({uint32_t(pt.tick - s), pt.value});
        }
        pointCount += int(lane.points.size());
        // Empty segments are kept: they carry "this span is silent" so paste
        // clears the destination range.
        clip.lanes.push_back(std::move(lane));
    };
    if (m_timeSel.scope == TimeSelection::Lanes) {
        for (const std::pair<int, uint8_t> &id : m_timeSel.lanes)
            copyLanePoints(id.first, id.second);
    } else {
        for (int t : timeSelectionTracks()) {
            ClipTrack ct{t, {}};
            for (const DocNote &note : m_document->notesForTrack(t)) {
                if (note.tick < s || note.tick >= e)
                    continue;
                ct.notes.push_back({uint32_t(note.tick - s), note.key,
                                    note.duration ? note.duration
                                                  : uint32_t(gridTicksAt(note.tick)),
                                    note.velocity});
            }
            noteCount += int(ct.notes.size());
            clip.tracks.push_back(std::move(ct));
            for (uint8_t cc : trackCcs(t))
                copyLanePoints(t, cc);
        }
    }
    m_clip = std::move(clip);
    announce(tr("Copied range: %1 note(s), %2 automation point(s)")
                 .arg(noteCount)
                 .arg(pointCount));
}

void SongView::deleteTimeSelection()
{
    if (!m_document || !m_timeSel.active())
        return;
    const uint64_t s = m_timeSel.startTick;
    const uint64_t e = m_timeSel.endTick;
    SongDocument::RangeEdit edit;
    const auto removeLanePoints = [&](int track, uint8_t cc) {
        const int query = track < 0 ? m_selectedTrack : track;
        for (const DocLanePoint &pt : m_document->lanePoints(query, cc)) {
            if (pt.tick >= s && pt.tick < e)
                edit.removePoints.push_back(pt);
        }
    };
    if (m_timeSel.scope == TimeSelection::Lanes) {
        for (const std::pair<int, uint8_t> &id : m_timeSel.lanes)
            removeLanePoints(id.first, id.second);
    } else {
        for (int t : timeSelectionTracks()) {
            for (const DocNote &note : m_document->notesForTrack(t)) {
                if (note.tick >= s && note.tick < e)
                    edit.removeNotes.push_back(note);
            }
            for (uint8_t cc : trackCcs(t))
                removeLanePoints(t, cc);
        }
    }
    if (edit.empty()) {
        announce(tr("Nothing to delete in the time selection"));
        return;
    }
    const int notes = int(edit.removeNotes.size());
    const int points = int(edit.removePoints.size());
    m_document->applyRangeEdit(tr("delete range"), edit);
    announce(tr("Deleted range: %1 note(s), %2 automation point(s)")
                 .arg(notes)
                 .arg(points));
}

void SongView::transposeTimeSelection(int dKey)
{
    if (!m_document || !m_timeSel.active() || dKey == 0
        || m_timeSel.scope == TimeSelection::Lanes)
        return;
    const uint64_t s = m_timeSel.startTick;
    const uint64_t e = m_timeSel.endTick;
    std::vector<DocNote> notes;
    for (int t : timeSelectionTracks()) {
        for (const DocNote &note : m_document->notesForTrack(t)) {
            if (note.tick >= s && note.tick < e)
                notes.push_back(note);
        }
    }
    if (notes.empty()) {
        announce(tr("No notes in the time selection"));
        return;
    }
    for (const DocNote &note : notes) {
        const int key = int(note.key) + dKey;
        if (key < 0 || key > 127) {
            announce(tr("Transpose out of range"));
            return;
        }
    }
    m_document->moveNotes(notes, 0, dKey, /*mergeable=*/true);
    // Keep the moved notes in sight: the row the move headed toward
    // scrolls into view just enough (no re-centering).
    int edge = int(notes.front().key) + dKey;
    for (const DocNote &note : notes) {
        const int key = int(note.key) + dKey;
        edge = dKey > 0 ? std::max(edge, key) : std::min(edge, key);
    }
    ensureKeyVisible(edge);
    announce(tr("Transposed %n note(s) by %1", nullptr, int(notes.size()))
                 .arg(dKey > 0 ? QStringLiteral("+%1").arg(dKey)
                               : QString::number(dKey)));
}
void SongView::resizeTimeSelectionNotes(bool lengthen)
{
    if (!m_document || !m_timeSel.active()
        || m_timeSel.scope == TimeSelection::Lanes)
        return;
    std::vector<DocNote> notes;
    for (int track : timeSelectionTracks()) {
        for (const DocNote &note : m_document->notesForTrack(track)) {
            if (note.tick >= m_timeSel.startTick && note.tick < m_timeSel.endTick)
                notes.push_back(note);
        }
    }
    if (notes.empty())
        return;
    const int64_t step = int64_t(gridTicksAt(m_timeSel.startTick));
    m_document->resizeNotes(notes, lengthen ? step : -step);
}
void SongView::fitTimeSelectionNotes()
{
    if (!m_document || !m_timeSel.active()
        || m_timeSel.scope == TimeSelection::Lanes)
        return;
    const uint64_t selectionStart = m_timeSel.startTick;
    const uint64_t selectionEnd = m_timeSel.endTick;
    const std::vector<int> tracks = timeSelectionTracks();
    uint64_t contentStart = UINT64_MAX;
    uint64_t contentEnd = 0;
    for (int track : tracks) {
        for (const DocNote &note : m_document->notesForTrack(track)) {
            if (note.unterminated() || note.tick < selectionStart
                || note.tick >= selectionEnd)
                continue;
            contentStart = std::min(contentStart, note.tick);
            contentEnd = std::max(contentEnd, note.tick + note.duration);
        }
    }
    if (contentStart == UINT64_MAX || contentEnd <= contentStart
        || (contentStart == selectionStart && contentEnd == selectionEnd))
        return;
    const long double sourceSpan = contentEnd - contentStart;
    const long double targetSpan = selectionEnd - selectionStart;
    const auto mapTick = [&](uint64_t tick) {
        const long double offset = tick - contentStart;
        return selectionStart
            + uint64_t(std::llround(offset * targetSpan / sourceSpan));
    };
    int fitted = 0;
    SongDocument::RangeEdit rangeEdit;
    for (int track : tracks) {
        SongDocument::RangeEdit::TrackNotes replacementNotesByTrack{track, {}};
        for (const DocNote &note : m_document->notesForTrack(track)) {
            if (note.unterminated() || note.tick < selectionStart
                || note.tick >= selectionEnd)
                continue;
            const uint64_t tick = mapTick(note.tick);
            const uint64_t end = mapTick(note.tick + note.duration);
            const uint32_t duration = uint32_t(std::min<uint64_t>(
                UINT32_MAX, std::max<uint64_t>(1, end - tick)));
            rangeEdit.removeNotes.push_back(note);
            replacementNotesByTrack.notes.push_back(
                {tick, note.key, duration, note.velocity});
            fitted += tick != note.tick || duration != note.duration;
        }
        if (!replacementNotesByTrack.notes.empty())
            rangeEdit.addNotes.push_back(std::move(replacementNotesByTrack));
    }
    m_document->applyRangeEdit(tr("fit notes to time range"), rangeEdit);
    announce(tr("Fit %n note(s) to the time range", nullptr, fitted));
}


void SongView::nudgeTimeSelectionVelocity(int delta)
{
    if (!m_document || !m_timeSel.active() || delta == 0
        || m_timeSel.scope == TimeSelection::Lanes)
        return;
    std::vector<DocNote> notes;
    for (int track : timeSelectionTracks()) {
        for (const DocNote &note : m_document->notesForTrack(track)) {
            if (note.tick >= m_timeSel.startTick && note.tick < m_timeSel.endTick)
                notes.push_back(note);
        }
    }
    if (!notes.empty())
        m_document->nudgeNotesVelocity(notes, delta);
}


void SongView::nudgeTimeSelection(bool right)
{
    if (!m_document || !m_timeSel.active())
        return;
    const uint64_t s = m_timeSel.startTick;
    const uint64_t e = m_timeSel.endTick;
    const uint64_t snapped =
        right ? snapTickUp(double(s) + 1.0) : snapTickDown(double(s) - 1.0);
    const int64_t dTick = int64_t(snapped) - int64_t(s);
    if (dTick == 0)
        return;
    std::vector<DocNote> notes;
    std::vector<DocLanePoint> points;
    const auto gatherLanePoints = [&](int track, uint8_t cc) {
        const int query = track < 0 ? m_selectedTrack : track;
        for (const DocLanePoint &pt : m_document->lanePoints(query, cc)) {
            if (pt.tick >= s && pt.tick < e)
                points.push_back(pt);
        }
    };
    if (m_timeSel.scope == TimeSelection::Lanes) {
        for (const std::pair<int, uint8_t> &id : m_timeSel.lanes)
            gatherLanePoints(id.first, id.second);
    } else {
        for (int t : timeSelectionTracks()) {
            for (const DocNote &note : m_document->notesForTrack(t)) {
                if (note.tick >= s && note.tick < e)
                    notes.push_back(note);
            }
            for (uint8_t cc : trackCcs(t))
                gatherLanePoints(t, cc);
        }
    }
    m_document->moveRange(notes, points, dTick);
    // The band follows even over empty content, so repeated nudges keep
    // aiming at the same region.
    TimeSelection moved = m_timeSel;
    moved.startTick = uint64_t(int64_t(s) + dTick);
    moved.endTick = uint64_t(int64_t(e) + dTick);
    setTimeSelection(moved);
    ensureRangeVisible(moved.startTick, moved.endTick, right);
}

void SongView::removeTimeSelectionContents()
{
    if (!m_document || !m_timeline || !m_timeSel.active())
        return;
    const uint64_t s = m_timeSel.startTick;
    const uint64_t e = m_timeSel.endTick;
    SongDocument::RippleScope scope;
    QString scopeText;
    if (m_timeSel.scope == TimeSelection::Lanes) {
        scope.lanes = m_timeSel.lanes;
        scopeText = tr("%n lane(s)", nullptr, int(scope.lanes.size()));
    } else {
        scope.tracks = timeSelectionTracks();
        if (scope.tracks.empty())
            return;
        int used = 0;
        for (int t = 0; t < 16; t++)
            used += m_timeline->tracks[t].used ? 1 : 0;
        scope.wholeSong = int(scope.tracks.size()) == used;
        scopeText = scope.wholeSong
                        ? tr("all tracks")
                        : tr("%n track(s)", nullptr, int(scope.tracks.size()));
    }
    if (!m_document->removeTimeRange(s, e, scope)) {
        announce(tr("Nothing to remove in the time selection"));
        return;
    }
    // The span is gone and later content now sits under where the selection
    // was; clear it and park the edit cursor at the seam.
    clearTimeSelection();
    commitEditCursor(s);
    const double beats = double(e - s)
                         / double(std::max<uint32_t>(1, m_timeline->ticksPerBeat));
    announce(tr("Removed %1 beats on %2 — later events shifted left")
                 .arg(beats, 0, 'g', 4)
                 .arg(scopeText));
}

void SongView::pasteRangeAtEditCursor()
{
    if (!m_document || m_clip.span == 0 || m_clip.empty())
        return;
    const uint64_t s = snapTick(double(m_editCursorTick));
    const uint64_t e = s + m_clip.span;

    // A clip whose content came from one track retargets to the selected
    // track (cross-track copy); multi-track clips paste back in place.
    int sole = -2;
    bool multi = false;
    const auto consider = [&](int track) {
        if (track < 0)
            return; // tempo is global
        if (sole == -2)
            sole = track;
        else if (sole != track)
            multi = true;
    };
    for (const ClipTrack &ct : m_clip.tracks)
        consider(ct.track);
    for (const ClipLane &cl : m_clip.lanes)
        consider(cl.track);
    const auto mapTrack = [&](int track) {
        return track < 0 ? -1 : (multi ? track : m_selectedTrack);
    };

    SongDocument::RangeEdit edit;
    for (const ClipTrack &ct : m_clip.tracks) {
        const int t = mapTrack(ct.track);
        if (t < 0 || m_document->smfTrackFor(t) < 0)
            continue;
        // Replace: whatever notes start inside the destination span go away.
        for (const DocNote &note : m_document->notesForTrack(t)) {
            if (note.tick >= s && note.tick < e)
                edit.removeNotes.push_back(note);
        }
        if (!ct.notes.empty()) {
            SongDocument::RangeEdit::TrackNotes tn{t, {}};
            for (const ClipNote &cn : ct.notes)
                tn.notes.push_back(
                    {s + cn.relTick, cn.key, cn.duration, cn.velocity});
            edit.addNotes.push_back(std::move(tn));
        }
    }
    for (const ClipLane &cl : m_clip.lanes) {
        const int t = mapTrack(cl.track);
        if (t >= 0 && m_document->smfTrackFor(t) < 0)
            continue;
        const int query = t < 0 ? m_selectedTrack : t;
        for (const DocLanePoint &pt : m_document->lanePoints(query, cl.cc)) {
            if (pt.tick >= s && pt.tick < e)
                edit.removePoints.push_back(pt);
        }
        if (!cl.points.empty()) {
            SongDocument::RangeEdit::LaneWrite lw{t, cl.cc, {}};
            for (const std::pair<uint32_t, int> &pv : cl.points)
                lw.points.push_back({s + pv.first, pv.second});
            edit.addPoints.push_back(std::move(lw));
        }
    }
    m_document->applyRangeEdit(tr("paste range"), edit);

    // Set up for tiling: the edit cursor advances to the end of the pasted
    // span so repeated Ctrl+V lays copies back-to-back, and the selection is
    // cleared so its band doesn't sit in the way of the next ruler click.
    clearTimeSelection();
    commitEditCursor(e);
    // Anchor on the start of the pasted span, not the advanced cursor:
    // seeing the content that just landed is what confirms the paste.
    ensureTickVisible(s);
    announce(tr("Pasted range · edit cursor moved to its end — paste again to repeat"));
}


void SongView::announceNote(const ViewNote &note)
{
    if (!m_timeline)
        return;
    const bool ext = m_document && m_document->cfg().extendedClocks;
    const bool exact = m_document && m_document->cfg().exactGate;
    const int64_t ticks = int64_t(note.endTick) - int64_t(note.startTick);
    emit statusMessage(tr("%1 · velocity %2 → plays %3 · length %4 ticks → %5 clocks")
                           .arg(midiKeyName(note.key))
                           .arg(note.velocity)
                           .arg(mid2agbEffectiveVelocity(note.velocity))
                           .arg(ticks)
                           .arg(mid2agbEffectiveDuration(ticks, m_timeline->ticksPerBeat,
                                                         ext, exact)));
}

void SongView::auditionTimed(int track, int key, int velocity, uint64_t startTick,
                             uint64_t endTick)
{
    if (!m_timeline || endTick <= startTick)
        return;
    uint64_t dur = m_timeline->sampleForTick(endTick) - m_timeline->sampleForTick(startTick);
    // Safety cap: an unterminated note's span runs to the end of the song,
    // which is not a useful audition length.
    const uint64_t cap = uint64_t(m_timeline->sampleRate * 10.0);
    if (cap > 0)
        dur = std::min(dur, cap);
    if (dur > 0)
        emit auditionNoteTimed(track, key, velocity,
                               quint32(std::min<uint64_t>(dur, UINT32_MAX)));
}

void SongView::setPlayheadSample(uint64_t samplePos, bool playing)
{
    if (!m_timeline)
        return;
    m_playheadTick = m_timeline->tickForSample(samplePos);
    m_playing = playing;
    // Follow the playhead — but not while the user is mid-gesture (panning,
    // dragging notes or selections, sweeping automation): yanking the view
    // out from under a held mouse button is disorienting.
    if (playing && m_followPlayback && !userGestureActive()) {
        const int px = contentX(m_playheadTick);
        const int vw = viewportWidth();
        if (px < 0 || px > vw * 85 / 100)
            setHScroll(int(m_playheadTick * m_pxPerTick) - vw / 10);
    }
    // The event list mirrors the playhead as a tinted row (and follows it
    // while playing, mirroring the roll's scroll-follow).
    m_events->setPlayheadTick(m_playheadTick, playing && m_followPlayback);
    m_headers->syncVoices();
    refreshTimelineViews();
}

bool SongView::userGestureActive() const
{
    return (m_ruler && m_ruler->gestureActive())
        || (m_roll && m_roll->gestureActive())
        || (m_lanes && m_lanes->gestureActive());
}

void SongView::showTimeSelectionContextMenu(const QPoint &globalPosition)
{
    m_lanes->showTimeSelectionContextMenu(globalPosition);
}

void SongView::setEditCursorTick(uint64_t tick)
{
    if (m_editCursorTick == tick)
        return;
    m_editCursorTick = tick;
    m_headers->syncVoices();
    refreshTimelineViews();
}

void SongView::commitEditCursor(uint64_t tick)
{
    setEditCursorTick(tick);
    emit editCursorMoved(tick);
}

void SongView::goToStart()
{
    setHScroll(0);
    commitEditCursor(0);
}

double SongView::pxPerBeat() const
{
    return m_timeline ? m_pxPerTick * m_timeline->ticksPerBeat : m_pxPerTick * 24.0;
}

void SongView::selectTrack(int track)
{
    if (track == m_selectedTrack || track < 0 || track > 15)
        return;
    m_selectedTrack = track;
    // Programmatic selection collapses the multi-track scope;
    // trackHeaderClicked restores it for modifier clicks.
    m_trackSelMask = 1u << track;
    m_selection.clear();
    // A track-scoped time selection would keep rendering only in the ruler
    // once the shown track leaves its scope; drop it on any track switch.
    clearTimeSelection();
    m_headers->syncSelection();
    m_lanes->rebuildRows();
    // Switching tracks readies the roll for keyboard editing (e.g. copy on
    // one track, click another's header, paste), wherever focus was.
    m_roll->setFocus();
    m_roll->refresh();
    emit selectedTrackChanged(track);
}

uint32_t SongView::trackSelectionMask() const
{
    uint32_t used = 0;
    if (m_timeline) {
        for (int t = 0; t < 16; t++)
            if (m_timeline->tracks[t].used)
                used |= 1u << t;
    }
    const uint32_t mask = (m_trackSelMask | (1u << m_selectedTrack)) & used;
    return mask ? mask : (1u << m_selectedTrack);
}

void SongView::trackHeaderClicked(int track, Qt::KeyboardModifiers modifiers)
{
    if (track < 0 || track > 15)
        return;
    if (modifiers & Qt::ControlModifier) {
        uint32_t mask = trackSelectionMask() ^ (1u << track);
        if (mask == 0)
            return; // the scope can't go empty
        if (!(mask & (1u << m_selectedTrack))) {
            // The primary track was toggled out; hand primary to the lowest
            // remaining scoped track. This is a scope adjustment, not a
            // track switch, so the time selection survives (selectTrack
            // clears it and collapses the mask — restore both after).
            int next = 0;
            while (!(mask & (1u << next)))
                next++;
            const TimeSelection keep = m_timeSel;
            selectTrack(next);
            m_timeSel = keep;
        }
        m_trackSelMask = mask;
    } else if (modifiers & Qt::ShiftModifier) {
        const int lo = std::min(track, m_selectedTrack);
        const int hi = std::max(track, m_selectedTrack);
        uint32_t mask = 0;
        for (int t = lo; t <= hi; t++) {
            if (m_timeline && m_timeline->tracks[t].used)
                mask |= 1u << t;
        }
        m_trackSelMask = mask | (1u << m_selectedTrack);
    } else {
        selectTrack(track);
        m_trackSelMask = 1u << track; // collapse even when already primary
    }
    m_headers->syncSelection();
    // The time selection's track scope is live; repaint its bands.
    refreshTimelineViews();
}

void SongView::setTrackMute(int track, bool on)
{
    const uint32_t bit = 1u << track;
    const uint32_t mask = on ? (m_muteMask | bit) : (m_muteMask & ~bit);
    if (mask != m_muteMask) {
        m_muteMask = mask;
        emit muteMaskChanged(mask);
    }
}

void SongView::setTrackSolo(int track, bool on)
{
    const uint32_t bit = 1u << track;
    const uint32_t mask = on ? (m_soloMask | bit) : (m_soloMask & ~bit);
    if (mask != m_soloMask) {
        m_soloMask = mask;
        emit soloMaskChanged(mask);
    }
}

QColor SongView::trackColor(int track)
{
    // Golden-angle hue spacing keeps adjacent tracks visually distinct.
    return QColor::fromHsv(int(track * 137.508) % 360, 150, 205);
}

int SongView::currentProgram(int track) const
{
    if (!m_timeline)
        return -1;
    int prog = m_timeline->tracks[track].firstProgram;
    const uint64_t tick = m_playing ? uint64_t(m_playheadTick) : m_editCursorTick;
    for (const VoiceChange &vc : m_model.voices) {
        if (vc.tick > tick)
            break;
        if (vc.track == track)
            prog = vc.program;
    }
    return prog;
}

void SongView::revealVoice(int program)
{
    if (program >= 0 && program < 128)
        emit revealVoiceRequested(program);
}

void SongView::revealTrackVoice(int track)
{
    if (!m_timeline || track < 0 || track > 15)
        return;
    const int prog = currentProgram(track);
    if (prog < 0) {
        emit statusMessage(tr("Track %1 has no voice set.").arg(track + 1));
        return;
    }
    revealVoice(prog);
}

QSet<int> SongView::usedVoices() const
{
    QSet<int> used;
    if (!m_timeline)
        return used;
    for (int t = 0; t < 16; t++) {
        if (m_timeline->tracks[t].used && m_timeline->tracks[t].firstProgram >= 0)
            used.insert(m_timeline->tracks[t].firstProgram);
    }
    for (const VoiceChange &vc : m_model.voices)
        used.insert(vc.program);
    return used;
}

QString SongView::instrumentLabel(int track) const
{
    if (!m_timeline)
        return QString();
    const int prog = currentProgram(track);
    if (prog < 0)
        return tr("(no voice set)");
    QString name = voiceShortName(uint8_t(prog));
    return QStringLiteral("%1 %2").arg(prog, 3, 10, QLatin1Char('0')).arg(name);
}

QString SongView::voiceShortName(uint8_t program) const
{
    QString name;
    QString type;
    if (m_voicegroup && program < VOICEGROUP_SIZE) {
        name = QString::fromUtf8(m_voicegroup->voiceNames[program]).trimmed();
        type = m4aVoiceTypeName(m_voicegroup->voices[program].type);
    }
    if (name.isEmpty())
        return type.isEmpty() ? tr("Voice") : type;
    return QStringLiteral("%1 (%2)").arg(name, type);
}

bool SongView::pickVoice(const QString &title, int initialVoice, int *outVoice)
{
    VoicePickerDialog dialog(this, title, initialVoice, [this](int voice, int velocity) {
        emit auditionVoice(voice, kVoiceAuditionKey, velocity);
    });
    if (dialog.exec() != QDialog::Accepted)
        return false;
    *outVoice = dialog.selectedVoice();
    return true;
}

void SongView::editTrackVoice(int track)
{
    if (!m_document || track < 0 || track > 15)
        return;
    const std::vector<DocLanePoint> changes = m_document->lanePoints(track, DOC_CC_VOICE);
    const int initial = changes.empty() ? 0 : changes.front().value;
    int voice = initial;
    if (!pickVoice(tr("Track %1 voice").arg(track + 1), initial, &voice))
        return;
    if (changes.empty())
        m_document->addLanePoint(track, DOC_CC_VOICE, 0, voice);
    else if (voice != initial)
        m_document->moveLanePoint(track, DOC_CC_VOICE, changes.front(),
                                  changes.front().tick, voice);
}

void SongView::renameTrack(int track)
{
    if (!m_document || track < 0 || track > 15 || m_document->smfTrackFor(track) < 0)
        return;
    m_headers->beginRename(track);
}

void SongView::commitTrackRename(int track, const QString &name)
{
    if (!m_document || track < 0 || track > 15 || m_document->smfTrackFor(track) < 0)
        return;
    const QString trimmed = name.trimmed();
    if (nameIsLoopMarker(trimmed)) {
        announce(tr("\"%1\" is read by the song build as a loop or label "
                    "marker, so it can't be a track name.").arg(trimmed));
        return;
    }
    // Queued: the commit arrives from the header row's editor signal, and
    // the edit rebuilds the header panel — deleting that editor mid-signal.
    QMetaObject::invokeMethod(
        this,
        [this, track, trimmed] {
            if (m_document)
                m_document->renameTrack(track, trimmed);
        },
        Qt::QueuedConnection);
}

void SongView::addTrack()
{
    if (!m_document || !m_document->canAddTrack())
        return;
    int voice = 0;
    if (!pickVoice(tr("New track voice"), 0, &voice))
        return;
    const int track = m_document->addTrack(voice); // rebuilds via documentChanged
    if (track >= 0) {
        selectTrack(track);
        announce(tr("Added track %1").arg(track + 1));
    }
}

void SongView::duplicateTrack(int track)
{
    if (!m_document || track < 0 || track > 15 || m_document->smfTrackFor(track) < 0)
        return;
    const int copy = m_document->duplicateTrack(track); // rebuilds via documentChanged
    if (copy >= 0) {
        selectTrack(copy);
        announce(tr("Duplicated track %1 as track %2").arg(track + 1).arg(copy + 1));
    }
}

void SongView::deleteTrack(int track)
{
    if (!m_document || track < 0 || track > 15 || m_document->smfTrackFor(track) < 0)
        return;
    // Removing a chunk shifts every higher engine slot down by one; move
    // the per-track view state with it, before the document edit rebuilds
    // the headers and lanes.
    const uint32_t low = (1u << track) - 1;
    const uint32_t mute = (m_muteMask & low) | ((m_muteMask >> 1) & ~low);
    const uint32_t solo = (m_soloMask & low) | ((m_soloMask >> 1) & ~low);
    if (mute != m_muteMask) {
        m_muteMask = mute;
        emit muteMaskChanged(mute);
    }
    if (solo != m_soloMask) {
        m_soloMask = solo;
        emit soloMaskChanged(solo);
    }
    for (auto it = m_emptyLanes.begin(); it != m_emptyLanes.end();) {
        if (it->first == track) {
            it = m_emptyLanes.erase(it);
        } else {
            if (it->first > track)
                it->first--;
            ++it;
        }
    }
    if (m_selectedTrack > track)
        m_selectedTrack--;
    // Track slots shift; collapse the multi-track scope and drop the time
    // selection rather than remap them.
    m_trackSelMask = 1u << m_selectedTrack;
    clearTimeSelection();
    m_document->deleteTrack(track); // rebuilds via documentChanged
    announce(tr("Deleted track %1").arg(track + 1));
}

void SongView::moveTrack(int from, int to)
{
    if (!m_document)
        return;
    // The document decides validity; the per-track view state follows in
    // onTrackMoved, which the reorder op signals through — undo and redo
    // replay the same permutation, so the masks stay on their tracks.
    if (m_document->moveTrack(from, to)) // rebuilds via documentChanged
        announce(tr("Moved track %1 to slot %2").arg(from + 1).arg(to + 1));
}

void SongView::onTrackMoved(int, int, const QVector<int> &map)
{
    // A reorder op is applying or reverting (interactive move, undo, or
    // redo — the document emits each direction with the inverse map): rotate
    // the per-track view state along with the renumbered engine slots
    // (deleteTrack's shift, generalized). The note selection needs nothing:
    // it is (tick, key) on the selected track, and the selected track's
    // number moves with its notes. The document is mid-mutation: remap
    // state only, don't read it back.
    if (map.size() < 16)
        return;
    const auto newIndex = [&map](int t) {
        return t >= 0 && t < 16 ? map[t] : t;
    };
    const auto permuteMask = [&newIndex](uint32_t mask) {
        uint32_t out = 0;
        for (int t = 0; t < 16; t++) {
            if (mask & (1u << t))
                out |= 1u << newIndex(t);
        }
        return out;
    };
    const uint32_t mute = permuteMask(m_muteMask);
    const uint32_t solo = permuteMask(m_soloMask);
    if (mute != m_muteMask) {
        m_muteMask = mute;
        emit muteMaskChanged(mute);
    }
    if (solo != m_soloMask) {
        m_soloMask = solo;
        emit soloMaskChanged(solo);
    }
    for (auto &lane : m_emptyLanes)
        lane.first = newIndex(lane.first);
    m_selectedTrack = newIndex(m_selectedTrack);
    // The multi-track scope and time selection are track-addressed;
    // collapse them like deleteTrack does rather than remap.
    m_trackSelMask = 1u << m_selectedTrack;
    clearTimeSelection();
}

void SongView::forEachGridLine(uint64_t tickBegin, uint64_t tickEnd,
                               const std::function<void(uint64_t, bool, int)> &fn) const
{
    if (!m_timeline || tickEnd <= tickBegin)
        return;
    const uint32_t tpb = m_timeline->ticksPerBeat;

    struct Seg {
        uint64_t tick;
        uint64_t beatTicks;
        int beatsPerBar;
    };
    std::vector<Seg> segs;
    segs.push_back({0, tpb, 4});
    for (const TimeSigPoint &ts : m_timeline->timeSigs) {
        uint64_t beatTicks = (uint64_t(tpb) * 4) >> std::min<int>(ts.denomPow2, 63);
        if (beatTicks < 1)
            beatTicks = 1;
        const Seg seg{ts.tick, beatTicks, ts.numerator ? ts.numerator : 4};
        if (ts.tick == segs.back().tick)
            segs.back() = seg;
        else
            segs.push_back(seg);
    }

    int bar = 1;
    for (size_t i = 0; i < segs.size(); i++) {
        const Seg &seg = segs[i];
        const uint64_t segEnd =
            i + 1 < segs.size() ? segs[i + 1].tick : std::max<uint64_t>(tickEnd, seg.tick);
        const uint64_t clampedEnd = std::min(segEnd, tickEnd);
        if (seg.tick < clampedEnd) {
            uint64_t k = tickBegin > seg.tick ? (tickBegin - seg.tick) / seg.beatTicks : 0;
            for (uint64_t tick = seg.tick + k * seg.beatTicks; tick < clampedEnd;
                 tick += seg.beatTicks, k++) {
                if (tick < tickBegin)
                    continue;
                fn(tick, k % seg.beatsPerBar == 0, bar + int(k / seg.beatsPerBar));
            }
        }
        if (i + 1 < segs.size()) {
            const uint64_t segTicks = segs[i + 1].tick - seg.tick;
            const uint64_t barTicks = seg.beatTicks * seg.beatsPerBar;
            bar += int((segTicks + barTicks - 1) / barTicks);
        }
    }
}
void SongView::zoomToTickRange(uint64_t startTick, uint64_t endTick)
{
    if (!m_timeline || endTick <= startTick)
        return;
    const double tpb = double(m_timeline->ticksPerBeat);
    constexpr int margin = 24;
    const int available = std::max(1, viewportWidth() - 2 * margin);
    m_pxPerTick =
        std::clamp(double(available) / double(endTick - startTick),
                   kMinPxPerBeat / tpb, kMaxPxPerBeat / tpb);
    m_scrollPx = std::max(0, int(double(startTick) * m_pxPerTick) - margin);
    updateScrollbars();
    refreshTimelineViews();
}

void SongView::zoomToFullSong()
{
    if (!m_timeline || m_timeline->lengthTicks == 0)
        return;
    zoomToTickRange(0, m_timeline->lengthTicks);
}


void SongView::zoomAroundContentX(double factor, int anchorContentX)
{
    if (!m_timeline)
        return;
    const double tpb = double(m_timeline->ticksPerBeat);
    const double anchorTick = tickAtContentX(anchorContentX);
    m_pxPerTick = std::clamp(m_pxPerTick * factor, kMinPxPerBeat / tpb, kMaxPxPerBeat / tpb);
    m_scrollPx = std::max(0, int(anchorTick * m_pxPerTick) - anchorContentX);
    updateScrollbars();
    refreshTimelineViews();
}

void SongView::zoomKeyHeight(int wheelDelta, int anchorY)
{
    if (!m_timeline)
        return;
    // One key-height pixel per wheel notch; the accumulator makes fine
    // trackpad deltas add up instead of stepping on every event.
    m_keyZoomAccum += wheelDelta;
    const int steps = m_keyZoomAccum / 120;
    if (steps == 0)
        return;
    m_keyZoomAccum -= steps * 120;
    const int newH = std::clamp(m_keyHeight + steps, kMinKeyHeight, kMaxKeyHeight);
    if (newH == m_keyHeight)
        return;
    // Pin the key under the cursor: same content row before and after.
    const double row = double(anchorY + m_scrollY) / double(m_keyHeight);
    m_keyHeight = newH;
    m_scrollY = std::max(0, int(std::lround(row * newH)) - anchorY);
    updateScrollbars();
    m_roll->refresh();
}

void SongView::scrollByPx(int dx)
{
    setHScroll(m_scrollPx + dx);
}

void SongView::scrollRollBy(int dy)
{
    m_vbar->setValue(m_vbar->value() + dy);
}

void SongView::setHScroll(int px)
{
    px = std::clamp(px, 0, m_hbar->maximum());
    if (px == m_scrollPx)
        return;
    m_scrollPx = px;
    m_hbar->blockSignals(true);
    m_hbar->setValue(px);
    m_hbar->blockSignals(false);
    refreshTimelineViews();
}

void SongView::ensureTickVisible(uint64_t tick)
{
    const int x = contentX(double(tick));
    const int vw = viewportWidth();
    if (x >= 0 && x < vw)
        return;
    setHScroll(int(double(tick) * m_pxPerTick) - vw / 3);
}

void SongView::ensureRangeVisible(uint64_t startTick, uint64_t endTick, bool preferEnd)
{
    const int x0 = contentX(double(startTick));
    const int x1 = contentX(double(endTick));
    const int vw = viewportWidth();
    int dx = 0;
    if (x1 - x0 >= vw) // wider than the viewport: the leading edge wins
        dx = preferEnd ? x1 - vw + 1 : x0;
    else if (x1 >= vw)
        dx = x1 - vw + 1;
    else if (x0 < 0)
        dx = x0;
    if (dx != 0)
        setHScroll(m_scrollPx + dx);
}

void SongView::ensureKeyVisible(int key)
{
    const int y0 = (127 - key) * m_keyHeight - m_scrollY;
    const int y1 = y0 + m_keyHeight;
    const int vh = m_roll->height();
    if (y0 < 0)
        m_vbar->setValue(m_vbar->value() + y0);
    else if (y1 > vh)
        m_vbar->setValue(m_vbar->value() + y1 - vh);
}

int SongView::viewportWidth() const
{
    return std::max(50, m_roll->width() - kKeyboardW);
}

void SongView::updateScrollbars()
{
    const int lengthPx =
        m_timeline ? int(double(m_timeline->lengthTicks) * m_pxPerTick) + 100 : 0;
    m_hbar->setRange(0, std::max(0, lengthPx - viewportWidth()));
    m_hbar->setPageStep(viewportWidth());
    m_hbar->blockSignals(true);
    m_hbar->setValue(std::min(m_scrollPx, m_hbar->maximum()));
    m_hbar->blockSignals(false);
    m_scrollPx = m_hbar->value();

    const int rollContentH = 128 * m_keyHeight;
    m_vbar->setRange(0, std::max(0, rollContentH - m_roll->height()));
    m_vbar->setPageStep(m_roll->height());
    m_vbar->blockSignals(true);
    m_vbar->setValue(std::min(m_scrollY, m_vbar->maximum()));
    m_vbar->blockSignals(false);
    m_scrollY = m_vbar->value();
}

void SongView::refreshTimelineViews()
{
    m_ruler->refresh();
    m_roll->refresh();
    m_lanes->refresh();
    m_strip->update();
}

void SongView::resizeEvent(QResizeEvent *event)
{
    QWidget::resizeEvent(event);
    // The splitter starts with the lanes area at its classic fixed height;
    // sizes can only be applied once real geometry exists.
    if (!m_splitInit && m_splitter->height() > 0) {
        m_splitInit = true;
        m_splitter->setSizes(
            {std::max(120, m_splitter->height() - kLanesAreaH), kLanesAreaH});
    }
    updateScrollbars();
}
