#include "pitchbendeditor.hpp"

#include "songview.h"
#include "ui/keymap.h"
#include "ui/songview/quick/timelinequickview.h"

#include <QApplication>
#include <QDebug>
#include <QEvent>
#include <QKeyEvent>
#include <QKeySequence>
#include <QMetaObject>
#include <QMouseEvent>
#include <QQmlEngine>
#include <QQmlError>
#include <QQuickItem>
#include <QQuickView>
#include <QRect>
#include <QWindow>
#include <algorithm>
#include <mutex>
#include <utility>

namespace songview {

constexpr int kHostInset = 8;
constexpr int kNoteGap = 8;

QPoint hostClippedPopupPosition(const QRect &noteHost, const QRect &hostRect,
                                const QSize &popupSize)
{
    const QRect available = hostRect.adjusted(kHostInset, kHostInset, -kHostInset, -kHostInset);
    QPoint popupPos(noteHost.center().x() - popupSize.width() / 2,
                    noteHost.bottom() + 1 + kNoteGap);
    const int maxX = std::max(available.left(), available.right() - popupSize.width() + 1);
    const int maxY = std::max(available.top(), available.bottom() - popupSize.height() + 1);
    popupPos.setX(std::clamp(popupPos.x(), available.left(), maxX));
    if (popupPos.y() + popupSize.height() > available.bottom() + 1)
        popupPos.setY(noteHost.top() - kNoteGap - popupSize.height());
    popupPos.setY(std::clamp(popupPos.y(), available.top(), maxY));
    return popupPos;
}

// The QML module is loaded by several independent engines across bands and
// tabs; registering the graph type here follows the timeline view's
// std::call_once convention and is visible to engines created afterwards.
void registerPitchBendGraphOnce()
{
    static std::once_flag registered;
    std::call_once(registered, [] {
        qmlRegisterType<songview::PitchBendGraph>("Porydaw.Ui", 1, 0, "PitchBendGraph");
    });
}

// Popup native window. Arbitration is two-phase: ShortcutOverride and
// document undo are resolved at the view level before Quick delivery, then
// unclaimed keys fall back out of child-first delivery into the session's
// Escape/solo/absorb logic. Nothing propagates to the roll.
class PitchBendPopupView final : public QQuickView
{
  public:
    explicit PitchBendPopupView(songview::PitchBendEditor *session)
        : QQuickView()
        , m_session(session)
    {}

  protected:
    bool event(QEvent *event) override
    {
        switch (event->type()) {
        case QEvent::ShortcutOverride: {
            auto *keyEvent = static_cast<QKeyEvent *>(event);
            if (keyEvent->matches(QKeySequence::Undo) ||
                keymap::Registry::instance().matches(keyEvent,
                                                     QStringLiteral("transport.play_pause"))) {
                event->accept();
                return true;
            }
            break;
        }
        case QEvent::KeyPress: {
            // Pre-delivery: document undo wins before a focused TextInput can
            // turn the chord into a local text undo.
            auto *keyEvent = static_cast<QKeyEvent *>(event);
            if (keyEvent->matches(QKeySequence::Undo)) {
                if (m_session)
                    m_session->undoFromKeyboard();
                event->accept();
                return true;
            }
            break;
        }
        default:
            break;
        }
        return QQuickView::event(event);
    }

    void keyPressEvent(QKeyEvent *event) override
    {
        QQuickView::keyPressEvent(event);
        if (event->isAccepted())
            return;
        if (event->key() == Qt::Key_Escape) {
            if (m_session)
                m_session->requestCancelClose();
            event->accept();
            return;
        }
        if (m_session && m_session->handleUnclaimedKeyPress(event)) {
            event->accept();
            return;
        }
        event->accept();
    }

    void keyReleaseEvent(QKeyEvent *event) override
    {
        QQuickView::keyReleaseEvent(event);
        // Keep releases paired with their absorbed presses.
        event->accept();
    }

  private:
    QPointer<songview::PitchBendEditor> m_session;
};

// Application-wide outside-click classification for the open popup.
class PitchBendCloseController final : public QObject
{
  public:
    PitchBendCloseController(songview::PitchBendEditor *session,
                             std::function<bool(QPointF)> focusNoteUnderCursor)
        : QObject(session)
        , m_session(session)
        , m_focusNoteUnderCursor(std::move(focusNoteUnderCursor))
    {
        qApp->installEventFilter(this);
    }

