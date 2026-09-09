#include "ui/workspacequick/workspacequickhost.h"

#include "ui/layout.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/quick/quickwindowinput.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"
#include "ui/workspacequick/songtabsmodel.h"

#include <QApplication>
#include <QFont>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickView>
#include <QQuickWindow>
#include <QSurfaceFormat>
#include <QUrl>
#include <QVariantMap>

#include <utility>

namespace {

// The strip's theme colors and layout metrics under the keys its QML reads,
// resolved once at view construction from the shared runtime primitives
// (typography, layout tokens, and the applied theme's tab roles).
QVariantMap workspaceChrome()
{
    const QFont font = typography::bodyFont().value_or(QApplication::font());
    QVariantMap chrome;
    chrome.insert(QStringLiteral("font"), font);
    chrome.insert(QStringLiteral("stripHeight"),
                  layout::chromeRowHeight(font, layout::space(layout::Space::Zero)));
    chrome.insert(QStringLiteral("spacing"), layout::space(layout::Space::Half));
    chrome.insert(QStringLiteral("paddingHorizontal"), layout::space(layout::Space::Two));
    chrome.insert(QStringLiteral("borderWidth"), layout::singlePixel());
    chrome.insert(QStringLiteral("radius"), layout::space(layout::Space::Half));
    chrome.insert(QStringLiteral("closeSize"), layout::space(layout::Space::Two));
    chrome.insert(QStringLiteral("minimumTabWidth"), layout::fontPx(8.0));
    // Match DragInput's scrub threshold so a press that becomes a tab drag
    // never reads as a click.
    chrome.insert(QStringLiteral("dragThreshold"), layout::fontPxF(1.0));
    chrome.insert(QStringLiteral("background"), themes::color(themes::Role::tab_pane_background));
    chrome.insert(QStringLiteral("tabBackground"), themes::color(themes::Role::tab_background));
    chrome.insert(QStringLiteral("tabText"), themes::color(themes::Role::tab_text));
    chrome.insert(QStringLiteral("tabHoverBackground"),
                  themes::color(themes::Role::tab_hover_background));
    chrome.insert(QStringLiteral("tabHoverText"), themes::color(themes::Role::tab_hover_text));
    chrome.insert(QStringLiteral("tabSelectedBackground"),
                  themes::color(themes::Role::tab_selected_background));
    chrome.insert(QStringLiteral("tabSelectedText"),
                  themes::color(themes::Role::tab_selected_text));
    chrome.insert(QStringLiteral("tabOutline"), themes::color(themes::Role::tab_outline));
    chrome.insert(QStringLiteral("focus"), themes::color(themes::Role::focus_outline));
    chrome.insert(QStringLiteral("disabledText"), themes::color(themes::Role::disabled_text));
    chrome.insert(QStringLiteral("tooltipBackground"),
                  themes::color(themes::Role::tooltip_background));
    chrome.insert(QStringLiteral("tooltipText"), themes::color(themes::Role::tooltip_text));
    chrome.insert(QStringLiteral("tooltipOutline"), themes::color(themes::Role::tooltip_outline));
    return chrome;
}

} // namespace

