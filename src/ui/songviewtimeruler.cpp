#include "ui/songviewtimeruler.hpp"

#include <QAction>
#include <QApplication>
#include <QComboBox>
#include <QDialog>
#include <QDialogButtonBox>
#include <QFontMetrics>
#include <QHBoxLayout>
#include <QLabel>
#include <QMenu>
#include <QMouseEvent>
#include <QPaintEvent>
#include <QPainter>
#include <QPainterPath>
#include <QResizeEvent>
#include <QSpinBox>
#include <QVBoxLayout>
#include <QWheelEvent>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <utility>
#include <vector>

#include "core/mid2agbtables.h"
#include "core/songdocument.h"
#include "liveshortcuts.hpp"
#include "ui/songview.h"

namespace songview {

namespace {

constexpr int kRulerH = 36;
constexpr int kRulerMarkerH = 14;

bool askTimeSignature(QWidget *parent, int *numerator, int *denomPow2)
{
    QDialog dialog(parent);
    dialog.setWindowTitle(SongView::tr("Time Signature"));
    auto *numeratorSpinBox = new QSpinBox(&dialog);
    numeratorSpinBox->setRange(1, 32);
    numeratorSpinBox->setValue(std::clamp(*numerator, 1, 32));
    auto *denominatorComboBox = new QComboBox(&dialog);
    for (int power = 0; power <= 5; power++)
        denominatorComboBox->addItem(QString::number(1 << power), power);
    denominatorComboBox->setCurrentIndex(std::clamp(*denomPow2, 0, 5));
    auto *rowLayout = new QHBoxLayout;
    rowLayout->addWidget(numeratorSpinBox);
    rowLayout->addWidget(new QLabel(QStringLiteral("/"), &dialog));
    rowLayout->addWidget(denominatorComboBox);
    auto *buttons =
        new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, &dialog);
    QObject::connect(buttons, &QDialogButtonBox::accepted, &dialog, &QDialog::accept);
    QObject::connect(buttons, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);
    auto *layout = new QVBoxLayout(&dialog);
    layout->addLayout(rowLayout);
    layout->addWidget(buttons);
    if (dialog.exec() != QDialog::Accepted)
        return false;
    *numerator = numeratorSpinBox->value();
    *denomPow2 = denominatorComboBox->currentData().toInt();
    return true;
}

QColor loopFill()
{
    return QColor(255, 200, 60, 16);
}

QColor loopEdge()
{
    return QColor(224, 168, 0);
}

QColor playheadColor()
{
    return QColor(226, 66, 66);
}

int subGridLevel(uint64_t relativeTick, uint64_t beatTicks, bool triplet)
{
    if (relativeTick % std::max<uint64_t>(1, beatTicks / (triplet ? 3 : 2)) == 0)
        return 1;
    if (relativeTick % std::max<uint64_t>(1, beatTicks / (triplet ? 6 : 4)) == 0)
        return 2;
    return 3;
}

} // namespace

