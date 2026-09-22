#include "tst_swiftrollgated.h"

#include "app/RewriteWindow.h"

#include <QAction>
#include <QApplication>
#include <QClipboard>
#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeyCombination>
#include <QMimeData>
#include <QPointer>
#include <QQuickItem>
#include <QQuickView>
#include <QtTest/QTest>

#include <algorithm>
#include <numeric>
#include <optional>
#include <utility>

namespace {

constexpr int kOpenTimeoutMs = 15'000;
constexpr int kSettleTimeoutMs = 5'000;
constexpr auto kClipMimeType = "application/x-porydaw-clip";

struct ClipboardNote {
    quint64 id = 0;
    int tick = 0;
    int duration = 0;
    int pitch = 0;
    int track = 0;
    int velocity = 0;
    bool selected = false;
};

struct GridSurface {
    QQuickView *view = nullptr;
    QQuickItem *root = nullptr;
    QQuickItem *input = nullptr;
    QQuickItem *fills = nullptr;
    QObject *grid = nullptr;
};

std::optional<QList<ClipboardNote>> notes(QObject *grid, QString *error)
{
    const QJsonDocument document =
        QJsonDocument::fromJson(grid->property("noteSummary").toString().toUtf8());
    if (!document.isArray()) {
        *error = QStringLiteral("noteSummary is not a JSON array");
        return std::nullopt;
    }
    QList<ClipboardNote> result;
    result.reserve(document.array().size());
    for (const QJsonValue value : document.array()) {
        if (!value.isObject()) {
            *error = QStringLiteral("noteSummary contains a non-object entry");
            return std::nullopt;
        }
        const QJsonObject object = value.toObject();
        const quint64 id = quint64(object.value(QStringLiteral("id")).toDouble());
        if (id == 0) {
            *error = QStringLiteral("noteSummary contains an unassigned note identity");
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

std::optional<ClipboardNote> noteWithId(const QList<ClipboardNote> &notes, quint64 id)
{
    for (const ClipboardNote &note : notes)
        if (note.id == id)
            return note;
    return std::nullopt;
}

bool resolveSurface(RewriteWindow &window, GridSurface *surface, QString *error)
{
    surface->view = window.gridView();
    surface->root =
        surface->view ? qobject_cast<QQuickItem *>(surface->view->rootObject()) : nullptr;
    surface->grid =
        surface->root ? surface->root->property("gridModel").value<QObject *>() : nullptr;
    surface->input = gridcheck::visualDescendant(surface->root, QStringLiteral("swiftRollInput"));
    surface->fills =
        gridcheck::visualDescendant(surface->root, QStringLiteral("timelineQuickPianoNoteFills"));
    if (!surface->view || !surface->root || !surface->grid || !surface->input || !surface->fills) {
        *error = QStringLiteral("the production grid scene is missing its presenter or input");
        return false;
    }
    return true;
}

QAction *actionNamed(RewriteWindow &window, const QString &text)
{
    for (QAction *action : window.findChildren<QAction *>()) {
        QString label = action->text();
        label.remove(QLatin1Char('&'));
        if (label == text)
            return action;
    }
    return nullptr;
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
bool sendWidgetShortcut(QWidget *widget, QAction *action)
{
    if (!widget || !action || action->shortcuts().isEmpty() ||
        action->shortcuts().front().count() != 1)
        return false;
    const QKeyCombination key = action->shortcuts().front()[0];
    QTest::keyClick(widget, key.key(), key.keyboardModifiers());
    QCoreApplication::processEvents();
    return true;
}

QList<ClipboardNote> visibleNotes(const GridSurface &surface, QString *error)
{
    QList<ClipboardNote> result;
    const auto parsed = notes(surface.grid, error);
    if (!parsed)
        return result;
    const QRectF viewRect(0.0, 0.0, surface.view->width(), surface.view->height());
    for (const ClipboardNote &note : *parsed) {
        QQuickItem *const item =
            gridcheck::visualDescendant(surface.fills, QStringLiteral("gridNote_%1").arg(note.id));
        if (item && viewRect.adjusted(1.0, 1.0, -1.0, -1.0)
                        .contains(item->mapRectToScene(item->boundingRect()))) {
            result.append(note);
        }
    }
    if (result.size() < 2)
        *error = QStringLiteral("the staged song has fewer than two fully visible notes to copy");
    return result;
}

std::optional<ClipboardNote> pastedAt(const QList<ClipboardNote> &notes, quint64 sourceId, int tick,
                                      const ClipboardNote &source)
{
    for (const ClipboardNote &note : notes) {
        if (note.id != sourceId && note.tick == tick && note.duration == source.duration &&
            note.pitch == source.pitch && note.track == source.track &&
            note.velocity == source.velocity) {
            return note;
        }
    }
    return std::nullopt;
}

int selectedCount(const QList<ClipboardNote> &notes)
{
    return int(std::count_if(notes.cbegin(), notes.cend(),
                             [](const ClipboardNote &note) { return note.selected; }));
}
QString presenterDiagnostic(QObject *grid, const QString &parseError)
{
    const QString summary =
        grid ? grid->property("noteSummary").toString() : QStringLiteral("<null presenter>");
    const QString cursor =
        grid ? QString::number(grid->property("editCursorTick").toInt()) : QStringLiteral("<null>");
    return QStringLiteral("noteSummary=%1; editCursorTick=%2; parseError=%3")
        .arg(summary, cursor, parseError);
}

QJsonObject clipPayload(int ticksPerBeat, int span, QJsonArray tracks = {}, QJsonArray lanes = {},
                        QJsonArray tempo = {})
{
    return {{QStringLiteral("format"), 1},
            {QStringLiteral("ticksPerBeat"), ticksPerBeat},
            {QStringLiteral("span"), span},
            {QStringLiteral("wholeLane"), false},
            {QStringLiteral("tracks"), std::move(tracks)},
            {QStringLiteral("lanes"), std::move(lanes)},
            {QStringLiteral("tempo"), std::move(tempo)}};
}

void writeClipboardData(const QByteArray &data)
{
    auto *mime = new QMimeData;
    mime->setData(QLatin1String(kClipMimeType), data);
    QApplication::clipboard()->setMimeData(mime);
    QCoreApplication::processEvents();
}

void writeClipboardPayload(const QJsonObject &payload)
{
    writeClipboardData(QJsonDocument(payload).toJson(QJsonDocument::Compact));
}

} // namespace

void SwiftRollGatedTest::hostClipboardRoundTripAndReplacement()
{
    if (m_mode != QStringLiteral("selectionkey"))
        QSKIP("actual host clipboard routing belongs to selectionkey");

    RewriteWindow window;
    window.show();
    window.openStartup(m_projectRoot, m_songLabel);
    QObject *const session = window.sessionObject();
    QVERIFY(session != nullptr);
    QVERIFY(QTest::qWaitFor(
        [session] {
            return session->property("projectOpen").toBool() &&
                   session->property("songOpen").toBool();
        },
        kOpenTimeoutMs));
    QVERIFY(QTest::qWaitFor(
        [&] {
            return window.gridView() && window.gridView()->isExposed() &&
                   window.gridView()->width() > 0 && window.gridView()->height() > 0 &&
                   window.gridView()->rootObject();
        },
        kSettleTimeoutMs));

    QString error;
    GridSurface surface;
    QVERIFY2(resolveSurface(window, &surface, &error), qPrintable(error));
    std::optional<ClipboardNote> source = std::nullopt;
    std::optional<ClipboardNote> secondSource = std::nullopt;
    QVERIFY2(QTest::qWaitFor(
                 [&] {
                     error.clear();
                     QList<ClipboardNote> visible = visibleNotes(surface, &error);
                     if (visible.size() < 2)
                         return false;
                     std::sort(visible.begin(), visible.end(),
                               [](const ClipboardNote &left, const ClipboardNote &right) {
                                   return left.tick < right.tick ||
                                          (left.tick == right.tick && left.id < right.id);
                               });
                     source = visible[0];
                     secondSource = visible[1];
                     return true;
                 },
                 kSettleTimeoutMs),
             qPrintable(error));
    QCOMPARE(secondSource->track, source->track);
    const auto clickNote = [&](const ClipboardNote &note, Qt::KeyboardModifiers modifiers) -> bool {
        QQuickItem *const item =
            gridcheck::visualDescendant(surface.fills, QStringLiteral("gridNote_%1").arg(note.id));
        if (!item)
            return false;
        const QPoint center = item->mapToScene(item->boundingRect().center()).toPoint();
        QTest::mouseClick(surface.view, Qt::LeftButton, modifiers, center);
        return true;
    };
    QVERIFY(clickNote(*source, Qt::NoModifier));
    QVERIFY(clickNote(*secondSource, Qt::ShiftModifier));
    QVERIFY2(QTest::qWaitFor(
                 [&] {
                     const auto current = notes(surface.grid, &error);
                     if (!current || selectedCount(*current) != 2)
                         return false;
                     const auto first = noteWithId(*current, source->id);
                     const auto second = noteWithId(*current, secondSource->id);
                     return first && first->selected && second && second->selected;
                 },
                 kSettleTimeoutMs),
             qPrintable(QStringLiteral("real pointer input did not select both source notes; %1")
                            .arg(presenterDiagnostic(surface.grid, error))));

    QAction *const copy = actionNamed(window, QStringLiteral("Copy Notes"));
    QAction *const paste = actionNamed(window, QStringLiteral("Paste Notes"));
    QAction *const undo = actionNamed(window, QStringLiteral("Undo"));
    QAction *const redo = actionNamed(window, QStringLiteral("Redo"));
    QVERIFY(copy && paste && undo && redo);
    QVERIFY(!undo->isEnabled());
    QVERIFY(!redo->isEnabled());
    QTRY_VERIFY_WITH_TIMEOUT(copy->isEnabled(), kSettleTimeoutMs);

    // Live-gesture Copy sentinel: seed real nonempty clipboard bytes/text, hold a
    // real pointer press, then issue the real Copy shortcut. A mid-gesture Copy
    // is a no-op that leaves exact clipboard bytes/text, noteSummary, and
    // appliedRevisionText unchanged. This exercises the user-reachable shortcut
    // path during a held press; it does not claim to prove direct menu
    // activation mid-drag.
    const QByteArray sentinelBytes = "sentinel_clip_payload_bytes_12345";
    const QString sentinelText = QStringLiteral("sentinel_clip_text");
    {
        auto *const mime = new QMimeData();
        mime->setData(QLatin1String(kClipMimeType), sentinelBytes);
        mime->setText(sentinelText);
        QApplication::clipboard()->setMimeData(mime);
    }
    const QMimeData *const initialMime = QApplication::clipboard()->mimeData();
    QVERIFY(initialMime && initialMime->hasFormat(QLatin1String(kClipMimeType)));
    QCOMPARE(initialMime->data(QLatin1String(kClipMimeType)), sentinelBytes);
    QCOMPARE(initialMime->text(), sentinelText);

    QQuickItem *const firstItem =
        gridcheck::visualDescendant(surface.fills, QStringLiteral("gridNote_%1").arg(source->id));
    QVERIFY(firstItem != nullptr);
    const QPoint pressPoint = firstItem->mapToScene(firstItem->boundingRect().center()).toPoint();
    QTest::mousePress(surface.view, Qt::LeftButton, Qt::NoModifier, pressPoint);
    const QString preGestureSummary = surface.grid->property("noteSummary").toString();
    const QString preGestureRevision = surface.grid->property("appliedRevisionText").toString();

    QVERIFY(!copy->isEnabled());
    QVERIFY(sendShortcut(surface.view, copy));

    const QMimeData *const duringMime = QApplication::clipboard()->mimeData();
    QVERIFY(duringMime && duringMime->hasFormat(QLatin1String(kClipMimeType)));
    QCOMPARE(duringMime->data(QLatin1String(kClipMimeType)), sentinelBytes);
    QCOMPARE(duringMime->text(), sentinelText);
    QCOMPARE(surface.grid->property("noteSummary").toString(), preGestureSummary);
    QCOMPARE(surface.grid->property("appliedRevisionText").toString(), preGestureRevision);

    QTest::mouseRelease(surface.view, Qt::LeftButton, Qt::NoModifier, pressPoint);

    // Positive copy after release
    QVERIFY(copy->isEnabled());
    QApplication::clipboard()->clear();
    QVERIFY(sendShortcut(surface.view, copy));
    const QMimeData *const mime = QApplication::clipboard()->mimeData();
    QVERIFY(mime && mime->hasFormat(QLatin1String(kClipMimeType)));
    const QByteArray copiedPayload = mime->data(QLatin1String(kClipMimeType));
    QVERIFY(!copiedPayload.isEmpty());
    const QJsonDocument copiedDocument = QJsonDocument::fromJson(copiedPayload);
    QVERIFY(copiedDocument.isObject());
    const QJsonObject copied = copiedDocument.object();
    QCOMPARE(copied.value(QStringLiteral("format")).toInt(), 1);
    QCOMPARE(copied.value(QStringLiteral("ticksPerBeat")).toInt(),
             surface.grid->property("ticksPerBeat").toInt());
    QCOMPARE(copied.value(QStringLiteral("span")).toInt(), 0);
    QCOMPARE(copied.value(QStringLiteral("wholeLane")).toBool(), false);
    QCOMPARE(copied.value(QStringLiteral("lanes")).toArray().size(), 0);
    QCOMPARE(copied.value(QStringLiteral("tempo")).toArray().size(), 0);
    const QJsonArray copiedTracks = copied.value(QStringLiteral("tracks")).toArray();
    QCOMPARE(copiedTracks.size(), 1);
    const QJsonObject copiedTrack = copiedTracks[0].toObject();
    QCOMPARE(copiedTrack.value(QStringLiteral("track")).toInt(), source->track);
    const QJsonArray copiedNotes = copiedTrack.value(QStringLiteral("notes")).toArray();
    QCOMPARE(copiedNotes.size(), 2);
    const int copiedOrigin = (std::min)(source->tick, secondSource->tick);
    const auto payloadContains = [&](const ClipboardNote &expected) {
        return std::any_of(copiedNotes.cbegin(), copiedNotes.cend(), [&](const QJsonValue &value) {
            const QJsonObject note = value.toObject();
            return note.value(QStringLiteral("relTick")).toInt() == expected.tick - copiedOrigin &&
                   note.value(QStringLiteral("key")).toInt() == expected.pitch &&
                   note.value(QStringLiteral("duration")).toInt() == expected.duration &&
                   note.value(QStringLiteral("velocity")).toInt() == expected.velocity;
        });
    };
    QVERIFY(payloadContains(*source));
    QVERIFY(payloadContains(*secondSource));
    const int copiedEnd = (std::max)(source->tick - copiedOrigin + source->duration,
                                     secondSource->tick - copiedOrigin + secondSource->duration);

    const auto beforePaste = notes(surface.grid, &error);
    QVERIFY2(beforePaste.has_value(), qPrintable(error));
    const int snap = surface.grid->property("snapTicks").toInt();
    QVERIFY(snap > 0);
    const int latestEnd = std::accumulate(beforePaste->cbegin(), beforePaste->cend(), 0,
                                          [](int latest, const ClipboardNote &note) {
                                              return (std::max)(latest, note.tick + note.duration);
                                          });
    const int cursor = ((latestEnd + snap - 1) / snap + 2) * snap;
    QVERIFY(QMetaObject::invokeMethod(surface.grid, "setEditCursorTick", Q_ARG(int, cursor)));
    QCOMPARE(surface.grid->property("editCursorTick").toInt(), cursor);
    QTRY_VERIFY_WITH_TIMEOUT(paste->isEnabled(), kSettleTimeoutMs);
    QVERIFY(sendShortcut(surface.view, paste));

    std::optional<ClipboardNote> pasted = std::nullopt;
    std::optional<ClipboardNote> secondPasted = std::nullopt;
    QVERIFY2(QTest::qWaitFor(
                 [&] {
                     const auto current = notes(surface.grid, &error);
                     if (!current || current->size() != beforePaste->size() + 2)
                         return false;
                     pasted = pastedAt(*current, source->id, cursor + source->tick - copiedOrigin,
                                       *source);
                     secondPasted =
                         pastedAt(*current, secondSource->id,
                                  cursor + secondSource->tick - copiedOrigin, *secondSource);
                     return pasted.has_value() && pasted->selected && secondPasted.has_value() &&
                            secondPasted->selected && selectedCount(*current) == 2 &&
                            surface.grid->property("editCursorTick").toInt() == cursor + copiedEnd;
                 },
                 kSettleTimeoutMs),
             qPrintable(QStringLiteral("initial span-0 paste did not publish two selected notes "
                                       "and the committed cursor; %1")
                            .arg(presenterDiagnostic(surface.grid, error))));
    QTRY_VERIFY_WITH_TIMEOUT(undo->isEnabled(), kSettleTimeoutMs);
    QVERIFY(!redo->isEnabled());

    QVERIFY(sendShortcut(surface.view, undo));
    QVERIFY2(QTest::qWaitFor(
                 [&] {
                     const auto current = notes(surface.grid, &error);
                     return current && current->size() == beforePaste->size() &&
                            !noteWithId(*current, pasted->id).has_value() &&
                            !noteWithId(*current, secondPasted->id).has_value();
                 },
                 kSettleTimeoutMs),
             qPrintable(QStringLiteral("initial Undo did not remove both pasted notes; %1")
                            .arg(presenterDiagnostic(surface.grid, error))));
    QVERIFY(!undo->isEnabled());
    QTRY_VERIFY_WITH_TIMEOUT(redo->isEnabled(), kSettleTimeoutMs);
    QVERIFY(sendShortcut(surface.view, redo));
    QVERIFY2(QTest::qWaitFor(
                 [&] {
                     const auto current = notes(surface.grid, &error);
                     return current && current->size() == beforePaste->size() + 2 &&
                            pastedAt(*current, source->id, cursor + source->tick - copiedOrigin,
                                     *source)
                                .has_value() &&
                            pastedAt(*current, secondSource->id,
                                     cursor + secondSource->tick - copiedOrigin, *secondSource)
                                .has_value() &&
                            surface.grid->property("editCursorTick").toInt() == cursor + copiedEnd;
                 },
                 kSettleTimeoutMs),
             qPrintable(QStringLiteral("initial Redo did not restore both pasted notes and the "
                                       "committed cursor; %1")
                            .arg(presenterDiagnostic(surface.grid, error))));
    QTRY_VERIFY_WITH_TIMEOUT(undo->isEnabled(), kSettleTimeoutMs);
    QVERIFY(!redo->isEnabled());

    QPointer<QQuickView> oldView = surface.view;
    QVERIFY(QMetaObject::invokeMethod(session, "openSong", Q_ARG(QString, m_songLabel),
                                      Q_ARG(bool, true)));
    QVERIFY(QTest::qWaitFor(
        [&] {
            return oldView.isNull() && window.gridView() && window.gridView()->isExposed() &&
                   window.gridView()->width() > 0 && window.gridView()->height() > 0 &&
                   window.gridView()->rootObject();
        },
        kOpenTimeoutMs));
    GridSurface replacement;
    QVERIFY2(resolveSurface(window, &replacement, &error), qPrintable(error));
    QVERIFY(!undo->isEnabled());
    QVERIFY(!redo->isEnabled());
    QCOMPARE(QApplication::clipboard()->mimeData()->data(QLatin1String(kClipMimeType)),
             copiedPayload);
    const auto replacementBefore = notes(replacement.grid, &error);
    QVERIFY2(replacementBefore.has_value(), qPrintable(error));
    const int replacementTicksPerBeat = replacement.grid->property("ticksPerBeat").toInt();
    QVERIFY(replacementTicksPerBeat > 0);
    const int replacementCursor = cursor + 4 * snap;
    QVERIFY(QMetaObject::invokeMethod(replacement.grid, "setEditCursorTick",
                                      Q_ARG(int, replacementCursor)));
    const QString replacementSummary = replacement.grid->property("noteSummary").toString();
    const bool replacementDirty = session->property("documentDirty").toBool();
    QCOMPARE(QApplication::clipboard()->mimeData()->data(QLatin1String(kClipMimeType)),
             copiedPayload);
    QTRY_VERIFY_WITH_TIMEOUT(paste->isEnabled(), kSettleTimeoutMs);
    QVERIFY(sendWidgetShortcut(window.centralWidget(), paste));
    std::optional<ClipboardNote> replacementPasted = std::nullopt;
    std::optional<ClipboardNote> replacementSecondPasted = std::nullopt;
    QVERIFY2(QTest::qWaitFor(
                 [&] {
                     const auto current = notes(replacement.grid, &error);
                     if (!current || current->size() != replacementBefore->size() + 2)
                         return false;
                     replacementPasted =
                         pastedAt(*current, source->id,
                                  replacementCursor + source->tick - copiedOrigin, *source);
                     replacementSecondPasted = pastedAt(
                         *current, secondSource->id,
                         replacementCursor + secondSource->tick - copiedOrigin, *secondSource);
                     return replacementPasted.has_value() && replacementPasted->selected &&
                            replacementSecondPasted.has_value() &&
                            replacementSecondPasted->selected && selectedCount(*current) == 2 &&
                            replacement.grid->property("editCursorTick").toInt() ==
                                replacementCursor + copiedEnd;
                 },
                 kSettleTimeoutMs),
             qPrintable(QStringLiteral("replacement span-0 paste did not publish two selected "
                                       "notes and the committed cursor; %1")
                            .arg(presenterDiagnostic(replacement.grid, error))));
    QTRY_VERIFY_WITH_TIMEOUT(undo->isEnabled(), kSettleTimeoutMs);
    const QString pastedSummary = replacement.grid->property("noteSummary").toString();
    const int pastedCursor = replacement.grid->property("editCursorTick").toInt();
    const bool pastedDirty = session->property("documentDirty").toBool();

    writeClipboardPayload(
        clipPayload(replacementTicksPerBeat, 48, QJsonArray{},
                    QJsonArray{QJsonObject{{QStringLiteral("track"), source->track},
                                           {QStringLiteral("cc"), 7},
                                           {QStringLiteral("points"), QJsonArray{}}}}));
    QVERIFY(sendShortcut(replacement.view, paste));
    QCOMPARE(replacement.grid->property("noteSummary").toString(), pastedSummary);
    QCOMPARE(replacement.grid->property("editCursorTick").toInt(), pastedCursor);
    QCOMPARE(session->property("documentDirty").toBool(), pastedDirty);

    QVERIFY(sendShortcut(replacement.view, undo));
    QVERIFY2(QTest::qWaitFor(
                 [&] {
                     const auto current = notes(replacement.grid, &error);
                     return current && current->size() == replacementBefore->size() &&
                            !noteWithId(*current, replacementPasted->id).has_value() &&
                            !noteWithId(*current, replacementSecondPasted->id).has_value();
                 },
                 kSettleTimeoutMs),
             qPrintable(QStringLiteral("one Undo after the empty clip did not remove the "
                                       "preceding real paste; %1")
                            .arg(presenterDiagnostic(replacement.grid, error))));
    QCOMPARE(replacement.grid->property("noteSummary").toString(), replacementSummary);
    QCOMPARE(session->property("documentDirty").toBool(), replacementDirty);

    const int replacementLatestEnd =
        std::accumulate(replacementBefore->cbegin(), replacementBefore->cend(), 0,
                        [](int latest, const ClipboardNote &note) {
                            return (std::max)(latest, note.tick + note.duration);
                        });
    const int occupiedEnd = (std::max)(replacementLatestEnd, replacementCursor + copiedEnd);
    const int tileStart = ((occupiedEnd + snap - 1) / snap + 2) * snap;
    ClipboardNote tileNote;
    tileNote.duration = 24;
    tileNote.pitch = 60;
    tileNote.track = source->track;
    tileNote.velocity = 100;
    writeClipboardPayload(clipPayload(
        replacementTicksPerBeat, 96,
        QJsonArray{QJsonObject{
            {QStringLiteral("track"), tileNote.track},
            {QStringLiteral("notes"),
             QJsonArray{QJsonObject{{QStringLiteral("relTick"), 0},
                                    {QStringLiteral("key"), tileNote.pitch},
                                    {QStringLiteral("duration"), tileNote.duration},
                                    {QStringLiteral("velocity"), tileNote.velocity}}}}}}));
    QVERIFY(
        QMetaObject::invokeMethod(replacement.grid, "setEditCursorTick", Q_ARG(int, tileStart)));
    QVERIFY(sendShortcut(replacement.view, paste));
    std::optional<ClipboardNote> firstTile = std::nullopt;
    QVERIFY2(QTest::qWaitFor(
                 [&] {
                     const auto current = notes(replacement.grid, &error);
                     if (!current || current->size() != replacementBefore->size() + 1)
                         return false;
                     firstTile = pastedAt(*current, 0, tileStart, tileNote);
                     return firstTile.has_value() &&
                            replacement.grid->property("editCursorTick").toInt() == tileStart + 96;
                 },
                 kSettleTimeoutMs),
             qPrintable(QStringLiteral("first span-96 tile did not publish its note and next "
                                       "cursor; expectedTick=%1 expectedCursor=%2; %3")
                            .arg(tileStart)
                            .arg(tileStart + 96)
                            .arg(presenterDiagnostic(replacement.grid, error))));

    QVERIFY(sendShortcut(replacement.view, paste));
    std::optional<ClipboardNote> secondTile = std::nullopt;
    QVERIFY2(QTest::qWaitFor(
                 [&] {
                     const auto current = notes(replacement.grid, &error);
                     if (!current || current->size() != replacementBefore->size() + 2)
                         return false;
                     secondTile = pastedAt(*current, firstTile->id, tileStart + 96, tileNote);
                     return secondTile.has_value() &&
                            replacement.grid->property("editCursorTick").toInt() == tileStart + 192;
                 },
                 kSettleTimeoutMs),
             qPrintable(QStringLiteral("second span-96 tile did not consume the published cursor; "
                                       "expectedTick=%1 expectedCursor=%2; %3")
                            .arg(tileStart + 96)
                            .arg(tileStart + 192)
                            .arg(presenterDiagnostic(replacement.grid, error))));

    QVERIFY(sendShortcut(replacement.view, undo));
    QVERIFY2(QTest::qWaitFor(
                 [&] {
                     const auto current = notes(replacement.grid, &error);
                     return current && current->size() == replacementBefore->size() + 1 &&
                            noteWithId(*current, firstTile->id).has_value() &&
                            !noteWithId(*current, secondTile->id).has_value();
                 },
                 kSettleTimeoutMs),
             qPrintable(QStringLiteral("first tiled Undo did not remove only the second tile; %1")
                            .arg(presenterDiagnostic(replacement.grid, error))));
    QVERIFY(sendShortcut(replacement.view, undo));
    QVERIFY2(QTest::qWaitFor(
                 [&] {
                     const auto current = notes(replacement.grid, &error);
                     return current && current->size() == replacementBefore->size() &&
                            !noteWithId(*current, firstTile->id).has_value() &&
                            !noteWithId(*current, secondTile->id).has_value();
                 },
                 kSettleTimeoutMs),
             qPrintable(QStringLiteral("second tiled Undo did not restore baseline notes; %1")
                            .arg(presenterDiagnostic(replacement.grid, error))));
    QCOMPARE(session->property("documentDirty").toBool(), replacementDirty);
    QVERIFY(QApplication::clipboard()->mimeData()->hasFormat(QLatin1String(kClipMimeType)));
}
