#include "tst_swiftrollgated.h"

#include "app/RewriteWindow.h"

#include <QAction>
#include <QCoreApplication>
#include <QEvent>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QKeyCombination>
#include <QKeyEvent>
#include <QPointer>
#include <QQuickItem>
#include <QQuickView>
#include <QSignalSpy>
#include <QtTest/QTest>

#include <algorithm>
#include <cmath>
#include <optional>

namespace {

constexpr int kOpenTimeoutMs = 15'000;
constexpr int kSettleTimeoutMs = 5'000;

struct NoteState {
    quint64 id = 0;
    int tick = 0;
    int duration = 0;
    int pitch = 0;
    int track = 0;
    int velocity = 0;
    bool selected = false;
};

std::optional<QList<NoteState>> publishedNotes(QObject *grid, QString *error)
{
    QJsonParseError parseError;
    const QJsonDocument document =
        QJsonDocument::fromJson(grid->property("noteSummary").toString().toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isArray()) {
        *error =
            QStringLiteral("noteSummary is not a JSON array: %1").arg(parseError.errorString());
        return std::nullopt;
    }

    QList<NoteState> result;
    result.reserve(document.array().size());
    for (const QJsonValue value : document.array()) {
        if (!value.isObject()) {
            *error = QStringLiteral("noteSummary contains a non-object entry");
            return std::nullopt;
        }
        const QJsonObject object = value.toObject();
        const quint64 id = quint64(object.value(QStringLiteral("id")).toDouble());
        if (id == 0 || !object.value(QStringLiteral("tick")).isDouble() ||
            !object.value(QStringLiteral("duration")).isDouble() ||
            !object.value(QStringLiteral("pitch")).isDouble()) {
            *error = QStringLiteral("noteSummary entry lacks its document-facing fields");
            return std::nullopt;
        }
        result.append({id, object.value(QStringLiteral("tick")).toInt(),
                       object.value(QStringLiteral("duration")).toInt(),
                       object.value(QStringLiteral("pitch")).toInt(),
                       object.value(QStringLiteral("track")).toInt(),
                       object.value(QStringLiteral("velocity")).toInt(),
                       object.value(QStringLiteral("selected")).toBool()});
    }
    return result;
}

std::optional<NoteState> noteWithId(const QList<NoteState> &notes, quint64 id)
{
    for (const NoteState &note : notes)
        if (note.id == id)
            return note;
    return std::nullopt;
}

class GridFixture final
{
  public:
    GridFixture(QString projectRoot, QString songLabel)
        : m_projectRoot(std::move(projectRoot))
        , m_songLabel(std::move(songLabel))
    {}

    bool open(QString *error)
    {
        m_window.show();
        m_window.openStartup(m_projectRoot, m_songLabel);
        QObject *const session = m_window.sessionObject();
        if (!session || !QTest::qWaitFor(
                            [session] {
                                return session->property("projectOpen").toBool() &&
                                       session->property("songOpen").toBool();
                            },
                            kOpenTimeoutMs)) {
            *error = QStringLiteral("the production session did not open the staged song");
            return false;
        }
        if (!QTest::qWaitFor(
                [this] {
                    return m_window.gridView() && m_window.gridView()->isExposed() &&
                           m_window.gridView()->rootObject();
                },
                kSettleTimeoutMs)) {
            *error = QStringLiteral("the production QQuickView did not expose its root");
            return false;
        }
        m_view = m_window.gridView();
        m_root = qobject_cast<QQuickItem *>(m_view->rootObject());
        m_grid = m_root ? m_root->property("gridModel").value<QObject *>() : nullptr;
        m_plot = gridcheck::visualDescendant(m_root, QStringLiteral("timelineQuickRollPlot"));
        m_input = gridcheck::visualDescendant(m_root, QStringLiteral("swiftRollInput"));
        m_surface = gridcheck::visualDescendant(m_root, QStringLiteral("pianoGridSurface"));
        m_fills =
            gridcheck::visualDescendant(m_root, QStringLiteral("timelineQuickPianoNoteFills"));
        if (!m_root || !m_grid || !m_plot || !m_input || !m_surface || !m_fills) {
            *error = QStringLiteral("the production grid scene is missing an input or render item");
            return false;
        }
        if (!QTest::qWaitFor([this] { return m_grid->property("renderedNoteCount").toInt() > 0; },
                             kSettleTimeoutMs)) {
            *error = QStringLiteral("the staged song published no grid notes");
            return false;
        }
        return true;
    }