namespace time_ruler_detail {

void drawOverlays(QPainter &painter, const SongView *songView, const QRect &rect,
                  int origin, bool timeSelectionCovered)
{
    const MidiTimeline *timeline = songView->timeline();
    if (!timeline)
        return;

    const SongView::TimeSelection &selection = songView->timeSelection();
    if (timeSelectionCovered && selection.active()) {
        const int startX = origin + songView->contentX(double(selection.startTick));
        const int endX = origin + songView->contentX(double(selection.endTick));
        if (endX > rect.left() && startX < rect.right()) {
            QColor fill = songView->palette().color(QPalette::Highlight);
            fill.setAlpha(30);
            painter.fillRect(QRect(QPoint(std::max(startX, rect.left()), rect.top()),
                                   QPoint(std::min(endX, rect.right()), rect.bottom())),
                             fill);
            painter.setPen(QPen(songView->palette().color(QPalette::Highlight), 1));
            painter.drawLine(startX, rect.top(), startX, rect.bottom());
            painter.drawLine(endX, rect.top(), endX, rect.bottom());
        }
    }
    if (timeline->loopStartTick != UINT64_MAX || timeline->loopEndTick != UINT64_MAX) {
        const int startX = timeline->loopStartTick != UINT64_MAX
                               ? origin + songView->contentX(double(timeline->loopStartTick))
                               : rect.left();
        const int endX = timeline->loopEndTick != UINT64_MAX
                             ? origin + songView->contentX(double(timeline->loopEndTick))
                             : rect.right();
        if (endX > rect.left() && startX < rect.right()) {
            painter.fillRect(QRect(QPoint(std::max(startX, rect.left()), rect.top()),
                                   QPoint(std::min(endX, rect.right()), rect.bottom())),
                             loopFill());
            painter.setPen(QPen(loopEdge(), 1));
            if (timeline->loopStartTick != UINT64_MAX)
                painter.drawLine(startX, rect.top(), startX, rect.bottom());
            if (timeline->loopEndTick != UINT64_MAX)
                painter.drawLine(endX, rect.top(), endX, rect.bottom());
        }
    }

    const int editCursorX = origin + songView->contentX(double(songView->editCursorTick()));
    if (editCursorX >= rect.left() && editCursorX <= rect.right()) {
        painter.setPen(
            QPen(songView->palette().color(QPalette::WindowText), 1, Qt::DashLine));
        painter.drawLine(editCursorX, rect.top(), editCursorX, rect.bottom());
    }

    const int playheadX = origin + songView->contentX(songView->playheadTick());
    if (playheadX >= rect.left() && playheadX <= rect.right()) {
        painter.setPen(QPen(playheadColor(), 1));
        painter.drawLine(playheadX, rect.top(), playheadX, rect.bottom());
    }
}

void forEachSubGridLine(const SongView *songView, double startTick, double endTick,
                        const std::function<void(uint64_t, int)> &callback)
{
    const bool triplet = songView->gridFeel() == SongView::GridFeel::Triplet;
    uint64_t tick = uint64_t(std::max(0.0, startTick));
    const uint64_t end = endTick <= 0.0 ? 0 : uint64_t(endTick);
    while (tick < end) {
        const SongView::GridSeg segment = songView->gridSegAt(tick);
        const uint64_t segmentEnd = std::min(segment.next, end);
        const uint64_t gridTicks = songView->gridTicksAt(tick);
        if (gridTicks > 0 && gridTicks < segment.beatTicks
            && songView->pxPerTick() * double(segment.beatTicks) >= 10.0) {
            const uint64_t gridIndex =
                tick > segment.start ? (tick - segment.start + gridTicks - 1) / gridTicks : 0;
            for (uint64_t gridTick = segment.start + gridIndex * gridTicks;
                 gridTick < segmentEnd; gridTick += gridTicks) {
                if ((gridTick - segment.start) % segment.beatTicks == 0)
                    continue;
                callback(gridTick,
                         subGridLevel(gridTick - segment.start, segment.beatTicks, triplet));
            }
        }
        if (segment.next >= end)
            break;
        tick = segment.next;
    }
}

} // namespace time_ruler_detail

