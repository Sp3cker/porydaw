#pragma once

#include <QObject>
#include <QWidget>

namespace songview {
class TimelineQuickView;
}

// External embedding host for the timeline Quick window: the only
// QWidget::createWindowContainer site in the production shell. Construction
// transfers the TimelineQuickView's window exactly once — the container
// widget created here sole-owns the QQuickWindow, and the host deliberately
// keeps no smart-pointer handle that could reclaim it. The supplied QWidget
// parents the container, so the embedding joins the owner's layout like any
// other widget; the host itself is a plain QObject beside SongTab, parented
// to the same supplied QWidget.
//
// Focus stays a Quick-driven bridge: the coordinator signals
// embeddingFocusRequested with the original focus reason and the host puts
// that focus on the container, preserving the TimelineInputHost focus path
// without a focus-memory framework.
//
// Teardown is one-way: destroying the host detaches the Quick view while
// its window is still valid, then deletes the container, whose destruction
// takes the unbound window with it. SongTab deletes the host before the
// SongView coordinator and the document members for exactly that ordering;
// the coordinator's own destructor repeats detach as a safe no-op.
class SongTabQuickHost final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(SongTabQuickHost)

  public:
    // The Quick view must still own its unhosted window: the transfer is
    // the embedding's single ownership handoff and cannot be repeated.
    SongTabQuickHost(songview::TimelineQuickView &timelineQuickView, QWidget &parent);
    ~SongTabQuickHost() override;

    // The embedded-window container. Never null over the host's lifetime;
    // parent it into the supplied QWidget's layout.
    QWidget *container() const noexcept { return m_container; }

  private:
    songview::TimelineQuickView &m_quick;
    QWidget *m_container = nullptr;
};
