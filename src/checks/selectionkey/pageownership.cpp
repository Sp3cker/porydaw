// Selection keyboard routing, protected-local-input tier: production page
// ownership. Every scenario drives the real MainWindow/WorkspaceUi shell and
// its one WorkspaceQuickHost window. The tabs are actual SongTab sessions:
// selection, readiness, page attachment, cancellation, audio handoff, and
// removal all pass through production rather than a fixture-local registry.
//
// The observable contracts:
// * only the selected, ready page owning the focused Quick subtree reacts to
//   the pencil shortcut; moving selection moves that ownership without
//   cross-page toggles;
// * a fresh selected but unready SongTab declines the binding, then the newly
//   ready page alone can commit an automation edit;
// * QML text input keeps its own typing, undo, and clipboard behavior and
//   refuses timeline shortcuts while it owns focus;
// * selecting away cancels an outgoing prompt, pencil draft, and held audition
//   without mutation or a dropped routed note-off; and
// * closing a page during a held press swallows its later release, while the
//   replacement page immediately accepts a fresh real click.

#include "checks/fwd.hpp"

#include "checks/automation/automationvalueprompt.h"
#include "checks/clipcheck_support.h"
#include "checks/selectionkey/automationprobe.h"
#include "checks/selectionkey/session.h"
#include "checks/support/eventsynth.h"

#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"

#include <QApplication>
#include <QClipboard>
#include <QCloseEvent>
#include <QCoreApplication>
#include <QKeyEvent>
#include <QKeySequence>
#include <QMetaObject>
#include <QMouseEvent>
#include <QPointer>
#include <QPointingDevice>
#include <QQuickItem>
#include <QQuickWindow>
#include <QValidator>
#include <QtTest>

#include <memory>
#include <optional>
#include <utility>
#include <vector>

namespace {

constexpr int kTrack = 0;
constexpr uint8_t kController = 10;
constexpr int kPromptInsertValue = 32;
constexpr int kAutomationHeight = 320;
constexpr uint64_t kFirstFixturePointTick = 48;
constexpr uint64_t kSecondFixturePointTick = 96;

struct DocumentState {
    QByteArray smf;
    int undoIndex = 0;
};

DocumentState documentState(SongDocument &document)
{
    return {document.smf().write(), document.undoStack()->index()};
}

bool matchesDocumentState(SongDocument &document, const DocumentState &state)
{
    return document.smf().write() == state.smf && document.undoStack()->index() == state.undoIndex;
}

bool deliverPencilPress(QQuickWindow &window, const QKeyCombination &pencil)
{
    return selectionkey::deliverKey(&window, pencil.key(), pencil.keyboardModifiers());
}

// Unlike the general QTest-backed shortcut helper, this path must not pump the
// event loop while the selected B page remains unready. Deliver the same
// window-level Qt key lifecycle synchronously so Quick routes it to B's real
// active subtree. Acceptance is not the oracle: the downstream per-page mode
// and document assertions observe whether B declined and A kept its state.
void deliverUnreadyPencilPress(QQuickWindow &window, const QKeyCombination &pencil)
{
    QKeyEvent shortcutOverride(QEvent::ShortcutOverride, pencil.key(), pencil.keyboardModifiers());
    QCoreApplication::sendEvent(&window, &shortcutOverride);
    QKeyEvent press(QEvent::KeyPress, pencil.key(), pencil.keyboardModifiers());
    QCoreApplication::sendEvent(&window, &press);
    QKeyEvent release(QEvent::KeyRelease, pencil.key(), pencil.keyboardModifiers());
    QCoreApplication::sendEvent(&window, &release);
}

// Window-local and scene coordinates are identical for the shared
// QQuickWindow target. Keeping both explicit preserves the full Qt 6 mouse
// event mapping while avoiding QTest's unconditional processEvents().
void sendSynchronousWindowMouse(QQuickWindow &window, QEvent::Type type, const QPoint &position,
                                Qt::MouseButton button, Qt::MouseButtons buttons)
{
    const QPointF windowPosition(position);
    QMouseEvent event(type, windowPosition, windowPosition, QPointF(window.mapToGlobal(position)),
                      button, buttons, Qt::NoModifier, QPointingDevice::primaryPointingDevice());
    QCoreApplication::sendEvent(&window, &event);
}

} // namespace

class SelectionPageOwnershipTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(SelectionPageOwnershipTest)

  public:
    SelectionPageOwnershipTest(QString projectRoot, QString songA, QString songB)
        : m_projectRoot(std::move(projectRoot))
        , m_songA(std::move(songA))
        , m_songB(std::move(songB))
    {}

  private slots:
    void init();
    void cleanup();

    // Both pages are ready: the focused, selected page alone toggles pencil
    // mode, and the same real click-plus-key sequence transfers ownership.
    void selectedPageTogglesPencilInSharedWindow();
    // Fresh B is selected but unready after its real load request, so it
    // declines input. Once B becomes ready it alone commits the delivered
    // automation change; A's document and undo history remain untouched.
    void ineligiblePageCannotStealFromEligibleOne();
    // Real QML text entry in page A's prompt keeps typing, clipboard, and
    // local undo local while the pencil shortcut remains refused.
    void valuePromptTextEntryStaysLocalToItsPage();
    // Production selection cancels an outgoing value prompt, pencil draft,
    // and held audition before B is exposed, preserving the routed note-off.
    void outgoingGestureCancelsWithoutCommittingIntoSibling();
    // Closing a held page removes its scene before the stale release arrives;
    // that release cannot reach B, whose following click still works.
    void releaseFromRemovedPageIsSwallowedBeforeNextPageClick();

  private:
    bool activateShell(QString &error) const;
    SongTab *openReadyB(QString &error);
    SongTab *openUnreadyB(QString &error);
    songview::TimelineQuickView *quick(SongTab &tab) const;
    songview::TimelineInputItem *automationInput(SongTab &tab) const;
    songview::TimelineInputItem *rollGutterInput(SongTab &tab) const;
    AutomationCanvas *automationCanvas(SongTab &tab) const;
    DrawerChrome *drawerChrome(SongTab &tab) const;
    bool waitForReadyPage(SongTab &tab, QString &diagnostics) const;
    bool selectReadyPage(SongTab &tab, QString &diagnostics) const;
    bool prepareAutomation(SongTab &tab, QString &diagnostics) const;
    bool locateEmptyLanePoint(SongTab &tab, QPoint &scene, QString &diagnostics) const;
    bool stageFocus(SongTab &tab, QString &diagnostics) const;
    bool openInsertionPrompt(SongTab &tab, QPoint &scene, QString &diagnostics) const;
    static std::optional<QString> printableText(const QKeyCombination &binding);
    void trackPointer(const QPoint &position);
    void trackRelease();
    bool undoLiveTabs(QString &error) const;

    QString m_projectRoot;
    QString m_songA;
    QString m_songB;
    std::unique_ptr<selectionkey::SessionSettingsGuard> m_settings;
    std::unique_ptr<clipcheck_support::ClipboardStateGuard> m_clipboard;
    selectionkey::WindowSession m_session;
    WorkspaceUi *m_workspace = nullptr;
    QPointer<WorkspaceQuickHost> m_host;
    QPointer<QQuickWindow> m_window;
    QPointer<SongTab> m_tabA;
    QPointer<SongTab> m_tabB;
    Qt::MouseButton m_heldButton = Qt::NoButton;
    QPoint m_lastWindowPosition;
};

