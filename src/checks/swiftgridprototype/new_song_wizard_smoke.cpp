#include "new_song_wizard_smoke.h"

#include <QGuiApplication>
#include <QKeySequence>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QString>
#include <QTest>
#include <QVector>
#include <QWindow>

#include <cstdio>
#include <cstdlib>
#include <exception>
#include <string>

namespace {

using namespace std::chrono_literals;

constexpr auto kWaitTimeout = 5000ms;

struct WizardSmokeFailure : std::exception {
    std::string message;
    const char *what() const noexcept override { return message.c_str(); }
};

[[noreturn]] void wizardFail(const QString &reason)
{
    std::fprintf(stderr, "SWIFT_GRID_WIDGET_SMOKE NewSongWizard FAIL: %s\n", qPrintable(reason));
    std::fflush(stderr);
    WizardSmokeFailure failure;
    failure.message = reason.toStdString();
    throw failure;
}

void wizardRequire(bool condition, const QString &reason)
{
    if (!condition)
        wizardFail(reason);
}

void wizardEvidence(const QString &text)
{
    std::printf("SWIFT_GRID_WIDGET_SMOKE evidence: %s\n", qPrintable(text));
    std::fflush(stdout);
}

void wizardPass(const QString &scenario)
{
    std::printf("SWIFT_GRID_WIDGET_SMOKE %s PASS\n", qPrintable(scenario));
    std::fflush(stdout);
}

QQuickItem *findItem(QQuickItem *parent, const QString &name)
{
    if (!parent)
        return nullptr;
    if (parent->objectName() == name)
        return parent;
    for (QQuickItem *child : parent->childItems()) {
        if (QQuickItem *found = findItem(child, name))
            return found;
    }
    return nullptr;
}

QQuickWindow *findWizardWindow(QQuickWindow * /*hostWindow*/)
{
    for (QWindow *window : QGuiApplication::allWindows()) {
        auto *quickWindow = qobject_cast<QQuickWindow *>(window);
        if (quickWindow && quickWindow->objectName() == QStringLiteral("newSongWizardWindow") &&
            quickWindow->isVisible()) {
            return quickWindow;
        }
    }
    return nullptr;
}

QQuickWindow *awaitWizardWindow(QQuickWindow *hostWindow,
                                std::chrono::milliseconds timeout = kWaitTimeout)
{
    QQuickWindow *found = nullptr;
    // Observe only: the wizard takes exposure, activation, and focus on its
    // own once begin() shows it. Never request activation to repair this.
    const auto appeared = [&found, hostWindow] {
        found = findWizardWindow(hostWindow);
        return found != nullptr && found->isVisible() && found->isExposed() && found->isActive() &&
               QGuiApplication::focusWindow() == found && QGuiApplication::modalWindow() == found;
    };
    wizardRequire(
        QTest::qWaitFor(appeared, timeout),
        QStringLiteral("the NewSongWizard window never became the exposed, active modal window"));
    return found;
}

void awaitWizardDismissed(QPointer<QQuickWindow> window, QObject *newSongWizard,
                          std::chrono::milliseconds timeout = kWaitTimeout)
{
    const auto dismissed = [&window, newSongWizard] {
        const bool winGone = window.isNull() || !window->isVisible();
        const bool ctrlInactive = !newSongWizard->property("active").toBool();
        return winGone && ctrlInactive;
    };
    wizardRequire(QTest::qWaitFor(dismissed, timeout),
                  QStringLiteral("the NewSongWizard window did not dismiss"));
}

void clickItem(QQuickWindow *window, QQuickItem *item, const QString &what)
{
    wizardRequire(item && item->isVisible() && item->isEnabled(),
                  QStringLiteral("%1 is not an enabled, visible control").arg(what));
    const QPointF center = item->mapToScene(QPointF(item->width() / 2.0, item->height() / 2.0));
    wizardRequire(window->contentItem()->boundingRect().contains(center),
                  QStringLiteral("%1 is outside the window").arg(what));
    QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, center.toPoint());
    QTest::qWait(25ms);
}
void typeText(QQuickWindow *window, QQuickItem *item, const QString &text, bool clear = true)
{
    wizardRequire(item && item->isVisible() && item->isEnabled(),
                  QStringLiteral("text control is not enabled/visible"));
    QQuickItem *target = item;
    if (QQuickItem *content = item->property("contentItem").value<QQuickItem *>())
        target = content;
    const QPointF center =
        target->mapToScene(QPointF(target->width() / 2.0, target->height() / 2.0));
    QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, center.toPoint());
    QTest::qWait(20ms);
    wizardRequire(target->hasActiveFocus() || item->hasActiveFocus(),
                  QStringLiteral("pointer click did not give text control active focus"));
    if (clear) {
        QTest::keySequence(window, QKeySequence(QKeySequence::SelectAll));
    }
    for (const QChar &ch : text) {
        QTest::keyClick(window, ch.toLatin1());
        QTest::qWait(5ms);
    }
    QTest::qWait(30ms);
}

