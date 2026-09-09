#pragma once
#include <QMetaObject>
#include <QObject>
#include <QPointF>
#include <QPointer>
#include <QRectF>
#include <QUrl>

#include <vector>

class QEvent;
class QQmlContext;
class QQuickItem;
class QQuickWindow;

namespace songview {

// Owns the one custom Quick popup surface for a timeline canvas. Menu adapters
// and typed form owners borrow this session; they never create a native window.
// Components are created in the page QQmlContext borrowed at construction, so
// popup QML resolves page-local state without touching the engine root context.
class QuickPopupSession final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(QuickPopupSession)

    Q_PROPERTY(bool isOpen READ isOpen NOTIFY isOpenChanged FINAL)

  public:
    explicit QuickPopupSession(QQuickWindow &window, QQmlContext &pageContext,
                               QObject *parent = nullptr);
    ~QuickPopupSession() override;

    bool isOpen() const;
    QQuickWindow *window() const;
    QQuickItem *overlayRoot() const;
    QQuickItem *contentItem() const;
    // The page root bounds the whole popup lifecycle: entry is refused and a
    // live popup cancels without focus restoration while the page is
    // disabled, hidden, detached, or clipped away, and popup geometry clamps
    // to the visible page rectangle so anything outside it (a shared tab
    // strip, a sibling page slot) stays usable.
    void setPageRoot(QQuickItem *pageRoot);
    // The actual visible page rectangle: the page root mapped into scene
    // space and intersected with every clipping ancestor and the window
    // bounds. Empty when the root is unset, detached, ineligible, or
    // clipped away entirely.
    QRectF pageRectInScene() const;
    // Scene-space union of all live popup content: the form container,
    // owner-governed surface content, and every active menu panel's frame.
    // Empty while closed; native occlusion consumes it together with
    // geometryChanged().
    QRectF contentRectInScene() const;
    // Guarded borrowed page context for owners that instantiate their own
    // QML under this session (menu panels); null once the context is gone.
    QQmlContext *creationContext() const;
    // Owners that move or retire their own content (menu panels) report it
    // here so geometryChanged() stays complete without the session
    // observing every panel.
    void notifyGeometryChanged();
    bool owns(const QObject *object) const;
    bool beginMenu(QObject *owner);
    // Loads a centered modal form. The QML root receives the bridge as its
    // required `bridge` property.
    bool openForm(const QUrl &url, QObject *bridge);
    // Loads owner-governed content into the shared overlay. The owner sets
    // its geometry and handles its outside input.
    bool openSurface(const QUrl &url, QObject *bridge);
    void close();
    void cancel(bool restoreFocus = true);

    Q_INVOKABLE void outsidePressed(int button, QPointF scenePos);

  signals:
    void isOpenChanged();
    void cancelled(bool restoreFocus);
    void closed();
    void outsideRightPressed(QObject *dismissedOwner, const QPointF &scenePos);
    // Emitted whenever contentRectInScene() may have moved, resized, or
    // changed emptiness: open, close, replace, form layout, page-rect drift,
    // and owner-reported panel changes.
    void geometryChanged();
    // Emitted when the visible page rectangle moves, resizes, or becomes
    // empty while a popup is open; owners re-clamp their panels to it.
    void pageBoundsChanged();

  public slots:
    // Recomputes the visible page bounds after any page or ancestor
    // geometry, mapping, or visibility change (TimelineQuickView forwards
    // viewportChanged here). Keeps a live popup contained: forms re-center
    // and menu owners re-clamp via pageBoundsChanged(); the popup cancels
    // without focus restoration when the visible page becomes empty.
    void handlePageGeometryChanged();

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    enum class Kind : quint8 {
        None,
        Menu,
        Form,
        Surface,
    };

    bool ensureLayer();
    bool openContent(const QUrl &url, QObject *bridge, Kind kind);
    void end(bool wasCancelled, bool restoreFocus);
    void layoutContent();
    void scheduleFocusCheck();
    void checkFocus();
    bool itemBelongsToPopup(const QQuickItem *item) const;
    bool pageEligible() const;
    void updateLayerPageRect();
    void handlePageEligibilityChanged();

    QPointer<QQuickWindow> m_window;
    QPointer<QQmlContext> m_pageContext;
    QPointer<QQuickItem> m_pageRoot;
    QPointer<QQuickItem> m_layer;
    QPointer<QQuickItem> m_formContainer;
    QPointer<QQuickItem> m_underlay;
    QPointer<QQuickItem> m_content;
    QPointer<QObject> m_owner;
    QPointer<QQuickItem> m_restoreFocus;
    QMetaObject::Connection m_ownerDestroyed;
    QMetaObject::Connection m_contentWidthChanged;
    QMetaObject::Connection m_contentHeightChanged;
    Kind m_kind = Kind::None;
    std::vector<QMetaObject::Connection> m_pageConnections;
    quint64 m_focusEpoch = 0;
    bool m_focusCheckPending = false;
    bool m_seenPopupFocus = false;
};

} // namespace songview