    ~PitchBendCloseController() override { qApp->removeEventFilter(this); }

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (!m_session || !m_session->isOpen())
            return false;
        if (event->type() == QEvent::MouseButtonPress) {
            auto *mouseEvent = static_cast<QMouseEvent *>(event);
            // Inside classification: our own popup window and any Quick item
            // it delivers to. Window-system delivery may observe the press on
            // our native window before item delivery, so both shapes count as
            // inside; every other surface keeps the dismissal path below.
            if (auto *window = qobject_cast<QWindow *>(watched);
                window != nullptr && window == m_session->view())
                return false;
            if (auto *item = qobject_cast<QQuickItem *>(watched);
                item != nullptr && item->window() != nullptr && item->window() == m_session->view())
                return false;
            if (m_focusNoteUnderCursor && m_focusNoteUnderCursor(mouseEvent->globalPosition())) {
                // Target note click: restore-focus dismissal, press consumed
                // exactly once.
                m_session->dismissWithCommit(true);
                event->accept();
                return true;
            }
            // Other outside UI dismisses (commit path, no focus restore) and
            // still receives this click.
            m_session->dismissWithCommit(false);
            return false;
        }
        if (event->type() == QEvent::ApplicationDeactivate) {
            if (m_session && m_session->isOpen())
                m_session->dismissWithCommit(false);
            return false;
        }
        if (event->type() == QEvent::ApplicationPaletteChange ||
            event->type() == QEvent::ApplicationFontChange) {
            if (m_session && m_session->isOpen())
                m_session->refreshChrome();
            return false;
        }
        return false;
    }

  private:
    QPointer<songview::PitchBendEditor> m_session;
    std::function<bool(QPointF)> m_focusNoteUnderCursor;
};
} // namespace songview