    RewriteWindow &window() { return m_window; }
    QQuickView *view() const { return m_view; }
    QQuickItem *root() const { return m_root; }
    QObject *grid() const { return m_grid; }
    QQuickItem *input() const { return m_input; }
    QQuickItem *surface() const { return m_surface; }
    QQuickItem *fills() const { return m_fills; }
    QString songLabel() const { return m_songLabel; }

    QList<NoteState> notes(QString *error) const
    {
        const auto parsed = publishedNotes(m_grid, error);
        return parsed.value_or(QList<NoteState>{});
    }

    int snap() const { return m_grid->property("snapTicks").toInt(); }

    QPoint pointFor(int tick, int pitch) const
    {
        const double pixelsPerTick =
            m_grid->property("beatWidth").toDouble() / m_grid->property("ticksPerBeat").toInt();
        const double x = tick * pixelsPerTick - m_grid->property("cameraScrollX").toDouble();
        const double y = (127.0 - pitch + 0.5) * m_grid->property("rowHeight").toDouble() -
                         m_grid->property("cameraScrollY").toDouble();
        return m_surface->mapToScene(QPointF(x, y)).toPoint();
    }

    std::optional<QPair<int, int>> freeLane(int spanInSnaps, QString *error) const
    {
        const QList<NoteState> current = notes(error);
        if (!error->isEmpty())
            return std::nullopt;
        const int grid = snap();
        const double rowHeight = m_grid->property("rowHeight").toDouble();
        const double pixelsPerTick =
            m_grid->property("beatWidth").toDouble() / m_grid->property("ticksPerBeat").toInt();
        const double scrollX = m_grid->property("cameraScrollX").toDouble();
        const double scrollY = m_grid->property("cameraScrollY").toDouble();
        const int firstTick = int(std::ceil(((scrollX + 24.0) / pixelsPerTick) / grid)) * grid;
        const int lastTick =
            int(std::floor(((scrollX + m_plot->width() - 24.0) / pixelsPerTick) / grid)) * grid;
        const int firstRow = std::clamp(int(std::ceil(scrollY / rowHeight)) + 2, 0, 127);
        const int lastRow =
            std::clamp(int(std::floor((scrollY + m_plot->height()) / rowHeight)) - 2, 0, 127);
        for (int row = firstRow; row <= lastRow; ++row) {
            const int pitch = 127 - row;
            for (int tick = (std::max)(0, firstTick); tick + spanInSnaps * grid <= lastTick;
                 tick += grid) {
                const int end = tick + spanInSnaps * grid;
                const bool occupied =
                    std::any_of(current.cbegin(), current.cend(), [&](const NoteState &note) {
                        return note.pitch == pitch && note.tick < end &&
                               note.tick + note.duration > tick;
                    });
                if (!occupied)
                    return QPair<int, int>{tick, pitch};
            }
        }
        *error = QStringLiteral("the visible fixture has no empty lane spanning %1 snap cells")
                     .arg(spanInSnaps);
        return std::nullopt;
    }

    QQuickItem *noteItem(quint64 id) const
    {
        return gridcheck::visualDescendant(m_fills, QStringLiteral("gridNote_%1").arg(id));
    }

    QAction *action(const QString &text) const
    {
        for (QAction *action : m_window.findChildren<QAction *>()) {
            QString label = action->text();
            label.remove(QLatin1Char('&'));
            if (label == text)
                return action;
        }
        return nullptr;
    }

