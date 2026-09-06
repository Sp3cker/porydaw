#include "checks/workspace/tst_workspacesessions.h"

#include <QtTest>

#include <QAbstractButton>
#include <QApplication>
#include <QComboBox>
#include <QFile>
#include <QMessageBox>
#include <QSettings>
#include <QTabWidget>
#include <QTimer>
#include <QToolButton>

#include <algorithm>
#include <cmath>
#include <memory>
#include <optional>

#include "core/smf.h"
#include "mainwindow.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/workspaceui.h"

namespace {

bool sameViewState(const SongView::ViewState &left, const SongView::ViewState &right)
{
    return left.valid == right.valid && left.pxPerBeat == right.pxPerBeat &&
           left.keyHeight == right.keyHeight && left.scrollPx == right.scrollPx &&
           left.scrollY == right.scrollY && left.selectedTrack == right.selectedTrack &&
           left.editCursorTick == right.editCursorTick && left.gridMinDenom == right.gridMinDenom &&
           left.gridTriplet == right.gridTriplet && left.eventList == right.eventList;
}

void verifyFreshView(const SongView &view, const SongView::ViewState &canonical)
{
    const SongView::ViewState defaults;
    const SongView::ViewState state = view.viewState();
    QVERIFY(state.valid);
    QVERIFY(std::abs(state.pxPerBeat - defaults.pxPerBeat) < 0.5);
    QCOMPARE(state.keyHeight, defaults.keyHeight);
    QCOMPARE(state.scrollPx, -view.camera().leadPadPx());
    QCOMPARE(state.scrollY, canonical.scrollY);
    QCOMPARE(state.selectedTrack, canonical.selectedTrack);
    QCOMPARE(state.editCursorTick, uint64_t(0));
    QCOMPARE(state.gridMinDenom, 0);
    QVERIFY(!state.gridTriplet);
    QVERIFY(!state.eventList);
    QVERIFY(!view.eventListVisible());
}

} // namespace

WorkspaceTabsTest::WorkspaceTabsTest(QString projectRoot, QString songA, QString songB)
    : m_songA(std::move(songA))
    , m_songB(std::move(songB))
    , m_project(std::move(projectRoot))
{}

void WorkspaceTabsTest::init()
{
    QSettings settings;
    settings.clear();
    settings.sync();
    QString error;
    QVERIFY2(m_project.reset(error), qPrintable(error));
}

void WorkspaceTabsTest::cleanup()
{
    QSettings settings;
    settings.clear();
    settings.sync();
}

SongTab *WorkspaceTabsTest::open(MainWindow &window, const QString &label, bool newTab)
{
    const std::optional<SongName> name = workspace_test::songName(label);
    if (!name)
        return nullptr;
    return workspace_test::openReady(*window.m_workspace, *name, newTab);
}

void WorkspaceTabsTest::lifecycle_data()
{
    QTest::addColumn<bool>("reverse");
    QTest::newRow("A-then-B") << false;
    QTest::newRow("B-then-A") << true;
}

