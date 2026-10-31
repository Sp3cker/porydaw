#pragma once

#include <QtCore/qobject.h>
#include <QtCore/qpointer.h>
#include <QtQml/qqmlregistration.h>
#include <QtQuick/qquickitem.h>

// The native codes of the key event its target is receiving, which QML's KeyEvent
// omits (macOS names the physical key only in nativeVirtualKey). The target's Keys
// handlers read them for the same event; nothing is forwarded or dispatched.
class NativeKeyCodes : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QQuickItem *target READ target WRITE setTarget NOTIFY targetChanged REQUIRED)

  public:
    explicit NativeKeyCodes(QObject *parent = nullptr);
    ~NativeKeyCodes() override;

    [[nodiscard]] QQuickItem *target() const { return m_target; }
    void setTarget(QQuickItem *target);

    // The last key press, release or shortcut override the target received.
    Q_INVOKABLE quint32 scanCode() const { return m_scanCode; }
    Q_INVOKABLE quint32 virtualKey() const { return m_virtualKey; }

  signals:
    void targetChanged();

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    QPointer<QQuickItem> m_target;
    quint32 m_scanCode = 0;
    quint32 m_virtualKey = 0;
};
