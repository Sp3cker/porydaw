#include <algorithm>
#include <cstdio>
#include <cstring>
#include <memory>
#include <utility>
#include <vector>

#include <QApplication>
#include <QCoreApplication>
#include <QInputDialog>
#include <QMenu>
#include <QMouseEvent>
#include <QTimer>

#include "core/miditimeline.h"
#include "core/timedefaults.h"
#include "project/decompproject.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/songview.h"
#include "ui/songview/tempostrip.h"

extern "C" {
#include "voicegroup_loader.h"
}

namespace {

int bpm(const TempoPoint &point)
{
    return qRound(CoreTimeDefaults::tempoBpm(point.microsecondsPerQuarterNote));
}

bool hasTempoPoint(const SongDocument &document, uint64_t tick, int value)
{
    return std::any_of(document.tempoPoints().cbegin(), document.tempoPoints().cend(),
                       [tick, value](const TempoPoint &point) {
                           return point.tick == tick && bpm(point) == value;
                       });
}

void replaceTempo(SongDocument &document, std::vector<TempoPoint> points)
{
    TempoEdit edit;
    edit.remove = document.tempoPoints();
    edit.add = std::move(points);
    document.applyTempoEdit(edit);
    document.undoStack()->clear();
}

class TempoStripCheckRig final
{
  public:
    static std::unique_ptr<TempoStripCheckRig> create(const QString &project, const QString &song,
                                                      QString *error)
    {
        DecompProject decomp;
        if (!decomp.open(project, error))
            return nullptr;
        const auto found =
            std::find_if(decomp.songs().cbegin(), decomp.songs().cend(),
                         [&song](const SongInfo &candidate) { return candidate.label == song; });
        if (found == decomp.songs().cend()) {
            *error = QStringLiteral("no playable song %1").arg(song);
            return nullptr;
        }
        auto result = std::unique_ptr<TempoStripCheckRig>(new TempoStripCheckRig);
        if (!result->initialize(*found, error))
            return nullptr;
        return result;
    }

    ~TempoStripCheckRig()
    {
        m_strip.reset();
        if (m_view) {
            m_view->setSong(nullptr, nullptr);
            m_view->setDocument(nullptr);
        }
    }

    SongDocument &document() noexcept { return *m_document; }
    SongView &view() noexcept { return *m_view; }
    songview::TempoStrip &strip() noexcept { return *m_strip; }

    QPointF pointAt(uint64_t tick, int value) const
    {
        const AutomationGeometry geometry = AutomationGeometry::resolve();
        const QRect body = m_strip->rect();
        return {m_view->displayX(tick, m_strip->plotOrigin(), m_strip->devicePixelRatioF()),
                AutomationProjection::valueY(body, geometry, CoreTimeDefaults::kMinTempoBpm,
                                             CoreTimeDefaults::kMaxTempoBpm, value)};
    }

    void mouse(QEvent::Type type, QPointF point, Qt::MouseButton button,
               Qt::MouseButtons buttons = Qt::NoButton,
               Qt::KeyboardModifiers modifiers = Qt::NoModifier)
    {
        QMouseEvent event(type, point, QPointF(m_strip->mapToGlobal(point.toPoint())), button,
                          buttons, modifiers);
        QCoreApplication::sendEvent(m_strip.get(), &event);
    }

    void press(QPointF point, Qt::KeyboardModifiers modifiers = Qt::NoModifier,
               Qt::MouseButton button = Qt::LeftButton)
    {
        mouse(QEvent::MouseButtonPress, point, button, button, modifiers);
    }

    void move(QPointF point, Qt::MouseButtons buttons = Qt::LeftButton,
              Qt::KeyboardModifiers modifiers = Qt::NoModifier)
    {
        mouse(QEvent::MouseMove, point, Qt::NoButton, buttons, modifiers);
    }

    void release(QPointF point, Qt::KeyboardModifiers modifiers = Qt::NoModifier,
                 Qt::MouseButton button = Qt::LeftButton)
    {
        mouse(QEvent::MouseButtonRelease, point, button, Qt::NoButton, modifiers);
    }

    bool doubleClickWithBpm(QPointF point, int value)
    {
        bool accepted = false;
        QTimer::singleShot(0, [&accepted, value] {
            auto *dialog = qobject_cast<QInputDialog *>(QApplication::activeModalWidget());
            if (!dialog)
                return;
            dialog->setIntValue(value);
            accepted = true;
            dialog->accept();
        });
        mouse(QEvent::MouseButtonDblClick, point, Qt::LeftButton, Qt::LeftButton);
        return accepted;
    }

