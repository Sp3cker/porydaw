#include "checks/workspace/tst_workspacesessions.h"

#include <QtTest>

#include <QApplication>
#include <QColor>
#include <QCoreApplication>
#include <QDockWidget>
#include <QFont>
#include <QPalette>
#include <QPointF>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSize>
#include <QStringList>
#include <QVariant>

#include <algorithm>
#include <cstddef>
#include <optional>
#include <vector>

#include "mainwindow.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/theme/themeresolver.h"
#include "ui/theme/themeruntime.h"
#include "ui/workspacequick/workspacequickhost.h"
#include "ui/workspaceui.h"

namespace {

const QString kStripSongC = QStringLiteral("mus_littleroot_test");
const QString kStripSongD = QStringLiteral("mus_oldale");
const QString kStripSongE = QStringLiteral("mus_gym");

void settle()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

SongTab *requestLoadingTab(WorkspaceUi &workspace, const QString &label)
{
    const std::optional<SongName> name = workspace_test::songName(label);
    if (!name)
        return nullptr;
    workspace.requestSongOpen(*name, true);
    return workspace.songTabFor(*name);
}

void sendStripKey(QQuickWindow &window, int key, Qt::KeyboardModifiers modifiers)
{
    QTest::keyClick(&window, static_cast<Qt::Key>(key), modifiers);
    settle();
}

class ScopedAppliedTheme final
{
  public:
    explicit ScopedAppliedTheme(QApplication &application)
        : m_application(application)
        , m_theme(captureAppliedTheme())
        , m_font(application.font())
        , m_palette(application.palette())
        , m_styleSheet(application.styleSheet())
    {}

    ~ScopedAppliedTheme()
    {
        themes::apply(m_application, m_theme);
        m_application.setFont(m_font);
        m_application.setPalette(m_palette);
        m_application.setStyleSheet(m_styleSheet);
    }

    Q_DISABLE_COPY_MOVE(ScopedAppliedTheme)

  private:
    static themes::Theme captureAppliedTheme()
    {
        themes::Theme theme;
        for (std::size_t index = 0; index < themes::roleCount; ++index)
            theme.colors.at(index) = themes::color(static_cast<themes::Role>(index));
        return theme;
    }

    QApplication &m_application;
    themes::Theme m_theme;
    QFont m_font;
    QPalette m_palette;
    QString m_styleSheet;
};

} // namespace

