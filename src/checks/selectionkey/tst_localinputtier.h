#pragma once

// Qt Test suite for selection keyboard routing at the protected-local-input
// tier. Each case runs on its own shown MainWindow shell (fresh per-case
// lifecycle in init/cleanup) and preserves the selectionkey plan contracts:
// surfaces which visibly own the keyboard keep it, and window commands resume
// exactly once after each surface closes.
//
// * the real QML track-rename TextInput, a real QWidget line edit (the song
//   search field), the inline automation value prompt opened by an
//   automation lane double click, the application modal roll velocity prompt
//   opened by the note menu, and the pitch-bend overlay: keys delivered into
//   the surface that visibly holds focus edit only that surface, Copy
//   carries the surface's own text, and every window command that production
//   routes out of a surface fires exactly once through its window owner
//   (plan 9);
// * the event list keeps row-local navigation, Delete, Alt reorder and
//   Select All, with no new selected-note Cut/Delete fallback and exactly one
//   window Copy owner (plan 11).
//
// All deliveries are QTest input into the real QQuickWindow or QWidget under
// test; native OS key injection is unavailable to the harness and is not
// claimed.

#include <cstdint>
#include <memory>
#include <optional>

#include <QKeySequence>
#include <QPoint>
#include <QPointer>
#include <QQuickWindow>
#include <QString>
#include <QtTest>

#include "checks/clipcheck_support.h"
#include "checks/selectionkey/session.h"
#include "core/noteid.h"
#include "core/songdocument.h"

class SelectionLocalInputTierTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(SelectionLocalInputTierTest)

  public:
    // Fixture identity only; the shell is created per case in init().
    SelectionLocalInputTierTest(QString projectRoot, QString songLabel);

  private slots:
    void init();
    void cleanup();

    // Plan 9: surfaces that visibly own the keyboard keep it.
    void renameTextInputOwnsKeys();
    void songSearchLineEditOwnsKeys();
    void numericPromptOwnsKeys();
    void velocityPromptOwnsKeys();
    void pitchBendOverlayOwnsKeys();
    // Plan 11: the event list keeps row-local keys.
    void eventListKeepsRowLocalKeys();

  private:
    // One inserted note plus its resolved document state.
    struct NoteRef {
        NoteId id{};
        DocNote note{};
    };

    SongView &view() const;
    SongDocument &document() const;
    QQuickWindow *quickWindow() const;

    // The typed-text expectation for a delivered command binding: only a plain
    // printable key derives a character, so a rebound F-key keeps assertions
    // honest ("text unchanged") instead of fabricating text from an arbitrary
    // nonprintable binding.
    static std::optional<QString> singleKeyText(const QKeyCombination &binding);

    // Window-scoped shortcuts fire only while the shell is the active window;
    // modal dialogs and the pitch-bend overlay activate themselves, so the
    // shell must be restored and observed before resumed-command deliveries.
    // Runs before band (re)focus and before every window-scoped shortcut
    // delivery: activating after a Quick band takes focus clears its
    // activeFocusItem (probe-measured), so the shell is activated first
    // everywhere.
    void activateShellForCommands();
    QString applicationFocusState() const;

    // Inserts one isolated note and resolves it from the live document.
    std::optional<NoteRef> addNote(int track, uint64_t tick, uint8_t key, uint32_t duration);

    QString m_projectRoot;
    QString m_songLabel;
    selectionkey::ActionCounts m_counts;
    std::unique_ptr<selectionkey::SessionSettingsGuard> m_settings;
    std::unique_ptr<clipcheck_support::ClipboardStateGuard> m_clipboard;
    selectionkey::WindowSession m_session;
    WorkspaceUi *m_workspace = nullptr;
    QPointer<SongTab> m_tab;
    QPointer<QQuickWindow> m_quickWindow;
};