bool SelectionPageOwnershipTest::activateShell(QString &error) const
{
    if (!m_session.window) {
        error = QStringLiteral("the production shell is missing");
        return false;
    }
    // The existing input-acquisition seam remains the outer native shell.
    // No rendering helper activates the shared Quick window or forces a page
    // focus; actual timeline clicks below acquire the Quick subtree focus.
    m_session.window->raise();
    m_session.window->activateWindow();
    if (checks::async_wait::waitUntil(
            [] { return true; },
            [this] { return QApplication::activeWindow() == m_session.window.get(); }, 5000,
            10) != checks::async_wait::Result::Ready) {
        error = QStringLiteral("the production shell never became the active window");
        return false;
    }
    return true;
}

SongTab *SelectionPageOwnershipTest::openReadyB(QString &error)
{
    if (m_tabB)
        return m_tabB.data();
    SongTab *const tab = selectionkey::openSongTab(m_session, m_songB, true, error);
    if (tab)
        m_tabB = tab;
    return tab;
}

SongTab *SelectionPageOwnershipTest::openUnreadyB(QString &error)
{
    if (m_tabB)
        return m_tabB.data();
    SongTab *const tab = selectionkey::requestSongTab(m_session, m_songB, true, error);
    if (tab)
        m_tabB = tab;
    return tab;
}

songview::TimelineQuickView *SelectionPageOwnershipTest::quick(SongTab &tab) const
{
    return selectionkey::quickCanvas(tab.view());
}

songview::TimelineInputItem *SelectionPageOwnershipTest::automationInput(SongTab &tab) const
{
    songview::TimelineQuickView *const canvas = quick(tab);
    QQuickItem *const root = canvas ? canvas->rootObject() : nullptr;
    return root ? root->findChild<songview::TimelineInputItem *>(
                      QStringLiteral("timelineAutomationInput"))
                : nullptr;
}

songview::TimelineInputItem *SelectionPageOwnershipTest::rollGutterInput(SongTab &tab) const
{
    songview::TimelineQuickView *const canvas = quick(tab);
    QQuickItem *const root = canvas ? canvas->rootObject() : nullptr;
    return root ? root->findChild<songview::TimelineInputItem *>(
                      QStringLiteral("timelineRollGutterInput"))
                : nullptr;
}

AutomationCanvas *SelectionPageOwnershipTest::automationCanvas(SongTab &tab) const
{
    EditorDrawer *const drawer = tab.view().editorDrawer();
    AutomationPage *const page = drawer ? drawer->automationPage() : nullptr;
    return page ? page->canvas() : nullptr;
}

DrawerChrome *SelectionPageOwnershipTest::drawerChrome(SongTab &tab) const
{
    EditorDrawer *const drawer = tab.view().editorDrawer();
    return drawer ? &drawer->chrome() : nullptr;
}

bool SelectionPageOwnershipTest::waitForReadyPage(SongTab &tab, QString &diagnostics) const
{
    diagnostics.clear();
    songview::TimelineQuickView *const canvas = quick(tab);
    if (!canvas || !m_workspace || !m_window) {
        diagnostics =
            QStringLiteral("the page coordinator, workspace, or shared window is missing");
        return false;
    }
    const QPointer<SongTab> liveTab(&tab);
    const QPointer<songview::TimelineQuickView> liveCanvas(canvas);
    const bool settled = QTest::qWaitFor(
        [this, liveTab, liveCanvas] {
            if (!liveTab || !liveCanvas || !m_workspace || !m_window)
                return false;
            songview::TimelineInputItem *const input = automationInput(*liveTab);
            return m_workspace->selectedSongTab() == liveTab.data() && liveTab->isReady() &&
                   liveCanvas->quickWindow() == m_window.data() && liveCanvas->inputEligible() &&
                   m_window->isVisible() && m_window->isExposed() && input &&
                   input->window() == m_window.data() && input->isVisible() && input->isEnabled() &&
                   !input->bounds().isEmpty();
        },
        30000);
    if (settled)
        return true;

    songview::TimelineInputItem *const input = liveTab ? automationInput(*liveTab) : nullptr;
    diagnostics = QStringLiteral("selected=%1 ready=%2 canvas-window=%3 eligible=%4 "
                                 "shared-visible=%5 shared-exposed=%6 input=%7 input-bounds=%8")
                      .arg(m_workspace->selectedSongTab() == liveTab.data())
                      .arg(liveTab && liveTab->isReady())
                      .arg(liveCanvas && liveCanvas->quickWindow() == m_window.data())
                      .arg(liveCanvas && liveCanvas->inputEligible())
                      .arg(m_window->isVisible())
                      .arg(m_window->isExposed())
                      .arg(input != nullptr)
                      .arg(input ? QStringLiteral("%1,%2 %3x%4")
                                       .arg(input->bounds().x())
                                       .arg(input->bounds().y())
                                       .arg(input->bounds().width())
                                       .arg(input->bounds().height())
                                 : QStringLiteral("none"));
    return false;
}

bool SelectionPageOwnershipTest::selectReadyPage(SongTab &tab, QString &diagnostics) const
{
    if (!m_workspace || m_workspace->songTabFor(tab.name()) != &tab) {
        diagnostics = QStringLiteral("the requested page is no longer live in WorkspaceUi");
        return false;
    }
    m_workspace->selectSongTab(&tab);
    selectionkey::settle();
    return waitForReadyPage(tab, diagnostics);
}

bool SelectionPageOwnershipTest::prepareAutomation(SongTab &tab, QString &diagnostics) const
{
    if (!waitForReadyPage(tab, diagnostics))
        return false;
    SongView &view = tab.view();
    // The visible automation surface is test staging, not the subject. Hide
    // unrelated drawers so the actual CC lane retains a real body rectangle.
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, false);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
    view.setDrawerActivePage(EditorDrawerPage::Automations);
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, kAutomationHeight);
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    tab.document().addLanePoint(kTrack, kController, kFirstFixturePointTick, 32);
    tab.document().addLanePoint(kTrack, kController, kSecondFixturePointTick, 64);
    selectionkey::settle();

    songview::TimelineInputItem *const input = automationInput(tab);
    AutomationCanvas *const canvas = automationCanvas(tab);
    if (!input || !canvas) {
        diagnostics = QStringLiteral("the selected page has no automation input or canvas");
        return false;
    }
    const auto probe =
        selectionkey::AutomationProbe::locate(view, input, kTrack, kController, &diagnostics);
    return probe.has_value();
}

