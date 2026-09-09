#pragma once

#include <QEvent>
#include <QHash>
#include <QObject>
#include <QPointer>
#include <QWidget>

class QQmlContext;
class QQuickItem;
class QQuickView;
class QQuickWindow;
class SongTab;
class SongTabsModel;

namespace songview {
class TimelineQuickView;
}

// The workspace Quick tab shell: the one permitted outer QWidget adapter for
// the migrated song tabs. Construction builds one alpha-capable QQuickView
// with its built-in engine, loads the WorkspaceSongs.qml root into it, and
// transfers that raw window exactly once to a NoFocus createWindowContainer —
// the host deliberately keeps no smart-pointer handle that could reclaim the
// window. The supplied QWidget parents the container, so the shell joins the
// owner's layout like any other widget; the host itself is a plain QObject
// beside the tab collection, parented to the same supplied QWidget.
//
// Sessions: the borrowed SongTabsModel stays the one collection and selection
// authority. The host projects each model row into a persistent page viewport
// item beneath the QML page slot (objectName songPageContainer) and attaches
// that session's TimelineQuickView coordinator to it, so every page keeps its
// coordinator-owned canvas for the page's whole lifetime. Pages are
// presentation state only — never a second session registry: rows insert a
// page, rows-about-to-be-remove detach and delete the page while the session
// is still live, and row moves change nothing (pages are keyed by session
// identity and only the selected page is visible, so order has no visual
// mapping). Selection changes hide and show existing pages and re-publish
// pageSelected eligibility; documents, timelines, and cameras never rebind.
//
// Input: the container accepts programmatic focus only (NoFocus). Pages share
// this one window, so their items gain active focus through the ordinary
// Quick focus chain and every session routes its keys through the shared
// QuickWindowInput owner for the window, whose selected scene the host keeps
// in lockstep with the model selection: on every publish the outgoing pages
// drop their flags first, the shared window input owner is pointed at the
// incoming scene (or nothing), and the incoming page is raised last — so the
// window's no-active-focus fallback never routes without the selected scene.
// The strip emits semantic requests only (selectRequested, closeRequested,
// moveRequested); the controller validates and applies every policy decision,
// because model selection is read-only. deactivateSelection() is the
// pre-publication seam: it cancels the outgoing page's live gestures and
// clears its input eligibility before the controller publishes audio and
// selection for the next session.
//
// Appearance: the strip chrome (fonts, metrics, theme roles) is resolved from
// the shared primitives and published to the QML context. The host watches
// the application for palette/font/style/theme changes — the same events the
// rest of the workspace reacts to — and re-resolves the chrome live, so an
// applied theme or font change restyles the strip without a restart.
//
// Teardown is one-way: the controller removes rows while their sessions live,
// so the host detaches and deletes every page inside the model bracket. It
// then destroys those sessions before releasing this host and its
// container-owned window/engine. The destructor defensively detaches any
// remaining page while its borrowed session is still live.
class WorkspaceQuickHost final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(WorkspaceQuickHost)

  public:
    // The host creates its QQuickView, loads the workspace QML, and transfers
    // it exactly once to the container. Existing model rows become pages
    // immediately; later inserts and removals are followed live.
    WorkspaceQuickHost(SongTabsModel &model, QWidget &parent);
    ~WorkspaceQuickHost() override;

    // The embedded-window container. Never null over the host's lifetime;
    // parent it into the supplied QWidget's layout.
    QWidget *container() const noexcept { return m_container; }

    // The Quick window the pages render into; null only after teardown.
    QQuickWindow *window() const noexcept;

    // Cancels the selected page's live gestures and clears its input
    // eligibility without touching the model. Call before switching the
    // selection or handing audio away, so the outgoing session never acts on
    // input that arrives during the publish.
    void deactivateSelection();

  public slots:
    // QML request seam: the strip calls these verbatim. Each emits the
    // matching signal; the controller validates and applies policy. Sessions
    // arrive as plain QObject pointers because QML only ever sees model
    // data; anything that is not a SongTab is reported and dropped here.
    void requestSelect(QObject *session);
    void requestClose(QObject *session);
    void requestMove(QObject *session, int destinationIndex);

    // The cyclic next/previous lookup behind the strip's standard keyboard
    // access: the session step rows away from row (wrapping in both
    // directions), or nullptr when the collection is empty. The returned
    // session stays owned by the C++ collection (explicit CppOwnership),
    // so the engine must never delete it.
    Q_INVOKABLE QObject *neighborSession(int row, int step) const;

  signals:
    void selectRequested(SongTab *session);
    void closeRequested(SongTab *session);
    void moveRequested(SongTab *session, int destinationIndex);

  protected:
    // Application-level palette, font, style, and theme change notifications
    // that drive the live chrome refresh.
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    struct Page final {
        // The page viewport item dies with the QML tree; the pointer guards
        // against a host outlived by its own window teardown.
        QPointer<QQuickItem> item;
        // The borrowed session coordinator; the session outlives the page
        // because removal detaches while the model's sessions are still live.
        songview::TimelineQuickView *quick = nullptr;
    };

    void attachRow(int row);
    void releaseRow(int row);
    void publishSelection();
    void fitPages();
    void refreshChrome();

    SongTabsModel &m_model;
    QQuickView *m_view = nullptr;
    QQmlContext *m_context = nullptr;
    QPointer<QQuickItem> m_pageContainer;
    QWidget *m_container = nullptr;
    QHash<SongTab *, Page> m_pages;
};