  private:
    QString m_projectRoot;
    QString m_songLabel;
    RewriteWindow m_window;
    QQuickView *m_view = nullptr;
    QQuickItem *m_root = nullptr;
    QObject *m_grid = nullptr;
    QQuickItem *m_plot = nullptr;
    QQuickItem *m_input = nullptr;
    QQuickItem *m_surface = nullptr;
    QQuickItem *m_fills = nullptr;
};

void dragMouse(QQuickView *view, Qt::MouseButton button, const QPoint &start, const QPoint &finish)
{
    QTest::mouseMove(view, start);
    QTest::mousePress(view, button, Qt::NoModifier, start);
    QTest::mouseMove(view, finish, 20);
    QTest::mouseRelease(view, button, Qt::NoModifier, finish);
    QCoreApplication::processEvents();
}

std::optional<NoteState> drawNote(GridFixture &fixture, int tick, int duration, int pitch,
                                  QString *error)
{
    const QList<NoteState> before = fixture.notes(error);
    if (!error->isEmpty())
        return std::nullopt;
    const int inset = (std::max)(1, fixture.snap() / 4);
    dragMouse(fixture.view(), Qt::LeftButton, fixture.pointFor(tick + inset, pitch),
              fixture.pointFor(tick + duration - inset, pitch));
    if (!QTest::qWaitFor(
            [&] {
                QString ignored;
                return fixture.notes(&ignored).size() == before.size() + 1;
            },
            kSettleTimeoutMs)) {
        *error = QStringLiteral("left drag did not add one document note");
        return std::nullopt;
    }
    const QList<NoteState> after = fixture.notes(error);
    for (const NoteState &candidate : after) {
        const bool existed =
            std::any_of(before.cbegin(), before.cend(),
                        [&](const NoteState &note) { return note.id == candidate.id; });
        if (!existed)
            return candidate;
    }
    *error = QStringLiteral("the added note has no new document identity");
    return std::nullopt;
}

bool sendShortcut(QQuickView *view, QAction *action)
{
    if (!view || !action || action->shortcuts().isEmpty() ||
        action->shortcuts().front().count() != 1)
        return false;
    const QKeyCombination key = action->shortcuts().front()[0];
    QTest::keyClick(view, key.key(), key.keyboardModifiers());
    QCoreApplication::processEvents();
    return true;
}

std::optional<QPair<QPoint, QPoint>> selectionBand(GridFixture &fixture, quint64 id)
{
    QQuickItem *const item = fixture.noteItem(id);
    if (!item)
        return std::nullopt;
    const QRectF rect = item->mapRectToScene(item->boundingRect());
    const QRectF inputRect = fixture.input()->mapRectToScene(fixture.input()->boundingRect());
    const QRectF band = rect.adjusted(-3.0, -3.0, 3.0, 3.0);
    if (!inputRect.adjusted(1.0, 1.0, -1.0, -1.0).contains(band))
        return std::nullopt;
    return QPair<QPoint, QPoint>{band.topLeft().toPoint(), band.bottomRight().toPoint()};
}

std::optional<NoteState> firstVisibleNote(GridFixture &fixture, QString *error)
{
    const QList<NoteState> notes = fixture.notes(error);
    for (const NoteState &note : notes)
        if (selectionBand(fixture, note.id))
            return note;
    *error = QStringLiteral("the staged grid has no fully visible note");
    return std::nullopt;
}

} // namespace

void SwiftRollGatedTest::pointerDrawMoveAndNeighborTrim()
{
    if (m_mode != QStringLiteral("swiftrollgated"))
        QSKIP("actual pointer editing belongs to swiftrollgated");
    GridFixture fixture(m_projectRoot, m_songLabel);
    QString error;
    QVERIFY2(fixture.open(&error), qPrintable(error));
    const auto lane = fixture.freeLane(12, &error);
    QVERIFY2(lane.has_value(), qPrintable(error));
    const int snap = fixture.snap();
    const int tick = lane->first;
    const int pitch = lane->second;
    const auto moving = drawNote(fixture, tick, 2 * snap, pitch, &error);
    const auto neighbor = drawNote(fixture, tick + 4 * snap, 4 * snap, pitch, &error);
    QVERIFY2(moving.has_value() && neighbor.has_value(), qPrintable(error));
    QCOMPARE(moving->tick, tick);
    QCOMPARE(moving->duration, 2 * snap);
    QCOMPARE(moving->pitch, pitch);

    dragMouse(fixture.view(), Qt::LeftButton, fixture.pointFor(tick + snap, pitch),
              fixture.pointFor(tick + 4 * snap, pitch));
    QVERIFY(QTest::qWaitFor(
        [&] {
            QString ignored;
            const auto notes = fixture.notes(&ignored);
            const auto moved = noteWithId(notes, moving->id);
            const auto trimmed = noteWithId(notes, neighbor->id);
            return moved && trimmed && moved->tick == tick + 3 * snap &&
                   moved->duration == 2 * snap && trimmed->tick == tick + 5 * snap &&
                   trimmed->duration == 3 * snap;
        },
        kSettleTimeoutMs));

    QQuickItem *const rendered = fixture.noteItem(moving->id);
    QVERIFY(rendered != nullptr && rendered->isVisible());
    const QImage frame = fixture.view()->grabWindow();
    QVERIFY(!frame.isNull());
    const QColor expected(rendered->property("fillColor").toString());
    const QColor actual = gridcheck::pixelAt(
        frame, rendered->mapToScene(rendered->boundingRect().center()).toPoint());
    QVERIFY2(gridcheck::colorsNear(actual, expected),
             "moved note summary changed but its rendered face did not follow");
}

