#pragma once

// Qt Test suite for selection keyboard routing at the full production window
// tier. Each case runs on its own shown MainWindow shell (fresh per-case
// lifecycle in init/cleanup) and preserves the selectionkeywindow plan
// contracts:
//
// * window Copy with timeline/automation focus executes exactly once, Copy
//   lands the note clip on the clipboard, and an unrecognized key is a
//   terminal no-op (plan 5);
// * parameter labels activate locally with Enter/Return — bare Space on
//   focused labels or drawer toggles routes exactly one transport
//   play/pause request — without retargeting multi-lane selection, and
//   retain shared editing commands; deliberately keyboard-focused drawer
//   grips keep local arrows and toggles still route selected-note arrows;
// * a live drawer resize drag holds the
//   pointer: shared editing keys cannot mutate the selected notes, Escape
//   cancels only the gesture, and the next idle Escape clears it (plan 6);
// * A/B tab switching, drawer hide/show, a primary-track change, and closing
//   plus reopening a song tab leave routing bound to the live view, with no
//   stale callback mutating a background document (plan 10).
//
// Asserted keys are QTest deliveries into the real shown Quick window; pointer
// gestures send Qt mouse events through the same window. Programmatic staging
// (band focus, selection, document inserts, drawer geometry) is setup, never a
// substitute for delivered input. Reserved note ticks per song: 960 (Copy),
// 2400 (chrome and gesture), 3840 (reselected first tab), track-1 960
// (primary-track change) — distinct so scenario rollbacks can never collide.

#include <array>
#include <cstdint>
#include <memory>
#include <optional>

#include <QPoint>
#include <QPointer>
#include <QQuickWindow>
#include <QString>
#include <QtTest>

#include "checks/clipcheck_support.h"
#include "checks/selectionkey/session.h"
#include "core/noteid.h"
#include "core/songdocument.h"

class SelectionWindowTierTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(SelectionWindowTierTest)

  public:
    // Fixture identity only; the shell is created per case in init().
    SelectionWindowTierTest(QString projectRoot, QString songA, QString songB);

  private slots:
    void init();
    void cleanup();

    // Plan 5: window Copy/Solo execute exactly once from band focus.
    void windowCopySoloExecutesExactlyOnce();
    // Plan 13: keyboard-focused chrome keeps its advertised local keys.
    void chromeGripKeysStayLocal();
    void parameterLabelActivationAndSharedCommands();
    void chromeToggleRoutesNoteArrows();
    // Plan 6: live pointer gestures protect the selected notes.
    void resizeDragProtectsSelectedNotes();
    // Plan 10: routing stays bound to the live view across tab lifecycles.
    void tabsDocumentsAndPrimaryTrackLifetime();

  private:
    // The two isolated notes every routing scenario stages and observes.
    struct NotePair {
        std::array<NoteId, 2> ids{};
        std::array<DocNote, 2> notes{};
    };

    SongView &view() const;
    SongDocument &document() const;
    QQuickWindow *quickWindow() const;
    // Inserts the isolated pair at the reserved tick on the given document
    // and resolves both notes.
    std::optional<NotePair> addNotePair(SongDocument &document, int track, uint64_t firstTick);
    bool notePairUnchanged(SongDocument &document, const NotePair &pair) const;
    // Requests automation-band focus through the production seam.
    bool focusAutomationBand(SongView &view) const;
    // Held-input record for the failure-safe cleanup; the gesture bodies
    // release their own presses, and cleanup releases whatever survives an
    // aborted assertion.
    void trackPointer(const QPoint &windowPos);
    void trackRelease();

    QString m_projectRoot;
    QString m_songA;
    QString m_songB;
    selectionkey::ActionCounts m_counts;
    std::unique_ptr<selectionkey::SessionSettingsGuard> m_settings;
    std::unique_ptr<clipcheck_support::ClipboardStateGuard> m_clipboard;
    selectionkey::WindowSession m_session;
    WorkspaceUi *m_workspace = nullptr;
    QPointer<SongTab> m_tab;
    QPointer<QQuickWindow> m_quickWindow;
    // Held-input record for the failure-safe cleanup.
    Qt::MouseButton m_heldButton = Qt::NoButton;
    QPoint m_lastWindowPos;
};