void WorkspaceTabsTest::lifecycle()
{
    QFETCH(bool, reverse);
    const QString firstLabel = reverse ? m_songB : m_songA;
    const QString secondLabel = reverse ? m_songA : m_songB;
    const std::optional<SongName> firstName = workspace_test::songName(firstLabel);
    const std::optional<SongName> secondName = workspace_test::songName(secondLabel);
    QVERIFY(firstName);
    QVERIFY(secondName);

    MainWindow window;
    auto *workspace = window.m_workspace.get();
    QVERIFY(workspace);
    workspace->requestProjectOpenAt(m_project.root());
    QVERIFY(workspace_test::waitForProject(*workspace));

    workspace->requestSongOpen(*firstName);
    SongTab *first = workspace->songTabFor(*firstName);
    QVERIFY(!first || !first->isReady());
    first = workspace_test::waitReady(*workspace, *firstName);
    QVERIFY(first);
    QCOMPARE(workspace->openTabCount(), qsizetype(1));
    QCOMPARE(window.m_selectedTab, first);
    QVERIFY(!first->view().isHidden());
    QVERIFY(first->isReady());
    QCOMPARE(first->document().label(), firstLabel);
    QCOMPARE(window.m_audio.timeline(), first->timeline().get());
    QCOMPARE(window.m_audio.voicegroup(), first->voicegroupLease().get());
    QCOMPARE(window.m_uiTimer->interval(), 500);

    workspace->requestSongOpen(*secondName, true);
    SongTab *second = workspace->songTabFor(*secondName);
    QVERIFY(!second || !second->isReady());
    second = workspace_test::waitReady(*workspace, *secondName);
    QVERIFY(second);
    QVERIFY(second != first);
    QCOMPARE(workspace->openTabCount(), qsizetype(2));
    QCOMPARE(window.m_selectedTab, second);
    QVERIFY(!second->view().isHidden());
    QVERIFY(second->isReady());
    QCOMPARE(second->document().label(), secondLabel);
    QCOMPARE(window.m_audio.timeline(), second->timeline().get());
    QCOMPARE(workspace->songTabFor(*firstName), first);
    QVERIFY(!first->document().isDirty());
    const SongView::ViewState secondCanonical = second->view().viewState();

    workspace->requestSongOpen(*secondName, true);
    QCOMPARE(workspace->openTabCount(), qsizetype(2));
    QCOMPARE(workspace->selectedSongTab(), second);

    workspace->requestCloseSelectedTab();
    QTRY_COMPARE(workspace->openTabCount(), qsizetype(1));
    QCOMPARE(workspace->selectedSongTab(), first);
    QCOMPARE(window.m_audio.timeline(), first->timeline().get());
    QCOMPARE(workspace->songTabFor(*secondName), nullptr);

    SongTab *replacement = open(window, secondLabel);
    QVERIFY(replacement);
    QCOMPARE(workspace->openTabCount(), qsizetype(1));
    QCOMPARE(replacement->document().label(), secondLabel);
    QCOMPARE(workspace->songTabFor(*firstName), nullptr);
    QCOMPARE(window.m_audio.timeline(), replacement->timeline().get());

    window.m_audio.play();
    QTRY_COMPARE(window.m_audio.transport(), Transport::Playing);
    window.synchronizePlayhead();
    QCOMPARE(window.m_uiTimer->interval(), 100);
    workspace->requestCloseSelectedTab();
    QTRY_COMPARE(workspace->openTabCount(), qsizetype(0));
    QCOMPARE(workspace->selectedSongTab(), nullptr);
    QCOMPARE(window.m_uiTimer->interval(), 500);
    auto *root = window.findChild<QComboBox *>(QStringLiteral("transportScaleRoot"));
    auto *scale = window.findChild<QComboBox *>(QStringLiteral("transportScaleType"));
    auto *highlight = window.findChild<QToolButton *>(QStringLiteral("transportScaleHighlight"));
    auto *fold = window.findChild<QToolButton *>(QStringLiteral("transportScaleFold"));
    QVERIFY(root);
    QVERIFY(scale);
    QVERIFY(highlight);
    QVERIFY(fold);
    QVERIFY(!root->isEnabled());
    QVERIFY(!scale->isEnabled());
    QVERIFY(!highlight->isEnabled());
    QVERIFY(!fold->isEnabled());

    SongTab *reopened = open(window, secondLabel);
    QVERIFY(reopened);
    verifyFreshView(reopened->view(), secondCanonical);
}

void WorkspaceTabsTest::editUndoIsPerTab()
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

    workspace->selectSongTab(first);
    SongDocument &document = first->document();
    QVERIFY(document.engineTrackCount() > 0);
    uint64_t end = 0;
    for (const SmfTrack &track : document.smf().tracks)
        end = (std::max)(end, track.endTick);
    document.addNote(0, end + 96, 72, 24, 93);
    QVERIFY(first->document().isDirty());
    QVERIFY(!second->document().isDirty());
    auto *tabs = window.findChild<QTabWidget *>();
    QVERIFY(tabs);
    QVERIFY(tabs->tabText(tabs->indexOf(first)).endsWith(QLatin1Char('*')));
    QVERIFY(!tabs->tabText(tabs->indexOf(second)).endsWith(QLatin1Char('*')));

    window.m_audio.play();
    QTRY_COMPARE(window.m_audio.transport(), Transport::Playing);
    window.synchronizePlayhead();
    QCOMPARE(window.m_uiTimer->interval(), 100);
    workspace->selectSongTab(second);
    QCOMPARE(window.m_audio.transport(), Transport::Stopped);
    QCOMPARE(window.m_uiTimer->interval(), 500);
    QCOMPARE(window.m_audio.timeline(), second->timeline().get());
    QVERIFY(!second->history().canUndo());
    workspace->requestUndo();
    QVERIFY(!second->document().isDirty());

    workspace->selectSongTab(first);
    QVERIFY(first->document().isDirty());
    workspace->requestUndo();
    QVERIFY(!first->document().isDirty());
    QVERIFY(!second->document().isDirty());
}