WorkspaceQuickHost::WorkspaceQuickHost(SongTabsModel &model, QWidget &parent)
    : QObject(&parent)
    , m_model(model)
{
    // Type registration must precede QQuickView construction because that
    // constructs the engine; the attached session canvases build into the
    // same engine later.
    songview::TimelineQuickView::registerQuickTypes();
    m_view = new QQuickView;
    QSurfaceFormat surfaceFormat = m_view->format();
    surfaceFormat.setAlphaBufferSize(8);
    m_view->setFormat(surfaceFormat);
    m_view->setColor(Qt::transparent);
    m_view->setResizeMode(QQuickView::SizeRootObjectToView);
    m_context = m_view->rootContext();
    QQmlContext *const context = m_context;
    context->setContextProperty(QStringLiteral("workspaceHost"), this);
    context->setContextProperty(QStringLiteral("workspaceTabs"), &m_model);
    context->setContextProperty(QStringLiteral("workspaceChrome"), workspaceChrome());
    m_view->setSource(QUrl(QStringLiteral("qrc:/qt/qml/Porydaw/Ui/WorkspaceSongs.qml")));
    if (m_view->status() == QQuickView::Error) {
        for (const QQmlError &error : m_view->errors())
            qWarning() << "WorkspaceQuickHost:" << error.toString();
    }
    m_pageContainer =
        m_view->rootObject()
            ? m_view->rootObject()->findChild<QQuickItem *>(QStringLiteral("songPageContainer"))
            : nullptr;
    if (!m_pageContainer)
        qWarning("WorkspaceQuickHost: WorkspaceSongs.qml has no songPageContainer");

    // The container takes the raw window exactly once and is its sole owner;
    // it accepts programmatic focus only and never joins the tab-focus chain.
    m_container = QWidget::createWindowContainer(m_view, &parent);
    m_container->setFocusPolicy(Qt::NoFocus);
    // Live appearance: the application-level change events below drive the
    // chrome refresh, exactly the notification surface the rest of the
    // workspace reacts to (SongView, PitchbendEditor).
    QCoreApplication::instance()->installEventFilter(this);

    if (m_pageContainer) {
        connect(m_pageContainer, &QQuickItem::widthChanged, this, &WorkspaceQuickHost::fitPages);
        connect(m_pageContainer, &QQuickItem::heightChanged, this, &WorkspaceQuickHost::fitPages);
    }
    connect(&m_model, &QAbstractItemModel::rowsInserted, this,
            [this](const QModelIndex &, int first, int last) {
                for (int row = first; row <= last; ++row)
                    attachRow(row);
            });
    connect(&m_model, &QAbstractItemModel::rowsAboutToBeRemoved, this,
            [this](const QModelIndex &, int first, int last) {
                for (int row = first; row <= last; ++row)
                    releaseRow(row);
            });
    connect(&m_model, &SongTabsModel::selectionChanged, this,
            &WorkspaceQuickHost::publishSelection);
    connect(&m_model, &SongTabsModel::selectedIndexChanged, this,
            &WorkspaceQuickHost::publishSelection);
    for (int row = 0; row < m_model.rowCount(); ++row)
        attachRow(row);
    publishSelection();
}

WorkspaceQuickHost::~WorkspaceQuickHost()
{
    // Detach every scene while the container-owned window is still valid so
    // windowAboutToDetach fires against a live window, then delete the
    // container, whose destruction takes the window and engine with it.
    for (const Page &page : std::as_const(m_pages)) {
        if (page.quick) {
            page.quick->setPageSelected(false);
            page.quick->detachScene();
        }
        if (page.item)
            delete page.item;
    }
    m_pages.clear();
    delete m_container;
    m_container = nullptr;
}

QQuickWindow *WorkspaceQuickHost::window() const noexcept
{
    return m_view;
}

void WorkspaceQuickHost::deactivateSelection()
{
    const auto it = m_pages.constFind(qobject_cast<SongTab *>(m_model.selectedSession()));
    if (it == m_pages.constEnd())
        return;
    // The outgoing page stops acting on input now: live pointer gestures
    // cancel and pageSelected clears, closing the eligibility seam before the
    // controller publishes audio and selection for the next session. The page
    // stays visible until the selection change itself hides it.
    it->quick->cancelActiveGestures();
    it->quick->setPageSelected(false);
}

void WorkspaceQuickHost::requestSelect(QObject *session)
{
    auto *tab = qobject_cast<SongTab *>(session);
    if (session && !tab) {
        qWarning("WorkspaceQuickHost: ignoring a select request for a non-session object");
        return;
    }
    emit selectRequested(tab);
}

void WorkspaceQuickHost::requestClose(QObject *session)
{
    auto *tab = qobject_cast<SongTab *>(session);
    if (session && !tab) {
        qWarning("WorkspaceQuickHost: ignoring a close request for a non-session object");
        return;
    }
    emit closeRequested(tab);
}

void WorkspaceQuickHost::requestMove(QObject *session, int destinationIndex)
{
    auto *tab = qobject_cast<SongTab *>(session);
    if (session && !tab) {
        qWarning("WorkspaceQuickHost: ignoring a move request for a non-session object");
        return;
    }
    emit moveRequested(tab, destinationIndex);
}

QObject *WorkspaceQuickHost::neighborSession(int row, int step) const
{
    const int count = m_model.rowCount();
    if (count == 0)
        return nullptr;
    const int neighbor = ((row + step) % count + count) % count;
    // CppOwnership is established once per session by SongTabsModel; a
    // lookup must not reassert it.
    return m_model.songAt(neighbor);
}