class TimeRuler::State final : public QWidget
{
public:
    State(TimeRuler *ruler, SongView *songView)
        : QWidget(ruler), m_ruler(ruler), m_sv(songView)
    {
        setMouseTracking(true);
        m_selectLoopContentsAction = new QAction(m_ruler);
        live_shortcuts::configureAction(*m_selectLoopContentsAction,
                                        live_shortcuts::Command::SelectLoopContents);
        m_sv->addAction(m_selectLoopContentsAction);
        QObject::connect(m_selectLoopContentsAction, &QAction::triggered, m_ruler,
                         [this] { selectLoopContents(); });

        auto *gridBox = new QWidget(this);
        gridBox->setGeometry(0, 0, kGutterW - 4, kRulerH - 2);
        auto *row = new QHBoxLayout(gridBox);
        row->setContentsMargins(8, 0, 0, 0);
        row->setSpacing(4);
        auto *gridLabel = new QLabel(SongView::tr("Grid"), gridBox);
        gridLabel->setObjectName(QStringLiteral("gridLabel"));
        row->addWidget(gridLabel);
        auto *narrowGridAction = new QAction(m_ruler);
        live_shortcuts::configureAction(*narrowGridAction,
                                        live_shortcuts::Command::NarrowGrid);
        m_sv->addAction(narrowGridAction);
        QObject::connect(narrowGridAction, &QAction::triggered, m_ruler,
                         [this] { adjustGrid(true); });
        auto *widenGridAction = new QAction(m_ruler);
        live_shortcuts::configureAction(*widenGridAction,
                                        live_shortcuts::Command::WidenGrid);
        m_sv->addAction(widenGridAction);
        QObject::connect(widenGridAction, &QAction::triggered, m_ruler,
                         [this] { adjustGrid(false); });
        m_tripletAction = new QAction(m_ruler);
        live_shortcuts::configureAction(*m_tripletAction,
                                        live_shortcuts::Command::TripletGrid);
        m_tripletAction->setCheckable(true);
        m_sv->addAction(m_tripletAction);
        QObject::connect(m_tripletAction, &QAction::triggered, m_ruler, [this] {
            m_sv->setGridFeel(m_sv->gridFeel() == SongView::GridFeel::Triplet
                                  ? SongView::GridFeel::Straight
                                  : SongView::GridFeel::Triplet);
        });
        m_snapAction = new QAction(m_ruler);
        live_shortcuts::configureAction(*m_snapAction,
                                        live_shortcuts::Command::ToggleSnapToGrid);
        m_snapAction->setCheckable(true);
        m_sv->addAction(m_snapAction);
        QObject::connect(m_snapAction, &QAction::triggered, m_ruler,
                         [this] { m_sv->setSnapToGrid(!m_sv->snapToGrid()); });
        auto *fixedAdaptiveGridAction = new QAction(m_ruler);
        live_shortcuts::configureAction(*fixedAdaptiveGridAction,
                                        live_shortcuts::Command::FixedAdaptiveGrid);
        m_sv->addAction(fixedAdaptiveGridAction);
        QObject::connect(fixedAdaptiveGridAction, &QAction::triggered, m_ruler,
                         [this] { toggleAdaptiveGrid(); });
        m_divCombo = new QComboBox(gridBox);
        m_divCombo->addItem(SongView::tr("Auto"), 0);
        for (int denominator : {4, 8, 16, 32})
            m_divCombo->addItem(QStringLiteral("1/%1").arg(denominator), denominator);
        m_divCombo->setToolTip(
            SongView::tr("Finest snap subdivision. Auto follows the zoom down to "
                         "the mid2agb clock grid; 1/4 never snaps finer than beats."));
        m_feelCombo = new QComboBox(gridBox);
        m_feelCombo->addItem(SongView::tr("Straight"));
        m_feelCombo->addItem(SongView::tr("Triplet"));
        m_feelCombo->setToolTip(SongView::tr("Straight or triplet beat subdivisions."));
        for (QComboBox *combo : {m_divCombo, m_feelCombo}) {
            combo->setFocusPolicy(Qt::NoFocus);
            row->addWidget(combo);
        }
        row->addStretch(1);
        QObject::connect(m_divCombo, &QComboBox::activated, m_sv, [this](int index) {
            const int denominator = m_divCombo->itemData(index).toInt();
            if (denominator != 0)
                m_lastFixedDenom = denominator;
            m_sv->setGridMinDenom(denominator);
        });
        QObject::connect(m_feelCombo, &QComboBox::activated, m_sv, [this](int index) {
            m_sv->setGridFeel(index == 1 ? SongView::GridFeel::Triplet
                                         : SongView::GridFeel::Straight);
        });
    }

    void syncGridControls()
    {
        m_divCombo->setCurrentIndex(
            std::max(0, m_divCombo->findData(m_sv->gridMinDenom())));
        m_feelCombo->setCurrentIndex(m_sv->gridFeel() == SongView::GridFeel::Triplet ? 1
                                                                                     : 0);
        m_tripletAction->setChecked(m_sv->gridFeel() == SongView::GridFeel::Triplet);
        m_snapAction->setChecked(m_sv->snapToGrid());
    }