void WorkspaceTabsTest::reloadRetainsCameraAndFreshOpenResetsIt()
{
    MainWindow window;
    auto *workspace = window.m_workspace.get();
    QVERIFY(workspace);
    workspace->requestProjectOpenAt(m_project.root());
    QVERIFY(workspace_test::waitForProject(*workspace));
    SongTab *tab = open(window, m_songB);
    QVERIFY(tab);
    const SongView::ViewState canonical = tab->view().viewState();

    SongDocument &document = tab->document();
    uint64_t end = 0;
    for (const SmfTrack &track : document.smf().tracks)
        end = (std::max)(end, track.endTick);
    document.addNote(0, end + 96, 72, 24, 93);
    workspace->requestUndo();
    QVERIFY(!document.isDirty());
    QVERIFY(document.undoStack()->count() > 0);

    const std::shared_ptr<const MidiTimeline> oldTimeline = tab->timeline();
    SongView::ViewState seeded = canonical;
    seeded.valid = true;
    seeded.pxPerBeat = canonical.pxPerBeat * 2.0;
    seeded.keyHeight = canonical.keyHeight + 9.0;
    seeded.scrollPx = canonical.scrollPx + 48.0;
    seeded.scrollY = canonical.scrollY + 40.0;
    for (int track = 0; track < 16; ++track) {
        if (oldTimeline->tracks[track].used && track != canonical.selectedTrack) {
            seeded.selectedTrack = track;
            break;
        }
    }
    QVERIFY(seeded.selectedTrack != canonical.selectedTrack);
    seeded.editCursorTick = oldTimeline->lengthTicks / 2;
    seeded.gridMinDenom = 16;
    seeded.gridTriplet = true;
    seeded.eventList = true;
    tab->view().applyViewState(seeded);
    const SongView::ViewState landed = tab->view().viewState();
    QVERIFY(sameViewState(landed, seeded));

    const SongName name = tab->name();
    workspace->requestSongOpen(name);
    QTRY_VERIFY(tab->isReady());
    QCOMPARE(workspace->openTabCount(), qsizetype(1));
    QCOMPARE(workspace->selectedSongTab(), tab);
    QVERIFY(workspace->openProjectEnabled());
    QCOMPARE(workspace->songTabFor(name), tab);
    QCOMPARE(document.undoStack()->count(), 0);
    QVERIFY(sameViewState(tab->view().viewState(), landed));
    QVERIFY(tab->timeline());
    QVERIFY(tab->timeline().get() != oldTimeline.get());
    QCOMPARE(window.m_audio.timeline(), tab->timeline().get());
    QCOMPARE(tab->view().timeline(), tab->timeline().get());
    QVERIFY(tab->voicegroupLease());
    QCOMPARE(tab->view().voicegroup(), tab->voicegroupLease().get());

    workspace->requestCloseSelectedTab();
    QTRY_COMPARE(workspace->openTabCount(), qsizetype(0));
    SongTab *reopened = open(window, m_songB);
    QVERIFY(reopened);
    verifyFreshView(reopened->view(), canonical);
}

void WorkspaceTabsTest::dirtyCloseUsesProductionGate_data()
{
    QTest::addColumn<int>("choice");
    QTest::newRow("cancel") << int(QMessageBox::Cancel);
    QTest::newRow("discard") << int(QMessageBox::Discard);
    QTest::newRow("save") << int(QMessageBox::Save);
}