void WorkspaceQuickHost::attachRow(int row)
{
    SongTab *const session = m_model.songAt(row);
    if (!session || m_pages.contains(session) || !m_view || !m_pageContainer)
        return;
    auto *page = new QQuickItem(m_pageContainer);
    page->setSize(QSizeF(m_pageContainer->width(), m_pageContainer->height()));
    songview::TimelineQuickView *const quick = session->view().quickView();
    quick->attachScene(*m_view->engine(), *page);
    const bool isSelection = session == qobject_cast<SongTab *>(m_model.selectedSession());
    page->setVisible(isSelection);
    quick->setPageSelected(isSelection);
    // If the model already selects this session, the row arrived after the
    // selection publish: establish the window routing here, or the shared
    // owner would keep routing without the selected scene until the next
    // publish. Attaching a non-selected scene never touches routing.
    if (isSelection && m_view)
        songview::QuickWindowInput::forWindow(*m_view).setSelectedScene(quick);
    m_pages.insert(session, Page{page, quick});
}

void WorkspaceQuickHost::releaseRow(int row)
{
    SongTab *const session = m_model.songAt(row);
    if (!session)
        return;
    const auto it = m_pages.constFind(session);
    if (it == m_pages.constEnd())
        return;
    // Clear the eligibility flag first — its edge cancels this page's live
    // pointer, key, and popup transients — then detach while the session and
    // the container-owned window are both still alive; the canvas, popup
    // session, and scene context die inside detachScene, and the page
    // viewport goes with them. Detach clears only this scene's window-input
    // association; a sibling the model still selects keeps its selection.
    it->quick->setPageSelected(false);
    it->quick->detachScene();
    delete it->item;
    m_pages.erase(it);
}

void WorkspaceQuickHost::publishSelection()
{
    SongTab *const selected = qobject_cast<SongTab *>(m_model.selectedSession());
    const auto selectionPage = m_pages.constFind(selected);
    // Outgoing pages first: dropping the flag fires each one's eligibility
    // edge, which cancels its live pointer work, key transients, and popup
    // before anything is shown or rerouted. A hidden item would ungrab
    // whatever it was dragging, so stop the gesture before hiding.
    for (auto it = m_pages.constBegin(); it != m_pages.constEnd(); ++it) {
        if (it.key() == selected)
            continue;
        if (it->item && it->item->isVisible())
            it->quick->cancelActiveGestures();
        it->quick->setPageSelected(false);
        if (it->item)
            it->item->setVisible(false);
    }
    // The shared window input owner follows the model selection exactly:
    // per-page flags alone would leave its no-active-focus fallback routing
    // without — or worse, with a stale — selected scene.
    if (m_view) {
        songview::QuickWindowInput &windowInput = songview::QuickWindowInput::forWindow(*m_view);
        windowInput.setSelectedScene(selectionPage == m_pages.constEnd() ? nullptr
                                                                         : selectionPage->quick);
    }
    // The incoming page is raised last, after routing is already in place.
    if (selectionPage != m_pages.constEnd()) {
        if (selectionPage->item)
            selectionPage->item->setVisible(true);
        selectionPage->quick->setPageSelected(true);
    }
}

void WorkspaceQuickHost::fitPages()
{
    if (!m_pageContainer)
        return;
    const QSizeF size(m_pageContainer->width(), m_pageContainer->height());
    for (const Page &page : std::as_const(m_pages)) {
        if (page.item)
            page.item->setSize(size);
    }
}

bool WorkspaceQuickHost::eventFilter(QObject *watched, QEvent *event)
{
    if (watched == QCoreApplication::instance()) {
        switch (event->type()) {
        case QEvent::ApplicationPaletteChange:
        case QEvent::ApplicationFontChange:
        case QEvent::StyleChange:
        case QEvent::ThemeChange:
            refreshChrome();
            break;
        default:
            break;
        }
    }
    return QObject::eventFilter(watched, event);
}

void WorkspaceQuickHost::refreshChrome()
{
    if (!m_context)
        return;
    // Republishing the context property invalidates the strip's bindings on
    // it, so colors, fonts, and metrics re-resolve against the now-current
    // theme in place — no rebuild, no restart.
    m_context->setContextProperty(QStringLiteral("workspaceChrome"), workspaceChrome());
}