    bool gestureActive() const
    {
        return m_dragMarker >= 0 || m_dragTimeSig || m_placingCursor
            || m_rightPress || m_dragSelEdge >= 0;
    }

protected:
    void paintEvent(QPaintEvent *) override
    {
        QPainter painter(this);
        painter.fillRect(rect(), palette().color(QPalette::Window).darker(104));
        painter.setPen(palette().color(QPalette::Mid));
        painter.drawLine(0, height() - 1, width(), height() - 1);

        if (!m_sv->timeline()) {
            painter.setPen(palette().color(QPalette::PlaceholderText));
            painter.drawText(rect().adjusted(kGutterW + 8, 0, 0, 0), Qt::AlignVCenter,
                             SongView::tr("No song loaded — double-click a song in the browser."));
            return;
        }

        const QRect area(kGutterW, 0, width() - kGutterW, height());
        painter.setClipRect(area);

        time_ruler_detail::drawOverlays(painter, m_sv, area, kGutterW, true);

        const double startTick = std::max(0.0, m_sv->tickAtContentX(0));
        const double endTick = m_sv->tickAtContentX(area.width()) + 1;
        const QColor foreground = palette().color(QPalette::WindowText);

        painter.setPen(palette().color(QPalette::Mid));
        time_ruler_detail::forEachSubGridLine(m_sv, startTick, endTick,
                                               [&](uint64_t tick, int level) {
                                                   const int x = kGutterW + m_sv->contentX(double(tick));
                                                   painter.drawLine(x, height() - (level == 1 ? 5 : 3), x,
                                                                    height() - 1);
                                               });

        int lastLabelX = -1000;
        m_sv->forEachGridLine(uint64_t(startTick), uint64_t(endTick),
                              [&](uint64_t tick, bool isBar, int barNumber) {
                                  const int x = kGutterW + m_sv->contentX(double(tick));
                                  painter.setPen(foreground);
                                  painter.drawLine(x, isBar ? height() - 12 : height() - 6, x,
                                                   height() - 1);
                                  if (isBar && x - lastLabelX >= 30) {
                                      painter.drawText(x + 3, height() - 12,
                                                       QString::number(barNumber));
                                      lastLabelX = x;
                                  }
                              });

        const MidiTimeline *timeline = m_sv->timeline();
        QFont font = painter.font();
        font.setBold(true);
        painter.setFont(font);

        for (const SigChip &chip : sigChips()) {
            if (chip.x > area.right() || chip.labelX + chip.labelW < area.left())
                continue;
            painter.setPen(palette().color(chip.implicit ? QPalette::PlaceholderText
                                                          : QPalette::WindowText));
            painter.drawLine(chip.x, 0, chip.x, kRulerMarkerH - 1);
            if (chip.labelW > 0)
                painter.drawText(chip.labelX, 11,
                                 midiTimeSigLabel(chip.numerator, chip.denomPow2));
        }

        painter.setPen(loopEdge());
        if (timeline->loopStartTick != UINT64_MAX)
            painter.drawText(kGutterW + m_sv->contentX(double(timeline->loopStartTick)) + 2,
                             11, QStringLiteral("["));
        if (timeline->loopEndTick != UINT64_MAX)
            painter.drawText(kGutterW + m_sv->contentX(double(timeline->loopEndTick)) + 2,
                             11, QStringLiteral("]"));

        if (m_dragMarker >= 0 || m_dragTimeSig) {
            const int x = kGutterW + m_sv->contentX(double(m_dragTick));
            painter.setPen(QPen(m_dragMarker >= 0 ? loopEdge()
                                                  : palette().color(QPalette::WindowText),
                                2));
            painter.drawLine(x, 0, x, height());
        }

        const SongView::TimeSelection &selection = m_sv->timeSelection();
        if (selection.active()) {
            painter.setPen(QPen(palette().color(QPalette::Highlight), 2));
            const int startX = kGutterW + m_sv->contentX(double(selection.startTick));
            const int endX = kGutterW + m_sv->contentX(double(selection.endTick));
            painter.drawLine(startX, 0, startX, height() / 2);
            painter.drawLine(endX, 0, endX, height() / 2);
        }

        const int playheadX = kGutterW + m_sv->contentX(m_sv->playheadTick());
        if (playheadX >= area.left() && playheadX <= area.right()) {
            QPainterPath triangle;
            triangle.moveTo(playheadX - 4, height() - 12);
            triangle.lineTo(playheadX + 4, height() - 12);
            triangle.lineTo(playheadX, height() - 4);
            triangle.closeSubpath();
            painter.fillPath(triangle, playheadColor());
        }
    }

