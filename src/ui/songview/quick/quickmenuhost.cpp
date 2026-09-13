#include "ui/songview/quick/quickengine.h"
#include "ui/songview/quick/quickmenumodel.h"
#include "ui/songview/quick/quickpopupsession.h"

#include "ui/songview/quick/quickmenulayout.h"
#include "ui/theme/themeruntime.h"

#include <QDebug>
#include <QFontMetrics>
#include <QGuiApplication>
#include <QKeyEvent>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlError>
#include <QQuickWindow>
#include <QUrl>
#include <QVariant>
#include <algorithm>
#include <chrono>

namespace songview {

namespace {

constexpr int kPanelZ = 1000000;
constexpr int kTypeAheadResetMs = 1000;

/// The level's own action-backed rows, deduplicated. Children are not walked:
/// each submenu level observes its own rows when it is pushed.
std::vector<QAction *> levelActionRows(const std::vector<QuickMenuItem> &items)
{
    std::vector<QAction *> actions;
    for (const QuickMenuItem &item : items) {
        if (!item.isActionBacked())
            continue;
        QAction *const action = item.action.data();
        if (action && std::find(actions.cbegin(), actions.cend(), action) == actions.cend())
            actions.push_back(action);
    }
    return actions;
}

int firstActivatableRow(const QuickMenuModel &model)
{
    for (int row = 0; row < model.rowCount(); ++row) {
        const QuickMenuItem *item = model.itemAt(row);
        if (item && !item->separator && item->enabled)
            return row;
    }
    return -1;
}

int lastActivatableRow(const QuickMenuModel &model)
{
    for (int row = model.rowCount() - 1; row >= 0; --row) {
        const QuickMenuItem *item = model.itemAt(row);
        if (item && !item->separator && item->enabled)
            return row;
    }
    return -1;
}

int findTypeAheadRow(const QuickMenuModel &model, const QString &prefix, int startRow)
{
    const int count = model.rowCount();
    if (count == 0)
        return -1;
    const int begin = startRow < 0 ? count - 1 : startRow;
    for (int offset = 1; offset <= count; ++offset) {
        const int row = (begin + offset) % count;
        const QuickMenuItem *item = model.itemAt(row);
        if (!item || item->separator || !item->enabled)
            continue;
        if (item->text.startsWith(prefix, Qt::CaseInsensitive))
            return row;
    }
    return -1;
}

} // namespace

QuickMenuHost::QuickMenuHost(QObject *parent) : QObject(parent)
{
    m_typeAheadReset.setSingleShot(true);
    m_typeAheadReset.setInterval(std::chrono::milliseconds(kTypeAheadResetMs));
    connect(&m_typeAheadReset, &QTimer::timeout, this, [this] { m_typeAhead.clear(); });

    // Defaults resolve the theme menu roles; owners may override keys wholesale.
    QVariantMap appearance;
    appearance.insert(QStringLiteral("font"), resolveMenuFont(m_appearance));
    appearance.insert(QStringLiteral("background"), themes::color(themes::Role::menu_background));
    appearance.insert(QStringLiteral("outline"), themes::color(themes::Role::menu_outline));
    appearance.insert(QStringLiteral("text"), themes::color(themes::Role::menu_text));
    appearance.insert(QStringLiteral("hoverBackground"),
                      themes::color(themes::Role::menu_item_hover_background));
    appearance.insert(QStringLiteral("hoverText"),
                      themes::color(themes::Role::menu_item_hover_text));
    appearance.insert(QStringLiteral("pressedBackground"),
                      themes::color(themes::Role::menu_item_pressed_background));
    appearance.insert(QStringLiteral("pressedText"),
                      themes::color(themes::Role::menu_item_pressed_text));
    appearance.insert(QStringLiteral("disabledText"), themes::color(themes::Role::disabled_text));
    appearance.insert(QStringLiteral("separator"), themes::color(themes::Role::menu_separator));
    m_appearance = std::move(appearance);
}

QuickMenuHost::~QuickMenuHost()
{
    if (m_sessionActive && m_popupSession)
        m_popupSession->cancel(false);
    teardown(false);
}

void QuickMenuHost::setPopupSession(QuickPopupSession *session)
{
    if (m_popupSession == session)
        return;
    if (m_sessionActive && m_popupSession)
        m_popupSession->cancel(false);
    if (m_popupSession)
        disconnect(m_popupSession, nullptr, this, nullptr);
    m_popupSession = session;
    if (m_popupSession) {
        connect(m_popupSession, &QuickPopupSession::cancelled, this,
                [this](bool) { handleSessionCancelled(); });
        connect(m_popupSession, &QuickPopupSession::closed, this,
                &QuickMenuHost::handleSessionClosed);
        connect(m_popupSession, &QuickPopupSession::outsideRightPressed, this,
                &QuickMenuHost::handleSessionOutsideRightPressed);
    }
    emit windowChanged();
}

void QuickMenuHost::setAppearance(QVariantMap appearance)
{
    if (appearance == m_appearance)
        return;
    m_appearance = std::move(appearance);
    emit appearanceChanged();
    relayoutRoot();
}

QuickMenuModel *QuickMenuHost::rootModel() const
{
    return m_levels.isEmpty() ? nullptr : m_levels.first().model.data();
}

QuickMenuModel *QuickMenuHost::currentModel() const
{
    return m_levels.isEmpty() ? nullptr : m_levels.last().model.data();
}

QQuickWindow *QuickMenuHost::window() const
{
    return m_popupSession ? m_popupSession->window() : nullptr;
}

void QuickMenuHost::open(QuickMenuModel *model, const QPointF &scenePos)
{
    if (!model || !m_popupSession || model->rowCount() == 0)
        return;
    if (!m_popupSession->beginMenu(this))
        return;

    m_sessionActive = true;
    m_waitingForClosed = false;
    m_anchor = scenePos;
    if (QQuickWindow *const popupWindow = window(); !m_filterInstalled && popupWindow) {
        popupWindow->installEventFilter(this);
        m_filterInstalled = true;
    }
    pushLevel(model, QRectF(scenePos, QSizeF(0, 0)), true);
    if (!isOpen()) {
        m_popupSession->close();
        return;
    }
    if (QQuickItem *const rootPanel = m_levels.first().panel)
        rootPanel->forceActiveFocus(Qt::PopupFocusReason);
    emit rootChanged();
    emit currentChanged();
    emit isOpenChanged();
}

void QuickMenuHost::close()
{
    if (m_sessionActive && m_popupSession)
        m_popupSession->close();
}

void QuickMenuHost::cancel()
{
    if (m_sessionActive && m_popupSession)
        m_popupSession->cancel();
}

void QuickMenuHost::hoverRow(QQuickItem *panel, int row)
{
    if (!panel || m_levels.isEmpty())
        return;
    popToLevel(panel);
    Level *level = currentLevel();
    if (!level || level->panel != panel || !level->model)
        return;
    const QuickMenuItem *item = level->model->itemAt(row);
    if (!item || item->separator || !item->enabled)
        return;
    if (level->highlightedRow != row)
        setHighlight(*level, row);
    if (item->hasSubmenu())
        openSubmenuForRow(row);
}

void QuickMenuHost::activateRow(QQuickItem *panel, int row)
{
    if (!panel || m_levels.isEmpty())
        return;
    popToLevel(panel);
    Level *level = currentLevel();
    if (!level || level->panel != panel || !level->model)
        return;
    const QuickMenuItem *item = level->model->itemAt(row);
    if (!item || item->separator || !item->enabled)
        return;
    if (item->isActionBacked()) {
        triggerActionBackedRow(item->action.data());
        return;
    }
    QuickMenuModel *const source = level->model.data();
    if (item->checkable && item->stayOpen) {
        source->setItemChecked(row, !item->checked);
        emit source->activated(item->id);
        return;
    }
    const int id = item->id;
    if (m_popupSession)
        m_popupSession->close(); // clear the session before owner command
    emit source->activated(id);
}

void QuickMenuHost::triggerActionBackedRow(QAction *action)
{
    const QPointer<QuickMenuHost> host{this};
    const QPointer<QAction> guard{action};
    const QPointer<QuickPopupSession> session{m_popupSession};
    if (!host || !guard || !session)
        return;
    // close() precedes trigger(): the handler may reenter open() for a new session.
    session->close();
    if (!host || !guard || !guard->isEnabled())
        return;
    guard->trigger();
    if (host && guard)
        emit actionActivated(guard.data());
}

bool QuickMenuHost::eventFilter(QObject *watched, QEvent *event)
{
    if (watched == window() && m_sessionActive && !m_levels.isEmpty()) {
        switch (event->type()) {
        case QEvent::KeyPress:
            handleKeyPress(static_cast<QKeyEvent *>(event));
            return true;
        case QEvent::KeyRelease:
            return true;
        default:
            break;
        }
    }
    return QObject::eventFilter(watched, event);
}

QQuickItem *QuickMenuHost::createPanel(QuickMenuModel *model, bool rootLevel,
                                       const MenuMetrics &layout)
{
    QQuickWindow *const popupWindow = window();
    QQuickItem *const overlay = m_popupSession ? m_popupSession->overlayRoot() : nullptr;
    QQmlEngine *const engine = quickEngine(popupWindow);
    if (!engine || !overlay) {
        qWarning("QuickMenuHost: menu session has no canvas overlay");
        return nullptr;
    }
    QQmlComponent component(engine,
                            QUrl(QStringLiteral("qrc:/qt/qml/Porydaw/Ui/QuickMenuPanel.qml")),
                            QQmlComponent::PreferSynchronous);
    if (component.isError()) {
        for (const QQmlError &error : component.errors())
            qWarning().noquote() << error.toString();
        return nullptr;
    }
    // Delegates must instantiate with the final row metrics: a panel created
    // at QML defaults collapses the list's contentHeight until the next
    // polish pass, so a click dispatched before polish never reaches a row.
    const QVariantMap initialProperties{
        {QStringLiteral("host"), QVariant::fromValue(this)},
        {QStringLiteral("menuModel"), QVariant::fromValue(model)},
        {QStringLiteral("appearance"), m_appearance},
        {QStringLiteral("rootLevel"), rootLevel},
        {QStringLiteral("rowHeight"), layout.rowHeight},
        {QStringLiteral("separatorHeight"), layout.separatorHeight},
        {QStringLiteral("checkX"), layout.checkX},
        {QStringLiteral("checkWidth"), layout.checkWidth},
        {QStringLiteral("textX"), layout.textX},
        {QStringLiteral("textRight"), layout.textRight},
        {QStringLiteral("shortcutRight"), layout.shortcutRight},
        {QStringLiteral("arrowRight"), layout.arrowRight},
        {QStringLiteral("arrowWidth"), layout.arrowWidth},
        {QStringLiteral("menuWidth"), layout.menuWidth},
        {QStringLiteral("menuHeight"), layout.menuHeight},
    };
    QObject *object =
        component.createWithInitialProperties(initialProperties, engine->rootContext());
    QQuickItem *panel = qobject_cast<QQuickItem *>(object);
    if (!panel) {
        qWarning("QuickMenuHost: QuickMenuPanel.qml did not produce an item");
        delete object;
        return nullptr;
    }
    panel->setParent(this);
    panel->setParentItem(overlay);
    panel->setZ(kPanelZ);
    connect(panel, &QObject::destroyed, this, [this, panel] {
        for (int index = m_levels.size() - 1; index >= 0; --index) {
            if (m_levels[index].panel == panel) {
                while (m_levels.size() > index)
                    popLevel(false);
                break;
            }
        }
        if (m_sessionActive && m_levels.isEmpty() && m_popupSession)
            m_popupSession->cancel(false);
    });
    return panel;
}

void QuickMenuHost::pushLevel(QuickMenuModel *model, const QRectF &anchor, bool rootLevel)
{
    QQuickWindow *const popupWindow = window();
    if (!popupWindow)
        return;
    const QFont font = resolveMenuFont(m_appearance);
    const QFontMetrics metrics(font);
    const MenuMetrics layout =
        measureMenu(*model, metrics, QSizeF(popupWindow->width(), popupWindow->height()));
    QQuickItem *const panel = createPanel(model, rootLevel, layout);
    if (!panel)
        return;
    Level level;
    level.model = model;
    level.panel = panel;
    m_levels.append(level);
    Level &stored = m_levels.last();
    stored.resetConnection = connect(model, &QAbstractItemModel::modelReset, this,
                                     [this, model] { handleLevelReset(model); });
    if (rootLevel) {
        stored.modelDestroyedConnection = connect(model, &QObject::destroyed, this, [this] {
            if (m_sessionActive && m_popupSession)
                m_popupSession->cancel(false);
        });
    }
    // Each level observes only its own action-backed rows: a changed or
    // destroyed action retires that level (the root retires the session, as
    // before) and never touches levels below it.
    const std::vector<QAction *> actions = levelActionRows(model->items());
    if (!actions.empty()) {
        const QPointer<QuickMenuModel> levelModel{model};
        const auto levelIndex = m_levels.size() - 1;
        const auto retireActionLevel = [this, levelModel, levelIndex] {
            if (!m_sessionActive || !levelModel || levelIndex >= m_levels.size() ||
                m_levels[levelIndex].model.data() != levelModel.data()) {
                return;
            }
            if (levelIndex == 0) {
                cancel();
                return;
            }
            while (m_levels.size() > levelIndex)
                popLevel();
        };
        stored.actionConnections.reserve(actions.size() * 2);
        for (QAction *const action : actions) {
            stored.actionConnections.push_back(
                connect(action, &QAction::changed, this, retireActionLevel));
            stored.actionConnections.push_back(
                connect(action, &QObject::destroyed, this, retireActionLevel));
        }
    }
    applyLevel(stored, layout, anchor, rootLevel);
    setHighlight(stored, -1);
}

void QuickMenuHost::popLevel(bool notifyState)
{
    if (m_levels.isEmpty())
        return;
    const Level level = m_levels.takeLast();
    QObject::disconnect(level.resetConnection);
    QObject::disconnect(level.modelDestroyedConnection);
    for (const QMetaObject::Connection &connection : level.actionConnections)
        QObject::disconnect(connection);
    if (level.panel) {
        level.panel->setParentItem(nullptr);
        level.panel->deleteLater();
    }
    if (notifyState)
        emit currentChanged();
}

void QuickMenuHost::popToLevel(QQuickItem *panel)
{
    while (m_levels.size() > 1 && m_levels.last().panel != panel)
        popLevel();
}

void QuickMenuHost::teardown(bool notifyState)
{
    m_typeAhead.clear();
    m_typeAheadReset.stop();
    while (!m_levels.isEmpty())
        popLevel(notifyState);
    if (m_filterInstalled) {
        if (QQuickWindow *const popupWindow = window())
            popupWindow->removeEventFilter(this);
        m_filterInstalled = false;
    }
}

void QuickMenuHost::handleSessionCancelled()
{
    if (!m_sessionActive)
        return;
    m_sessionActive = false;
    m_waitingForClosed = true;
    teardown(false);
    emit isOpenChanged();
    emit rootChanged();
    emit currentChanged();
    emit cancelled();
}

void QuickMenuHost::handleSessionClosed()
{
    if (!m_sessionActive && !m_waitingForClosed)
        return;
    const bool wasActive = m_sessionActive;
    m_sessionActive = false;
    m_waitingForClosed = false;

    teardown(false);
    if (wasActive) {
        emit isOpenChanged();
        emit rootChanged();
        emit currentChanged();
    }
    emit closed();
}

void QuickMenuHost::handleSessionOutsideRightPressed(QObject *dismissedOwner,
                                                     const QPointF &scenePos)
{
    // The session was already cancelled when this arrives. Only the owner of
    // the dismissed menu may retarget, and only while the canvas stayed
    // idle: a cancellation callback that already opened a new foreign
    // session wins, and this retarget must not displace it.
    if (dismissedOwner == this && m_popupSession && !m_popupSession->isOpen())
        emit outsideRightPressed(scenePos);
}

void QuickMenuHost::handleLevelReset(QuickMenuModel *model)
{
    int levelIndex = -1;
    for (int index = 0; index < m_levels.size(); ++index) {
        if (m_levels[index].model == model) {
            levelIndex = index;
            break;
        }
    }
    if (levelIndex < 0)
        return;
    // Submenu models are QObject children cleared by setItems(): any level
    // above the rebuilt one is dangling and falls back to the rebuilt level.
    while (m_levels.size() > levelIndex + 1)
        popLevel();
    Level &level = m_levels[levelIndex];
    if (!level.model)
        return;
    // Preserve navigation across the rebuild when the id still exists.
    const int restoredRow = level.model->rowForId(level.rememberedId);
    level.highlightedRow = restoredRow;
    layoutLevel(level,
                levelIndex == 0 ? QRectF(m_anchor, QSizeF(0, 0))
                                : rowSceneRect(m_levels[levelIndex - 1].panel,
                                               m_levels[levelIndex - 1].highlightedRow),
                levelIndex == 0);
    syncPanelHighlight(level);
}

void QuickMenuHost::layoutLevel(Level &level, const QRectF &anchor, bool rootLevel)
{
    QQuickWindow *const popupWindow = window();
    if (!popupWindow || !level.panel || !level.model)
        return;
    const QFont font = resolveMenuFont(m_appearance);
    const QFontMetrics metrics(font);
    const MenuMetrics layout =
        measureMenu(*level.model, metrics, QSizeF(popupWindow->width(), popupWindow->height()));
    applyLevel(level, layout, anchor, rootLevel);
}

void QuickMenuHost::applyLevel(Level &level, const MenuMetrics &layout, const QRectF &anchor,
                               bool rootLevel)
{
    QQuickItem *const panel = level.panel.data();
    QQuickWindow *const popupWindow = window();
    if (!panel || !popupWindow)
        return;
    panel->setProperty("rowHeight", layout.rowHeight);
    panel->setProperty("separatorHeight", layout.separatorHeight);
    panel->setProperty("checkX", layout.checkX);
    panel->setProperty("checkWidth", layout.checkWidth);
    panel->setProperty("textX", layout.textX);
    panel->setProperty("textRight", layout.textRight);
    panel->setProperty("shortcutRight", layout.shortcutRight);
    panel->setProperty("arrowRight", layout.arrowRight);
    panel->setProperty("arrowWidth", layout.arrowWidth);
    panel->setProperty("menuWidth", layout.menuWidth);
    panel->setProperty("menuHeight", layout.menuHeight);
    panel->setProperty("appearance", m_appearance);
    panel->setWidth(popupWindow->width());
    panel->setHeight(popupWindow->height());

    const qreal windowWidth = popupWindow->width();
    const qreal windowHeight = popupWindow->height();
    const qreal width = layout.menuWidth;
    const qreal height = layout.menuHeight;
    qreal x = 0;
    qreal y = 0;
    if (rootLevel) {
        x = anchor.x();
        y = anchor.y();
        if (y + height > windowHeight)
            y = anchor.y() - height;
        if (x + width > windowWidth)
            x = anchor.x() - width;
    } else {
        x = anchor.right();
        y = anchor.y();
        if (x + width > windowWidth)
            x = anchor.left() - width;
    }
    x = std::clamp(x, qreal(0.0), std::max<qreal>(0.0, windowWidth - width));
    y = std::clamp(y, qreal(0.0), std::max<qreal>(0.0, windowHeight - height));
    panel->setProperty("menuOrigin", QPointF(x, y));
}

void QuickMenuHost::relayoutRoot()
{
    if (m_levels.isEmpty() || !window())
        return;
    for (int index = 0; index < m_levels.size(); ++index) {
        Level &level = m_levels[index];
        if (!level.panel || !level.model)
            continue;
        const QRectF anchor = index == 0 ? QRectF(m_anchor, QSizeF(0, 0))
                                         : rowSceneRect(m_levels[index - 1].panel,
                                                        m_levels[index - 1].highlightedRow);
        layoutLevel(level, anchor, index == 0);
    }
}

void QuickMenuHost::setHighlight(Level &level, int row)
{
    level.highlightedRow = row;
    if (const QuickMenuItem *item = level.model ? level.model->itemAt(row) : nullptr)
        level.rememberedId = item->id;
    syncPanelHighlight(level);
}

void QuickMenuHost::syncPanelHighlight(Level &level)
{
    if (level.panel)
        level.panel->setProperty("highlightedRow", level.highlightedRow);
}

void QuickMenuHost::openSubmenuForRow(int row)
{
    Level *parent = currentLevel();
    if (!parent || !parent->model)
        return;
    const QuickMenuItem *item = parent->model->itemAt(row);
    if (!item || item->separator || !item->enabled || !item->hasSubmenu())
        return;
    if (parent->highlightedRow != row)
        setHighlight(*parent, row);
    QuickMenuModel *const child = parent->model->submenuForRow(row);
    if (!child)
        return;
    if (!m_levels.isEmpty() && m_levels.last().model == child)
        return; // already open for this row
    const QRectF anchor = rowSceneRect(parent->panel, row);
    pushLevel(child, anchor, false);
    if (!m_levels.isEmpty() && m_levels.last().model == child)
        setHighlight(m_levels.last(), firstActivatableRow(*child));
    emit currentChanged();
}

QRectF QuickMenuHost::rowSceneRect(QQuickItem *panel, int row) const
{
    if (!panel || row < 0)
        return {};
    QVariant result;
    if (!QMetaObject::invokeMethod(panel, "rowSceneRect", Q_RETURN_ARG(QVariant, result),
                                   Q_ARG(QVariant, row)))
        return {};
    return result.toRectF();
}

bool QuickMenuHost::moveSelection(int delta)
{
    Level *level = currentLevel();
    if (!level || !level->model)
        return false;
    QuickMenuModel *const model = level->model.data();
    const int count = model->rowCount();
    if (count == 0)
        return false;
    int row = level->highlightedRow;
    for (int step = 0; step < count; ++step) {
        if (row < 0) {
            row = delta > 0 ? 0 : count - 1;
        } else {
            row += delta;
            if (row < 0)
                row = count - 1;
            else if (row >= count)
                row = 0;
        }
        const QuickMenuItem *item = model->itemAt(row);
        if (item && !item->separator && item->enabled) {
            setHighlight(*level, row);
            return true;
        }
    }
    return false;
}

void QuickMenuHost::handleKeyPress(QKeyEvent *event)
{
    Level *level = currentLevel();
    if (!level)
        return;
    switch (event->key()) {
    case Qt::Key_Escape:
        cancel();
        return;
    case Qt::Key_Return:
    case Qt::Key_Enter:
    case Qt::Key_Select:
        activateRow(level->panel, level->highlightedRow);
        return;
    case Qt::Key_Up:
        moveSelection(-1);
        return;
    case Qt::Key_Down:
        moveSelection(1);
        return;
    case Qt::Key_Left:
        if (m_levels.size() > 1)
            popLevel();
        return;
    case Qt::Key_Right:
        if (level->highlightedRow >= 0)
            openSubmenuForRow(level->highlightedRow);
        return;
    case Qt::Key_Home:
        if (level->model)
            setHighlight(*level, firstActivatableRow(*level->model));
        return;
    case Qt::Key_End:
        if (level->model)
            setHighlight(*level, lastActivatableRow(*level->model));
        return;
    case Qt::Key_Tab:
    case Qt::Key_Backtab:
        return;
    default: {
        const Qt::KeyboardModifiers modifiers = event->modifiers();
        if (!event->text().isEmpty() &&
            (modifiers & (Qt::ControlModifier | Qt::AltModifier | Qt::MetaModifier)) == 0) {
            typeAhead(event->text());
        }
        return;
    }
    }
}

void QuickMenuHost::typeAhead(const QString &text)
{
    Level *level = currentLevel();
    if (!level || !level->model || level->model->rowCount() == 0)
        return;
    m_typeAhead += text;
    m_typeAheadReset.start();
    const int start = level->highlightedRow;
    int row = findTypeAheadRow(*level->model, m_typeAhead, start);
    if (row < 0 && m_typeAhead.size() > 1) {
        m_typeAhead = m_typeAhead.right(1);
        row = findTypeAheadRow(*level->model, m_typeAhead, start);
    }
    if (row >= 0)
        setHighlight(*level, row);
}

QuickMenuHost::Level *QuickMenuHost::currentLevel()
{
    return m_levels.isEmpty() ? nullptr : &m_levels.last();
}

} // namespace songview