namespace songview {

PitchBendEditor::~PitchBendEditor()
{
    // Owner/tab teardown cancels unsettled work and never restores focus.
    finalize(DismissAction::Cancel, CloseFocus::Discard, /*deferTeardown=*/false);
    // A prior close may have queued deletion without an event-loop turn.
    // Keep the window/root/engine inside the lifetime of this session.
    delete m_view.data();
}

void PitchBendEditor::cancelAndClose()
{
    close(DismissAction::Cancel, CloseFocus::Restore);
}

void PitchBendEditor::cancelAndCloseWithoutFocus()
{
    close(DismissAction::Cancel, CloseFocus::Discard);
}

// Top-level window hosting the timeline Quick surface: the Quick window
// itself when unhosted, otherwise its top-level ancestor when the window is
// embedded in a container. Popup framing and transient parenthood resolve
// against it; a null result means no Quick surface to frame against.
QWindow *quickTopLevelWindow(::SongView *songView)
{
    if (!songView || !songView->quickView())
        return nullptr;
    QQuickWindow *quick = songView->quickView()->quickWindow();
    if (!quick)
        return nullptr;
    QWindow *topLevel = quick;
    while (topLevel->parent())
        topLevel = topLevel->parent();
    return topLevel;
}

void PitchBendEditor::openAt(const QRect &noteGlobal, double noteFraction)
{
    if (!isOpen() || !ensureView())
        return;
    QWindow *host = quickTopLevelWindow(m_songView);
    if (!host) {
        close(DismissAction::Cancel, CloseFocus::Discard);
        return;
    }
    const double fraction = noteFraction >= 0.0 && noteFraction <= 1.0 ? noteFraction : 0.5;
    if (m_pitchGraph)
        m_pitchGraph->setKeyboardFraction(fraction);
    if (m_modGraph)
        m_modGraph->setKeyboardFraction(fraction);
    const QRect noteHost(host->mapFromGlobal(noteGlobal.topLeft()),
                         host->mapFromGlobal(noteGlobal.bottomRight()));
    const QPoint popupPos =
        hostClippedPopupPosition(noteHost, QRect(QPoint(0, 0), host->size()), m_geometry.popupSize);
    // Fixed global placement after opening; no follow-note behavior.
    m_view->setPosition(host->mapToGlobal(popupPos));
    m_view->show();
    m_view->raise();
    m_view->requestActivate();
    if (m_pitchGraph)
        m_pitchGraph->forceActiveFocus(Qt::PopupFocusReason);
}

bool PitchBendEditor::ensureView()
{
    if (m_view)
        return true;
    registerPitchBendGraphOnce();

    auto *view = new PitchBendPopupView(this);
    view->setFlags(Qt::Tool | Qt::FramelessWindowHint);
    if (QWindow *topLevel = quickTopLevelWindow(m_songView))
        view->setTransientParent(topLevel);
    view->setResizeMode(QQuickView::SizeRootObjectToView);
    view->setColor(m_appearance.value(QStringLiteral("windowBackground")).value<QColor>());
    view->resize(m_geometry.popupSize);
    // The session must exist before the document loads its required property.
    view->setInitialProperties({{QStringLiteral("session"), QVariant::fromValue(this)}});
    view->setSource(QUrl(QStringLiteral("qrc:/qt/qml/Porydaw/Ui/PitchBendPopup.qml")));
    if (view->status() != QQuickView::Ready) {
        const auto errors = view->errors();
        if (errors.isEmpty())
            qCritical("Qt Quick pitch-bend popup QML did not become ready");
        for (const QQmlError &error : errors)
            qCritical().noquote() << error.toString();
        delete view;
        close(DismissAction::Cancel, CloseFocus::Discard);
        return false;
    }

    QQuickItem *root = view->rootObject();
    if (!root) {
        qCritical("Qt Quick pitch-bend popup QML loaded without a root object");
        delete view;
        close(DismissAction::Cancel, CloseFocus::Discard);
        return false;
    }
    PitchBendGraph *pitchGraph = qobject_cast<PitchBendGraph *>(
        root->findChild<QQuickItem *>(QStringLiteral("pitchBendGraph")));
    PitchBendGraph *modGraph = qobject_cast<PitchBendGraph *>(
        root->findChild<QQuickItem *>(QStringLiteral("modWheelGraph")));
    if (!pitchGraph || !modGraph) {
        if (!pitchGraph)
            qCritical("Qt Quick pitch-bend popup QML has no PitchBendGraph named pitchBendGraph");
        if (!modGraph)
            qCritical("Qt Quick pitch-bend popup QML has no PitchBendGraph named modWheelGraph");
        delete view;
        close(DismissAction::Cancel, CloseFocus::Discard);
        return false;
    }

    m_view = view;
    m_pitchGraph = pitchGraph;
    m_modGraph = modGraph;
    // Graphs belong to the QML root; bind complete document snapshots before
    // the window is exposed so no graph can receive input uninitialized.
    bindGraph(m_pitchGraph.data(), PitchBendGraph::Lane::PitchBend);
    bindGraph(m_modGraph.data(), PitchBendGraph::Lane::ModWheel);

    // Native close/hide (minimize, transient-parent hide) follows ordinary
    // dismissal: settle pending work, no focus steal. Our own finalize hides
    // with the Closed guard already set, so this cannot reenter.
    connect(view, &QWindow::visibleChanged, this, [this](bool visible) {
        if (!visible && m_lifecycle == Lifecycle::Open)
            close(DismissAction::Commit, CloseFocus::Discard);
    });
    return true;
}

void PitchBendEditor::undoFromKeyboard()
{
    undoCurve();
}

void PitchBendEditor::requestCancelClose()
{
    close(DismissAction::Cancel, CloseFocus::Restore);
}

void PitchBendEditor::dismissWithCommit(bool restoreFocus)
{
    close(DismissAction::Commit, restoreFocus ? CloseFocus::Restore : CloseFocus::Discard);
}

bool PitchBendEditor::handleUnclaimedKeyPress(QKeyEvent *event)
{
    if (event->key() == Qt::Key_Delete || event->key() == Qt::Key_Backspace) {
        if (PitchBendGraph *graph = focusedGraph(); graph && graph->selectedTick()) {
            if (noteSpanStillPresent())
                graph->removeSelectedVertex();
            return true;
        }
    }
    if (PitchBendGraph *graph = focusedGraph(); graph && graph->handleKeyPress(event))
        return true;
    // Only solo routes out of the popup; the remaining roll edit commands
    // must not reach the song while the note automation popup has focus.
    if (m_songView &&
        keymap::Registry::instance().matches(event, QStringLiteral("roll.solo_tracks"))) {
        m_songView->toggleSoloOnSelectedTracks();
        return true;
    }
    return false;
}

void PitchBendEditor::installCloseController(std::function<bool(QPointF)> focusNoteUnderCursor)
{
    new PitchBendCloseController(this, std::move(focusNoteUnderCursor));
}

void PitchBendEditor::close(DismissAction action, CloseFocus focus)
{
    finalize(action, focus, /*deferTeardown=*/true);
}

void PitchBendEditor::finalize(DismissAction action, CloseFocus focus, bool deferTeardown)
{
    if (m_lifecycle != Lifecycle::Open)
        return;
    // Set the lifecycle guard before callbacks can write or hiding can emit:
    // each dismissal settles exactly once on every close, tab and document path.
    m_lifecycle = Lifecycle::Closed;
    m_closeFocus = focus;
    if (m_pitchGraph)
        m_pitchGraph->cancelGesture();
    if (m_modGraph)
        m_modGraph->cancelGesture();
    if (action == DismissAction::Cancel)
        cancelCurve();
    else
        commitCurve();

    // Window-first destruction: the view owns the QML root (the graph items)
    // and the independent engine; they die with it, before session teardown.
    const QPointer<QQuickView> view = m_view;
    m_pitchGraph.clear();
    m_modGraph.clear();
    m_pendingGraph.clear();
    if (view) {
        view->setVisible(false); // guarded: m_lifecycle is already Closed
        if (deferTeardown)
            view->deleteLater();
        else
            delete view;
    }

    // Deferred focus only on the restore reason; tab/app/document changes use
    // the no-focus path and never steal focus.
    if (m_closeFocus == CloseFocus::Restore && m_songView) {
        const QPointer<::SongView> songView = m_songView;
        QMetaObject::invokeMethod(
            songView.data(),
            [songView] {
                if (songView)
                    songView->focusTimelineBand(TimelineBand::Roll, Qt::PopupFocusReason);
            },
            Qt::QueuedConnection);
    }
    if (deferTeardown)
        deleteLater();
}

} // namespace songview
