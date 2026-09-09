// One window-owned input arbiter retains cancelled mouse releases across pages.

#include <QEvent>
#include <QObject>

class QQuickWindow;

namespace songview {

class QuickWindowInput final : public QObject
{
    Q_OBJECT

  public:
    // Returns the window-owned singleton.
    static QuickWindowInput &forWindow(QQuickWindow &window);

    // Consumes the next matching release after cancellation drops a grab.
    void swallowRelease(Qt::MouseButton button);

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    explicit QuickWindowInput(QQuickWindow &window);

    QQuickWindow *m_window = nullptr;
    // Outstanding swallowed releases, one slot per button. Only the press
    // currently grabbed arms a slot; delivering or discarding clears it.
    int m_swallowedReleaseButtons = 0;
};

} // namespace songview
