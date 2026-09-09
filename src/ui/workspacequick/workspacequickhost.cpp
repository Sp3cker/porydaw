#include "ui/workspacequick/workspacequickhost.h"

#include "ui/layout.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"
#include "ui/workspacequick/songtabsmodel.h"
#include "ui/workspaceui.h"

#include <QApplication>
#include <QFont>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickView>
#include <QQuickWindow>
#include <QSurfaceFormat>
#include <QUrl>
#include <QVariantMap>
#include <QWidget>

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
    return chrome;
}

} // namespace

WorkspaceQuickHost::WorkspaceQuickHost(SongTabsModel &model, WorkspaceUi &workspaceUi,
                                       QWidget &parent)
    : QObject(&parent)
    , m_model(model)
    , m_workspaceUi(workspaceUi)
{
    // Register types before QQuickView constructs its engine.
    songview::TimelineQuickView::registerQuickTypes();
    m_view = new QQuickView;
    QSurfaceFormat surfaceFormat = m_view->format();
    surfaceFormat.setAlphaBufferSize(8);
    m_view->setFormat(surfaceFormat);
    m_view->setColor(Qt::transparent);
    m_view->setResizeMode(QQuickView::SizeRootObjectToView);
    m_context = m_view->rootContext();
    QQmlContext *const context = m_context;
    context->setContextProperty(QStringLiteral("workspaceTabs"), &m_model);
    context->setContextProperty(QStringLiteral("workspaceUi"), &m_workspaceUi);
    context->setContextProperty(QStringLiteral("workspaceChrome"), workspaceChrome());
    m_view->setSource(QUrl(QStringLiteral("qrc:/qt/qml/Porydaw/Ui/WorkspaceSongs.qml")));
    if (m_view->status() == QQuickView::Error) {
        for (const QQmlError &error : m_view->errors())
            qWarning() << "WorkspaceQuickHost:" << error.toString();
    }
    m_rootItem = qobject_cast<QQuickItem *>(m_view->rootObject());
    if (!m_rootItem)
        qWarning("WorkspaceQuickHost: WorkspaceSongs.qml has no root item for focusEditor");

    // The StrongFocus container owns the window and outer focus entry.
    m_container = QWidget::createWindowContainer(m_view, &parent);
    m_container->setFocusPolicy(Qt::StrongFocus);
    // Application appearance changes refresh the published chrome.
    QCoreApplication::instance()->installEventFilter(this);
}

WorkspaceQuickHost::~WorkspaceQuickHost()
{
    // WorkspaceUi detaches and removes every page before host destruction.
    delete m_container;
    m_container = nullptr;
}

QQuickWindow *WorkspaceQuickHost::window() const noexcept
{
    return m_view;
}

void WorkspaceQuickHost::focusEditor(Qt::FocusReason reason)
{
    if (!m_container || !m_rootItem)
        return;
    m_container->setFocus(reason);
    QMetaObject::invokeMethod(m_rootItem.get(), "enterEditor",
                              Q_ARG(QVariant, QVariant::fromValue(static_cast<int>(reason))));
    m_view->requestActivate();
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