void selectComboIndex(QQuickWindow *window, QQuickItem *combo, int targetIndex, const QString &what)
{
    wizardRequire(combo && combo->isVisible() && combo->isEnabled(),
                  QStringLiteral("%1 is not visible/enabled").arg(what));
    const QPointer<QQuickWindow> guardedWindow(window);
    auto *indicator = combo->property("indicator").value<QQuickItem *>();
    auto *popup = combo->property("popup").value<QObject *>();
    clickItem(window, indicator, what);
    wizardRequire(popup && popup->property("visible").toBool(),
                  QStringLiteral("%1 did not open its option list").arg(what));
    QWindow *inputWindow = QGuiApplication::focusWindow();
    wizardRequire(inputWindow, QStringLiteral("%1 popup has no focused window").arg(what));
    QTest::keyClick(inputWindow, Qt::Key_Home);
    QTest::qWait(20ms);
    for (int i = 0; i < targetIndex; ++i) {
        QTest::keyClick(inputWindow, Qt::Key_Down);
        QTest::qWait(10ms);
    }
    QTest::keyClick(inputWindow, Qt::Key_Return);
    QTest::qWait(50ms);
    wizardRequire(guardedWindow && guardedWindow->isVisible(),
                  QStringLiteral("Selecting %1 unexpectedly dismissed the wizard").arg(what));
    wizardRequire(!popup->property("visible").toBool() &&
                      combo->property("currentIndex").toInt() == targetIndex,
                  QStringLiteral("%1 did not accept the selected option").arg(what));
}

void adjustSpinBox(QQuickWindow *window, QQuickItem *spinBox, int targetValue, const QString &what)
{
    wizardRequire(spinBox && spinBox->isVisible() && spinBox->isEnabled(),
                  QStringLiteral("%1 is not visible/enabled").arg(what));
    QQuickItem *textInput = spinBox->property("contentItem").value<QQuickItem *>();
    QQuickItem *target = textInput ? textInput : spinBox;
    const QPointF center =
        target->mapToScene(QPointF(target->width() / 2.0, target->height() / 2.0));
    QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, center.toPoint());
    QTest::qWait(20ms);
    wizardRequire(target->hasActiveFocus() || spinBox->hasActiveFocus(),
                  QStringLiteral("pointer click did not give %1 active focus").arg(what));

    QTest::keySequence(window, QKeySequence(QKeySequence::SelectAll));
    const QString text = QString::number(targetValue);
    for (const QChar &ch : text) {
        QTest::keyClick(window, ch.toLatin1());
        QTest::qWait(5ms);
    }
    QTest::keyClick(window, Qt::Key_Tab);
    QTest::qWait(30ms);

    wizardRequire(
        spinBox->property("value").toInt() == targetValue,
        QStringLiteral("%1 value was not updated to %2 after edit and Tab (value=%3, text=%4)")
            .arg(what)
            .arg(targetValue)
            .arg(spinBox->property("value").toInt())
            .arg(target->property("text").toString()));
}

void setCheckBox(QQuickWindow *window, QQuickItem *checkBox, bool checked, const QString &what)
{
    wizardRequire(checkBox && checkBox->isVisible() && checkBox->isEnabled(),
                  QStringLiteral("%1 is not visible/enabled").arg(what));
    if (checkBox->property("checked").toBool() != checked) {
        clickItem(window, checkBox, what);
        QTest::qWait(25ms);
    }
    wizardRequire(checkBox->property("checked").toBool() == checked,
                  QStringLiteral("failed to toggle %1 to %2").arg(what).arg(checked));
}

