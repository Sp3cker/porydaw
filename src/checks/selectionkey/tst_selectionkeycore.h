#pragma once

// Genuine Qt Test port of the selectionkey-core routing check. The original
// manual suite ran seven scenario functions through one stateful band loop
// with a shared failure counter; every scenario is now an independently
// selectable slot (plus named data rows for the band, direction, precedence
// and clipboard matrices), each starting from its own freshly assembled
// CoreFixture. The old-to-new mapping is recorded above
// runSelectionKeyCoreCheck() in core.cpp.

#include "checks/selectionkey/corefixture.h"

#include <QObject>
#include <QPoint>
#include <QPointer>
#include <QQuickWindow>
#include <QString>

#include <memory>
#include <optional>

class SelectionKeyCoreTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(SelectionKeyCoreTest)

  public:
    SelectionKeyCoreTest(QString projectRoot, QString songLabel);

  private slots:
    void init();
    void cleanup();

    // Plan scenario 1, staging half: the incidental first click on each band
    // keeps its production semantics (focus, selection-preserving velocity
    // stem drag, no replacement range) without disturbing the eligible note
    // selection.
    void incidentalBandClickPreservesSelection_data();
    void incidentalBandClickPreservesSelection();

    // Plan scenario 1, routing half: all four arrows move only the selected
    // notes on every keyboard-eligible band — the full 5-band x 4-direction
    // matrix as named data rows.
    void arrowsMoveSelectedNotesAcrossBands_data();
    void arrowsMoveSelectedNotesAcrossBands();

    // The arrows route through the production mergeable-move history; one
    // transposing press proves increment/undo/redo preservation end to end.
    void mergeableMoveHistorySupportsUndoRedoRoundTrip();

    // Drawer transposition auditions stop on the physical key-up, not on the
    // autorepeat releases that precede it.
    void drawerTransposeAuditionReleasesOnPhysicalKeyUp();

    // An automation right-drag range replaces the note selection with lane
    // scope, and a rebound Delete removes only its selected points.
    void automationRangeAndReboundDelete();

    // Pencil-hover Delete precedence: note selection, then track time
    // selection, then the hovered point; a miss never mutates the document.
    void pencilHoverDeletePrecedence_data();
    void pencilHoverDeletePrecedence();

    // Lane-scoped arrows: vertical mutates nothing, horizontal nudges the
    // points and the selected interval together.
    void laneScopedVerticalArrowLeavesDocumentUntouched();
    void laneScopedHorizontalArrowNudgesPointsAndInterval();

    // Keyboard Paste lands the roll-copied clip both from the roll band and
    // from the automation drawer destination.
    void keyboardClipboardParity_data();
    void keyboardClipboardParity();

    // Select All works from an empty selection and replaces a track time
    // selection staged before an incidental ruler click.
    void selectAllFromEmptySelection();
    void selectAllReplacesTimeSelectionAfterRulerClick();

  private:
    std::unique_ptr<selectionkey::CoreFixture>
    createFixture(std::optional<EditorDrawerPage> drawerPage);
    // Real QTest delivery that records the held button and last position so
    // cleanup() can release input even when a case aborts mid-gesture.
    void stageMousePress(Qt::MouseButton button, const QPoint &windowPosition);
    void stageMouseMove(const QPoint &windowPosition);
    void stageMouseRelease(Qt::MouseButton button, const QPoint &windowPosition);

    QString m_projectRoot;
    QString m_songLabel;
    // Snapshot/restore RAII for the shared keymap registry; init() resets the
    // registry to defaults per case, so rebound bindings cannot leak in
    // either direction.
    std::unique_ptr<selectionkey::KeymapRestore> m_keymap;
    std::unique_ptr<selectionkey::CoreFixture> m_fixture;
    QString m_lastFixtureError;
    // Held-input record for the failure-safe cleanup.
    QPointer<QQuickWindow> m_quickWindow;
    Qt::MouseButton m_heldButton = Qt::NoButton;
    QPoint m_lastWindowPosition;
};
