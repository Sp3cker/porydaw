#pragma once

#include <QMetaObject>
#include <QObject>
#include <QPointF>
#include <QPointer>
#include <QUrl>

class QEvent;
class QQuickItem;
class QQuickWindow;

namespace songview {

// Owns the one custom Quick popup surface for a timeline canvas. Menu adapters
// and typed form owners borrow this session; they never create a native window.
class QuickPopupSession final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(QuickPopupSession)

    Q_PROPERTY(bool isOpen READ isOpen NOTIFY isOpenChanged FINAL)

  public:
    explicit QuickPopupSession(QQuickWindow &window, QObject *parent = nullptr);
    ~QuickPopupSession() override;

    bool isOpen() const;
    QQuickWindow *window() const;
    QQuickItem *overlayRoot() const;
    QQuickItem *contentItem() const;
    bool owns(const QObject *object) const;
    bool beginMenu(QObject *owner);
    bool openForm(const QUrl &url, QObject *bridge);
    void close();
    void cancel(bool restoreFocus = true);

    Q_INVOKABLE void outsidePressed(int button, QPointF scenePos);

  signals:
    void isOpenChanged();
    void cancelled(bool restoreFocus);
    void closed();
    void outsideRightPressed(const QPointF &scenePos);

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    enum class Kind : quint8 {
        None,
        Menu,
        Form,
    };

    bool ensureLayer();
    void end(bool wasCancelled, bool restoreFocus);
    void layoutContent();
    void scheduleFocusCheck();
    void checkFocus();
    bool itemBelongsToPopup(const QQuickItem *item) const;

    QPointer<QQuickWindow> m_window;
    QPointer<QQuickItem> m_layer;
    QPointer<QQuickItem> m_formContainer;
    QPointer<QQuickItem> m_content;
    QPointer<QObject> m_owner;
    QPointer<QQuickItem> m_restoreFocus;
    QMetaObject::Connection m_ownerDestroyed;
    QMetaObject::Connection m_contentWidthChanged;
    QMetaObject::Connection m_contentHeightChanged;
    Kind m_kind = Kind::None;
    Qt::MouseButton m_swallowedReleaseButton = Qt::NoButton;
    quint64 m_focusEpoch = 0;
    bool m_focusCheckPending = false;
    bool m_seenPopupFocus = false;
};

} // namespace songview