void WorkspaceTabsTest::quickTabStripSelectsWithoutStealingFocus()
{
    MainWindow window;
    window.m_persistSession = false;
    auto *workspace = window.m_workspace.get();
    QVERIFY(workspace);
    workspace->requestProjectOpenAt(m_project.root());
    QVERIFY(workspace_test::waitForProject(*workspace));

    SongTab *a = open(window, m_songA);
    SongTab *b = open(window, m_songB, true);
    QVERIFY(a && b);
    QVERIFY(a->isReady() && b->isReady());
    workspace->selectSongTab(a);
    QCOMPARE(workspace->selectedSongTab(), a);

    auto *host = workspace_test::quickHost(window);
    QVERIFY(host);
    QVERIFY2(workspace_test::exposeWorkspaceHost(window, *host, QSize(1280, 800)),
             "the production workspace host did not expose its embedded Quick window");
    QQuickWindow *const quickWindow = host->window();
    QVERIFY(quickWindow);

    QPointer<SongTab> aGuard(a);
    QPointer<SongTab> bGuard(b);
    const std::vector<SongTab *> initialOrder = workspace->tabsInDisplayOrder();
    QCOMPARE(initialOrder.size(), size_t(2));
    QCOMPARE(initialOrder[0], a);
    QCOMPARE(initialOrder[1], b);

    QQuickItem *const aRoot = a->view().quickView()->rootObject();
    QQuickItem *const bRoot = b->view().quickView()->rootObject();
    QVERIFY(aRoot && bRoot);
    QVERIFY(aRoot->isVisible());
    QVERIFY(!bRoot->isVisible());
    QCOMPARE(a->view().quickView()->quickWindow(), quickWindow);
    QCOMPARE(b->view().quickView()->quickWindow(), quickWindow);

    QQuickItem *stripRoot = nullptr;
    QTRY_VERIFY((stripRoot = workspace_test::quickItem(*quickWindow,
                                                       QStringLiteral("songTabStrip"))) != nullptr);
    aRoot->forceActiveFocus(Qt::OtherFocusReason);
    QTRY_COMPARE(quickWindow->activeFocusItem(), aRoot);

    QQuickItem *tabB = nullptr;
    QTRY_VERIFY((tabB = workspace_test::quickItem(*quickWindow, QStringLiteral("songTab:") +
                                                                    m_songB)) != nullptr);
    QTRY_VERIFY(tabB->isVisible());
    workspace_test::clickQuickItem(*quickWindow, *tabB);

    QCOMPARE(workspace->selectedSongTab(), b);
    QCOMPARE(window.m_audio.timeline(), b->timeline().get());
    QCOMPARE(window.m_audio.voicegroup(), b->voicegroupLease().get());
    QTRY_VERIFY(bRoot->isVisible());
    QTRY_VERIFY(!aRoot->isVisible());
    QQuickItem *focusItem = quickWindow->activeFocusItem();
    QVERIFY(!focusItem || !stripRoot->isAncestorOf(focusItem));

    QQuickItem *tabA = nullptr;
    QTRY_VERIFY((tabA = workspace_test::quickItem(*quickWindow, QStringLiteral("songTab:") +
                                                                    m_songA)) != nullptr);
    QTRY_VERIFY(tabA->isVisible());
    workspace_test::clickQuickItem(*quickWindow, *tabA);
    QCOMPARE(workspace->selectedSongTab(), a);
    QCOMPARE(window.m_audio.timeline(), a->timeline().get());
    QCOMPARE(window.m_audio.voicegroup(), a->voicegroupLease().get());
    QTRY_VERIFY(aRoot->isVisible());
    QTRY_VERIFY(!bRoot->isVisible());
    focusItem = quickWindow->activeFocusItem();
    QVERIFY(!focusItem || !stripRoot->isAncestorOf(focusItem));

    SongTab *c = open(window, kStripSongC, true);
    SongTab *d = open(window, kStripSongD, true);
    QVERIFY(c && d);
    QCOMPARE(workspace->openTabCount(), qsizetype(4));
    workspace->selectSongTab(a);
    QCOMPARE(workspace->selectedSongTab(), a);
    QQuickItem *const cRoot = c->view().quickView()->rootObject();
    QQuickItem *const dRoot = d->view().quickView()->rootObject();
    QVERIFY(cRoot && dRoot);
    QTRY_VERIFY(!cRoot->isVisible());
    QTRY_VERIFY(!dRoot->isVisible());

    QQuickItem *closeB = nullptr;
    QTRY_VERIFY((closeB = workspace_test::quickItem(*quickWindow, QStringLiteral("songTabClose:") +
                                                                      m_songB)) != nullptr);
    QTRY_VERIFY(closeB->isVisible());
    int bDetachCount = 0;
    bool bDetachedWhileLive = false;
    QObject::connect(b->view().quickView(), &songview::TimelineQuickView::windowAboutToDetach,
                     [&bDetachCount, &bDetachedWhileLive, &bGuard] {
                         bDetachedWhileLive = !bGuard.isNull();
                         ++bDetachCount;
                     });
    workspace_test::clickQuickItem(*quickWindow, *closeB);

    QTRY_COMPARE(workspace->openTabCount(), qsizetype(3));
    QCOMPARE(workspace->selectedSongTab(), a);
    QCOMPARE(window.m_audio.timeline(), a->timeline().get());
    QCOMPARE(window.m_audio.voicegroup(), a->voicegroupLease().get());
    QCOMPARE(bDetachCount, 1);
    QVERIFY(bDetachedWhileLive);
    QVERIFY(bGuard.isNull());
    QTRY_VERIFY(aRoot->isVisible());

    QQuickItem *closeA = nullptr;
    QTRY_VERIFY((closeA = workspace_test::quickItem(*quickWindow, QStringLiteral("songTabClose:") +
                                                                      m_songA)) != nullptr);
    QTRY_VERIFY(closeA->isVisible());
    int aDetachCount = 0;
    bool aDetachedWhileLive = false;
    QObject::connect(a->view().quickView(), &songview::TimelineQuickView::windowAboutToDetach,
                     [&aDetachCount, &aDetachedWhileLive, &aGuard] {
                         aDetachedWhileLive = !aGuard.isNull();
                         ++aDetachCount;
                     });
    workspace_test::clickQuickItem(*quickWindow, *closeA);

    QTRY_COMPARE(workspace->openTabCount(), qsizetype(2));
    const std::vector<SongTab *> remainingOrder = workspace->tabsInDisplayOrder();
    QCOMPARE(remainingOrder.size(), size_t(2));
    QCOMPARE(remainingOrder[0], c);
    QCOMPARE(remainingOrder[1], d);
    QCOMPARE(workspace->selectedSongTab(), c);
    QCOMPARE(window.m_audio.timeline(), c->timeline().get());
    QCOMPARE(window.m_audio.voicegroup(), c->voicegroupLease().get());
    QCOMPARE(aDetachCount, 1);
    QVERIFY(aDetachedWhileLive);
    QVERIFY(aGuard.isNull());
    QTRY_VERIFY(cRoot->isVisible());
    QTRY_VERIFY(!dRoot->isVisible());

    QQuickItem *tabD = nullptr;
    QTRY_VERIFY((tabD = workspace_test::quickItem(*quickWindow, QStringLiteral("songTab:") +
                                                                    kStripSongD)) != nullptr);
    QTRY_VERIFY(tabD->isVisible());
    workspace_test::clickQuickItem(*quickWindow, *tabD);
    QCOMPARE(workspace->selectedSongTab(), d);
    QCOMPARE(window.m_audio.timeline(), d->timeline().get());
    QCOMPARE(window.m_audio.voicegroup(), d->voicegroupLease().get());
    QTRY_VERIFY(dRoot->isVisible());
    QTRY_VERIFY(!cRoot->isVisible());
    focusItem = quickWindow->activeFocusItem();
    QVERIFY(!focusItem || !stripRoot->isAncestorOf(focusItem));

    QQuickItem *stripBackground = nullptr;
    QTRY_VERIFY((stripBackground = workspace_test::quickItem(
                     *quickWindow, QStringLiteral("songTabStripBackground"))) != nullptr);
    auto *const application = static_cast<QApplication *>(QCoreApplication::instance());
    QVERIFY(application);
    const ScopedAppliedTheme baselineChrome(*application);
    themes::apply(*application, themes::darkNeutralHigh());
    QTRY_COMPARE(stripBackground->property("color").value<QColor>(),
                 themes::color(themes::Role::tab_pane_background));
    themes::apply(*application, themes::vanilla());
    QTRY_COMPARE(stripBackground->property("color").value<QColor>(),
                 themes::color(themes::Role::tab_pane_background));
}