bool SelectionPageOwnershipTest::locateEmptyLanePoint(SongTab &tab, QPoint &scene,
                                                      QString &diagnostics) const
{
    songview::TimelineInputItem *const input = automationInput(tab);
    if (!input) {
        diagnostics = QStringLiteral("the automation input is missing");
        return false;
    }
    const auto probe =
        selectionkey::AutomationProbe::locate(tab.view(), input, kTrack, kController, &diagnostics);
    if (!probe)
        return false;
    return probe->emptyNodePoint(kPromptInsertValue, scene, &diagnostics);
}

bool SelectionPageOwnershipTest::stageFocus(SongTab &tab, QString &diagnostics) const
{
    if (!waitForReadyPage(tab, diagnostics))
        return false;
    songview::TimelineInputItem *const input = automationInput(tab);
    if (!input) {
        diagnostics = QStringLiteral("the automation input is missing");
        return false;
    }
    QPoint lanePoint;
    if (!locateEmptyLanePoint(tab, lanePoint, diagnostics))
        return false;
    const bool clicked = selectionkey::clickTimelineInput(m_window.data(), input, lanePoint);
    // Selection-focus publication is queued behind the model notification, so
    // the click-driven acquisition and the queued request converge a few
    // event-loop turns after the click — especially after an outgoing prompt
    // cancellation reroutes focus across the B→A return. Observe that
    // convergence here at the staging seam: one click, no forced focus, the
    // oracle itself unchanged.
    const QPointer<songview::TimelineInputItem> liveInput(input);
    const bool focused =
        clicked && m_window &&
        QTest::qWaitFor(
            [this, liveInput] {
                return liveInput && liveInput->hasActiveFocus() && m_window &&
                       automation_valueprompt::inputOwnsFocus(*m_window, *liveInput);
            },
            5000);
    if (!focused) {
        diagnostics = QStringLiteral("clicked=%1 active-focus=%2 owner-focus=%3 point=(%4,%5) "
                                     "input-window=%6 input-bounds=%7")
                          .arg(clicked)
                          .arg(input->hasActiveFocus())
                          .arg(automation_valueprompt::inputOwnsFocus(*m_window, *input))
                          .arg(lanePoint.x())
                          .arg(lanePoint.y())
                          .arg(input->window() == m_window.data())
                          .arg(QStringLiteral("%1,%2 %3x%4")
                                   .arg(input->bounds().x())
                                   .arg(input->bounds().y())
                                   .arg(input->bounds().width())
                                   .arg(input->bounds().height()));
    }
    return focused;
}

