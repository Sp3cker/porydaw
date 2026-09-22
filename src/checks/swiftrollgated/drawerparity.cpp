#include "tst_swiftrollgated.h"

#include "nativefixture.h"
#include "ui/layout.h"

#include <QGuiApplication>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeyEvent>
#include <QPointer>
#include <QQuickItem>
#include <QQuickView>
#include <QScopeGuard>
#include <QStyleHints>
#include <QtTest/QTest>

#include <algorithm>
// Ports the sibling automation raster and keyboard contracts onto the real
// Swift session's final Quick-only surface.
using gridcheck::NativeScene;

void SwiftRollGatedTest::drawerAutomationHoverRaster_data()
{
    QTest::addColumn<QString>("parameter");
    QTest::newRow("pan") << QStringLiteral("Pan");
    QTest::newRow("tempo") << QStringLiteral("Tempo");
}

void SwiftRollGatedTest::drawerAutomationHoverRaster()
{
    if (m_mode != QStringLiteral("swiftrollgated"))
        QSKIP("drawer raster parity belongs to swiftrollgated");
    QFETCH(QString, parameter);
    NativeScene scene;
    QString error;
    QVERIFY2(scene.open(m_projectRoot, m_songLabel, &error), qPrintable(error));
    auto *page = scene.item("automationPage");
    auto *input = scene.item("automationPlotInput");
    auto *model = scene.model("automationPage");
    QVERIFY(page && input && model);
    QPointer<QQuickItem> tab;
    for (int index = 0; index < model->property("tabCount").toInt(); ++index) {
        auto *candidate = gridcheck::visualDescendant(
            page, QStringLiteral("automationParameterTab%1").arg(index));
        if (candidate && candidate->property("text").toString() == parameter)
            tab = candidate;
    }
    QVERIFY2(tab, qPrintable(QStringLiteral("missing parameter tab: %1").arg(parameter)));
    // Focus scrolls the real selector into view; activation still arrives by pointer.
    tab->forceActiveFocus(Qt::TabFocusReason);
    QTest::mouseClick(scene.view, Qt::LeftButton, Qt::NoModifier,
                      tab->mapToScene(QPointF(tab->width() * 0.2, tab->height() * 0.5)).toPoint());
    QTRY_VERIFY(tab && tab->property("checked").toBool());
    scene.move(scene.item("swiftRollInput"), QPointF(20, 20));
    QTRY_VERIFY(!model->property("hoverVisible").toBool());
    const QString before = scene.revision();
    QVERIFY(!before.isEmpty());
    const QImage idle = scene.capture(input);
    QVERIFY(!idle.isNull());

    // Background insertion hover must actually paint, remain read-only, and be
    // pixel-stable when the same pointer position is delivered twice.
    const QPointF insertion(input->width() * 0.55, input->height() * 0.5);
    scene.move(input, insertion);
    QTRY_VERIFY(model->property("hoverVisible").toBool());
    QImage hovered;
    QTRY_VERIFY(!(hovered = scene.capture(input)).isNull() && hovered != idle);
    QCOMPARE(scene.revision(), before);
    scene.move(input, insertion);
    QCOMPARE(scene.capture(input), hovered);

    scene.move(scene.item("swiftRollInput"), QPointF(20, 20));
    QTRY_VERIFY(!model->property("hoverVisible").toBool());
    QTRY_COMPARE(scene.capture(input), idle);
    QCOMPARE(scene.revision(), before);

    // A written node must paint a ring, not merely flip a presenter flag.
    const auto fills = scene.descendants(page, "automationNodeFill");
    QQuickItem *node = nullptr;
    for (auto *fill : fills) {
        const QPointF center = fill->mapToItem(input, fill->boundingRect().center());
        if (fill->isVisible() &&
            input->boundingRect().adjusted(12, 12, -12, -12).contains(center)) {
            node = fill;
            break;
        }
    }
    QVERIFY2(node, "the fixture must expose a written node away from plot edges");
    const QPoint nodeCenter = node->mapToScene(node->boundingRect().center()).toPoint();
    auto *ring =
        gridcheck::visualDescendant(node->parentItem(), QStringLiteral("automationNodeHover"));
    QVERIFY(ring);
    const QRectF ringBounds = ring->mapRectToScene(ring->boundingRect());
    const QImage ringIdle = scene.capture(ringBounds);
    QVERIFY(!ringIdle.isNull());
    // Hover publication may replace delegates. Keep coordinates, not pointers,
    // across the input boundary, and inspect freshly resolved render items.
    QTest::mouseMove(scene.view, nodeCenter);
    QTRY_VERIFY([&] {
        const auto rings = scene.descendants(page, "automationNodeHover");
        return std::any_of(rings.cbegin(), rings.cend(),
                           [](auto *item) { return item->isVisible(); });
    }());
    QImage ringFrame;
    QTRY_VERIFY(!(ringFrame = scene.capture(ringBounds)).isNull() && ringFrame != ringIdle);
    QCOMPARE(scene.revision(), before);
    scene.move(scene.item("swiftRollInput"), QPointF(20, 20));
    QTRY_COMPARE(scene.capture(ringBounds), ringIdle);
    QTRY_COMPARE(scene.capture(input), idle);
    QCOMPARE(scene.revision(), before);
}

