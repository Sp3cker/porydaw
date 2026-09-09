// The single window-level input arbiter for Quick timeline pages: one
// instance per QQuickWindow (a QObject child of that window, obtained with
// forWindow()), owning exactly two cross-page concerns that no individual
// scene may own — the no-activeFocusItem song-key fallback and outstanding
// swallowed mouse releases. Hosts select the interactive scene explicitly;
// a scene's detach clears only that scene's association and never touches a
// sibling's selection. The instance lives until its window dies, surviving
// page removal so a later attach on the same window finds it again.

#include <QEvent>
#include <QObject>
#include <QPointer>

class QQuickWindow;
class QMouseEvent;
class QKeyEvent;

namespace songview {

class TimelineQuickView;

class QuickWindowInput final : public QObject
{
    Q_OBJECT

  public:
    // One arbiter per window, parented to it: repeated lookups return the
    // same instance, and window destruction destroys it. No global registry.
    static QuickWindowInput &forWindow(QQuickWindow &window);

    // The explicitly selected scene of this window. Hosts select after the
    // scene attaches; detaching clears only that scene's association.
    void setSelectedScene(TimelineQuickView *scene);
    [[nodiscard]] TimelineQuickView *selectedScene() const noexcept;

    // The scene's cancellation edge arms this before releasing a grabbed
    // pointer: the next release of the button on this window is consumed
    // once, before any item or scene sees it, so a cancelled grab cannot
    // deliver its release as a click. Unconsumed state clears with the
    // window's focus loss and on any dispatch.
    void swallowRelease(Qt::MouseButton button);

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    explicit QuickWindowInput(QQuickWindow &window);

    bool dispatchWindowKey(QKeyEvent &event);

    QQuickWindow *m_window = nullptr;
    QPointer<TimelineQuickView> m_selectedScene;
    // Outstanding swallowed releases, one slot per button. Only the press
    // currently grabbed arms a slot; delivering or discarding clears it.
    int m_swallowedReleaseButtons = 0;
};

} // namespace songview
