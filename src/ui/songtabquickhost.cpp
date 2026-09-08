#include "ui/songtabquickhost.h"

#include "ui/songview/quick/timelinequickview.h"

#include <QQuickWindow>

#include <memory>

SongTabQuickHost::SongTabQuickHost(songview::TimelineQuickView &timelineQuickView, QWidget &parent)
    : QObject(&parent)
    , m_quick(timelineQuickView)
{
    // Exactly-once transfer: the container takes sole ownership of the
    // window and the host keeps no reclaiming handle. Container focus is
    // programmatic only (NoFocus), matching the TimelineInputHost bridge —
    // Quick items gain focus through the coordinator's request, never the
    // click/tab focus chain.
    std::unique_ptr<QQuickWindow> window = m_quick.takeWindowForEmbedding();
    m_container = QWidget::createWindowContainer(window.release(), &parent);
    m_container->setFocusPolicy(Qt::NoFocus);
    connect(&m_quick, &songview::TimelineQuickView::embeddingFocusRequested, this,
            [this](Qt::FocusReason reason) { m_container->setFocus(reason); });
}

SongTabQuickHost::~SongTabQuickHost()
{
    // One-way teardown: detach while the window is still valid so
    // windowAboutToDetach fires against a live window, then let the
    // container — sole owner of the window — destroy it. The Quick
    // coordinator's own destructor repeats detach as a safe no-op.
    m_quick.detachWindow();
    delete m_container;
    m_container = nullptr;
}
