#include "checks/workspace/tst_workspacesessions.h"

#include <QtTest>

#include <QAction>
#include <QApplication>
#include <QComboBox>
#include <QDial>
#include <QImage>
#include <QKeyEvent>
#include <QLabel>
#include <QLineEdit>
#include <QSettings>
#include <QSizePolicy>
#include <QSpinBox>
#include <QToolBar>
#include <QToolButton>

#include <QtMath>
#include <algorithm>
#include <cmath>

#include "checks/support/eventsynth.h"
#include "mainwindow.h"
#include "ui/layout.h"
#include "ui/songtab.h"
#include "ui/theme/themeruntime.h"
#include "ui/transportbar.h"
#include "ui/workspaceui.h"

namespace {

bool hasTickAt(const QDial &dial, qreal degrees)
{
    QImage image(dial.size(), QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    const_cast<QDial &>(dial).render(&image);
    const int inset = layout::space(layout::Space::One);
    const QRect bounds = dial.rect().adjusted(inset, inset, -inset, -inset);
    const QPointF center(bounds.left() + bounds.width() / 2.0 + 0.5,
                         bounds.top() + bounds.height() / 2.0 + 0.5);
    const qreal horizontal = std::min(center.x(), qreal(dial.width() - 1) - center.x());
    const qreal vertical = std::min(center.y(), qreal(dial.height() - 1) - center.y());
    const qreal radius = std::min(horizontal, vertical) - layout::singlePixel() -
                         qreal(layout::space(layout::Space::Half)) / 2.0;
    const QPoint probe =
        (center +
         QPointF(qCos(qDegreesToRadians(degrees)), -qSin(qDegreesToRadians(degrees))) * radius)
            .toPoint();
    const QColor expected = themes::color(themes::Role::toolbar_outline);
    for (int y = probe.y() - 2; y <= probe.y() + 2; ++y) {
        for (int x = probe.x() - 2; x <= probe.x() + 2; ++x) {
            if (!image.valid(x, y))
                continue;
            const QColor actual = image.pixelColor(x, y);
            if (std::abs(actual.red() - expected.red()) <= 8 &&
                std::abs(actual.green() - expected.green()) <= 8 &&
                std::abs(actual.blue() - expected.blue()) <= 8)
                return true;
        }
    }
    return false;
}

} // namespace

void WorkspaceTabsTest::transportVolumesAndRaster()
{
    MainWindow window;
    auto *workspace = window.m_workspace.get();
    QVERIFY(workspace);
    auto *root = window.findChild<QComboBox *>(QStringLiteral("transportScaleRoot"));
    auto *scale = window.findChild<QComboBox *>(QStringLiteral("transportScaleType"));
    auto *highlight = window.findChild<QToolButton *>(QStringLiteral("transportScaleHighlight"));
    auto *fold = window.findChild<QToolButton *>(QStringLiteral("transportScaleFold"));
    QVERIFY(root);
    QVERIFY(scale);
    QVERIFY(highlight);
    QVERIFY(fold);
    QVERIFY(!root->isEnabled() && !scale->isEnabled() && !highlight->isEnabled() &&
            !fold->isEnabled());
    QCOMPARE(root->focusPolicy(), Qt::NoFocus);
    QCOMPARE(scale->focusPolicy(), Qt::NoFocus);
    QCOMPARE(highlight->focusPolicy(), Qt::NoFocus);
    QCOMPARE(fold->focusPolicy(), Qt::NoFocus);

    TransportBar defaultTransport;
    auto *time = defaultTransport.findChild<QLabel *>(QStringLiteral("transportTimeLabel"));
    auto *defaultDial =
        defaultTransport.findChild<QDial *>(QStringLiteral("transportOutputVolume"));
    QVERIFY(time);
    QVERIFY(defaultDial);
    QVERIFY(time->minimumWidth() > 0);
    QCOMPARE(time->minimumWidth(), time->maximumWidth());
    const int reserved = time->minimumWidth();
    defaultTransport.setTimeText(QStringLiteral("99:59.9 / 99:59.9"));
    QCOMPARE(time->minimumWidth(), reserved);
    QCOMPARE(time->maximumWidth(), reserved);
    QCOMPARE(defaultDial->value(), 100);
    QVERIFY(hasTickAt(*defaultDial, 240.0));
    QVERIFY(hasTickAt(*defaultDial, -60.0));
    QVERIFY(!hasTickAt(*defaultDial, 270.0));

    workspace->requestProjectOpenAt(m_project.root());
    QVERIFY(workspace_test::waitForProject(*workspace));
    SongTab *first = open(window, m_songA);
    SongTab *second = open(window, m_songB, true);
    QVERIFY(first);
    QVERIFY(second);
    workspace->selectSongTab(first);

    auto *toolbar = window.findChild<QToolBar *>(QStringLiteral("transportToolbar"));
    auto *spacer = window.findChild<QWidget *>(QStringLiteral("transportVolumeSpacer"));
    auto *caption = window.findChild<QLabel *>(QStringLiteral("transportMasterVolumeCaption"));
    auto *spin = window.findChild<QSpinBox *>(QStringLiteral("transportMasterVolume"));
    auto *outputCaption =
        window.findChild<QLabel *>(QStringLiteral("transportOutputVolumeCaption"));
    auto *dial = window.findChild<QDial *>(QStringLiteral("transportOutputVolume"));
    QVERIFY(toolbar);
    QVERIFY(spacer);
    QVERIFY(caption);
    QVERIFY(spin);
    QVERIFY(outputCaption);
    QVERIFY(dial);
    const QList<QAction *> actions = toolbar->actions();
    const auto indexOf = [toolbar, &actions](QWidget *widget) {
        for (int index = 0; index < actions.size(); ++index) {
            if (toolbar->widgetForAction(actions[index]) == widget)
                return index;
        }
        return -1;
    };
    const int spacerIndex = indexOf(spacer);
    const int captionIndex = indexOf(caption);
    const int spinIndex = indexOf(spin);
    const int outputCaptionIndex = indexOf(outputCaption);
    const int dialIndex = indexOf(dial);
    QVERIFY(spacerIndex >= 0 && spacerIndex < captionIndex && captionIndex + 1 == spinIndex &&
            spinIndex < outputCaptionIndex && outputCaptionIndex < dialIndex &&
            dialIndex == actions.size() - 1);
    QCOMPARE(spacer->sizePolicy().horizontalPolicy(), QSizePolicy::Expanding);
    QVERIFY(spin->isEnabled());
    QCOMPARE(spin->value(), first->document().cfg().masterVolume);
    const int volumeBeforeOutput = first->document().cfg().masterVolume;
    const int undoBeforeOutput = first->document().undoStack()->count();
    dial->setValue(37);
    QSettings settings;
    QCOMPARE(dial->minimum(), 0);
    QCOMPARE(dial->maximum(), 100);
    QVERIFY(dial->toolTip().contains(QStringLiteral("Does not change the song volume")));
    QCOMPARE(window.m_audio.outputVolume(), 37);
    QCOMPARE(settings.value(QStringLiteral("outputVolume")).toInt(), 37);
    QCOMPARE(first->document().cfg().masterVolume, volumeBeforeOutput);
    QCOMPARE(first->document().undoStack()->count(), undoBeforeOutput);
    QVERIFY(!first->document().isDirty());

    dial->setValue(50);
    const QPointF center(dial->rect().center());
    checks::events::sendMouse(*dial, QEvent::MouseButtonPress, center, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*dial, QEvent::MouseButtonRelease, center, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    QCOMPARE(dial->value(), 50);
    QCOMPARE(first->document().undoStack()->count(), undoBeforeOutput);
    checks::events::sendMouse(*dial, QEvent::MouseButtonPress, center, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*dial, QEvent::MouseMove, center + QPointF(0.0, 11.0), Qt::NoButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*dial, QEvent::MouseButtonRelease, center + QPointF(0.0, 11.0),
                              Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    QVERIFY(dial->value() > 50);
    dial->setValue(50);
    checks::events::sendMouse(*dial, QEvent::MouseButtonPress, center, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*dial, QEvent::MouseMove, center + QPointF(0.0, -11.0), Qt::NoButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*dial, QEvent::MouseButtonRelease, center + QPointF(0.0, -11.0),
                              Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    QVERIFY(dial->value() < 50);
    dial->setValue(42);
    QCOMPARE(dial->value(), 42);
    QCOMPARE(window.m_audio.outputVolume(), 42);
    QCOMPARE(settings.value(QStringLiteral("outputVolume")).toInt(), 42);
    QCOMPARE(first->document().undoStack()->count(), undoBeforeOutput);
    QVERIFY(!first->document().isDirty());
    dial->setValue(37);

    const int beforeSongVolume = first->document().cfg().masterVolume;
    const int editedSongVolume = beforeSongVolume == 100 ? 101 : 100;
    spin->setValue(editedSongVolume);
    QCOMPARE(first->document().cfg().masterVolume, editedSongVolume);
    QVERIFY(first->document().isDirty());
    QVERIFY(first->history().canUndo());
    QVERIFY(window.m_appliedSettings);
    QCOMPARE(window.m_appliedSettings->songVolume, uint8_t(editedSongVolume));
    workspace->selectSongTab(second);
    QCOMPARE(spin->value(), second->document().cfg().masterVolume);
    QCOMPARE(dial->value(), 37);
    QCOMPARE(window.m_audio.outputVolume(), 37);
    QVERIFY(!second->document().isDirty());
    workspace->selectSongTab(first);
    QCOMPARE(spin->value(), editedSongVolume);
    workspace->requestUndo();
    QCOMPARE(first->document().cfg().masterVolume, beforeSongVolume);
    QVERIFY(!first->document().isDirty());
    QCOMPARE(spin->value(), beforeSongVolume);

    auto *lineEdit = spin->findChild<QLineEdit *>();
    QVERIFY(lineEdit);
    QKeyEvent space(QEvent::ShortcutOverride, Qt::Key_Space, Qt::NoModifier, QStringLiteral(" "));
    space.ignore();
    QApplication::sendEvent(lineEdit, &space);
    QVERIFY(!space.isAccepted());
    QKeyEvent digit(QEvent::ShortcutOverride, Qt::Key_5, Qt::NoModifier, QStringLiteral("5"));
    digit.ignore();
    QApplication::sendEvent(lineEdit, &digit);
    QVERIFY(digit.isAccepted());
}