void SwiftRollGatedTest::resizeEdgesRespectMinimumDuration()
{
    if (m_mode != QStringLiteral("swiftrollgated"))
        QSKIP("actual resize editing belongs to swiftrollgated");
    GridFixture fixture(m_projectRoot, m_songLabel);
    QString error;
    QVERIFY2(fixture.open(&error), qPrintable(error));
    const auto lane = fixture.freeLane(18, &error);
    QVERIFY2(lane.has_value(), qPrintable(error));
    const int snap = fixture.snap();
    const int tick = lane->first;
    const int pitch = lane->second;
    const auto trailing = drawNote(fixture, tick, 6 * snap, pitch, &error);
    const auto leading = drawNote(fixture, tick + 9 * snap, 6 * snap, pitch, &error);
    QVERIFY2(trailing.has_value() && leading.has_value(), qPrintable(error));

    dragMouse(fixture.view(), Qt::LeftButton,
              fixture.pointFor(trailing->tick + trailing->duration, pitch) - QPoint(1, 0),
              fixture.pointFor(trailing->tick, pitch));
    QVERIFY(QTest::qWaitFor(
        [&] {
            QString ignored;
            const auto note = noteWithId(fixture.notes(&ignored), trailing->id);
            return note && note->tick == trailing->tick && note->duration == snap;
        },
        kSettleTimeoutMs));

    const int leadingEnd = leading->tick + leading->duration;
    dragMouse(fixture.view(), Qt::LeftButton, fixture.pointFor(leading->tick, pitch) + QPoint(1, 0),
              fixture.pointFor(leadingEnd, pitch));
    QVERIFY(QTest::qWaitFor(
        [&] {
            QString ignored;
            const auto note = noteWithId(fixture.notes(&ignored), leading->id);
            return note && note->tick == leadingEnd - snap && note->duration == snap;
        },
        kSettleTimeoutMs));
}

void SwiftRollGatedTest::windowUndoRedoRerenders()
{
    if (m_mode != QStringLiteral("swiftrollgated"))
        QSKIP("window history rerender belongs to swiftrollgated");
    GridFixture fixture(m_projectRoot, m_songLabel);
    QString error;
    QVERIFY2(fixture.open(&error), qPrintable(error));
    const int baseline = fixture.grid()->property("renderedNoteCount").toInt();
    const auto lane = fixture.freeLane(4, &error);
    QVERIFY2(lane.has_value(), qPrintable(error));
    const auto added = drawNote(fixture, lane->first, 2 * fixture.snap(), lane->second, &error);
    QVERIFY2(added.has_value(), qPrintable(error));
    QVERIFY(fixture.noteItem(added->id) != nullptr);

    QVERIFY(sendShortcut(fixture.view(), fixture.action(QStringLiteral("Undo"))));
    QVERIFY(QTest::qWaitFor(
        [&] {
            return fixture.grid()->property("renderedNoteCount").toInt() == baseline &&
                   fixture.noteItem(added->id) == nullptr;
        },
        kSettleTimeoutMs));
    QVERIFY(sendShortcut(fixture.view(), fixture.action(QStringLiteral("Redo"))));
    QVERIFY(QTest::qWaitFor(
        [&] {
            QString ignored;
            const auto restored = noteWithId(fixture.notes(&ignored), added->id);
            return restored && restored->tick == added->tick &&
                   restored->duration == added->duration && fixture.noteItem(added->id) != nullptr;
        },
        kSettleTimeoutMs));
}