    void wheelEvent(QWheelEvent *event) override
    {
        const QPoint delta = event->angleDelta();
        if (event->modifiers() & Qt::ShiftModifier)
            m_sv->scrollByPx(-(delta.y() ? delta.y() : delta.x()));
        else if (delta.x() && !delta.y())
            m_sv->scrollByPx(-delta.x());
        else
            m_sv->zoomAroundContentX(std::pow(1.0015, delta.y()),
                                     int(event->position().x()) - kGutterW);
        event->accept();
    }

    void mousePressEvent(QMouseEvent *event) override
    {
        SongDocument *document = m_sv->document();
        const MidiTimeline *timeline = m_sv->timeline();
        if (!timeline || event->pos().x() < kGutterW)
            return;
        const uint64_t clickTick =
            m_sv->snapTick(m_sv->tickAtContentX(event->pos().x() - kGutterW));

        if (event->button() == Qt::RightButton) {
            if (!document)
                return;
            m_rightPress = true;
            m_rightPressPos = event->pos();
            m_selAnchor = clickTick;
            return;
        }
        if (event->button() != Qt::LeftButton)
            return;
        m_dragMarker = document ? hitMarker(event->pos()) : -1;
        if (m_dragMarker >= 0) {
            m_dragTick = clickTick;
            update();
            return;
        }
        uint64_t signatureTick;
        int signatureNumerator;
        int signatureDenomPow2;
        bool signatureImplicit;
        if (document
            && hitTimeSigChip(event->pos(), &signatureTick, &signatureNumerator,
                              &signatureDenomPow2, &signatureImplicit)
            && !signatureImplicit) {
            m_dragTimeSig = true;
            m_dragTimeSigFrom = signatureTick;
            m_dragTick = signatureTick;
            update();
            return;
        }
        m_dragSelEdge = document ? hitSelEdge(event->pos()) : -1;
        if (m_dragSelEdge >= 0)
            return;
        m_placingCursor = true;
        m_sv->setEditCursorTick(clickTick);
    }

    void mouseMoveEvent(QMouseEvent *event) override
    {
        const auto dragTick = [this, event] {
            return m_sv->snapTick(
                m_sv->tickAtContentX(std::max(kGutterW, event->pos().x()) - kGutterW));
        };
        if (m_rightPress) {
            if (!m_selSweep
                && (event->pos() - m_rightPressPos).manhattanLength()
                       >= QApplication::startDragDistance())
                m_selSweep = true;
            if (m_selSweep) {
                const uint64_t tick = dragTick();
                SongView::TimeSelection selection;
                selection.startTick = std::min(m_selAnchor, tick);
                selection.endTick = std::max(m_selAnchor, tick);
                m_sv->setTimeSelection(selection);
            }
            return;
        }
        if (m_dragMarker >= 0 || m_dragTimeSig) {
            m_dragTick = dragTick();
            update();
            return;
        }
        if (m_dragSelEdge >= 0) {
            SongView::TimeSelection selection = m_sv->timeSelection();
            const uint64_t tick = dragTick();
            if (m_dragSelEdge == 0)
                selection.startTick = tick;
            else
                selection.endTick = tick;
            if (selection.startTick > selection.endTick) {
                std::swap(selection.startTick, selection.endTick);
                m_dragSelEdge ^= 1;
            }
            m_sv->setTimeSelection(selection);
            return;
        }
        if (m_placingCursor) {
            m_sv->setEditCursorTick(dragTick());
            return;
        }
        uint64_t signatureTick;
        int signatureNumerator;
        int signatureDenomPow2;
        bool signatureImplicit;
        setCursor(m_sv->document()
                          && (hitMarker(event->pos()) >= 0
                              || hitSelEdge(event->pos()) >= 0
                              || hitTimeSigChip(event->pos(), &signatureTick,
                                                &signatureNumerator, &signatureDenomPow2,
                                                &signatureImplicit))
                      ? Qt::SplitHCursor
                      : Qt::ArrowCursor);
    }

