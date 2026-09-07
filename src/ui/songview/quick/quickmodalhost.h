#pragma once

#include <QMetaObject>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QUrl>

class QEvent;
class QQuickItem;
class QQuickWindow;

namespace songview {

// Owns one native application-modal Quick window. Dialog-specific state and
// acceptance stay on the typed domain owner supplied as bridge; this class
// only realizes, replaces, and dismisses the native surface.
class QuickModalHost final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(QuickModalHost)

    Q_PROPERTY(bool open READ isOpen NOTIFY openChanged FINAL)

  public:
    explicit QuickModalHost(QQuickWindow &parentWindow, QObject *parent = nullptr);
    ~QuickModalHost() override;

    bool isOpen() const noexcept;
    QQuickWindow *modalWindow() const noexcept;
    bool open(const QUrl &contentQml, QObject *bridge, const QString &title);
    void cancel();
    void close();

  signals:
    void openChanged();
    // A cancellation is distinct from close(): the owner already applied its
    // typed result before asking the host to close.
    void cancelled();
    void closed();

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    void dismiss(bool cancelled);
    void resizeToContent();

    QPointer<QQuickWindow> m_parentWindow;
    QPointer<QQuickWindow> m_modalWindow;
    QPointer<QQuickItem> m_content;
    QPointer<QObject> m_bridge;
    QMetaObject::Connection m_bridgeDestroyed;
    bool m_dismissing = false;
};

} // namespace songview
