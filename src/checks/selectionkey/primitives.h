#pragma once

// Shared primitives for the selectionkey checks: real QTest delivery, live
// keymap resolution, isolated standalone-rig assembly, document note lookups,
// focus diagnostics.
// MainWindow session lifecycle remains in session.h. This is deliberately not
// a test framework: it owns only the few identical seams used by more than
// one selection-routing tier.

#include "checks/support/editorrig.h"
#include "checks/support/eventsynth.h"
#include "checks/support/songfixture.h"
#include "core/songdocument.h"
#include "ui/keymap.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"

#include <QCoreApplication>
#include <QEvent>
#include <QKeySequence>
#include <QObject>
#include <QPointF>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRect>
#include <QString>
#include <QtGlobal>
#include <QtTest>
#include <memory>
#include <optional>
#include <utility>
#include <vector>

namespace selectionkey {

// Drain posted events twice so Quick relayout and workspace publications land
// before the next assertion.
inline void settle()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

// QTest delivery into the real Quick window: Qt delivery evidence, never an
// OS-injection claim.

inline bool deliverKey(QQuickWindow *window, Qt::Key key,
                       Qt::KeyboardModifiers modifiers = Qt::NoModifier)
{
    if (!window)
        return false;
    QTest::keyClick(window, key, modifiers);
    settle();
    return true;
}

// QTest delivery into a shown Quick window. Pointer callers choose when to
// settle because gesture sequences must preserve their pressed state between
// events.
inline void sendMouseEvent(QQuickWindow &window, QEvent::Type type, const QPointF &position,
                           Qt::MouseButton button)
{
    const QPoint windowPosition = position.toPoint();
    if (type == QEvent::MouseMove)
        QTest::mouseEvent(QTest::MouseMove, &window, Qt::NoButton, Qt::NoModifier, windowPosition);
    else if (type == QEvent::MouseButtonPress)
        QTest::mousePress(&window, button, Qt::NoModifier, windowPosition);
    else
        QTest::mouseRelease(&window, button, Qt::NoModifier, windowPosition);
}

inline bool clickTimelineInput(QQuickWindow *window, songview::TimelineInputItem *input,
                               const QPoint &position)
{
    if (!window || !input || input->bounds().isEmpty() || input->window() != window ||
        !QRect(QPoint{}, window->size()).contains(position) ||
        !input->bounds().contains(input->mapFromScene(QPointF(position)))) {
        return false;
    }
    QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, position);
    settle();
    return true;
}

inline bool focusTimelineInput(QQuickWindow *window, songview::TimelineInputItem *input)
{
    return input &&
           clickTimelineInput(window, input,
                              input->mapToScene(input->bounds().center()).toPoint()) &&
           input->hasActiveFocus();
}

inline bool moveMouseToTimelineInput(QQuickWindow *window, songview::TimelineInputItem *input,
                                     const QPoint &position)
{
    if (!window || !input || !checks::events::primeMouseMove(*window, *input, position))
        return false;
    QTest::mouseMove(window, position);
    settle();
    return true;
}

inline QString focusObjectIdentity(const QObject *object)
{
    if (!object)
        return QStringLiteral("none");
    return QStringLiteral("%1('%2')@0x%3")
        .arg(QString::fromLatin1(object->metaObject()->className()), object->objectName(),
             QString::number(reinterpret_cast<quintptr>(object), 16));
}

// The first single-key binding of a command, so deliveries follow the live
// keymap instead of hardcoded keys.
inline std::optional<QKeyCombination> firstBinding(const QString &id)
{
    return keymap::Registry::instance().singleStroke(id);
}

// --- document note lookups ---

// SongDocument::findNote writes its out parameter whenever the note exists
// (songdocument.cpp noteAt), so the output is never nullable at a hit.
// Existence checks must go through these helpers, which pass real storage.
inline std::optional<DocNote> noteById(const SongDocument &document, NoteId id)
{
    DocNote note;
    if (!document.findNote(id, &note))
        return std::nullopt;
    return note;
}

inline bool noteExists(const SongDocument &document, NoteId id)
{
    return noteById(document, id).has_value();
}

inline bool noteExists(const SongDocument &document, int engineTrack, uint64_t tick, uint8_t key)
{
    DocNote note;
    return document.findNote(engineTrack, tick, key, &note);
}

// Inserts specs as one undoable command and returns the inserted ids; error
// reports a broken isolation contract (the ids are what makes the inserted
// notes addressable alongside the project fixture's pre-existing content).
inline std::vector<NoteId> insertIsolatedNotes(SongDocument &document, int engineTrack,
                                               const std::vector<SongDocument::NewNote> &specs,
                                               QString &error)
{
    const std::vector<DocNote> before = document.notesForTrack(engineTrack);
    document.addNotes(engineTrack, specs);
    std::vector<NoteId> inserted = document.insertedNoteIds(engineTrack, before);
    if (inserted.size() != specs.size()) {
        error = QStringLiteral("could not isolate %1 inserted note(s) on track %2")
                    .arg(specs.size())
                    .arg(engineTrack);
        return {};
    }
    return inserted;
}
// Canonical standalone selection-routing world. Callers provide the notes,
// rig configuration, and the small document setup their scenario needs.
struct RigWorld {
    std::unique_ptr<checks::LoadedSong> song;
    std::unique_ptr<checks::EditorRig> rig;
    std::vector<NoteId> notes;
};

template <typename PrepareDocument>
std::unique_ptr<RigWorld> makeRigWorld(const QString &projectRoot, const QString &songLabel,
                                       int track,
                                       const std::vector<SongDocument::NewNote> &noteSpecs,
                                       const checks::EditorRigConfig &config,
                                       PrepareDocument &&prepareDocument, QString &error)
{
    auto world = std::make_unique<RigWorld>();
    world->song = checks::LoadedSong::load(projectRoot, songLabel, error);
    if (!world->song)
        return nullptr;
    SongDocument &document = world->song->document();
    world->notes = insertIsolatedNotes(document, track, noteSpecs, error);
    if (world->notes.size() != noteSpecs.size())
        return nullptr;
    std::forward<PrepareDocument>(prepareDocument)(document);
    world->rig = checks::EditorRig::create(document, config, error);
    if (!world->rig)
        return nullptr;
    songview::TimelineQuickView *const quick = world->rig->view().quickView();
    QQuickWindow *const quickWindow = quick ? quick->quickWindow() : nullptr;
    if (!quickWindow || !QTest::qWaitFor([quickWindow] {
            return quickWindow->isVisible() && quickWindow->isExposed();
        })) {
        error = QStringLiteral("production Quick window did not become exposed");
        return nullptr;
    }
    return world;
}

inline SongView &rigView(RigWorld &world)
{
    return world.rig->view();
}

inline SongDocument &rigDocument(RigWorld &world)
{
    return world.rig->document();
}

inline QQuickWindow *rigWindow(RigWorld &world)
{
    songview::TimelineQuickView *const quick = rigView(world).quickView();
    return quick ? quick->quickWindow() : nullptr;
}

inline songview::TimelineInputItem *rigInput(RigWorld &world, const char *name)
{
    QQuickItem *const root = world.rig->quickRoot();
    return root ? root->findChild<songview::TimelineInputItem *>(QLatin1String(name)) : nullptr;
}

} // namespace selectionkey