void SwiftRollGatedTest::rightDragSelectionCommits()
{
    if (m_mode != QStringLiteral("swiftbandkeys"))
        QSKIP("right-drag selection belongs to swiftbandkeys");
    GridFixture fixture(m_projectRoot, m_songLabel);
    QString error;
    QVERIFY2(fixture.open(&error), qPrintable(error));
    const auto target = firstVisibleNote(fixture, &error);
    QVERIFY2(target.has_value(), qPrintable(error));
    QVERIFY(!target->selected);
    const auto band = selectionBand(fixture, target->id);
    QVERIFY(band.has_value());
    dragMouse(fixture.view(), Qt::RightButton, band->first, band->second);
    QVERIFY(QTest::qWaitFor(
        [&] {
            QString ignored;
            const auto selected = noteWithId(fixture.notes(&ignored), target->id);
            return selected && selected->selected;
        },
        kSettleTimeoutMs));
}

void SwiftRollGatedTest::escapeCancelsSelectionBand()
{
    if (m_mode != QStringLiteral("swiftbandkeys"))
        QSKIP("Escape cancellation belongs to swiftbandkeys");
    GridFixture fixture(m_projectRoot, m_songLabel);
    QString error;
    QVERIFY2(fixture.open(&error), qPrintable(error));
    const QString before = fixture.grid()->property("noteSummary").toString();
    const auto target = firstVisibleNote(fixture, &error);
    QVERIFY2(target.has_value(), qPrintable(error));
    const auto band = selectionBand(fixture, target->id);
    QVERIFY(band.has_value());
    QTest::mouseMove(fixture.view(), band->first);
    QTest::mousePress(fixture.view(), Qt::RightButton, Qt::NoModifier, band->first);
    QTest::mouseMove(fixture.view(), band->second, 20);
    QVERIFY(QTest::qWaitFor(
        [&] {
            QString ignored;
            const auto selected = noteWithId(fixture.notes(&ignored), target->id);
            return selected && selected->selected;
        },
        kSettleTimeoutMs));
    fixture.input()->forceActiveFocus(Qt::OtherFocusReason);
    QTest::keyClick(fixture.view(), Qt::Key_Escape);
    QTest::mouseRelease(fixture.view(), Qt::RightButton, Qt::NoModifier, band->second);
    QVERIFY(QTest::qWaitFor(
        [&] { return fixture.grid()->property("noteSummary").toString() == before; },
        kSettleTimeoutMs));
    QCOMPARE(fixture.grid()->property("lastCancelReason").toInt(), -1);
    // Idle Escape clears the ephemeral note selection without a document or
    // history edit: the same notes at the same revision, none selected, and
    // no fabricated cancel reason. All through actual window input.
    QQuickItem *const idleItem = fixture.noteItem(target->id);
    QVERIFY(idleItem != nullptr);
    const QPoint idleCenter = idleItem->mapToScene(idleItem->boundingRect().center()).toPoint();
    QTest::mouseClick(fixture.view(), Qt::LeftButton, Qt::NoModifier, idleCenter);
    QVERIFY(QTest::qWaitFor(
        [&] {
            QString ignored;
            const auto selected = noteWithId(fixture.notes(&ignored), target->id);
            return selected && selected->selected;
        },
        kSettleTimeoutMs));
    QString idleError;
    const QList<NoteState> idleBefore = fixture.notes(&idleError);
    QVERIFY2(idleError.isEmpty(), qPrintable(idleError));
    const QString idleRevision = fixture.grid()->property("appliedRevisionText").toString();
    const int idleReason = fixture.grid()->property("lastCancelReason").toInt();
    fixture.input()->forceActiveFocus(Qt::OtherFocusReason);
    QTest::keyClick(fixture.view(), Qt::Key_Escape);
    QVERIFY(QTest::qWaitFor(
        [&] {
            QString ignored;
            const auto cleared = noteWithId(fixture.notes(&ignored), target->id);
            return cleared && !cleared->selected;
        },
        kSettleTimeoutMs));
    QString idleAfterError;
    const QList<NoteState> idleAfter = fixture.notes(&idleAfterError);
    QVERIFY2(idleAfterError.isEmpty(), qPrintable(idleAfterError));
    QCOMPARE(idleAfter.size(), idleBefore.size());
    for (int index = 0; index < idleBefore.size(); ++index) {
        QCOMPARE(idleAfter[index].id, idleBefore[index].id);
        QCOMPARE(idleAfter[index].tick, idleBefore[index].tick);
        QCOMPARE(idleAfter[index].duration, idleBefore[index].duration);
        QCOMPARE(idleAfter[index].pitch, idleBefore[index].pitch);
        QCOMPARE(idleAfter[index].track, idleBefore[index].track);
        QCOMPARE(idleAfter[index].velocity, idleBefore[index].velocity);
        QVERIFY(!idleAfter[index].selected);
    }
    QCOMPARE(fixture.grid()->property("appliedRevisionText").toString(), idleRevision);
    QCOMPARE(fixture.grid()->property("lastCancelReason").toInt(), idleReason);
}