    void mouseReleaseEvent(QMouseEvent *event) override
    {
        if (event->button() == Qt::RightButton && m_rightPress) {
            m_rightPress = false;
            if (m_selSweep) {
                m_selSweep = false;
                if (m_sv->timeSelection().active())
                    m_sv->announceTimeSelection();
                else
                    m_sv->clearTimeSelection();
            } else {
                showRulerMenu(m_selAnchor, event->globalPosition().toPoint());
            }
            return;
        }
        if (event->button() != Qt::LeftButton)
            return;
        if (m_placingCursor) {
            m_placingCursor = false;
            m_sv->commitEditCursor(m_sv->editCursorTick());
            return;
        }
        if (m_dragSelEdge >= 0) {
            m_dragSelEdge = -1;
            if (m_sv->timeSelection().active())
                m_sv->announceTimeSelection();
            else
                m_sv->clearTimeSelection();
            return;
        }
        if (m_dragTimeSig) {
            m_dragTimeSig = false;
            if (SongDocument *document = m_sv->document())
                document->moveTimeSig(m_dragTimeSigFrom, m_dragTick);
            update();
            return;
        }
        if (m_dragMarker < 0)
            return;
        const bool endMarker = m_dragMarker == 1;
        m_dragMarker = -1;
        if (SongDocument *document = m_sv->document())
            document->setLoopTick(endMarker, int64_t(m_dragTick));
        update();
    }

    void mouseDoubleClickEvent(QMouseEvent *event) override
    {
        SongDocument *document = m_sv->document();
        uint64_t signatureTick;
        int numerator;
        int denomPow2;
        bool implicit;
        if (event->button() != Qt::LeftButton || !document
            || !hitTimeSigChip(event->pos(), &signatureTick, &numerator, &denomPow2,
                               &implicit))
            return;
        m_dragTimeSig = false;
        m_placingCursor = false;
        if (askTimeSignature(this, &numerator, &denomPow2))
            document->setTimeSig(signatureTick, numerator, denomPow2);
        update();
    }

private:
    int hitMarker(QPoint position) const
    {
        const MidiTimeline *timeline = m_sv->timeline();
        if (!timeline || position.y() >= height() / 2)
            return -1;
        if (timeline->loopStartTick != UINT64_MAX
            && std::abs(kGutterW + m_sv->contentX(double(timeline->loopStartTick))
                        - position.x())
                   <= 6)
            return 0;
        if (timeline->loopEndTick != UINT64_MAX
            && std::abs(kGutterW + m_sv->contentX(double(timeline->loopEndTick))
                        - position.x())
                   <= 6)
            return 1;
        return -1;
    }

    struct SigChip {
        uint64_t tick;
        int numerator;
        int denomPow2;
        bool implicit;
        int x;
        int labelX;
        int labelW;
    };

    std::vector<SigChip> sigChips() const
    {
        std::vector<SigChip> chips;
        const MidiTimeline *timeline = m_sv->timeline();
        if (!timeline)
            return chips;
        QFont font = this->font();
        font.setBold(true);
        const QFontMetrics metrics(font);
        const auto add = [&](uint64_t tick, int numerator, int denomPow2, bool implicit) {
            const int x = kGutterW + m_sv->contentX(double(tick));
            chips.push_back({tick, numerator, denomPow2, implicit, x, x + 3,
                             metrics.horizontalAdvance(midiTimeSigLabel(numerator, denomPow2))});
        };
        if (timeline->timeSigs.empty() || timeline->timeSigs.front().tick != 0)
            add(0, 4, 2, true);
        for (size_t index = 0; index < timeline->timeSigs.size(); index++) {
            if (index + 1 < timeline->timeSigs.size()
                && timeline->timeSigs[index + 1].tick == timeline->timeSigs[index].tick)
                continue;
            const TimeSigPoint &signature = timeline->timeSigs[index];
            add(signature.tick, signature.numerator ? signature.numerator : 4,
                signature.denomPow2, false);
        }
        const uint64_t loopTicks[2] = {timeline->loopStartTick, timeline->loopEndTick};
        for (SigChip &chip : chips) {
            for (uint64_t loopTick : loopTicks) {
                if (loopTick == UINT64_MAX)
                    continue;
                const int bracketRight =
                    kGutterW + m_sv->contentX(double(loopTick)) + 8;
                if (bracketRight > chip.labelX
                    && bracketRight - 8 < chip.labelX + chip.labelW)
                    chip.labelX = bracketRight;
            }
        }
        for (size_t index = 0; index + 1 < chips.size(); index++) {
            if (chips[index].labelX + chips[index].labelW + 2 > chips[index + 1].x)
                chips[index].labelW = 0;
        }
        return chips;
    }