    bool chooseMenuAction(QPointF point, const QString &text)
    {
        bool triggered = false;
        QTimer::singleShot(0, [this, &text, &triggered] {
            auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
            if (!menu) {
                const auto menus = m_strip->findChildren<QMenu *>();
                if (!menus.empty())
                    menu = menus.back();
            }
            if (!menu)
                return;
            const auto actions = menu->actions();
            const auto found = std::find_if(actions.cbegin(), actions.cend(), [&text](QAction *a) {
                return a && a->text() == text && a->isEnabled();
            });
            if (found == actions.cend()) {
                menu->close();
                return;
            }
            triggered = true;
            (*found)->trigger();
        });
        press(point, Qt::NoModifier, Qt::RightButton);
        release(point, Qt::NoModifier, Qt::RightButton);
        QCoreApplication::processEvents();
        return triggered;
    }

  private:
    bool initialize(const SongInfo &song, QString *error)
    {
        m_document = std::make_unique<SongDocument>();
        if (!m_document->load(song, error))
            return false;
        m_timeline = m_document->buildTimeline(48000.0);
        if (!m_timeline) {
            *error = QStringLiteral("could not build timeline for %1").arg(song.label);
            return false;
        }
        m_voicegroup = std::make_unique<LoadedVoiceGroup>();
        std::strncpy(m_voicegroup->voiceNames[0], "tempo-strip-voice",
                     sizeof(m_voicegroup->voiceNames[0]) - 1);
        m_view = std::make_unique<SongView>();
        m_view->resize(960, 720);
        m_view->setDocument(m_document.get());
        m_view->setSong(m_timeline.get(), m_voicegroup.get());
        m_view->setEditorTimeZoom(96.0);
        m_strip = std::make_unique<songview::TempoStrip>(*m_view);
        m_strip->resize(960, m_strip->height());
        m_strip->show();
        m_view->show();
        QCoreApplication::processEvents();
        return true;
    }

    std::unique_ptr<SongDocument> m_document;
    std::unique_ptr<LoadedVoiceGroup> m_voicegroup;
    std::unique_ptr<MidiTimeline> m_timeline;
    std::unique_ptr<SongView> m_view;
    std::unique_ptr<songview::TempoStrip> m_strip;
};

} // namespace

