#include "checks/workspace/tst_workspacesessions.h"

#include <QtTest>

#include <QComboBox>
#include <QToolButton>

#include <algorithm>

#include "mainwindow.h"
#include "porydaw_scale.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/workspaceui.h"

namespace {

void selectData(QComboBox &combo, int value)
{
    const int index = combo.findData(value);
    QVERIFY(index >= 0);
    combo.setCurrentIndex(index);
}

} // namespace

void WorkspaceTabsTest::scaleRouting()
{
    MainWindow window;
    auto *workspace = window.m_workspace.get();
    QVERIFY(workspace);
    workspace->requestProjectOpenAt(m_project.root());
    QVERIFY(workspace_test::waitForProject(*workspace));
    SongTab *first = open(window, m_songA);
    SongTab *second = open(window, m_songB, true);
    QVERIFY(first);
    QVERIFY(second);
    auto *root = window.findChild<QComboBox *>(QStringLiteral("transportScaleRoot"));
    auto *scale = window.findChild<QComboBox *>(QStringLiteral("transportScaleType"));
    auto *highlight = window.findChild<QToolButton *>(QStringLiteral("transportScaleHighlight"));
    auto *fold = window.findChild<QToolButton *>(QStringLiteral("transportScaleFold"));
    QVERIFY(root);
    QVERIFY(scale);
    QVERIFY(highlight);
    QVERIFY(fold);

    QCOMPARE(first->view().scaleRoot(), 0);
    QCOMPARE(first->view().scaleId(), porydaw_scale::ScaleId::major);
    QVERIFY(!first->view().scaleHighlight());
    QVERIFY(!first->view().scaleFold());
    QCOMPARE(second->view().scaleRoot(), 0);
    QCOMPARE(second->view().scaleId(), porydaw_scale::ScaleId::major);
    QVERIFY(!second->view().scaleHighlight());
    QVERIFY(!second->view().scaleFold());

    constexpr int firstRoot = 9;
    constexpr auto firstScale = porydaw_scale::ScaleId::dorian;
    constexpr int secondRoot = 2;
    constexpr auto secondScale = porydaw_scale::ScaleId::minor_pentatonic;
    workspace->selectSongTab(first);
    selectData(*root, firstRoot);
    selectData(*scale, static_cast<int>(firstScale));
    highlight->click();
    QCOMPARE(first->view().scaleRoot(), firstRoot);
    QCOMPARE(first->view().scaleId(), firstScale);
    QVERIFY(first->view().scaleHighlight());
    QVERIFY(!first->view().scaleFold());
    highlight->click();
    QVERIFY(!first->view().scaleHighlight());
    QVERIFY(!first->view().scaleFold());
    highlight->click();

    workspace->selectSongTab(second);
    selectData(*root, secondRoot);
    selectData(*scale, static_cast<int>(secondScale));
    SongView &view = second->view();
    SongDocument &document = second->document();
    const int originalTrack = view.selectionModel().primaryTrack();
    int otherTrack = -1;
    bool addedTrack = false;
    if (document.engineTrackCount() < 2) {
        otherTrack = document.addTrack(0);
        addedTrack = otherTrack >= 0;
    } else {
        for (int track = 0; track < document.engineTrackCount(); ++track) {
            if (track != originalTrack) {
                otherTrack = track;
                break;
            }
        }
    }
    QVERIFY(otherTrack >= 0);
    view.selectTrack(originalTrack);
    fold->click();
    QCOMPARE(view.scaleRoot(), secondRoot);
    QCOMPARE(view.scaleId(), secondScale);
    QVERIFY(!view.scaleHighlight());
    QVERIFY(view.scaleFold());
    QVERIFY(!highlight->isChecked());
    QVERIFY(fold->isChecked());
    highlight->click();
    QVERIFY(view.scaleHighlight() && view.scaleFold());
    highlight->click();
    QVERIFY(!view.scaleHighlight() && view.scaleFold());
    highlight->click();
    fold->click();
    QVERIFY(view.scaleHighlight() && !view.scaleFold());
    fold->click();
    QVERIFY(view.scaleHighlight() && view.scaleFold());

    workspace->selectSongTab(first);
    QCOMPARE(root->currentData().toInt(), firstRoot);
    QCOMPARE(scale->currentData().toInt(), static_cast<int>(firstScale));
    QVERIFY(highlight->isChecked());
    QVERIFY(!fold->isChecked());
    workspace->selectSongTab(second);
    QCOMPARE(root->currentData().toInt(), secondRoot);
    QCOMPARE(scale->currentData().toInt(), static_cast<int>(secondScale));
    QVERIFY(highlight->isChecked());
    QVERIFY(fold->isChecked());

    view.selectTrack(otherTrack);
    QVERIFY(view.scaleHighlight() && view.scaleFold());
    view.selectTrack(originalTrack);
    QVERIFY(view.scaleHighlight() && view.scaleFold());
    view.setScaleHighlight(false);
    view.setScaleFold(false);
    view.selectTrack(otherTrack);
    view.selectTrack(originalTrack);
    QVERIFY(!view.scaleHighlight() && !view.scaleFold());
    view.setScaleHighlight(true);
    view.selectTrack(otherTrack);
    QVERIFY(view.scaleHighlight() && !view.scaleFold());
    view.selectTrack(originalTrack);
    view.setScaleFold(true);
    view.selectTrack(0);
    view.deleteTrack(0);
    QVERIFY(view.scaleHighlight() && view.scaleFold());
    workspace->requestUndo();

    const int remapped = (std::max)(originalTrack, otherTrack);
    view.selectTrack(remapped);
    view.setScaleHighlight(true);
    view.setScaleFold(true);
    view.deleteTrack(0);
    QVERIFY(view.scaleHighlight() && view.scaleFold());
    workspace->requestUndo();
    QVERIFY(view.scaleHighlight() && view.scaleFold());
    if (addedTrack)
        workspace->requestUndo();
    QVERIFY(!second->document().isDirty());
    workspace->selectSongTab(first);
    QCOMPARE(first->view().scaleRoot(), firstRoot);
    QCOMPARE(first->view().scaleId(), firstScale);
    QVERIFY(first->view().scaleHighlight());
    QVERIFY(!first->view().scaleFold());
}