void SwiftRollGatedTest::ungrabCancelsSelectionBand()
{
    if (m_mode != QStringLiteral("swiftbandkeys"))
        QSKIP("pointer-ungrab cancellation belongs to swiftbandkeys");
    GridFixture fixture(m_projectRoot, m_songLabel);
    QString error;
    QVERIFY2(fixture.open(&error), qPrintable(error));
    const QString before = fixture.grid()->property("noteSummary").toString();
    const auto target = firstVisibleNote(fixture, &error);
    QVERIFY2(target.has_value(), qPrintable(error));
    const auto band = selectionBand(fixture, target->id);
    QVERIFY(band.has_value());
    QTest::mouseMove(fixture.view(), band->first);
    QTest::mousePress(fixture.view(), Qt::RightButton, Qt::NoModifier, band->first);
    QTest::mouseMove(fixture.view(), band->second, 20);
    QEvent ungrab(QEvent::UngrabMouse);
    QCoreApplication::sendEvent(fixture.view(), &ungrab);
    QTest::mouseRelease(fixture.view(), Qt::RightButton, Qt::NoModifier, band->second);
    QVERIFY(QTest::qWaitFor(
        [&] {
            return fixture.grid()->property("lastCancelReason").toInt() == 1 &&
                   fixture.grid()->property("noteSummary").toString() == before;
        },
        kSettleTimeoutMs));
}

void SwiftRollGatedTest::trackFollowAndSessionReplacement()
{
    if (m_mode != QStringLiteral("swiftqtml"))
        QSKIP("QML object-return lifetime belongs to swiftqtml");
    QPointer<QObject> finalGrid;
    QPointer<QQuickView> finalView;
    {
        GridFixture fixture(m_projectRoot, m_songLabel);
        QString error;
        QVERIFY2(fixture.open(&error), qPrintable(error));
        QVERIFY(QMetaObject::invokeMethod(fixture.grid(), "setTrack", Q_ARG(int, 1)));
        QVERIFY(QTest::qWaitFor(
            [&] {
                if (fixture.grid()->property("trackIndex").toInt() != 1)
                    return false;
                const QList<NoteState> notes = fixture.notes(&error);
                return error.isEmpty() && !notes.isEmpty() &&
                       fixture.grid()->property("renderedNoteCount").toInt() == notes.size() &&
                       std::all_of(notes.cbegin(), notes.cend(),
                                   [](const NoteState &note) { return note.track == 1; });
            },
            kSettleTimeoutMs));

        QPointer<QQuickView> oldView = fixture.view();
        QPointer<QObject> oldRoot = fixture.root();
        QPointer<QObject> oldGrid = fixture.grid();
        QVERIFY(QMetaObject::invokeMethod(fixture.window().sessionObject(), "openSong",
                                          Q_ARG(QString, fixture.songLabel()), Q_ARG(bool, false)));
        QVERIFY(QTest::qWaitFor(
            [&] {
                return oldView.isNull() && oldRoot.isNull() && oldGrid.isNull() &&
                       fixture.window().gridView() && fixture.window().gridView() != oldView &&
                       fixture.window().gridView()->rootObject();
            },
            kOpenTimeoutMs));
        finalView = fixture.window().gridView();
        finalGrid = finalView->rootObject()->property("gridModel").value<QObject *>();
        QVERIFY(finalGrid && finalGrid->property("renderedNoteCount").toInt() > 0);
    }
    QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
    QCoreApplication::processEvents();
    QVERIFY(finalView.isNull());
    QVERIFY(finalGrid.isNull());
}