bool SelectionPageOwnershipTest::openInsertionPrompt(SongTab &tab, QPoint &scene,
                                                     QString &diagnostics) const
{
    AutomationCanvas *const canvas = automationCanvas(tab);
    DrawerChrome *const chrome = drawerChrome(tab);
    songview::TimelineInputItem *const input = automationInput(tab);
    if (!canvas || !chrome || !input) {
        diagnostics =
            QStringLiteral("the automation canvas, its drawer chrome, or its input is missing");
        return false;
    }
    if (canvas->pencilMode()) {
        diagnostics = QStringLiteral("pencil mode must be off before opening a value prompt");
        return false;
    }
    if (!locateEmptyLanePoint(tab, scene, diagnostics))
        return false;
    // Item-direct double-click seam. TimelinePointerInput.position is
    // QMouseEvent::position() — item-local by contract — and the canvas adds
    // only the vertical scroll before lane/node hit, so the DblClick event
    // must reach TimelineInputItem::mouseDoubleClickEvent carrying item-local
    // coordinates. Every passing double-click precedent in the repo delivers
    // exactly that: an explicit MouseButtonDblClick plus Release sent
    // synchronously to the QQuickItem itself (checks::events::sendMouse;
    // rollcheck/harness.cpp drawNote, drawerpresentation/voice.cpp). The
    // window-level direct-sendEvent DblClick tried before never opened the
    // prompt even with an explicit DblClick-typed event and green geometry
    // diagnostics, which refutes the earlier platform-recognition account:
    // the failure is the delivery seam, not Cocoa. The preceding synthetic
    // Press is omitted deliberately — the proven pattern sends none, and a
    // window-level Press would arm a real sweep gesture and grab at the
    // insertion point ahead of the DblClick. No QTest, no event-loop pump,
    // no semantic prompt API.
    const QPointF local = input->mapFromScene(QPointF(scene));
    if (!input->bounds().contains(local)) {
        diagnostics = QStringLiteral("the staged insertion point left the automation input "
                                     "(scene=(%1,%2) local=(%3,%4) bounds=%5)")
                          .arg(scene.x())
                          .arg(scene.y())
                          .arg(local.x())
                          .arg(local.y())
                          .arg(QStringLiteral("%1,%2 %3x%4")
                                   .arg(input->bounds().x())
                                   .arg(input->bounds().y())
                                   .arg(input->bounds().width())
                                   .arg(input->bounds().height()));
        return false;
    }
    checks::events::sendMouse(*input, QEvent::MouseButtonDblClick, local, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*input, QEvent::MouseButtonRelease, local, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    const bool opened =
        QTest::qWaitFor([chrome] { return automation_valueprompt::promptVisible(*chrome); }, 5000);
    selectionkey::settle();
    if (!opened) {
        const QQuickItem *const grabber = m_window ? m_window->mouseGrabberItem() : nullptr;
        diagnostics =
            QStringLiteral("the item-direct double click did not open the automation value prompt "
                           "(point=(%1,%2) window=%3x%4 contains=%5 input=%6 bounds=%7 "
                           "input-contains=%8 active-focus=%9 owner-focus=%10 pencil=%11 "
                           "grabber=%12 modal=%13 shared-visible=%14 shared-exposed=%15)")
                .arg(scene.x())
                .arg(scene.y())
                .arg(m_window ? m_window->width() : -1)
                .arg(m_window ? m_window->height() : -1)
                .arg(m_window && QRect(QPoint{}, m_window->size()).contains(scene))
                .arg(input != nullptr)
                .arg(input ? QStringLiteral("%1,%2 %3x%4")
                                 .arg(input->bounds().x())
                                 .arg(input->bounds().y())
                                 .arg(input->bounds().width())
                                 .arg(input->bounds().height())
                           : QStringLiteral("none"))
                .arg(input ? input->bounds().contains(input->mapFromScene(QPointF(scene))) : false)
                .arg(input && input->hasActiveFocus())
                .arg(input && m_window && automation_valueprompt::inputOwnsFocus(*m_window, *input))
                .arg(canvas->pencilMode())
                .arg(selectionkey::focusObjectIdentity(grabber))
                .arg(selectionkey::focusObjectIdentity(QApplication::activeModalWidget()))
                .arg(m_window && m_window->isVisible())
                .arg(m_window && m_window->isExposed());
    }
    return opened;
}

std::optional<QString> SelectionPageOwnershipTest::printableText(const QKeyCombination &binding)
{
    if (binding.keyboardModifiers() != Qt::NoModifier)
        return std::nullopt;
    const int key = int(binding.key());
    if (key >= int(Qt::Key_A) && key <= int(Qt::Key_Z))
        return QString(QChar::fromLatin1(char('a' + (key - int(Qt::Key_A)))));
    if (key >= int(Qt::Key_0) && key <= int(Qt::Key_9))
        return QString(QChar::fromLatin1(char('0' + (key - int(Qt::Key_0)))));
    return std::nullopt;
}

void SelectionPageOwnershipTest::trackPointer(const QPoint &position)
{
    m_heldButton = Qt::LeftButton;
    m_lastWindowPosition = position;
}

void SelectionPageOwnershipTest::trackRelease()
{
    m_heldButton = Qt::NoButton;
}

bool SelectionPageOwnershipTest::undoLiveTabs(QString &error) const
{
    if (!m_workspace)
        return true;
    for (SongTab *const tab : m_workspace->tabsInDisplayOrder()) {
        if (!tab)
            continue;
        if (!tab->isReady() && !selectionkey::waitForTabReady(*m_workspace, tab)) {
            error = QStringLiteral("the live %1 tab did not finish loading during cleanup")
                        .arg(tab->name().value());
            return false;
        }
        m_workspace->selectSongTab(tab);
        selectionkey::settle();
        QString cleanError;
        if (!selectionkey::undoTabToClean(
                tab->document(),
                QStringLiteral("the %1 tab stayed dirty during cleanup").arg(tab->name().value()),
                &cleanError)) {
            error = cleanError;
            return false;
        }
    }
    return true;
}

void SelectionPageOwnershipTest::init()
{
    m_heldButton = Qt::NoButton;
    m_lastWindowPosition = QPoint();
    m_settings = std::make_unique<selectionkey::SessionSettingsGuard>();
    m_clipboard = std::make_unique<clipcheck_support::ClipboardStateGuard>();

    QString error;
    QVERIFY2(selectionkey::openWindowSession(m_session, m_projectRoot, error),
             qUtf8Printable(error));
    m_workspace = m_session.workspace;
    QVERIFY2(m_workspace, "the production shell has no WorkspaceUi");
    m_host = selectionkey::workspaceQuickHost(m_session);
    QVERIFY2(m_host && m_host->container() && m_host->window(),
             "the production shell has no WorkspaceQuickHost child");
    m_window = m_host->window();
    QVERIFY2(activateShell(error), qUtf8Printable(error));
    QVERIFY2(QTest::qWaitFor(
                 [this] {
                     return m_host && m_host->window() == m_window.data() && m_host->container() &&
                            m_host->container()->isVisible() && m_window && m_window->isVisible() &&
                            m_window->isExposed();
                 },
                 30000),
             "the real shared WorkspaceQuickHost window never became exposed");

    SongTab *const tab = selectionkey::openSongTab(m_session, m_songA, false, error);
    QVERIFY2(tab, qUtf8Printable(error));
    m_tabA = tab;
    QVERIFY2(m_workspace->selectedSongTab() == tab && m_workspace->openTabCount() == 1,
             "opening A did not create the selected first production tab");
    const std::vector<SongTab *> tabs = m_workspace->tabsInDisplayOrder();
    QVERIFY2(tabs.size() == 1 && tabs.front() == tab,
             "the first production tab is not the sole display-order session");
    QVERIFY2(waitForReadyPage(*tab, error), qUtf8Printable(error));
}

void SelectionPageOwnershipTest::cleanup()
{
    bool released = true;
    if (m_window) {
        if (m_heldButton != Qt::NoButton) {
            QTest::mouseRelease(m_window, m_heldButton, Qt::NoModifier, m_lastWindowPosition);
            trackRelease();
            selectionkey::settle();
        }
        // A failed scenario can leave its QML value prompt active; cancel it
        // through the real window before undoing setup edits.
        QTest::keyClick(m_window, Qt::Key_Escape, Qt::NoModifier);
        selectionkey::settle();
        if (QQuickItem *const grabber = m_window->mouseGrabberItem())
            grabber->ungrabMouse();
        released =
            QTest::qWaitFor([this] { return m_window.isNull() || !m_window->mouseGrabberItem(); });
    }

    QString closeProblem;
    if (m_session.window && m_workspace) {
        if (!undoLiveTabs(closeProblem)) {
            // Keep closing the shell below; the terminal assertion retains the
            // exact cleanup failure after all resources have been released.
        }
        const bool cleanShell = m_workspace->projectState().state == ProjectOpenState::Ready &&
                                !m_workspace->selectedSongDirty() &&
                                !m_workspace->hasPendingSaveWork();
        {
            selectionkey::DeclineModalsWithin guard(
                QStringLiteral("closing the page-ownership window session"));
            QCloseEvent closeEvent;
            QApplication::sendEvent(m_session.window.get(), &closeEvent);
            if (closeProblem.isEmpty() && cleanShell && !closeEvent.isAccepted()) {
                closeProblem = QStringLiteral("the clean page-ownership session close was not "
                                              "accepted by the production shell");
            }
            m_session.window->close();
            selectionkey::settle();
        }
    }

    m_tabA.clear();
    m_tabB.clear();
    m_window.clear();
    m_host.clear();
    m_session.window.reset();
    m_session.workspace = nullptr;
    m_workspace = nullptr;
    m_clipboard.reset();
    m_settings.reset();
    QVERIFY2(released, "the shared Quick window kept a mouse grab across the case");
    QVERIFY2(closeProblem.isEmpty(), qUtf8Printable(closeProblem));
}

void SelectionPageOwnershipTest::selectedPageTogglesPencilInSharedWindow()
{
    SongTab *const tabA = m_tabA.data();
    QVERIFY2(tabA, "the first tab is missing");
    selectionkey::ScenarioRollback rollbackA(tabA->view(), tabA->document());

    QString diagnostics;
    SongTab *const tabB = openReadyB(diagnostics);
    QVERIFY2(tabB, qUtf8Printable(diagnostics));
    selectionkey::ScenarioRollback rollbackB(tabB->view(), tabB->document());
    const std::vector<SongTab *> tabs = m_workspace->tabsInDisplayOrder();
    QVERIFY2(tabs.size() == 2 && tabs[0] == tabA && tabs[1] == tabB,
             "opening B did not retain A and append B in authoritative display order");

    QVERIFY2(selectReadyPage(*tabA, diagnostics),
             qUtf8Printable(QStringLiteral("selecting A: %1").arg(diagnostics)));
    QVERIFY2(prepareAutomation(*tabA, diagnostics),
             qUtf8Printable(QStringLiteral("preparing A: %1").arg(diagnostics)));
    QVERIFY2(selectReadyPage(*tabB, diagnostics),
             qUtf8Printable(QStringLiteral("selecting B: %1").arg(diagnostics)));
    QVERIFY2(prepareAutomation(*tabB, diagnostics),
             qUtf8Printable(QStringLiteral("preparing B: %1").arg(diagnostics)));

    const DocumentState aBefore = documentState(tabA->document());
    const DocumentState bBefore = documentState(tabB->document());
    const auto pencil = selectionkey::firstBinding(QStringLiteral("automation.pencil_mode"));
    QVERIFY2(pencil.has_value() && pencil->key() != Qt::Key_unknown && pencil->key() != Qt::Key(0),
             "automation.pencil_mode has no usable single-key binding");
    AutomationCanvas *const canvasA = automationCanvas(*tabA);
    AutomationCanvas *const canvasB = automationCanvas(*tabB);
    QVERIFY2(canvasA && canvasB, "one production page is missing its automation canvas");

    QVERIFY2(selectReadyPage(*tabA, diagnostics),
             qUtf8Printable(QStringLiteral("returning to A: %1").arg(diagnostics)));
    QVERIFY2(stageFocus(*tabA, diagnostics),
             qUtf8Printable(QStringLiteral("staging A focus: %1").arg(diagnostics)));
    QVERIFY(!canvasA->pencilMode());
    QVERIFY(!canvasB->pencilMode());
    QVERIFY2(deliverPencilPress(*m_window, *pencil), "the A pencil delivery failed");
    QVERIFY(canvasA->pencilMode());
    QVERIFY(!canvasB->pencilMode());

    // B has its own persistent canvas in the same host window. Its real lane
    // click moves the focused subtree and makes B—not hidden A—the next key's
    // owner. A's mode remains its own per-page state.
    QVERIFY2(selectReadyPage(*tabB, diagnostics),
             qUtf8Printable(QStringLiteral("selecting B: %1").arg(diagnostics)));
    QVERIFY2(stageFocus(*tabB, diagnostics),
             qUtf8Printable(QStringLiteral("staging B focus: %1").arg(diagnostics)));
    QVERIFY2(deliverPencilPress(*m_window, *pencil), "the B pencil delivery failed");
    QVERIFY(canvasA->pencilMode());
    QVERIFY(canvasB->pencilMode());
    QVERIFY2(matchesDocumentState(tabA->document(), aBefore),
             "A's pencil shortcut mutated A's document or undo history");
    QVERIFY2(matchesDocumentState(tabB->document(), bBefore),
             "B's pencil shortcut mutated B's document or undo history");
}

void SelectionPageOwnershipTest::ineligiblePageCannotStealFromEligibleOne()
{
    SongTab *const tabA = m_tabA.data();
    QVERIFY2(tabA, "the first tab is missing");
    selectionkey::ScenarioRollback rollbackA(tabA->view(), tabA->document());

    QString diagnostics;
    QVERIFY2(selectReadyPage(*tabA, diagnostics),
             qUtf8Printable(QStringLiteral("selecting A: %1").arg(diagnostics)));
    QVERIFY2(prepareAutomation(*tabA, diagnostics),
             qUtf8Printable(QStringLiteral("preparing A: %1").arg(diagnostics)));
    QVERIFY2(stageFocus(*tabA, diagnostics),
             qUtf8Printable(QStringLiteral("staging A focus: %1").arg(diagnostics)));
    const DocumentState aBefore = documentState(tabA->document());
    const auto pencil = selectionkey::firstBinding(QStringLiteral("automation.pencil_mode"));
    QVERIFY2(pencil.has_value() && pencil->key() != Qt::Key_unknown && pencil->key() != Qt::Key(0),
             "automation.pencil_mode has no usable single-key binding");
    AutomationCanvas *const canvasA = automationCanvas(*tabA);
    QVERIFY2(canvasA, "A has no automation canvas");
    QVERIFY2(deliverPencilPress(*m_window, *pencil), "the A pencil delivery failed");
    QVERIFY(canvasA->pencilMode());
    // Stage A's real pointer-edit geometry BEFORE requesting B: the measured
    // unready-interval stroke below must not pump the event loop, so no probe,
    // wait, or settle may run between B's placement and A's release.
    QPoint aScene;
    QVERIFY2(locateEmptyLanePoint(*tabA, aScene, diagnostics),
             qUtf8Printable(QStringLiteral("staging A lane point: %1").arg(diagnostics)));
    const QPoint aDragEnd = aScene + QPoint(48, 0);

    // This is the real load interval: B is appended and selected by the
    // production placement policy, yet has no terminal VoicegroupBound. It
    // must decline the press rather than act through its disabled subtree or
    // fall back to the hidden A scene.
    SongTab *const tabB = openUnreadyB(diagnostics);
    QVERIFY2(tabB, qUtf8Printable(diagnostics));
    QVERIFY2(m_workspace->selectedSongTab() == tabB && tabA->isReady() && !tabB->isReady(),
             "the real ready-A/unready-B load state did not hold after B's placement request");
    songview::TimelineQuickView *const quickB = quick(*tabB);
    AutomationCanvas *const canvasB = automationCanvas(*tabB);
    QVERIFY2(quickB && quickB->quickWindow() == m_window.data() && !quickB->inputEligible() &&
                 canvasB,
             "fresh B was not attached as an unready page in the real shared host");
    deliverUnreadyPencilPress(*m_window, *pencil);
    QVERIFY(canvasA->pencilMode());
    QVERIFY(!canvasB->pencilMode());
    QVERIFY2(matchesDocumentState(tabA->document(), aBefore),
             "the unready B delivery mutated A's document or undo history");
    // Binding case: two live pages with B unready and inactive. Reselect A
    // synchronously — no settle, wait, or pump, so the GUI-thread loader
    // cannot publish B's terminal payload across the measured interval — then
    // drive A's real pencil stroke press/move/release through the shared
    // QQuickWindow. Each delivery is synchronous Qt/QML input; B must still be
    // unready at both ends while only A's document and undo history move.
    m_workspace->selectSongTab(tabA);
    songview::TimelineQuickView *const quickA = quick(*tabA);
    songview::TimelineInputItem *const inputA = automationInput(*tabA);
    QVERIFY2(m_workspace->selectedSongTab() == tabA && tabA->isReady() && !tabB->isReady(),
             "reselecting A did not leave A selected and ready with B still unready");
    QVERIFY2(quickA && quickA->quickWindow() == m_window.data() && quickA->inputEligible() &&
                 inputA && inputA->window() == m_window.data() && inputA->isVisible() &&
                 inputA->isEnabled() && !inputA->bounds().isEmpty() && canvasA->pencilMode(),
             "reselected A is not an eligible pencil surface while B loads");
    QVERIFY2(QRect(QPoint{}, m_window->size()).contains(aScene) &&
                 QRect(QPoint{}, m_window->size()).contains(aDragEnd) &&
                 inputA->bounds().contains(inputA->mapFromScene(QPointF(aScene))) &&
                 inputA->bounds().contains(inputA->mapFromScene(QPointF(aDragEnd))),
             "the staged A lane stroke left the eligible surface before delivery");
    QVERIFY2(!tabB->isReady(), "B finished loading before A's unready-interval stroke");
    const DocumentState aPreStroke = documentState(tabA->document());
    const DocumentState bPreStroke = documentState(tabB->document());
    sendSynchronousWindowMouse(*m_window, QEvent::MouseButtonPress, aScene, Qt::LeftButton,
                               Qt::LeftButton);
    trackPointer(aScene);
    sendSynchronousWindowMouse(*m_window, QEvent::MouseMove, aDragEnd, Qt::NoButton,
                               Qt::LeftButton);
    trackPointer(aDragEnd);
    sendSynchronousWindowMouse(*m_window, QEvent::MouseButtonRelease, aDragEnd, Qt::LeftButton,
                               Qt::NoButton);
    trackRelease();
    QVERIFY2(!tabB->isReady(), "B finished loading inside A's measured stroke interval");
    QVERIFY2(m_workspace->selectedSongTab() == tabA,
             "A's stroke moved selection while B was unready");
    QVERIFY2(tabA->document().smf().write() != aPreStroke.smf &&
                 tabA->document().undoStack()->index() == aPreStroke.undoIndex + 1,
             "A's real unready-interval stroke did not create exactly one A document undo entry");
    QVERIFY2(matchesDocumentState(tabB->document(), bPreStroke),
             "A's unready-interval stroke leaked into B's document or undo history");
    const DocumentState aAfterStroke = documentState(tabA->document());
    selectionkey::settle();

    QVERIFY2(selectionkey::waitForTabReady(*m_workspace, tabB),
             "B never reached ready state after its real load request");
    selectionkey::ScenarioRollback rollbackB(tabB->view(), tabB->document());
    QVERIFY2(selectReadyPage(*tabB, diagnostics),
             qUtf8Printable(QStringLiteral("selecting ready B: %1").arg(diagnostics)));
    QVERIFY2(prepareAutomation(*tabB, diagnostics),
             qUtf8Printable(QStringLiteral("preparing ready B: %1").arg(diagnostics)));
    const DocumentState bBefore = documentState(tabB->document());
    QVERIFY2(stageFocus(*tabB, diagnostics),
             qUtf8Printable(QStringLiteral("staging ready B focus: %1").arg(diagnostics)));
    QVERIFY2(deliverPencilPress(*m_window, *pencil), "the ready B pencil delivery failed");
    QVERIFY(canvasA->pencilMode());
    QVERIFY(canvasB->pencilMode());
    // Turn B's mode back off through its real shortcut before the pointer
    // sequence that opens a value prompt.
    QVERIFY2(deliverPencilPress(*m_window, *pencil), "the second B pencil delivery failed");
    QVERIFY(canvasA->pencilMode());
    QVERIFY(!canvasB->pencilMode());

    QPoint scene;
    QVERIFY2(openInsertionPrompt(*tabB, scene, diagnostics),
             qUtf8Printable(QStringLiteral("opening B value prompt: %1").arg(diagnostics)));
    DrawerChrome *const chromeB = drawerChrome(*tabB);
    QVERIFY2(chromeB, "B has no drawer chrome");
    QPointer<QQuickItem> prompt(automation_valueprompt::focusedTextInput(*m_window));
    QVERIFY2(prompt, "B's value prompt did not take text focus");
    QTest::keyClick(m_window, Qt::Key_4, Qt::NoModifier);
    QTest::keyClick(m_window, Qt::Key_Return, Qt::NoModifier);
    selectionkey::settle();
    QTRY_VERIFY2(!automation_valueprompt::promptVisible(*chromeB),
                 "Return did not commit B's real value prompt");
    QVERIFY2(tabB->document().smf().write() != bBefore.smf &&
                 tabB->document().undoStack()->index() == bBefore.undoIndex + 1,
             "the ready B prompt did not create exactly one B document undo entry");
    QVERIFY2(matchesDocumentState(tabA->document(), aAfterStroke),
             "B's eligible prompt commit leaked into A's document or undo history");
}

void SelectionPageOwnershipTest::valuePromptTextEntryStaysLocalToItsPage()
{
    SongTab *const tabA = m_tabA.data();
    QVERIFY2(tabA, "the first tab is missing");
    selectionkey::ScenarioRollback rollbackA(tabA->view(), tabA->document());

    QString diagnostics;
    SongTab *const tabB = openReadyB(diagnostics);
    QVERIFY2(tabB, qUtf8Printable(diagnostics));
    QVERIFY2(selectReadyPage(*tabA, diagnostics),
             qUtf8Printable(QStringLiteral("selecting A: %1").arg(diagnostics)));
    QVERIFY2(prepareAutomation(*tabA, diagnostics),
             qUtf8Printable(QStringLiteral("preparing A: %1").arg(diagnostics)));
    QVERIFY2(stageFocus(*tabA, diagnostics),
             qUtf8Printable(QStringLiteral("staging A focus: %1").arg(diagnostics)));
    const auto pencil = selectionkey::firstBinding(QStringLiteral("automation.pencil_mode"));
    QVERIFY2(pencil.has_value() && pencil->key() != Qt::Key_unknown && pencil->key() != Qt::Key(0),
             "automation.pencil_mode has no usable single-key binding");

    const DocumentState aBefore = documentState(tabA->document());
    const DocumentState bBefore = documentState(tabB->document());
    QPoint scene;
    QVERIFY2(openInsertionPrompt(*tabA, scene, diagnostics),
             qUtf8Printable(QStringLiteral("opening A value prompt: %1").arg(diagnostics)));
    DrawerChrome *const chromeA = drawerChrome(*tabA);
    DrawerChrome *const chromeB = drawerChrome(*tabB);
    QVERIFY2(chromeA && chromeB, "one production page is missing drawer chrome");
    QPointer<QQuickItem> prompt(automation_valueprompt::focusedTextInput(*m_window));
    QVERIFY2(prompt, "the value prompt did not take active text focus after the double click");
    QVERIFY(!automation_valueprompt::promptVisible(*chromeB));

    // The prompt opens with its plotted insertion value selected, so these
    // real key presses replace that selection rather than appending to it.
    QTest::keyClick(m_window, Qt::Key_1);
    QTest::keyClick(m_window, Qt::Key_2);
    selectionkey::settle();
    QVERIFY2(prompt && prompt->property("text").toString() == QStringLiteral("12"),
             "the delivered digits did not land in A's value prompt");
    QVERIFY(!automationCanvas(*tabA)->pencilMode());
    QVERIFY(!automationCanvas(*tabB)->pencilMode());

    // Text/IME gets the first refusal. A plain printable binding can become
    // prompt text only when its validator accepts it; no timeline page may
    // toggle pencil mode while the field owns active focus.
    QVERIFY(QMetaObject::invokeMethod(prompt, "selectAll"));
    QString expectedText = QStringLiteral("12");
    if (const std::optional<QString> pencilText = printableText(*pencil)) {
        QString candidate = *pencilText;
        int cursorPosition = candidate.size();
        const QVariant validatorValue = prompt->property("validator");
        QValidator *const validator = validatorValue.value<QValidator *>();
        if (!validator || validator->validate(candidate, cursorPosition) != QValidator::Invalid)
            expectedText = candidate;
    }
    QVERIFY2(deliverPencilPress(*m_window, *pencil), "the prompt pencil delivery failed");
    QVERIFY(!automationCanvas(*tabA)->pencilMode());
    QVERIFY(!automationCanvas(*tabB)->pencilMode());
    QVERIFY2(prompt && automation_valueprompt::promptVisible(*chromeA) &&
                 automation_valueprompt::focusedTextInput(*m_window) == prompt.data() &&
                 prompt->property("text").toString() == expectedText,
             "the pencil binding disturbed the focused value prompt");

    QVERIFY(QMetaObject::invokeMethod(prompt, "selectAll"));
    const QString copiedFrom = prompt->property("selectedText").toString();
    const QKeySequence copySequence(QKeySequence::Copy);
    QVERIFY2(copySequence.count() == 1, "the platform has no single-chord Copy sequence");
    QTest::keyClick(m_window, copySequence[0].key(), copySequence[0].keyboardModifiers());
    selectionkey::settle();
    QVERIFY2(!copiedFrom.isEmpty() && QApplication::clipboard()->text() == copiedFrom,
             "the prompt Copy chord did not copy its own selection");

    QVERIFY(QMetaObject::invokeMethod(prompt, "selectAll"));
    const QString undoBaseline = prompt ? prompt->property("text").toString() : QString();
    QTest::keyClick(m_window, Qt::Key_7);
    selectionkey::settle();
    QVERIFY2(prompt && prompt->property("text").toString() == QStringLiteral("7"),
             "the single keyboard edit did not land in the value prompt");
    const QKeySequence undoSequence(QKeySequence::Undo);
    QVERIFY2(undoSequence.count() == 1, "the platform has no single-chord Undo sequence");
    QTest::keyClick(m_window, undoSequence[0].key(), undoSequence[0].keyboardModifiers());
    selectionkey::settle();
    QVERIFY2(prompt && prompt->property("text").toString() == undoBaseline,
             "the native Undo chord did not revert the single text edit");

    QTest::keyClick(m_window, Qt::Key_Escape);
    QTRY_VERIFY2(!automation_valueprompt::promptVisible(*chromeA),
                 "Escape did not cancel A's value prompt");
    QVERIFY(!automation_valueprompt::promptVisible(*chromeB));
    QVERIFY2(matchesDocumentState(tabA->document(), aBefore),
             "the cancelled value prompt mutated A's document or undo history");
    QVERIFY2(matchesDocumentState(tabB->document(), bBefore),
             "A's prompt text entry leaked into B's document or undo history");
}

void SelectionPageOwnershipTest::outgoingGestureCancelsWithoutCommittingIntoSibling()
{
    SongTab *const tabA = m_tabA.data();
    QVERIFY2(tabA, "the first tab is missing");
    selectionkey::ScenarioRollback rollbackA(tabA->view(), tabA->document());

    QString diagnostics;
    SongTab *const tabB = openReadyB(diagnostics);
    QVERIFY2(tabB, qUtf8Printable(diagnostics));
    QVERIFY2(selectReadyPage(*tabA, diagnostics),
             qUtf8Printable(QStringLiteral("selecting A: %1").arg(diagnostics)));
    QVERIFY2(prepareAutomation(*tabA, diagnostics),
             qUtf8Printable(QStringLiteral("preparing A: %1").arg(diagnostics)));
    QVERIFY2(stageFocus(*tabA, diagnostics),
             qUtf8Printable(QStringLiteral("staging A focus: %1").arg(diagnostics)));
    const DocumentState aBefore = documentState(tabA->document());
    const DocumentState bBefore = documentState(tabB->document());

    // Selection loss cancels an actual prompt instead of letting the incoming
    // page inherit it. Neither document gains an undo entry.
    QPoint promptScene;
    QVERIFY2(openInsertionPrompt(*tabA, promptScene, diagnostics),
             qUtf8Printable(QStringLiteral("opening A prompt: %1").arg(diagnostics)));
    DrawerChrome *const chromeA = drawerChrome(*tabA);
    QVERIFY2(chromeA && automation_valueprompt::promptVisible(*chromeA),
             "A's value prompt was not visible before the outgoing selection");
    QVERIFY2(selectReadyPage(*tabB, diagnostics),
             qUtf8Printable(QStringLiteral("selecting B to cancel A prompt: %1").arg(diagnostics)));
    QTRY_VERIFY2(!automation_valueprompt::promptVisible(*chromeA),
                 "selecting B did not cancel A's outgoing value prompt");
    QVERIFY2(matchesDocumentState(tabA->document(), aBefore),
             "the cancelled outgoing prompt mutated A's document or undo history");
    QVERIFY2(matchesDocumentState(tabB->document(), bBefore),
             "A's cancelled prompt mutated B's document or undo history");

    QVERIFY2(selectReadyPage(*tabA, diagnostics),
             qUtf8Printable(QStringLiteral("returning to A for draft: %1").arg(diagnostics)));
    QVERIFY2(stageFocus(*tabA, diagnostics),
             qUtf8Printable(QStringLiteral("restaging A focus: %1").arg(diagnostics)));
    const auto pencil = selectionkey::firstBinding(QStringLiteral("automation.pencil_mode"));
    QVERIFY2(pencil.has_value() && pencil->key() != Qt::Key_unknown && pencil->key() != Qt::Key(0),
             "automation.pencil_mode has no usable single-key binding");
    QVERIFY2(deliverPencilPress(*m_window, *pencil), "the A pencil delivery failed");
    QVERIFY(automationCanvas(*tabA)->pencilMode());

    QPoint draftScene;
    QVERIFY2(locateEmptyLanePoint(*tabA, draftScene, diagnostics), qUtf8Printable(diagnostics));
    QTest::mousePress(m_window, Qt::LeftButton, Qt::NoModifier, draftScene);
    trackPointer(draftScene);
    const QPoint draftEnd = draftScene + QPoint(48, 0);
    QTest::mouseMove(m_window, draftEnd);
    trackPointer(draftEnd);
    selectionkey::settle();
    QTRY_VERIFY2(tabA->view().userGestureActive(), "the pencil press did not arm A's draft");

    QVERIFY2(selectReadyPage(*tabB, diagnostics),
             qUtf8Printable(QStringLiteral("selecting B to cancel A draft: %1").arg(diagnostics)));
    QTest::mouseRelease(m_window, Qt::LeftButton, Qt::NoModifier, draftEnd);
    trackRelease();
    QTRY_VERIFY2(!tabA->view().userGestureActive(),
                 "A's outgoing draft stayed active after selection moved to B");
    QVERIFY2(matchesDocumentState(tabA->document(), aBefore),
             "the cancelled A draft committed into A's document or undo history");
    QVERIFY2(matchesDocumentState(tabB->document(), bBefore),
             "the cancelled A draft committed into B's document or undo history");
    QVERIFY(!tabB->view().userGestureActive());

    QVERIFY2(
        selectReadyPage(*tabA, diagnostics),
        qUtf8Printable(QStringLiteral("returning to A for held audition: %1").arg(diagnostics)));
    songview::TimelineInputItem *const gutterA = rollGutterInput(*tabA);
    QVERIFY2(gutterA && gutterA->window() == m_window.data() && !gutterA->bounds().isEmpty(),
             "A's roll gutter is not a real input surface in the shared host");

    int heldKey = -1;
    int releasedKey = -1;
    int routedRelease = -1;
    int siblingAuditions = 0;
    const auto held = QObject::connect(&tabA->view(), &SongView::auditionNote, &tabA->view(),
                                       [&heldKey, &releasedKey](int, int key, int velocity) {
                                           if (velocity > 0)
                                               heldKey = key;
                                           else if (velocity == 0 && key == heldKey)
                                               releasedKey = key;
                                       });
    const auto routed =
        QObject::connect(m_workspace, &WorkspaceUi::auditionNoteRequested, m_workspace,
                         [&heldKey, &routedRelease](uint8_t, uint8_t key, uint8_t velocity) {
                             if (velocity == 0 && key == heldKey)
                                 routedRelease = key;
                         });
    const auto sibling =
        QObject::connect(&tabB->view(), &SongView::auditionNote, &tabB->view(),
                         [&siblingAuditions](int, int, int) { ++siblingAuditions; });
    QVERIFY2(held && routed && sibling, "the audition monitors did not connect");

    const QPoint keyScene = gutterA->mapToScene(gutterA->bounds().center()).toPoint();
    QTest::mousePress(m_window, Qt::LeftButton, Qt::NoModifier, keyScene);
    trackPointer(keyScene);
    selectionkey::settle();
    QTRY_VERIFY2(heldKey >= 0, "the held piano press did not audition through A");

    // WorkspaceUi deactivates A while it is still the selected authority.
    // Therefore the velocity-zero cancellation above remains routed through
    // WorkspaceUi instead of being filtered as a stale background request.
    QVERIFY2(selectReadyPage(*tabB, diagnostics),
             qUtf8Printable(QStringLiteral("selecting B to cancel audition: %1").arg(diagnostics)));
    QTRY_VERIFY2(releasedKey == heldKey && routedRelease == heldKey,
                 "selection loss did not emit and route A's audition note-off");
    QTest::mouseRelease(m_window, Qt::LeftButton, Qt::NoModifier, keyScene);
    trackRelease();
    selectionkey::settle();
    QVERIFY2(matchesDocumentState(tabA->document(), aBefore),
             "the audition selection handoff mutated A's document or undo history");
    QVERIFY2(matchesDocumentState(tabB->document(), bBefore),
             "the audition selection handoff mutated B's document or undo history");
    QCOMPARE(siblingAuditions, 0);
}

void SelectionPageOwnershipTest::releaseFromRemovedPageIsSwallowedBeforeNextPageClick()
{
    SongTab *const tabA = m_tabA.data();
    QVERIFY2(tabA, "the first tab is missing");

    QString diagnostics;
    SongTab *const tabB = openReadyB(diagnostics);
    QVERIFY2(tabB, qUtf8Printable(diagnostics));
    QVERIFY2(selectReadyPage(*tabA, diagnostics),
             qUtf8Printable(QStringLiteral("selecting A: %1").arg(diagnostics)));
    songview::TimelineInputItem *const gutterA = rollGutterInput(*tabA);
    QVERIFY2(gutterA && gutterA->window() == m_window.data() && !gutterA->bounds().isEmpty(),
             "A's roll gutter is not a real shared-window input surface");
    const DocumentState bBefore = documentState(tabB->document());

    int heldKey = -1;
    int routedRelease = -1;
    int bAuditions = 0;
    int bPresses = 0;
    const auto aMonitor = QObject::connect(&tabA->view(), &SongView::auditionNote, &tabA->view(),
                                           [&heldKey](int, int key, int velocity) {
                                               if (velocity > 0)
                                                   heldKey = key;
                                           });
    const auto routed =
        QObject::connect(m_workspace, &WorkspaceUi::auditionNoteRequested, m_workspace,
                         [&heldKey, &routedRelease](uint8_t, uint8_t key, uint8_t velocity) {
                             if (velocity == 0 && key == heldKey)
                                 routedRelease = key;
                         });
    const auto bMonitor = QObject::connect(&tabB->view(), &SongView::auditionNote, &tabB->view(),
                                           [&bAuditions, &bPresses](int, int, int velocity) {
                                               ++bAuditions;
                                               if (velocity > 0)
                                                   ++bPresses;
                                           });
    QVERIFY2(aMonitor && routed && bMonitor, "the held-page audition monitors did not connect");

    const QPoint staleReleasePoint = gutterA->mapToScene(gutterA->bounds().center()).toPoint();
    QTest::mousePress(m_window, Qt::LeftButton, Qt::NoModifier, staleReleasePoint);
    trackPointer(staleReleasePoint);
    selectionkey::settle();
    QTRY_VERIFY2(heldKey >= 0, "the held A press did not audition before closing A");

    // A is clean: this is the actual selected-page close path. It publishes
    // null/unloads audio, detaches A while the model/session are alive, then
    // selects B. The later physical release must not be delivered to B.
    {
        selectionkey::DeclineModalsWithin guard(
            QStringLiteral("closing A while its gutter press is held"));
        m_workspace->requestCloseSelectedTab();
    }
    QTRY_VERIFY2(m_tabA.isNull(), "the selected held A tab was not removed");
    QTRY_VERIFY2(m_workspace->selectedSongTab() == tabB && m_workspace->openTabCount() == 1,
                 "closing A did not leave B as the sole selected replacement tab");
    QTRY_VERIFY2(routedRelease == heldKey,
                 "closing the selected held page did not route its audition note-off");

    QTest::mouseRelease(m_window, Qt::LeftButton, Qt::NoModifier, staleReleasePoint);
    trackRelease();
    selectionkey::settle();
    QCOMPARE(bAuditions, 0);
    QVERIFY(!tabB->view().userGestureActive());
    QVERIFY2(matchesDocumentState(tabB->document(), bBefore),
             "the stale release from removed A mutated B's document or undo history");

    // A fresh B press/release proves the shared window no longer owns a stale
    // grab and its ordinary input pipeline resumed after the structural row
    // removal; it is intentionally the same real gutter control, not a
    // semantic audition call.
    QVERIFY2(selectReadyPage(*tabB, diagnostics),
             qUtf8Printable(QStringLiteral("settling replacement B: %1").arg(diagnostics)));
    songview::TimelineInputItem *const gutterB = rollGutterInput(*tabB);
    QVERIFY2(gutterB && gutterB->window() == m_window.data() && !gutterB->bounds().isEmpty(),
             "replacement B's roll gutter is not a real shared-window input surface");
    const QPoint bPoint = gutterB->mapToScene(gutterB->bounds().center()).toPoint();
    QTest::mouseClick(m_window, Qt::LeftButton, Qt::NoModifier, bPoint);
    selectionkey::settle();
    QVERIFY2(bPresses > 0, "a fresh B gutter click did not route after A's stale release");
    QVERIFY2(matchesDocumentState(tabB->document(), bBefore),
             "the fresh B gutter audition unexpectedly mutated B's document");
}

int runSelectionPageOwnershipTests(const QString &projectRoot, const QString &songA,
                                   const QString &songB, const QStringList &qtArguments)
{
    SelectionPageOwnershipTest test(projectRoot, songA, songB);
    QStringList arguments{QStringLiteral("selectionkey-pageownership")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "pageownership.moc"
