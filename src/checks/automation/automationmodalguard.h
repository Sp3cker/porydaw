#pragma once

#include <functional>
#include <utility>
#include <vector>

#include <QAction>
#include <QApplication>
#include <QElapsedTimer>
#include <QMenu>
#include <QPointer>
#include <QScopeGuard>
#include <QString>
#include <QTimer>
#include <QWidget>
#include <QtTest>

namespace automation_modal {

constexpr qint64 kModalWatchdogMs = 1000;

inline void closeBlockingWidgets()
{
    if (QWidget *const modal = QApplication::activeModalWidget())
        modal->close();
    for (QWidget *widget : QApplication::allWidgets()) {
        auto *const menu = qobject_cast<QMenu *>(widget);
        if (menu && menu->isVisible())
            menu->close();
    }
}

inline QMenu *openMenu()
{
    if (auto *const menu = qobject_cast<QMenu *>(QApplication::activePopupWidget()))
        return menu;
    if (auto *const menu = qobject_cast<QMenu *>(QApplication::activeModalWidget()))
        return menu;
    for (QWidget *widget : QApplication::allWidgets()) {
        auto *const menu = qobject_cast<QMenu *>(widget);
        if (menu && menu->isVisible())
            return menu;
    }
    return nullptr;
}

// mousePress() first delivers a hover move to the real QQuickWindow. A zero-delay
// one-shot can therefore run before the press opens its nested QMenu event loop.
// Keep polling in a test-owned scope and retain a watchdog so every failure exits
// the nested loop instead of consuming the harness-wide deadline.
class ModalInteractionGuard final
{
  public:
    ModalInteractionGuard(std::function<QWidget *()> locate,
                          std::function<void(QWidget &)> interact, QString &diagnostic,
                          QString timeoutDiagnostic, bool watchForNestedModal)
        : m_locate(std::move(locate))
        , m_interact(std::move(interact))
        , m_diagnostic(diagnostic)
        , m_timeoutDiagnostic(std::move(timeoutDiagnostic))
        , m_watchForNestedModal(watchForNestedModal)
    {
        QObject::connect(&m_timer, &QTimer::timeout, &m_timer, [this] { poll(); });
        m_elapsed.start();
        m_timer.start(1);
    }

    ~ModalInteractionGuard()
    {
        m_timer.stop();
        closeBlockingWidgets();
    }

    Q_DISABLE_COPY_MOVE(ModalInteractionGuard)

  private:
    void poll()
    {
        if (!m_interacted) {
            if (QWidget *const widget = m_locate()) {
                m_interacted = true;
                m_diagnostic.clear();
                const QPointer<QWidget> guardedWidget(widget);
                const auto closeWidget = qScopeGuard([guardedWidget] {
                    if (guardedWidget && guardedWidget->isVisible())
                        guardedWidget->close();
                });
                m_interact(*widget);
                if (!m_watchForNestedModal)
                    m_timer.stop();
                return;
            }
        }
        if (m_elapsed.elapsed() < kModalWatchdogMs)
            return;
        if (!m_interacted) {
            m_diagnostic = m_timeoutDiagnostic;
        } else if (QApplication::activeModalWidget()) {
            m_diagnostic =
                QStringLiteral("Menu action left a modal widget open; watchdog closed it");
        }
        closeBlockingWidgets();
        m_timer.stop();
    }

    std::function<QWidget *()> m_locate;
    std::function<void(QWidget &)> m_interact;
    QString &m_diagnostic;
    QString m_timeoutDiagnostic;
    QTimer m_timer;
    QElapsedTimer m_elapsed;
    bool m_watchForNestedModal = false;
    bool m_interacted = false;
};

struct MenuInteractionResult final {
    bool opened = false;
    QWidget *parentWidget = nullptr;
    bool actionFound = false;
    bool actionEnabled = false;
    bool actionClicked = false;
    int actionCount = 0;
    QString diagnostic = QStringLiteral("Context menu interaction did not observe a QMenu");
    std::vector<int> actionData;
};

inline QAction *findMenuAction(QMenu &menu, const QString &text)
{
    for (QAction *action : menu.actions()) {
        if (!action->isSeparator() && action->text() == text)
            return action;
    }
    return nullptr;
}

inline bool clickMenuAction(QMenu &menu, QAction *action)
{
    if (!action)
        return false;
    const QRect geometry = menu.actionGeometry(action);
    if (!geometry.isValid())
        return false;
    QTest::mouseClick(&menu, Qt::LeftButton, Qt::NoModifier, geometry.center());
    return true;
}

template <typename Interact>
ModalInteractionGuard schedulePopupInteraction(QString &diagnostic, Interact interact)
{
    return ModalInteractionGuard(
        [] { return static_cast<QWidget *>(openMenu()); },
        [interact = std::move(interact)](QWidget &widget) mutable {
            interact(static_cast<QMenu &>(widget));
        },
        diagnostic, QStringLiteral("Timed out waiting for QMenu; watchdog closed blocking widgets"),
        true);
}

template <typename Select>
ModalInteractionGuard scheduleMenuInteraction(MenuInteractionResult &result, Select select)
{
    result.diagnostic = QStringLiteral("Context menu interaction did not observe a QMenu");
    return schedulePopupInteraction(result.diagnostic, [&result, select = std::move(select)](
                                                           QMenu &menu) mutable {
        result.opened = true;
        result.parentWidget = menu.parentWidget();
        for (QAction *action : menu.actions()) {
            if (action->isSeparator())
                continue;
            ++result.actionCount;
            if (action->data().isValid())
                result.actionData.push_back(action->data().toInt());
        }
        QAction *const action = select(menu);
        result.actionFound = action != nullptr;
        result.actionEnabled = action && action->isEnabled();
        result.actionClicked = result.actionEnabled && clickMenuAction(menu, action);
        if (!result.actionFound) {
            result.diagnostic = QStringLiteral("Context menu opened without the selected action");
        } else if (!result.actionEnabled) {
            result.diagnostic = QStringLiteral("Selected context-menu action was disabled");
        } else if (!result.actionClicked) {
            result.diagnostic =
                QStringLiteral("Selected context-menu action had no clickable geometry");
        }
    });
}

} // namespace automation_modal