void WorkspaceTabsTest::quickTabStripOverflowKeepsTabsReachable()
{
    MainWindow window;
    window.m_persistSession = false;
    auto *workspace = window.m_workspace.get();
    QVERIFY(workspace);
    workspace->requestProjectOpenAt(m_project.root());
    QVERIFY(workspace_test::waitForProject(*workspace));
    // The default left docks squeeze the central strip inside this narrow
    // window, so the production reachability oracle would measure a docked
    // layout instead of the strip's own overflow. Stage the window with both
    // left docks closed (the polyphony dock already ships hidden); the strip
    // then owns the full client width, as in every other window arrangement.
    if (auto *songsDock = window.findChild<QDockWidget *>(QStringLiteral("songsDock")))
        songsDock->hide();
    if (auto *voicegroupDock = window.findChild<QDockWidget *>(QStringLiteral("voicegroupDock")))
        voicegroupDock->hide();

    SongTab *a = open(window, m_songA);
    SongTab *b = open(window, m_songB, true);
    QVERIFY(a && b);
    QVERIFY(a->isReady() && b->isReady());

    auto *host = workspace_test::quickHost(window);
    QVERIFY(host);
    QVERIFY2(workspace_test::exposeWorkspaceHost(window, *host, QSize(360, 480)),
             "the production workspace host did not expose its embedded Quick window");
    QQuickWindow *const quickWindow = host->window();
    QVERIFY(quickWindow);

    SongTab *c = requestLoadingTab(*workspace, kStripSongC);
    SongTab *d = requestLoadingTab(*workspace, kStripSongD);
    SongTab *e = requestLoadingTab(*workspace, kStripSongE);
    QVERIFY(c && d && e);
    QVERIFY(!c->isReady());
    QVERIFY(!d->isReady());
    QVERIFY(!e->isReady());
    QCOMPARE(workspace->openTabCount(), qsizetype(5));
    workspace->selectSongTab(a);
    QCOMPARE(workspace->selectedSongTab(), a);
    QQuickItem *stripRoot = nullptr;
    QTRY_VERIFY((stripRoot = workspace_test::quickItem(*quickWindow,
                                                       QStringLiteral("songTabStrip"))) != nullptr);

    const QStringList labels = {m_songA, m_songB, kStripSongC, kStripSongD, kStripSongE};
    const std::vector<SongTab *> tabs = {a, b, c, d, e};
    // Establish real stock-TabBar overflow before testing reachability.
    QTRY_VERIFY([&] {
        qreal left = 0.0;
        qreal right = 0.0;
        for (qsizetype index = 0; index < labels.size(); ++index) {
            QQuickItem *const tab = workspace_test::quickItem(
                *quickWindow, QStringLiteral("songTab:") + labels.at(index));
            if (!tab || tab->width() <= 0.0 || tab->height() <= 0.0)
                return false;
            if (index == 0)
                left = tab->mapToItem(stripRoot, QPointF()).x();
            if (index == labels.size() - 1)
                right = tab->mapToItem(stripRoot, QPointF(tab->width(), 0.0)).x();
        }
        return right - left > stripRoot->width();
    }());

    QVERIFY(!quickWindow->activeFocusItem() ||
            !stripRoot->isAncestorOf(quickWindow->activeFocusItem()));
    for (int step = 1; step < labels.size(); ++step) {
        if (step == 2) {
            SongTab *const focusedTab = tabs[size_t(step - 1)];
            QVERIFY(focusedTab->isReady());
            QQuickItem *const focusRoot = focusedTab->view().quickView()->rootObject();
            QVERIFY(focusRoot);
            focusRoot->forceActiveFocus(Qt::OtherFocusReason);
            QTRY_COMPARE(quickWindow->activeFocusItem(), focusRoot);
        }

        sendStripKey(*quickWindow, Qt::Key_Tab, Qt::ControlModifier);
        SongTab *const selected = tabs[size_t(step)];
        QTRY_COMPARE(workspace->selectedSongTab(), selected);
        QQuickItem *const selectedRoot = selected->view().quickView()->rootObject();
        QVERIFY(selectedRoot);
        QTRY_VERIFY(selectedRoot->isVisible());
        QQuickItem *tabButton = nullptr;
        QTRY_VERIFY((tabButton = workspace_test::quickItem(
                         *quickWindow, QStringLiteral("songTab:") + labels.at(step))) != nullptr);
        if (!QTest::qWaitFor(
                [&] { return workspace_test::itemInsideViewport(*tabButton, *stripRoot); }, 5000)) {
            const QPointF mapped = tabButton->mapToItem(stripRoot, QPointF());
            QWARN(
                qPrintable(QStringLiteral("step %1 tab %2 not reachable: mapped(%3,%4) item %5x%6 "
                                          "strip %7x%8 tabVisible=%9 stripVisible=%10")
                               .arg(step)
                               .arg(labels.at(step))
                               .arg(mapped.x())
                               .arg(mapped.y())
                               .arg(tabButton->width())
                               .arg(tabButton->height())
                               .arg(stripRoot->width())
                               .arg(stripRoot->height())
                               .arg(tabButton->isVisible())
                               .arg(stripRoot->isVisible())));
            QFAIL("the selected tab did not become reachable inside the strip viewport");
        }
    }

    sendStripKey(*quickWindow, Qt::Key_Tab, Qt::ControlModifier | Qt::ShiftModifier);
    QTRY_COMPARE(workspace->selectedSongTab(), d);
    QQuickItem *previousTab = nullptr;
    QTRY_VERIFY((previousTab = workspace_test::quickItem(
                     *quickWindow, QStringLiteral("songTab:") + kStripSongD)) != nullptr);
    if (!QTest::qWaitFor(
            [&] { return workspace_test::itemInsideViewport(*previousTab, *stripRoot); }, 5000)) {
        const QPointF mapped = previousTab->mapToItem(stripRoot, QPointF());
        QWARN(qPrintable(QStringLiteral("previous tab %1 not reachable: mapped(%2,%3) item %4x%5 "
                                        "strip %6x%7 tabVisible=%8 stripVisible=%9")
                             .arg(kStripSongD)
                             .arg(mapped.x())
                             .arg(mapped.y())
                             .arg(previousTab->width())
                             .arg(previousTab->height())
                             .arg(stripRoot->width())
                             .arg(stripRoot->height())
                             .arg(previousTab->isVisible())
                             .arg(stripRoot->isVisible())));
        QFAIL("the previous tab did not stay reachable inside the strip viewport");
    }
}