    bool hitTimeSigChip(QPoint position, uint64_t *tick, int *numerator, int *denomPow2,
                        bool *implicit) const
    {
        if (position.y() >= height() / 2)
            return false;
        const std::vector<SigChip> chips = sigChips();
        for (auto it = chips.rbegin(); it != chips.rend(); ++it) {
            const bool onStem = std::abs(it->x - position.x()) <= 4;
            const bool onLabel = it->labelW > 0 && position.x() >= it->labelX - 1
                && position.x() <= it->labelX + it->labelW + 2;
            if (onStem || onLabel) {
                *tick = it->tick;
                *numerator = it->numerator;
                *denomPow2 = it->denomPow2;
                *implicit = it->implicit;
                return true;
            }
        }
        return false;
    }

    void sigAtTick(uint64_t tick, int *numerator, int *denomPow2) const
    {
        *numerator = 4;
        *denomPow2 = 2;
        for (const TimeSigPoint &signature : m_sv->timeline()->timeSigs) {
            if (signature.tick > tick)
                break;
            *numerator = signature.numerator ? signature.numerator : 4;
            *denomPow2 = signature.denomPow2;
        }
    }

    int hitSelEdge(QPoint position) const
    {
        const SongView::TimeSelection &selection = m_sv->timeSelection();
        if (!selection.active() || position.y() >= height() / 2)
            return -1;
        if (std::abs(kGutterW + m_sv->contentX(double(selection.startTick)) - position.x())
            <= 5)
            return 0;
        if (std::abs(kGutterW + m_sv->contentX(double(selection.endTick)) - position.x())
            <= 5)
            return 1;
        return -1;
    }

    void showRulerMenu(uint64_t clickTick, const QPoint &globalPosition)
    {
        SongDocument *document = m_sv->document();
        const MidiTimeline *timeline = m_sv->timeline();
        if (!document || !timeline)
            return;
        QMenu menu(this);
        QAction *setStart = menu.addAction(SongView::tr("Set loop start here"));
        QAction *setEnd = menu.addAction(SongView::tr("Set loop end here"));
        QAction *remove = menu.addAction(SongView::tr("Remove loop markers"));
        remove->setEnabled(timeline->loopStartTick != UINT64_MAX
                           || timeline->loopEndTick != UINT64_MAX);
        menu.addAction(m_selectLoopContentsAction);
        QAction *loopFromSelection = nullptr;
        QAction *removeContents = nullptr;
        QAction *clearSelection = nullptr;
        const SongView::TimeSelection selection = m_sv->timeSelection();
        if (selection.active()) {
            menu.addSeparator();
            loopFromSelection = menu.addAction(SongView::tr("Set loop to selection"));
            removeContents =
                menu.addAction(SongView::tr("Remove selection contents (shift left)"));
            clearSelection = menu.addAction(SongView::tr("Clear time selection"));
        }
        menu.addSeparator();
        uint64_t signatureTick = clickTick;
        int signatureNumerator;
        int signatureDenomPow2;
        bool signatureImplicit = true;
        const bool onChip = hitTimeSigChip(m_rightPressPos, &signatureTick,
                                           &signatureNumerator, &signatureDenomPow2,
                                           &signatureImplicit);
        if (!onChip)
            sigAtTick(clickTick, &signatureNumerator, &signatureDenomPow2);
        QAction *editSignature =
            menu.addAction(onChip ? SongView::tr("Edit time signature…")
                                  : SongView::tr("Set time signature here…"));
        QAction *removeSignature = menu.addAction(SongView::tr("Remove time signature"));
        removeSignature->setEnabled(onChip && !signatureImplicit);
        QAction *chosen = menu.exec(globalPosition);
        if (chosen == setStart) {
            document->setLoopTick(false, int64_t(clickTick));
        } else if (chosen == setEnd) {
            document->setLoopTick(true, int64_t(clickTick));
        } else if (chosen == remove) {
            if (timeline->loopStartTick != UINT64_MAX)
                document->setLoopTick(false, -1);
            if (m_sv->timeline()->loopEndTick != UINT64_MAX)
                document->setLoopTick(true, -1);
        } else if (chosen && chosen == loopFromSelection) {
            document->setLoopTick(false, int64_t(selection.startTick));
            document->setLoopTick(true, int64_t(selection.endTick));
        } else if (chosen && chosen == removeContents) {
            m_sv->removeTimeSelectionContents();
        } else if (chosen && chosen == clearSelection) {
            m_sv->clearTimeSelection();
        } else if (chosen == editSignature) {
            if (askTimeSignature(this, &signatureNumerator, &signatureDenomPow2))
                document->setTimeSig(signatureTick, signatureNumerator, signatureDenomPow2);
        } else if (chosen == removeSignature) {
            document->deleteTimeSig(signatureTick);
        }
    }