void proveHostBlocked(QQuickWindow *hostWindow, QQuickWindow *wizardWindow)
{
    QObject *songTabs = hostWindow->property("songTabs").value<QObject *>();
    QObject *audio = hostWindow->property("audio").value<QObject *>();
    const int tabBefore = songTabs ? songTabs->property("selectedId").toInt() : -1;
    const bool playingBefore = audio ? audio->property("playing").toBool() : false;
    wizardRequire(wizardWindow->modality() == Qt::WindowModal,
                  "wizard window is not Qt::WindowModal");
    wizardRequire(wizardWindow->transientParent() == hostWindow,
                  "wizard window transientParent is not the host window");
    wizardRequire(QGuiApplication::modalWindow() == wizardWindow,
                  "wizard window is not the application modal window");
    wizardRequire(QGuiApplication::focusWindow() == wizardWindow,
                  "wizard window is not the focused window");

    // Pointer input addressed at the blocked host: Qt drops it before QML
    // sees it, so the click must change nothing and steal no focus.
    QTest::mouseClick(hostWindow, Qt::LeftButton, Qt::NoModifier, QPoint(100, 100));
    wizardRequire(QGuiApplication::focusWindow() == wizardWindow,
                  "blocked host click stole keyboard focus from the wizard");

    // Keyboard input goes to the real focused window. QTest target injection
    // bypasses normal routing, so addressing the blocked host directly would
    // toggle transport even though a real keypress reaches the modal wizard.
    QWindow *focused = QGuiApplication::focusWindow();
    wizardRequire(focused != nullptr, "no focused window while wizard is modal");
    wizardEvidence(QStringLiteral("blocked spaceRoutedTo='%1'").arg(focused->title()));
    QTest::keyClick(focused, Qt::Key_Space);
    QTest::qWait(30ms);

    if (songTabs) {
        wizardRequire(songTabs->property("selectedId").toInt() == tabBefore,
                      "host tab switched while wizard window was modal");
    }
    if (audio) {
        wizardRequire(audio->property("playing").toBool() == playingBefore,
                      "host transport toggled while wizard window was modal");
    }
}

void proveHostResumed(QQuickWindow *hostWindow)
{
    const auto active = [&hostWindow] {
        return hostWindow && hostWindow->isActive() && QGuiApplication::focusWindow() == hostWindow;
    };
    wizardRequire(QTest::qWaitFor(active, kWaitTimeout),
                  "Quick host window did not regain activation after wizard closed");

    QObject *audio = hostWindow->property("audio").value<QObject *>();
    if (audio) {
        const bool playingBefore = audio->property("playing").toBool();
        QTest::keyClick(hostWindow, Qt::Key_Space);
        wizardRequire(QTest::qWaitFor(
                          [audio, playingBefore] {
                              return audio->property("playing").toBool() != playingBefore;
                          },
                          3s),
                      "Space shortcut did not reach transport after wizard closed");
        QTest::keyClick(hostWindow, Qt::Key_Space);
        wizardRequire(QTest::qWaitFor(
                          [audio, playingBefore] {
                              return audio->property("playing").toBool() == playingBefore;
                          },
                          3s),
                      "Space shortcut did not toggle transport back");
    }
}

} // namespace

