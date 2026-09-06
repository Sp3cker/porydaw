#include "checks/selectionkey/tst_selectionkeycore.h"

#include "checks/fwd.hpp"

#include <QQuickItem>
#include <QtTest>

#include <utility>

namespace {

// Old-to-new mapping (manual runSelectionKeyCoreCheck band loop -> Qt Test):
//   arrowsFollowNotesAcrossClickedBands        -> incidentalBandClickPreservesSelection (5 band rows),
//                                                 arrowsMoveSelectedNotesAcrossBands (20 band x
//                                                 direction rows), and
//                                                 mergeableMoveHistorySupportsUndoRedoRoundTrip
//   drawerTransposeAuditionReleasesOnPhysicalKeyUp -> same-named slot
//   automationRangeAndReboundDelete            -> same-named slot
//   deletePrecedenceAndPencilHover             -> pencilHoverDeletePrecedence (4 precedence rows)
//   laneNudgeConsumesVerticalAndMovesHorizontal -> laneScopedVerticalArrowLeavesDocumentUntouched +
//                                                 laneScopedHorizontalArrowNudgesPointsAndInterval
//   keyboardClipboardParity                    -> keyboardClipboardParity (2 destination rows)
//   selectAllFromEmptyAndTimeSelection         -> selectAllFromEmptySelection +
//                                                 selectAllReplacesTimeSelectionAfterRulerClick
// The runner itself only assembles the test object; every verdict lives in
// the slots, and Qt Test owns the failure accounting.

} // namespace

SelectionKeyCoreTest::SelectionKeyCoreTest(QString projectRoot, QString songLabel)
    : m_projectRoot(std::move(projectRoot))
    , m_songLabel(std::move(songLabel))
{}

// Per-case lifecycle: init() resets the shared keymap registry so every case
// resolves bindings from defaults (rebinds go through the RAII member that
// restores on destruction); cleanup() quiesces any surviving interaction and
// releases recorded held input even when the body aborted mid-gesture.
void SelectionKeyCoreTest::init()
{
    m_heldButton = Qt::NoButton;
    m_lastWindowPosition = QPoint();
    m_keymap = std::make_unique<selectionkey::KeymapRestore>();
    m_keymap->registry().resetAll();
}

void SelectionKeyCoreTest::cleanup()
{
    // Unconditional quiesce, independent of how the body ended: cancel any
    // surviving interaction, release every recorded held input, then drop
    // any residual grab before the fixture dies.
    bool mouseGrabCleared = true;
    if (m_quickWindow) {
        QTest::keyClick(m_quickWindow, Qt::Key_Escape);
        if (m_heldButton != Qt::NoButton)
            QTest::mouseRelease(m_quickWindow, m_heldButton, Qt::NoModifier, m_lastWindowPosition);
        if (QQuickItem *grabber = m_quickWindow->mouseGrabberItem())
            grabber->ungrabMouse();
        mouseGrabCleared = QTest::qWaitFor(
            [this] { return m_quickWindow.isNull() || !m_quickWindow->mouseGrabberItem(); });
    }
    m_heldButton = Qt::NoButton;
    m_quickWindow.clear();
    m_fixture.reset();
    m_keymap.reset();
    QVERIFY2(mouseGrabCleared, "the Quick window kept a mouse grab after cleanup");
}

std::unique_ptr<selectionkey::CoreFixture>
SelectionKeyCoreTest::createFixture(std::optional<EditorDrawerPage> drawerPage)
{
    m_lastFixtureError.clear();
    QString error;
    auto fixture = selectionkey::CoreFixture::create(m_projectRoot, m_songLabel, drawerPage, error);
    if (!fixture)
        m_lastFixtureError = error;
    m_quickWindow = fixture ? fixture->window() : nullptr;
    return fixture;
}

void SelectionKeyCoreTest::stageMousePress(Qt::MouseButton button, const QPoint &windowPosition)
{
    m_heldButton = button;
    m_lastWindowPosition = windowPosition;
    QTest::mousePress(m_quickWindow, button, Qt::NoModifier, windowPosition);
}

void SelectionKeyCoreTest::stageMouseMove(const QPoint &windowPosition)
{
    QTest::mouseMove(m_quickWindow, windowPosition);
}

void SelectionKeyCoreTest::stageMouseRelease(Qt::MouseButton button, const QPoint &windowPosition)
{
    QTest::mouseRelease(m_quickWindow, button, Qt::NoModifier, windowPosition);
    m_heldButton = Qt::NoButton;
}

// Dispatched once per process by the selectionkey-core catalog row; the
// catalog already passed only the Qt payload.
int runSelectionKeyCoreCheck(const QString &projectRoot, const QString &songLabel,
                             const QStringList &qtArguments)
{
    SelectionKeyCoreTest test(projectRoot, songLabel);
    QStringList arguments{QStringLiteral("selectionkey-core")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