void SwiftRollGatedTest::drawerVoicePreviewTransaction_data()
{
    QTest::addColumn<bool>("cancel");
    QTest::newRow("release-commits") << false;
    QTest::newRow("escape-cancels") << true;
}

void SwiftRollGatedTest::drawerVoicePreviewTransaction()
{
    if (m_mode != QStringLiteral("swiftrollgated"))
        QSKIP("drawer raster parity belongs to swiftrollgated");
    QFETCH(bool, cancel);
    NativeScene scene;
    QString error;
    QVERIFY2(scene.open(m_projectRoot, m_songLabel, &error), qPrintable(error));
    auto *input = scene.item("voicePlotInput");
    auto *page = scene.item("voiceChangesPage");
    auto *model = scene.model("voiceChangesPage");
    auto *preview = scene.item("voiceDragPreview");
    QVERIFY(input && page && model && preview);
    scene.move(scene.item("swiftRollInput"), QPointF(20, 20));
    auto *line = scene.item("voiceChangeMarkerLine");
    QVERIFY2(line, "the fixture must publish a voice-change marker");
    const QPointF source = line->mapToItem(input, line->boundingRect().center());
    QVERIFY(input->boundingRect().contains(source));
    scene.move(input, source);
    QTRY_COMPARE(model->property("hoverHintProfile").toInt(), 21);
    const QString before = scene.revision();
    QVERIFY(!before.isEmpty());
    const QImage idle = scene.capture(input);
    QVERIFY(!idle.isNull());
    const QPoint press = input->mapToScene(source).toPoint();
    QTest::mousePress(scene.view, Qt::LeftButton, Qt::NoModifier, press);
    bool buttonHeld = true;
    const auto release = qScopeGuard([&] {
        if (buttonHeld)
            QTest::mouseRelease(scene.view, Qt::LeftButton);
    });
    QCoreApplication::processEvents();
    QCOMPARE(scene.revision(), before);
    QVERIFY(!preview->isVisible());
    const QImage pressed = scene.capture(input);
    QCOMPARE(pressed, idle);

    const QPointF target(source.x() + scene.grid->property("beatWidth").toDouble() * 2, source.y());
    QVERIFY(input->boundingRect().contains(target));
    scene.move(input, target);
    QTRY_VERIFY(preview->isVisible());
    QTRY_COMPARE(input->cursor().shape(), Qt::SizeHorCursor);
    QImage draft;
    QTRY_VERIFY(!(draft = scene.capture(input)).isNull() && draft != idle);
    QCOMPARE(draft.size(), idle.size());
    QCOMPARE(scene.revision(), before);
    QVERIFY(model->property("interactionActive").toBool());

    if (cancel) {
        input->parentItem()->forceActiveFocus(Qt::OtherFocusReason);
        QTest::keyClick(scene.view, Qt::Key_Escape);
        QTRY_VERIFY(!preview->isVisible());
        QTest::mouseRelease(scene.view, Qt::LeftButton, Qt::NoModifier,
                            input->mapToScene(target).toPoint());
        buttonHeld = false;
        QCOMPARE(scene.revision(), before);
        QVERIFY(!scene.session->property("canUndo").toBool());
    } else {
        QTest::mouseRelease(scene.view, Qt::LeftButton, Qt::NoModifier,
                            input->mapToScene(target).toPoint());
        buttonHeld = false;
        QTRY_VERIFY(scene.revision() != before);
        QTRY_VERIFY(!preview->isVisible());
        QTRY_VERIFY(scene.session->property("canUndo").toBool());
        const QString committed = scene.revision();
        QVERIFY(QMetaObject::invokeMethod(scene.session, "requestUndo"));
        // canUndo clears before asynchronous replay starts; the published
        // revision, not the disabled action, establishes completion.
        QTRY_VERIFY(scene.revision() != committed);
        QTRY_VERIFY(!scene.session->property("canUndo").toBool());
    }
    QTRY_VERIFY(!model->property("interactionActive").toBool());
    scene.move(input, source);
    QTRY_COMPARE(scene.capture(input), idle);
}