    void selectLoopContents()
    {
        const MidiTimeline *timeline = m_sv->timeline();
        if (!timeline || timeline->loopStartTick == UINT64_MAX
            || timeline->loopEndTick == UINT64_MAX
            || timeline->loopEndTick <= timeline->loopStartTick)
            return;
        SongView::TimeSelection selection;
        selection.startTick = timeline->loopStartTick;
        selection.endTick = timeline->loopEndTick;
        m_sv->setTimeSelection(selection);
        m_sv->announce(SongView::tr("Selected loop contents"));
    }

    void adjustGrid(bool narrower)
    {
        constexpr std::array<int, 5> denominations = {4, 8, 16, 32, 0};
        const auto current =
            std::find(denominations.begin(), denominations.end(), m_sv->gridMinDenom());
        const int index = current == denominations.end()
                              ? int(denominations.size()) - 1
                              : int(std::distance(denominations.begin(), current));
        const int next =
            std::clamp(index + (narrower ? 1 : -1), 0, int(denominations.size()) - 1);
        const int denominator = denominations[size_t(next)];
        if (denominator != 0)
            m_lastFixedDenom = denominator;
        m_sv->setGridMinDenom(denominator);
    }

    void toggleAdaptiveGrid()
    {
        const int current = m_sv->gridMinDenom();
        if (current == 0) {
            m_sv->setGridMinDenom(m_lastFixedDenom);
            return;
        }
        m_lastFixedDenom = current;
        m_sv->setGridMinDenom(0);
    }

    TimeRuler *m_ruler;
    SongView *m_sv;
    int m_dragMarker = -1;
    uint64_t m_dragTick = 0;
    bool m_dragTimeSig = false;
    uint64_t m_dragTimeSigFrom = 0;
    bool m_placingCursor = false;
    bool m_rightPress = false;
    bool m_selSweep = false;
    QPoint m_rightPressPos;
    uint64_t m_selAnchor = 0;
    int m_dragSelEdge = -1;
    QComboBox *m_divCombo = nullptr;
    QComboBox *m_feelCombo = nullptr;
    QAction *m_tripletAction = nullptr;
    QAction *m_snapAction = nullptr;
    QAction *m_selectLoopContentsAction = nullptr;
    int m_lastFixedDenom = 16;
};

TimeRuler::TimeRuler(SongView *songView)
    : QWidget(songView), m_state(std::make_unique<State>(this, songView))
{
    setFixedHeight(kRulerH);
    m_state->setGeometry(rect());
}

TimeRuler::~TimeRuler() = default;

void TimeRuler::syncGridControls()
{
    m_state->syncGridControls();
}

bool TimeRuler::gestureActive() const
{
    return m_state->gestureActive();
}

void TimeRuler::refresh()
{
    m_state->update();
}

void TimeRuler::resizeEvent(QResizeEvent *event)
{
    QWidget::resizeEvent(event);
    m_state->setGeometry(rect());
}

} // namespace songview