int runTempoStripCheck(const QString &project, const QString &song)
{
    QString error;
    auto rig = TempoStripCheckRig::create(project, song, &error);
    if (!rig) {
        std::fprintf(stderr, "tempo-strip-check: %s\n", qUtf8Printable(error));
        return 1;
    }

    auto failures = 0;
    const auto expect = [&failures](bool condition, const QString &message) {
        if (condition)
            return;
        std::fprintf(stderr, "tempo-strip-check: %s\n", qUtf8Printable(message));
        ++failures;
    };
    const AutomationGeometry geometry = AutomationGeometry::resolve();
    const QPointF plotPoint = rig->pointAt(96, 120);
    expect(rig->strip().height() == geometry.rowDefaultHeight &&
               rig->strip().minimumHeight() == geometry.rowDefaultHeight &&
               rig->strip().maximumHeight() == geometry.rowDefaultHeight,
           QStringLiteral("strip height is not fixed to rowDefaultHeight"));
    expect(rig->strip().plotOrigin() == geometry.plotOrigin &&
               qFuzzyCompare(
                   plotPoint.x() + 1.0,
                   rig->view().displayX(96, geometry.plotOrigin, rig->strip().devicePixelRatioF()) +
                       1.0),
           QStringLiteral("strip plot origin does not align with the SongView projection"));

    replaceTempo(rig->document(), {{96, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(120)},
                                   {192, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(100)}});
    const QPointF dragStart = rig->pointAt(96, 120);
    const QPointF dragEnd = dragStart + QPointF(80.0, 1.0);
    const uint64_t dragRevision = rig->document().revision();
    const int dragUndo = rig->document().undoStack()->index();
    rig->press(dragStart, Qt::ShiftModifier);
    rig->move(dragStart + QPointF(10.0, 0.0), Qt::LeftButton, Qt::ShiftModifier);
    rig->move(dragEnd, Qt::LeftButton, Qt::ShiftModifier);
    rig->release(dragEnd, Qt::ShiftModifier);
    expect(rig->document().revision() == dragRevision + 1 &&
               rig->document().undoStack()->index() == dragUndo + 1 &&
               std::any_of(
                   rig->document().tempoPoints().cbegin(), rig->document().tempoPoints().cend(),
                   [](const TempoPoint &point) { return point.tick != 96 && bpm(point) == 120; }),
           QStringLiteral("Shift node drag did not move exactly one tempo node in one undo step"));

    replaceTempo(rig->document(), {{96, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(110)},
                                   {192, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(100)}});
    const uint64_t addTick = rig->view().snapTick(288.0);
    const QPointF addPoint = rig->pointAt(addTick, 140);
    const int addUndo = rig->document().undoStack()->index();
    expect(rig->doubleClickWithBpm(addPoint, 140) && hasTempoPoint(rig->document(), addTick, 140) &&
               rig->document().undoStack()->index() == addUndo + 1,
           QStringLiteral("double-click BPM dialog did not add its tempo point"));

    replaceTempo(rig->document(), {{96, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(110)},
                                   {192, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(100)}});
    const uint64_t deleteRevision = rig->document().revision();
    const int deleteUndo = rig->document().undoStack()->index();
    const QPointF deletePoint = rig->pointAt(96, 110);
    rig->press(deletePoint);
    rig->release(deletePoint);
    expect(!hasTempoPoint(rig->document(), 96, 110) &&
               rig->document().revision() == deleteRevision + 1 &&
               rig->document().undoStack()->index() == deleteUndo + 1,
           QStringLiteral("stationary click did not delete one tempo node"));

    replaceTempo(rig->document(), {{96, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(110)},
                                   {192, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(100)}});
    const QPointF bandStart = rig->pointAt(96, 110) + QPointF(20.0, 0.0);
    const QPointF bandEnd = rig->pointAt(192, 100) + QPointF(20.0, 0.0);
    rig->press(bandStart, Qt::NoModifier, Qt::RightButton);
    rig->move(bandEnd, Qt::RightButton);
    rig->release(bandEnd, Qt::NoModifier, Qt::RightButton);
    const auto &band = rig->view().selectionModel().timeSelection();
    expect(band.active() && band.scope == songview::EditorSelectionModel::TimeSelection::Lanes &&
               band.tempo && band.lanes.empty(),
           QStringLiteral("right-drag did not publish a tempo-only lane selection"));

    replaceTempo(rig->document(), {{96, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(110)},
                                   {192, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(100)}});
    const QPointF gutter(rig->strip().plotOrigin() / 2.0, rig->strip().height() / 2.0);
    expect(rig->chooseMenuAction(gutter, QStringLiteral("Copy")),
           QStringLiteral("tempo Copy menu action was unavailable"));
    replaceTempo(rig->document(), {{48, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(80)}});
    expect(rig->chooseMenuAction(gutter, QStringLiteral("Paste")) &&
               hasTempoPoint(rig->document(), 96, 110) && hasTempoPoint(rig->document(), 192, 100),
           QStringLiteral("tempo Paste menu action did not restore the copied lane"));
    expect(rig->chooseMenuAction(gutter, QStringLiteral("Clear Tempo")) &&
               rig->document().tempoPoints().empty(),
           QStringLiteral("tempo Clear menu action did not remove every tempo point"));

    replaceTempo(rig->document(), {{96, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(110)},
                                   {192, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(100)}});
    const QPointF staleStart = rig->pointAt(96, 110);
    const QPointF staleEnd = staleStart + QPointF(80.0, 1.0);
    rig->press(staleStart, Qt::ShiftModifier);
    rig->move(staleStart + QPointF(10.0, 0.0), Qt::LeftButton, Qt::ShiftModifier);
    rig->move(staleEnd, Qt::LeftButton, Qt::ShiftModifier);
    TempoEdit external;
    external.add.push_back({240, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(90)});
    rig->document().applyTempoEdit(external);
    const uint64_t staleRevision = rig->document().revision();
    const int staleUndo = rig->document().undoStack()->index();
    rig->release(staleEnd, Qt::ShiftModifier);
    expect(rig->document().revision() == staleRevision &&
               rig->document().undoStack()->index() == staleUndo &&
               hasTempoPoint(rig->document(), 240, 90),
           QStringLiteral("stale document revision committed a tempo gesture"));

    return failures == 0 ? 0 : 1;
}