void SwiftRollGatedTest::drawerGripKeyboardIsolation()
{
    if (m_mode != QStringLiteral("swiftrollgated"))
        QSKIP("drawer window keyboard routing belongs to swiftrollgated");
    NativeScene scene;
    QString error;
    QVERIFY2(scene.open(m_projectRoot, m_songLabel, &error), qPrintable(error));
    auto *grip = scene.item("drawerHandle_automation");
    auto *plot = scene.item("automationPlot");
    QVERIFY(grip && plot);
    // Without selected notes, leaked arrows could be harmless and the check
    // would miss the regression. Select a real visible note before traversal.
    const auto notesBefore =
        QJsonDocument::fromJson(scene.grid->property("noteSummary").toString().toUtf8());
    QVERIFY(notesBefore.isArray());
    auto *roll = scene.item("swiftRollInput");
    QVERIFY(roll);
    QQuickItem *note = nullptr;
    for (const auto value : notesBefore.array()) {
        const auto id = quint64(value.toObject().value(QStringLiteral("id")).toDouble());
        auto *candidate =
            gridcheck::visualDescendant(scene.root, QStringLiteral("gridNote_%1").arg(id));
        if (candidate && roll->boundingRect().contains(
                             candidate->mapToItem(roll, candidate->boundingRect().center()))) {
            note = candidate;
            break;
        }
    }
    QVERIFY2(note, "the fixture must expose a note for the routing negative control");
    QTest::mouseClick(scene.view, Qt::LeftButton, Qt::NoModifier,
                      note->mapToScene(note->boundingRect().center()).toPoint());
    QTRY_VERIFY([&] {
        const auto selected =
            QJsonDocument::fromJson(scene.grid->property("noteSummary").toString().toUtf8())
                .array();
        return std::any_of(selected.cbegin(), selected.cend(), [](const auto &entry) {
            return entry.toObject().value(QStringLiteral("selected")).toBool();
        });
    }());
    const auto previous = QGuiApplication::styleHints()->tabFocusBehavior();
    const auto restore =
        qScopeGuard([&] { QGuiApplication::styleHints()->setTabFocusBehavior(previous); });
    QGuiApplication::styleHints()->setTabFocusBehavior(Qt::TabFocusAllControls);
    plot->forceActiveFocus(Qt::OtherFocusReason);
    QTRY_VERIFY(plot->hasActiveFocus());
    QTRY_COMPARE(QGuiApplication::focusWindow(), scene.view);
    QStringList focusPath;
    for (int count = 0; count < 80 && !grip->hasActiveFocus(); ++count) {
        QTest::keyClick(scene.view, Qt::Key_Tab);
        QCoreApplication::processEvents();
        auto *focus = scene.view->activeFocusItem();
        focusPath.append(focus ? focus->objectName() : QStringLiteral("<none>"));
    }
    QVERIFY2(grip->hasActiveFocus(), qPrintable(QStringLiteral("Tab traversal missed grip: %1")
                                                    .arg(focusPath.join(QStringLiteral(" -> ")))));
    const QString before = scene.revision();
    const QString notes = scene.grid->property("noteSummary").toString();
    const qreal height = plot->height();
    const int step = layout::space(layout::Space::Two);
    const auto arrow = [&](Qt::Key code) {
        QKeyEvent press(QEvent::KeyPress, code, Qt::NoModifier);
        QCoreApplication::sendEvent(scene.view, &press);
        QKeyEvent release(QEvent::KeyRelease, code, Qt::NoModifier);
        QCoreApplication::sendEvent(scene.view, &release);
        return press.isAccepted();
    };
    QVERIFY(arrow(Qt::Key_Up));
    QTRY_COMPARE(plot->height(), height + step);
    QVERIFY(arrow(Qt::Key_Down));
    QTRY_COMPARE(plot->height(), height);
    QVERIFY(arrow(Qt::Key_Left));
    QVERIFY(arrow(Qt::Key_Right));
    QCOMPARE(plot->height(), height);
    QCOMPARE(scene.revision(), before);
    QCOMPARE(scene.grid->property("noteSummary").toString(), notes);
}