void runNewSongWizardSmoke(QQuickWindow *hostWindow, QQuickItem *wizardButton,
                           QObject *newSongWizard, QObject *newSongResult)
{
    wizardRequire(hostWindow && wizardButton && newSongWizard && newSongResult,
                  "null pointer passed to runNewSongWizardSmoke");

    // =========================================================================
    // Pass 1: Initial incomplete state & Cancel / Reopen reset
    // =========================================================================
    wizardRequire(!newSongWizard->property("active").toBool(),
                  "NewSongWizardController started active");

    clickItem(hostWindow, wizardButton, QStringLiteral("New Song button"));
    QQuickWindow *wizardWin = awaitWizardWindow(hostWindow);
    const QPointer<QQuickWindow> guardedWin = wizardWin;

    wizardRequire(newSongWizard->property("active").toBool(),
                  "controller.active did not become true after begin");
    wizardRequire(newSongWizard->property("page").toInt() == 0,
                  "wizard did not open on identity page (page 0)");
    wizardRequire(!newSongWizard->property("canNext").toBool(),
                  "canNext is true on empty identity page");
    wizardRequire(!newSongWizard->property("canFinish").toBool(),
                  "canFinish is true on empty identity page");

    QQuickItem *content = wizardWin->contentItem();
    QQuickItem *nameItem = findItem(content, QStringLiteral("newSongName"));
    QQuickItem *constItem = findItem(content, QStringLiteral("newSongConstant"));
    QQuickItem *playerItem = findItem(content, QStringLiteral("newSongPlayer"));
    QQuickItem *idErrorItem = findItem(content, QStringLiteral("newSongIdentityError"));
    QQuickItem *nextButton = findItem(content, QStringLiteral("newSongNext"));
    QQuickItem *cancelButton = findItem(content, QStringLiteral("newSongCancel"));

    wizardRequire(nameItem && constItem && playerItem && nextButton && cancelButton,
                  "identity page controls missing from NewSongWizard.qml");

    // Next is disabled initially
    wizardRequire(!nextButton->isEnabled(), "Next button is enabled before name is entered");

    proveHostBlocked(hostWindow, wizardWin);

    // Cancel dismissal
    const int countBeforeCancel = newSongResult->property("completedCount").toInt();
    clickItem(wizardWin, cancelButton, QStringLiteral("Cancel button"));
    awaitWizardDismissed(guardedWin, newSongWizard);

    wizardRequire(newSongResult->property("completedCount").toInt() == countBeforeCancel + 1,
                  "Cancel did not complete observer");
    wizardRequire(!newSongResult->property("accepted").toBool(),
                  "Cancel accepted the result observer");

    proveHostResumed(hostWindow);
    wizardEvidence(QStringLiteral("initial incomplete Next verified, Cancel resets draft"));
    wizardPass("new-song-wizard-initial-incomplete-and-cancel-reset");

    // =========================================================================
    // Pass 2: Duplicate name blocking & Titlebar close
    // =========================================================================
    clickItem(hostWindow, wizardButton, QStringLiteral("New Song button"));
    wizardWin = awaitWizardWindow(hostWindow);
    const QPointer<QQuickWindow> guardedWin2 = wizardWin;
    content = wizardWin->contentItem();
    nameItem = findItem(content, QStringLiteral("newSongName"));
    constItem = findItem(content, QStringLiteral("newSongConstant"));
    idErrorItem = findItem(content, QStringLiteral("newSongIdentityError"));
    nextButton = findItem(content, QStringLiteral("newSongNext"));

    // Verify reopening gave a fresh draft
    wizardRequire(newSongWizard->property("name").toString().isEmpty(),
                  "reopened draft had non-empty name");
    wizardRequire(newSongWizard->property("constant").toString().isEmpty(),
                  "reopened draft had non-empty constant");

    // Type the duplicate label as uppercase text: the draft folds it to
    // lowercase mus_route101 while the constant stays MUS_ROUTE101.
    typeText(wizardWin, nameItem, QStringLiteral("MUS_ROUTE101"));
    wizardRequire(newSongWizard->property("name").toString() == QStringLiteral("mus_route101"),
                  "controller name was not folded to mus_route101");
    wizardRequire(newSongWizard->property("constant").toString() == QStringLiteral("MUS_ROUTE101"),
                  "controller constant was not automatically uppercase MUS_ROUTE101");
    wizardRequire(!nextButton->isEnabled(),
                  "Next button is enabled for duplicate song name mus_route101");
    wizardRequire(!newSongWizard->property("identityError").toString().isEmpty(),
                  "duplicate error message missing from controller");
    wizardRequire(idErrorItem && idErrorItem->isVisible() &&
                      !idErrorItem->property("text").toString().isEmpty(),
                  "duplicate error text not displayed on identity page");

    // Close via window close
    const int countBeforeClose = newSongResult->property("completedCount").toInt();
    wizardWin->close();
    awaitWizardDismissed(guardedWin2, newSongWizard);

    wizardRequire(newSongResult->property("completedCount").toInt() == countBeforeClose + 1,
                  "window close did not complete observer");
    wizardRequire(!newSongResult->property("accepted").toBool(),
                  "window close accepted the result observer");

    proveHostResumed(hostWindow);
    wizardEvidence(QStringLiteral("duplicate name blocked, close tested"));
    wizardPass("new-song-wizard-duplicate-name-blocked-and-close");

    // =========================================================================
    // Pass 3: Constant persistence, Voicegroup collision rejection & correction
    // =========================================================================
    clickItem(hostWindow, wizardButton, QStringLiteral("New Song button"));
    wizardWin = awaitWizardWindow(hostWindow);
    const QPointer<QQuickWindow> guardedWin3 = wizardWin;
    content = wizardWin->contentItem();
    nameItem = findItem(content, QStringLiteral("newSongName"));
    constItem = findItem(content, QStringLiteral("newSongConstant"));
    nextButton = findItem(content, QStringLiteral("newSongNext"));

    // Type valid name
    typeText(wizardWin, nameItem, QStringLiteral("mus_existing_bank"));
    wizardRequire(newSongWizard->property("canNext").toBool(),
                  "canNext rejected valid name mus_existing_bank");
    wizardRequire(newSongWizard->property("constant").toString() ==
                      QStringLiteral("MUS_EXISTING_BANK"),
                  "constant did not auto-populate");

    // Manually edit constant
    typeText(wizardWin, constItem, QStringLiteral("MUS_PERSISTENT_CONST"));
    wizardRequire(newSongWizard->property("constant").toString() ==
                      QStringLiteral("MUS_PERSISTENT_CONST"),
                  "controller did not accept manual constant");

    // Edit name again -> constant must persist!
    typeText(wizardWin, nameItem, QStringLiteral("mus_existing_bank_test"));
    wizardRequire(newSongWizard->property("constant").toString() ==
                      QStringLiteral("MUS_PERSISTENT_CONST"),
                  "manual constant was overwritten by subsequent name edit");

    // Restore name to mus_existing_bank for voicegroup collision test
    typeText(wizardWin, nameItem, QStringLiteral("mus_existing_bank"));

    // Advance to Sound page
    clickItem(wizardWin, nextButton, QStringLiteral("Next button"));
    wizardRequire(
        QTest::qWaitFor([newSongWizard] { return newSongWizard->property("page").toInt() == 1; },
                        kWaitTimeout),
        "did not advance to sound page (page 1)");

    // Sound page controls
    QQuickItem *backButton = findItem(content, QStringLiteral("newSongBack"));
    QQuickItem *finishButton = findItem(content, QStringLiteral("newSongFinish"));
    QQuickItem *vgItem = findItem(content, QStringLiteral("newSongVoicegroup"));
    QQuickItem *soundErrorItem = findItem(content, QStringLiteral("newSongSoundError"));

    wizardRequire(backButton && finishButton && vgItem,
                  "sound page controls missing from NewSongWizard.qml");

    // Go Back to page 0 to prove constant persists across page transitions
    clickItem(wizardWin, backButton, QStringLiteral("Back button"));
    wizardRequire(
        QTest::qWaitFor([newSongWizard] { return newSongWizard->property("page").toInt() == 0; },
                        kWaitTimeout),
        "did not navigate back to identity page (page 0)");

    wizardRequire(newSongWizard->property("constant").toString() ==
                      QStringLiteral("MUS_PERSISTENT_CONST"),
                  "manual constant was lost after back navigation");

    // Go Next to sound page again
    clickItem(wizardWin, nextButton, QStringLiteral("Next button"));
    wizardRequire(
        QTest::qWaitFor([newSongWizard] { return newSongWizard->property("page").toInt() == 1; },
                        kWaitTimeout),
        "did not re-advance to sound page");

    // Test collision: select create-new voicegroup (index 0)
    // The song label is "mus_existing_bank", which collides with "_mus_existing_bank"
    selectComboIndex(wizardWin, vgItem, 0, QStringLiteral("Voicegroup combo (create new)"));
    QTest::qWait(30ms);

    wizardRequire(!finishButton->isEnabled(),
                  "Finish button is enabled during voicegroup collision");
    wizardRequire(!newSongWizard->property("soundError").toString().isEmpty(),
                  "sound collision error message missing from controller");
    wizardRequire(soundErrorItem && soundErrorItem->isVisible() &&
                      !soundErrorItem->property("text").toString().isEmpty(),
                  "sound collision error not displayed on sound page");

    // Typing a correction must unblock Finish before any acceptance action.
    typeText(wizardWin, vgItem, QStringLiteral("custom_sound_bank"));

    wizardRequire(finishButton->isEnabled(),
                  "Finish button remained disabled after collision was corrected");
    wizardRequire(newSongWizard->property("soundError").toString().isEmpty(),
                  "soundError not cleared after correcting voicegroup");

    wizardEvidence(QStringLiteral("constant persisted, collision rejected then corrected"));
    wizardPass("new-song-wizard-constant-persistence-and-collision-correction");

    // =========================================================================
    // Pass 4: Sound choices reach typed result observer upon finish
    // =========================================================================
    QQuickItem *volItem = findItem(content, QStringLiteral("newSongVolume"));
    QQuickItem *revItem = findItem(content, QStringLiteral("newSongReverb"));
    QQuickItem *priItem = findItem(content, QStringLiteral("newSongPriority"));
    QQuickItem *gateItem = findItem(content, QStringLiteral("newSongExactGate"));
    QQuickItem *clockItem = findItem(content, QStringLiteral("newSongExtendedClocks"));
    QQuickItem *compItem = findItem(content, QStringLiteral("newSongNoCompression"));

    wizardRequire(volItem && revItem && priItem && gateItem && clockItem && compItem,
                  "sound settings items missing from sound page");

    adjustSpinBox(wizardWin, volItem, 85, QStringLiteral("Volume spinbox"));
    adjustSpinBox(wizardWin, revItem, 32, QStringLiteral("Reverb spinbox"));
    adjustSpinBox(wizardWin, priItem, 64, QStringLiteral("Priority spinbox"));
    setCheckBox(wizardWin, gateItem, false, QStringLiteral("Exact gate checkbox"));
    setCheckBox(wizardWin, clockItem, true, QStringLiteral("Extended clocks checkbox"));
    setCheckBox(wizardWin, compItem, true, QStringLiteral("No compression checkbox"));

    const int countBeforeFinish = newSongResult->property("completedCount").toInt();
    clickItem(wizardWin, finishButton, QStringLiteral("Finish button"));
    awaitWizardDismissed(guardedWin3, newSongWizard);

    wizardRequire(newSongResult->property("completedCount").toInt() == countBeforeFinish + 1,
                  "Finish did not complete observer");
    wizardRequire(newSongResult->property("accepted").toBool(),
                  "Finish did not record accepted = true on observer");

    // Verify typed result fields
    wizardRequire(newSongResult->property("label").toString() ==
                      QStringLiteral("mus_existing_bank"),
                  "observer label did not match accepted name");
    wizardRequire(newSongResult->property("constant").toString() ==
                      QStringLiteral("MUS_PERSISTENT_CONST"),
                  "observer constant did not match manual constant");
    wizardRequire(newSongResult->property("player").toString() ==
                      QStringLiteral("MUSIC_PLAYER_BGM"),
                  "observer player did not match default BGM player");
    // Normalization added leading underscore
    wizardRequire(newSongResult->property("voicegroupArg").toString() ==
                      QStringLiteral("_custom_sound_bank"),
                  "custom voicegroup was not normalized with leading underscore");
    wizardRequire(newSongResult->property("newVoicegroupName").toString().isEmpty(),
                  "newVoicegroupName was unexpectedly set for custom existing voicegroup");
    wizardRequire(newSongResult->property("masterVolume").toInt() == 85,
                  "observer masterVolume did not match 85");
    wizardRequire(newSongResult->property("reverb").toInt() == 32,
                  "observer reverb did not match 32");
    wizardRequire(newSongResult->property("priority").toInt() == 64,
                  "observer priority did not match 64");
    wizardRequire(newSongResult->property("exactGate").toBool() == false,
                  "observer exactGate was not false");
    wizardRequire(newSongResult->property("extendedClocks").toBool() == true,
                  "observer extendedClocks was not true");
    wizardRequire(newSongResult->property("noCompression").toBool() == true,
                  "observer noCompression was not true");

    proveHostResumed(hostWindow);
    wizardPass("new-song-wizard-sound-choices-reach-typed-result");

    // =========================================================================
    // Pass 5: Create new voicegroup accepted
    // =========================================================================
    clickItem(hostWindow, wizardButton, QStringLiteral("New Song button"));
    wizardWin = awaitWizardWindow(hostWindow);
    const QPointer<QQuickWindow> guardedWin4 = wizardWin;
    content = wizardWin->contentItem();
    nameItem = findItem(content, QStringLiteral("newSongName"));
    playerItem = findItem(content, QStringLiteral("newSongPlayer"));
    nextButton = findItem(content, QStringLiteral("newSongNext"));

    typeText(wizardWin, nameItem, QStringLiteral("mus_fresh_tune"));
    selectComboIndex(wizardWin, playerItem, 1, QStringLiteral("Player combo (SE)"));
    clickItem(wizardWin, nextButton, QStringLiteral("Next button"));
    wizardRequire(
        QTest::qWaitFor([newSongWizard] { return newSongWizard->property("page").toInt() == 1; },
                        kWaitTimeout),
        "did not advance to sound page");

    vgItem = findItem(content, QStringLiteral("newSongVoicegroup"));
    finishButton = findItem(content, QStringLiteral("newSongFinish"));

    // Select index 0 (create new voicegroup)
    selectComboIndex(wizardWin, vgItem, 0, QStringLiteral("Voicegroup combo (create new)"));
    QTest::qWait(30ms);

    const int countBeforeCreateNew = newSongResult->property("completedCount").toInt();
    QTest::keyClick(wizardWin, Qt::Key_Return);
    awaitWizardDismissed(guardedWin4, newSongWizard);

    wizardRequire(newSongResult->property("completedCount").toInt() == countBeforeCreateNew + 1,
                  "Finish did not complete observer for create-new pass");
    wizardRequire(newSongResult->property("accepted").toBool(),
                  "Finish did not accept for create-new pass");
    wizardRequire(newSongResult->property("label").toString() == QStringLiteral("mus_fresh_tune"),
                  "observer label mismatch");
    wizardRequire(newSongResult->property("constant").toString() ==
                      QStringLiteral("MUS_FRESH_TUNE"),
                  "observer constant mismatch");
    wizardRequire(newSongResult->property("player").toString() == QStringLiteral("MUSIC_PLAYER_SE"),
                  "observer player mismatch");
    wizardRequire(newSongResult->property("voicegroupArg").toString() ==
                      QStringLiteral("_mus_fresh_tune"),
                  "observer voicegroupArg mismatch for create new");
    wizardRequire(newSongResult->property("newVoicegroupName").toString() ==
                      QStringLiteral("mus_fresh_tune"),
                  "observer newVoicegroupName mismatch for create new");

    proveHostResumed(hostWindow);
    wizardPass("new-song-wizard-create-new-voicegroup-accepted");

    // Escape closes the option list first, then cancels the dialog from its editor.
    clickItem(hostWindow, wizardButton, QStringLiteral("New Song button"));
    wizardWin = awaitWizardWindow(hostWindow);
    const QPointer<QQuickWindow> keyboardWindow = wizardWin;
    content = wizardWin->contentItem();
    typeText(wizardWin, findItem(content, QStringLiteral("newSongName")),
             QStringLiteral("mus_keyboard_cancel"));
    QTest::keyClick(wizardWin, Qt::Key_Return);
    wizardRequire(newSongWizard->property("page").toInt() == 1,
                  "Return did not advance from the name field");
    vgItem = findItem(content, QStringLiteral("newSongVoicegroup"));
    auto *voicegroupPopup = vgItem->property("popup").value<QObject *>();
    clickItem(wizardWin, vgItem->property("indicator").value<QQuickItem *>(),
              QStringLiteral("Voicegroup popup arrow"));
    wizardRequire(voicegroupPopup->property("visible").toBool(), "voicegroup popup did not open");
    QTest::keyClick(QGuiApplication::focusWindow(), Qt::Key_Escape);
    QTest::qWait(30ms);
    wizardRequire(keyboardWindow && keyboardWindow->isVisible() &&
                      !voicegroupPopup->property("visible").toBool(),
                  "Escape did not close only the voicegroup popup");
    const int countBeforeEscape = newSongResult->property("completedCount").toInt();
    QTest::keyClick(wizardWin, Qt::Key_Escape);
    awaitWizardDismissed(keyboardWindow, newSongWizard);
    wizardRequire(newSongResult->property("completedCount").toInt() == countBeforeEscape + 1 &&
                      !newSongResult->property("accepted").toBool(),
                  "Escape from the combo editor did not cancel exactly once");
    proveHostResumed(hostWindow);
    wizardPass("new-song-wizard-return-and-popup-escape-routing");
}
