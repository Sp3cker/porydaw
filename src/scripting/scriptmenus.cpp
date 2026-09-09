#include "scriptmenus.h"

#include <QAction>
#include <QJSEngine>
#include <QKeySequence>
#include <QMenu>
#include <QPainter>

#include <algorithm>

#include "scripthost.h"
#include "scriptwidgets.h"
#include "ui/keymap.h"
#include "ui/songview.h"

namespace scripting {

namespace {

constexpr int kPaintErrorHoldMs = 1000;

} // namespace

// ---- MenuItemHandle ----

MenuItemHandle::MenuItemHandle(ScriptHost &host, Plugin &plugin, const QVariantMap &spec,
                               const QJSValue &run, const QJSValue &shouldShow, QObject *parent)
    : QObject(parent)
    , m_host(host)
    , m_plugin(plugin)
    , m_action(new QAction(this))
    , m_label(spec.value(QStringLiteral("label")).toString())
    , m_commandId(spec.value(QStringLiteral("action")).toString())
    , m_run(run)
    , m_shouldShow(shouldShow.isCallable() ? shouldShow : QJSValue())
{
    // macOS's native menu bar relocates items whose text looks like
    // "Settings", "About …" or "Quit" into the application menu (Qt's
    // TextHeuristicRole default). A plugin's items belong where the
    // plugin put them, on every platform.
    m_action->setMenuRole(QAction::NoRole);
    m_action->setCheckable(spec.value(QStringLiteral("checkable")).toBool());
    if (m_action->isCheckable())
        m_action->setChecked(spec.value(QStringLiteral("checked")).toBool());
    m_action->setEnabled(spec.value(QStringLiteral("enabled"), true).toBool());
    const QString tip = spec.value(QStringLiteral("tooltip")).toString();
    if (!tip.isEmpty()) {
        m_action->setToolTip(tip);
        m_action->setStatusTip(tip);
    }
    refreshText();
    if (!m_commandId.isEmpty()) {
        auto &keys = keymap::Registry::instance();
        connect(&keys, &keymap::Registry::bindingsChanged, this, &MenuItemHandle::refreshText);
        connect(&keys, &keymap::Registry::commandsChanged, this, &MenuItemHandle::refreshText);
    }
    connect(m_action, &QAction::triggered, this, [this](bool checked) {
        if (m_settingValue)
            return;
        if (m_run.isCallable())
            m_host.invoke(m_plugin, m_run, {QJSValue(checked)});
        else if (!m_commandId.isEmpty())
            m_host.runCommand(m_commandId);
    });
}

void MenuItemHandle::refreshText()
{
    if (!m_action)
        return;
    QString text = m_label;
    if (!m_commandId.isEmpty()) {
        const QList<QKeySequence> bindings = keymap::Registry::instance().bindings(m_commandId);
        if (!bindings.isEmpty())
            text += QLatin1Char('\t') + bindings.first().toString(QKeySequence::NativeText);
    }
    m_action->setText(text);
}

void MenuItemHandle::setLabel(const QString &label)
{
    m_label = label;
    refreshText();
}

bool MenuItemHandle::enabled() const
{
    return m_action && m_action->isEnabled();
}

void MenuItemHandle::setEnabled(bool on)
{
    if (m_action)
        m_action->setEnabled(on);
}

bool MenuItemHandle::visible() const
{
    return m_action && m_visible;
}

void MenuItemHandle::setVisible(bool on)
{
    m_visible = on;
    if (m_action)
        m_action->setVisible(on);
}

bool MenuItemHandle::shouldShow()
{
    if (!m_action || !m_visible)
        return false;
    if (!m_shouldShow.isCallable())
        return true;
    // The call may unwind into a teardown that deletes this handle (a
    // predicate spinning a nested loop while a reload lands), or the
    // predicate may remove the item: nothing of `this` is read after it
    // without the guard.
    const QPointer<MenuItemHandle> self(this);
    const QJSValue verdict = m_host.invoke(m_plugin, m_shouldShow, {});
    if (!self || !self->m_action)
        return false;
    return verdict.isError() || verdict.isUndefined() || verdict.toBool();
}

bool MenuItemHandle::checked() const
{
    return m_action && m_action->isChecked();
}

void MenuItemHandle::setChecked(bool on)
{
    if (!m_action)
        return;
    m_settingValue = true;
    m_action->setChecked(on);
    m_settingValue = false;
}

void MenuItemHandle::remove()
{
    // The handle outlives its entry (a script may still hold it). The
    // action leaves its menus now but dies later: remove() may be running
    // from the action's own triggered handler, whose QMenu frames still
    // hold it.
    QAction *dying = m_action.data();
    m_action = nullptr;
    m_run = QJSValue();
    m_shouldShow = QJSValue();
    if (!dying)
        return;
    dying->setVisible(false);
    for (QWidget *w : dying->associatedWidgets())
        w->removeAction(dying);
    dying->deleteLater();
}

// ---- MenuHandle ----

MenuHandle::MenuHandle(ScriptHost &host, Plugin &plugin, QMenu *menu, QObject *parent)
    : QObject(parent)
    , m_host(host)
    , m_plugin(plugin)
    , m_menu(menu)
{
    if (menu)
        connect(menu, &QMenu::aboutToShow, this, &MenuHandle::refreshItems);
}

void MenuHandle::refreshItems()
{
    // Guarded copies: a predicate may remove its item or add another, and
    // its call may tear the plugin down, deleting this handle and every
    // item with it.
    const QPointer<MenuHandle> self(this);
    QList<QPointer<MenuItemHandle>> items;
    for (QObject *child : children()) {
        if (auto *item = qobject_cast<MenuItemHandle *>(child))
            items.append(item);
    }
    for (const QPointer<MenuItemHandle> &item : items) {
        if (!self)
            return;
        if (!item || !item->visible())
            continue;
        const bool show = item->shouldShow();
        if (!self || !item)
            return;
        if (QAction *action = item->action())
            action->setVisible(show);
    }
}

MenuHandle::MenuHandle(ScriptHost &host, Plugin &plugin, const QString &surface, QObject *parent)
    : QObject(parent)
    , m_host(host)
    , m_plugin(plugin)
    , m_surface(surface)
{}

MenuHandle::~MenuHandle()
{
    delete m_menu.data();
}

QString MenuHandle::label() const
{
    return m_menu ? m_menu->title() : m_surface;
}

void MenuHandle::setLabel(const QString &label)
{
    if (m_menu)
        m_menu->setTitle(label);
}

bool MenuHandle::enabled() const
{
    return m_menu ? m_menu->isEnabled() : m_enabled;
}

void MenuHandle::setEnabled(bool on)
{
    m_enabled = on;
    if (m_menu)
        m_menu->setEnabled(on);
    for (QObject *child : children()) {
        if (m_surface.isEmpty())
            break;
        if (auto *item = qobject_cast<MenuItemHandle *>(child))
            item->setEnabled(on);
    }
}

bool MenuHandle::visible() const
{
    return m_menu ? m_menu->menuAction()->isVisible() : m_visible;
}

void MenuHandle::setVisible(bool on)
{
    m_visible = on;
    if (m_menu)
        m_menu->menuAction()->setVisible(on);
    for (QObject *child : children()) {
        if (m_surface.isEmpty())
            break;
        if (auto *item = qobject_cast<MenuItemHandle *>(child))
            item->setVisible(on);
    }
}

QObject *MenuHandle::addItem(const QVariantMap &spec, const QJSValue &run,
                             const QJSValue &shouldShow)
{
    QJSEngine *e = m_plugin.engine.get();
    if (m_surface.isEmpty() && !m_menu) {
        if (e)
            e->throwError(QJSValue::TypeError,
                          QStringLiteral("menu.addItem: the menu was removed"));
        return nullptr;
    }
    const QString label = spec.value(QStringLiteral("label")).toString();
    if (label.trimmed().isEmpty()) {
        if (e)
            e->throwError(QJSValue::TypeError,
                          QStringLiteral("menu.addItem: an item needs a label"));
        return nullptr;
    }
    const QString commandId = spec.value(QStringLiteral("action")).toString();
    if (!commandId.isEmpty() && keymap::Registry::instance().command(commandId).id != commandId) {
        if (e)
            e->throwError(QJSValue::TypeError,
                          QStringLiteral("menu.addItem: no command '%1' is registered (use the "
                                         "id actions.register returned)")
                              .arg(commandId));
        return nullptr;
    }
    if (!run.isCallable() && commandId.isEmpty()) {
        if (e)
            e->throwError(QJSValue::TypeError,
                          QStringLiteral("menu.addItem: an item needs run() or an action"));
        return nullptr;
    }
    auto *item = new MenuItemHandle(m_host, m_plugin, spec, run, shouldShow, this);
    QJSEngine::setObjectOwnership(item, QJSEngine::CppOwnership);
    if (m_menu) {
        m_menu->addAction(item->action());
    } else {
        // Context items: the host appends live ones when the surface's
        // menu opens. Prune entries whose actions were removed.
        auto &items = m_plugin.contextItems;
        items.erase(std::remove_if(items.begin(), items.end(),
                                   [](const Plugin::ContextItem &c) {
                                       return c.item.isNull() || !c.item->action();
                                   }),
                    items.end());
        items.push_back({m_surface, item});
        if (!m_enabled)
            item->setEnabled(false);
        if (!m_visible)
            item->setVisible(false);
    }
    return item;
}

void MenuHandle::addSeparator()
{
    if (m_menu)
        m_menu->addSeparator();
    else if (QJSEngine *e = m_plugin.engine.get())
        e->throwError(QJSValue::TypeError,
                      QStringLiteral("menu.addSeparator: context menus take items only"));
}

QObject *MenuHandle::addMenu(const QString &label)
{
    QJSEngine *e = m_plugin.engine.get();
    if (!m_menu) {
        if (e)
            e->throwError(QJSValue::TypeError,
                          m_surface.isEmpty()
                              ? QStringLiteral("menu.addMenu: the menu was removed")
                              : QStringLiteral("menu.addMenu: context menus take items only"));
        return nullptr;
    }
    if (label.trimmed().isEmpty()) {
        if (e)
            e->throwError(QJSValue::TypeError,
                          QStringLiteral("menu.addMenu: a menu needs a label"));
        return nullptr;
    }
    QMenu *sub = m_menu->addMenu(label);
    sub->menuAction()->setMenuRole(QAction::NoRole); // see MenuItemHandle's ctor
    auto *handle = new MenuHandle(m_host, m_plugin, sub, this);
    QJSEngine::setObjectOwnership(handle, QJSEngine::CppOwnership);
    return handle;
}

void MenuHandle::clear()
{
    // Entries go, handles stay (dead): a script holding one can't dangle.
    // Deferred deletes throughout: clear() may run from one of these
    // entries' own triggered handler.
    const QList<QObject *> kids = children();
    for (QObject *child : kids) {
        if (auto *item = qobject_cast<MenuItemHandle *>(child)) {
            item->remove();
        } else if (auto *sub = qobject_cast<MenuHandle *>(child)) {
            sub->clear();
            QMenu *dying = sub->m_menu.data();
            sub->m_menu = nullptr;
            if (dying) {
                if (m_menu)
                    m_menu->removeAction(dying->menuAction());
                dying->deleteLater();
            }
        }
    }
    if (m_menu) {
        // Separators are the menu's own.
        for (QAction *action : m_menu->actions()) {
            if (action->isSeparator()) {
                m_menu->removeAction(action);
                action->deleteLater();
            }
        }
    }
}

// ---- OverlayView ----

void OverlayView::begin(SongView &view, const RollOverlayGeometry &geometry)
{
    m_geometry = &geometry;
    uint64_t from = 0, to = 0;
    view.visibleTickRange(&from, &to);
    m_from = double(from);
    m_to = double(to);
    m_keyHeight = view.keyHeight();
    m_pxPerBeat = view.pxPerBeat();
    m_track = view.selectedTrack();
}

void OverlayView::end()
{
    m_geometry = nullptr;
}

double OverlayView::width() const
{
    return m_geometry ? m_geometry->grid.width() : 0.0;
}

double OverlayView::height() const
{
    return m_geometry ? m_geometry->grid.height() : 0.0;
}

double OverlayView::x(double tick) const
{
    return m_geometry ? double(m_geometry->xForTick(tick) - m_geometry->grid.left()) : 0.0;
}

double OverlayView::tick(double x) const
{
    return m_geometry ? m_geometry->tickForX(qreal(x) + m_geometry->grid.left()) : 0.0;
}

double OverlayView::keyTop(int key) const
{
    return m_geometry ? double(m_geometry->keyTop(key) - m_geometry->grid.top()) : 0.0;
}

double OverlayView::keyBottom(int key) const
{
    return m_geometry ? double(m_geometry->keyBottom(key) - m_geometry->grid.top()) : 0.0;
}

int OverlayView::key(double y) const
{
    return m_geometry ? m_geometry->keyAtY(qreal(y) + m_geometry->grid.top()) : 0;
}

// ---- OverlayHandle ----

OverlayHandle::OverlayHandle(ScriptHost &host, Plugin &plugin, const QString &id,
                             const QJSValue &paint, QObject *parent)
    : QObject(parent)
    , m_host(host)
    , m_plugin(plugin)
    , m_id(id)
    , m_paint(paint)
    , m_g(new Painter(host, plugin, this))
    , m_view(new OverlayView(this))
{
    QJSEngine::setObjectOwnership(m_g, QJSEngine::CppOwnership);
    QJSEngine::setObjectOwnership(m_view, QJSEngine::CppOwnership);
    m_g->setOverlay(true);
}

void OverlayHandle::setVisible(bool on)
{
    if (m_visible == on)
        return;
    m_visible = on;
    m_host.invalidateOverlays();
}

void OverlayHandle::repaint()
{
    if (!m_removed)
        m_host.invalidateOverlays();
}

void OverlayHandle::remove()
{
    if (m_removed)
        return;
    m_removed = true;
    m_paint = QJSValue();
    auto &overlays = m_plugin.overlays;
    overlays.erase(std::remove_if(overlays.begin(), overlays.end(),
                                  [this](const QPointer<OverlayHandle> &o) {
                                      return o.isNull() || o == this;
                                  }),
                   overlays.end());
    m_host.invalidateOverlays();
}

void OverlayHandle::paint(QPainter &painter, SongView &view, const RollOverlayGeometry &geometry)
{
    if (m_painting || m_removed || !m_paint.isCallable() || m_plugin.state != PluginState::Loaded ||
        !m_plugin.engine)
        return;
    if (!m_errorHold.isForever() && !m_errorHold.hasExpired())
        return;
    if (m_gValue.isUndefined()) {
        m_gValue = m_plugin.engine->newQObject(m_g);
        m_viewValue = m_plugin.engine->newQObject(m_view);
    }
    m_painting = true;
    painter.save();
    painter.translate(geometry.grid.topLeft());
    painter.setRenderHint(QPainter::Antialiasing, true);
    painter.setRenderHint(QPainter::SmoothPixmapTransform, true);
    m_g->begin(&painter, geometry.grid.width(), geometry.grid.height(), geometry.dpr);
    m_view->begin(view, geometry);
    m_host.beginPaint();
    const QJSValue result = m_host.invoke(m_plugin, m_paint, {m_gValue, m_viewValue});
    m_host.endPaint();
    m_view->end();
    m_g->end();
    painter.restore();
    m_painting = false;
    m_paintCount++;
    if (result.isError()) {
        m_errorCount++;
        m_errorHold = QDeadlineTimer(kPaintErrorHoldMs);
    }
}

} // namespace scripting