void SwiftRollGatedTest::focusedGridCommandRouting()
{
    if (m_mode != QStringLiteral("selectionkey"))
        QSKIP("focused-grid command routing belongs to selectionkey");
    GridFixture fixture(m_projectRoot, m_songLabel);
    QString error;
    QVERIFY2(fixture.open(&error), qPrintable(error));
    const auto target = firstVisibleNote(fixture, &error);
    QVERIFY2(target.has_value(), qPrintable(error));
    QQuickItem *const item = fixture.noteItem(target->id);
    QVERIFY(item != nullptr);
    const QPoint center = item->mapToScene(item->boundingRect().center()).toPoint();
    QTest::mouseClick(fixture.view(), Qt::LeftButton, Qt::NoModifier, center);
    QAction *const nudge = fixture.action(QStringLiteral("Nudge Right"));
    QVERIFY(nudge != nullptr);
    QTRY_VERIFY_WITH_TIMEOUT(nudge->isEnabled(), kSettleTimeoutMs);
    QVERIFY(sendShortcut(fixture.view(), nudge));
    QVERIFY(QTest::qWaitFor(
        [&] {
            QString ignored;
            const auto moved = noteWithId(fixture.notes(&ignored), target->id);
            return moved && moved->tick == target->tick + fixture.snap() &&
                   moved->pitch == target->pitch;
        },
        kSettleTimeoutMs));

    QAction *const pencil = fixture.action(QStringLiteral("Pencil Mode"));
    QVERIFY(pencil != nullptr && sendShortcut(fixture.view(), pencil));
    QVERIFY(fixture.grid()->property("pencilMode").toBool());
    const QKeyCombination pencilKey = pencil->shortcuts().front()[0];
    QKeyEvent repeat(QEvent::KeyPress, pencilKey.key(), pencilKey.keyboardModifiers(), {}, true);
    QCoreApplication::sendEvent(fixture.view(), &repeat);
    QVERIFY(fixture.grid()->property("pencilMode").toBool());
    QAction *const deleteNotes = fixture.action(QStringLiteral("Delete Notes"));
    QVERIFY(deleteNotes != nullptr && deleteNotes->isEnabled());
    // Press at the moved note's current scene position. No extra click here:
    // a click immediately before the press would double-click and delete
    // the note via doublePointer; selection is already established above.
    QQuickItem *const movedItem = fixture.noteItem(target->id);
    QVERIFY(movedItem != nullptr);
    const QPoint movedCenter = movedItem->mapToScene(movedItem->boundingRect().center()).toPoint();
    const QString beforeGesture = fixture.grid()->property("noteSummary").toString();
    QTest::mouseMove(fixture.view(), movedCenter);
    QTest::mousePress(fixture.view(), Qt::LeftButton, Qt::NoModifier, movedCenter);
    // Only actual keyboard activation is exercised mid-gesture; a menu
    // click cannot reach the grid while the press is held, and action
    // enablement mid-drag is not a user-visible invariant.
    QVERIFY(sendShortcut(fixture.view(), deleteNotes));
    QCOMPARE(fixture.grid()->property("noteSummary").toString(), beforeGesture);
    // The surviving Pencil row still executes from the keyboard mid-gesture.
    const bool pencilBefore = fixture.grid()->property("pencilMode").toBool();
    QVERIFY(sendShortcut(fixture.view(), pencil));
    QCOMPARE(fixture.grid()->property("pencilMode").toBool(), !pencilBefore);
    QCOMPARE(fixture.grid()->property("noteSummary").toString(), beforeGesture);
    QVERIFY(sendShortcut(fixture.view(), pencil));
    QCOMPARE(fixture.grid()->property("pencilMode").toBool(), pencilBefore);
    QCOMPARE(fixture.grid()->property("noteSummary").toString(), beforeGesture);
    QTest::mouseRelease(fixture.view(), Qt::LeftButton, Qt::NoModifier, movedCenter);
    QCOMPARE(fixture.grid()->property("noteSummary").toString(), beforeGesture);
}

void SwiftRollGatedTest::bareSpaceKeepsWindowPriority()
{
    if (m_mode != QStringLiteral("selectionkey"))
        QSKIP("bare-Space window priority belongs to selectionkey");
    GridFixture fixture(m_projectRoot, m_songLabel);
    QString error;
    QVERIFY2(fixture.open(&error), qPrintable(error));
    QAction *const playPause = fixture.action(QStringLiteral("Play/Pause"));
    QVERIFY(playPause != nullptr && playPause->isEnabled());
    QSignalSpy triggered(playPause, &QAction::triggered);
    QVERIFY(triggered.isValid());
    const QString before = fixture.grid()->property("noteSummary").toString();
    QTest::keyClick(fixture.view(), Qt::Key_Space);
    QCoreApplication::processEvents();
    QCOMPARE(triggered.count(), 1);
    QCOMPARE(fixture.grid()->property("noteSummary").toString(), before);
}