void WorkspaceTabsTest::dirtyCloseUsesProductionGate()
{
    QFETCH(int, choice);
    const auto requestedChoice = static_cast<QMessageBox::StandardButton>(choice);

    MainWindow window;
    auto *workspace = window.m_workspace.get();
    QVERIFY(workspace);
    workspace->requestProjectOpenAt(m_project.root());
    QVERIFY(workspace_test::waitForProject(*workspace));
    SongTab *tab = open(window, m_songA);
    QVERIFY(tab);
    QVERIFY(tab->document().engineTrackCount() > 0);

    const QString midPath = tab->document().midPath();
    QFile originalFile(midPath);
    QVERIFY2(originalFile.open(QIODevice::ReadOnly), qPrintable(originalFile.errorString()));
    const QByteArray originalBytes = originalFile.readAll();
    originalFile.close();

    uint64_t end = 0;
    for (const SmfTrack &track : tab->document().smf().tracks)
        end = (std::max)(end, track.endTick);
    const uint64_t insertedTick = end + 96;
    tab->document().addNote(0, insertedTick, 72, 24, 93);
    QVERIFY(tab->document().isDirty());
    QVERIFY(tab->history().canUndo());

    bool handled = false;
    QString dialogError;
    QTimer chooser;
    chooser.setInterval(0);
    connect(&chooser, &QTimer::timeout, &window, [&] {
        QWidget *const modal = QApplication::activeModalWidget();
        if (!modal)
            return;
        auto *const box = qobject_cast<QMessageBox *>(modal);
        if (!box || box->parentWidget() != &window) {
            dialogError =
                QStringLiteral("unexpected modal dialog: ") + modal->metaObject()->className();
            chooser.stop();
            modal->close();
            return;
        }
        constexpr auto expectedButtons =
            QMessageBox::Save | QMessageBox::Discard | QMessageBox::Cancel;
        if ((box->standardButtons() & expectedButtons) != expectedButtons) {
            dialogError = QStringLiteral("dirty-close dialog did not offer Save, Discard, Cancel");
            chooser.stop();
            box->reject();
            return;
        }
        QAbstractButton *const button = box->button(requestedChoice);
        if (!button) {
            dialogError = QStringLiteral("dirty-close dialog lacked the requested semantic choice");
            chooser.stop();
            box->reject();
            return;
        }
        handled = true;
        chooser.stop();
        button->click();
    });
    chooser.start();
    workspace->requestCloseSelectedTab();
    chooser.stop();
    QVERIFY2(dialogError.isEmpty(), qPrintable(dialogError));
    QVERIFY2(handled, "dirty-close production dialog did not appear");

    if (requestedChoice == QMessageBox::Cancel) {
        QCOMPARE(workspace->openTabCount(), qsizetype(1));
        QCOMPARE(workspace->selectedSongTab(), tab);
        QVERIFY(tab->document().isDirty());
        QVERIFY(tab->history().canUndo());
        workspace->requestUndo();
        QVERIFY(!tab->document().isDirty());
        QVERIFY(!tab->history().canUndo());
        workspace->requestCloseSelectedTab();
        QTRY_COMPARE(workspace->openTabCount(), qsizetype(0));
    } else {
        QTRY_COMPARE(workspace->openTabCount(), qsizetype(0));
    }

    QFile persistedFile(midPath);
    QVERIFY2(persistedFile.open(QIODevice::ReadOnly), qPrintable(persistedFile.errorString()));
    const QByteArray persistedBytes = persistedFile.readAll();
    persistedFile.close();
    if (requestedChoice == QMessageBox::Save)
        QVERIFY(persistedBytes != originalBytes);
    else
        QCOMPARE(persistedBytes, originalBytes);

    SongTab *reopened = open(window, m_songA);
    QVERIFY(reopened);
    QVERIFY(!reopened->document().isDirty());
    QVERIFY(!reopened->history().canUndo());
    DocNote inserted;
    QCOMPARE(reopened->document().findNote(0, insertedTick, 72, &inserted),
             requestedChoice == QMessageBox::Save);
    workspace->requestCloseSelectedTab();
    QTRY_COMPARE(workspace->openTabCount(), qsizetype(0));
}
