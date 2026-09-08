#include "checks/keyboard/tst_keymapcheck.h"

#include <QAction>
#include <QKeyEvent>
#include <QSet>
#include <QSettings>
#include <QtTest>

#include <array>
#include <memory>

void KeymapCheckTest::initTestCase()
{
    QVERIFY2(m_settingsDirectory.isValid(), "could not create isolated QSettings directory");
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_settingsDirectory.path());
    QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, m_settingsDirectory.path());
}

void KeymapCheckTest::init()
{
    auto &registry = keymap::Registry::instance();
    m_snapshot = registry.snapshotOverrides();
    registry.resetAll();
}

void KeymapCheckTest::cleanup()
{
    keymap::Registry::instance().restoreOverrides(m_snapshot);
}

bool KeymapCheckTest::matches(const QString &id, int key, Qt::KeyboardModifiers modifiers) const
{
    QKeyEvent event(QEvent::KeyPress, key, modifiers);
    return keymap::Registry::instance().matches(&event, id);
}

void KeymapCheckTest::shippedTable()
{
    const QList<keymap::CommandInfo> commands = keymap::Registry::instance().commands();
    QVERIFY(!commands.isEmpty());

    QSet<QString> ids;
    for (const keymap::CommandInfo &command : commands) {
        QVERIFY(!ids.contains(command.id));
        ids.insert(command.id);
        // Effective bindings probed from Global: that context overlaps every
        // consumer context, so a conflict here would make two commands fire
        // on one key anywhere.
        for (const QKeySequence &sequence : keymap::Registry::instance().bindings(command.id))
            QVERIFY(keymap::Registry::instance()
                        .conflicts(command.id, keymap::Context::Global, sequence)
                        .isEmpty());
    }
    // Note-length editing rides the shared timeline seam beside the nudges:
    // Shift+Right lengthens, Shift+Left shortens. The conflict loop above
    // already proves neither default collides with any other command.
    const keymap::CommandInfo lengthenNote =
        keymap::Registry::instance().command(QStringLiteral("roll.lengthen_note"));
    QCOMPARE(int(lengthenNote.context), int(keymap::Context::Timeline));
    QCOMPARE(lengthenNote.category, QStringLiteral("Piano Roll"));
    QCOMPARE(lengthenNote.defaults,
             QList<QKeySequence>{QKeySequence(QStringLiteral("Shift+Right"))});

    const keymap::CommandInfo shortenNote =
        keymap::Registry::instance().command(QStringLiteral("roll.shorten_note"));
    QCOMPARE(int(shortenNote.context), int(keymap::Context::Timeline));
    QCOMPARE(shortenNote.category, QStringLiteral("Piano Roll"));
    QCOMPARE(shortenNote.defaults, QList<QKeySequence>{QKeySequence(QStringLiteral("Shift+Left"))});
}

void KeymapCheckTest::preferencesDefaultBinding()
{
    QList<QKeySequence> expected = QKeySequence::keyBindings(QKeySequence::Preferences);
    if (expected.isEmpty())
        expected.append(QKeySequence(QStringLiteral("Ctrl+,")));

    QCOMPARE(keymap::Registry::instance().command(QStringLiteral("edit.preferences")).defaults,
             expected);
}

void KeymapCheckTest::defaultMatching_data()
{
    QTest::addColumn<QString>("id");
    QTest::addColumn<int>("key");
    QTest::addColumn<Qt::KeyboardModifiers>("modifiers");
    QTest::addColumn<bool>("expected");

    QTest::newRow("semitone-up") << QStringLiteral("roll.transpose_up") << int(Qt::Key_Up)
                                 << Qt::KeyboardModifiers(Qt::NoModifier) << true;
    QTest::newRow("shift-not-semitone") << QStringLiteral("roll.transpose_up") << int(Qt::Key_Up)
                                        << Qt::KeyboardModifiers(Qt::ShiftModifier) << false;
    QTest::newRow("octave-up") << QStringLiteral("roll.transpose_up_octave") << int(Qt::Key_Up)
                               << Qt::KeyboardModifiers(Qt::ShiftModifier) << true;
    QTest::newRow("keypad-up") << QStringLiteral("roll.transpose_up") << int(Qt::Key_Up)
                               << Qt::KeyboardModifiers(Qt::KeypadModifier) << true;
    QTest::newRow("delete") << QStringLiteral("roll.delete") << int(Qt::Key_Delete)
                            << Qt::KeyboardModifiers(Qt::NoModifier) << true;
    QTest::newRow("backspace") << QStringLiteral("roll.delete") << int(Qt::Key_Backspace)
                               << Qt::KeyboardModifiers(Qt::NoModifier) << true;
    QTest::newRow("copy") << QStringLiteral("roll.copy") << int(Qt::Key_C)
                          << Qt::KeyboardModifiers(Qt::ControlModifier) << true;
    QTest::newRow("mute") << QStringLiteral("roll.mute_tracks") << int(Qt::Key_M)
                          << Qt::KeyboardModifiers(Qt::NoModifier) << true;
    QTest::newRow("control-not-mute") << QStringLiteral("roll.mute_tracks") << int(Qt::Key_M)
                                      << Qt::KeyboardModifiers(Qt::ControlModifier) << false;
    QTest::newRow("solo") << QStringLiteral("roll.solo_tracks") << int(Qt::Key_S)
                          << Qt::KeyboardModifiers(Qt::NoModifier) << true;
    QTest::newRow("automation-pencil") << QStringLiteral("automation.pencil_mode") << int(Qt::Key_B)
                                       << Qt::KeyboardModifiers(Qt::NoModifier) << true;
    QTest::newRow("pitch-bend") << QStringLiteral("roll.pitch_bend") << int(Qt::Key_G)
                                << Qt::KeyboardModifiers(Qt::NoModifier) << true;
    QTest::newRow("play-pause") << QStringLiteral("transport.play_pause") << int(Qt::Key_Space)
                                << Qt::KeyboardModifiers(Qt::NoModifier) << true;
    QTest::newRow("control-not-play-pause")
        << QStringLiteral("transport.play_pause") << int(Qt::Key_Space)
        << Qt::KeyboardModifiers(Qt::ControlModifier) << false;
    QTest::newRow("insert-time") << QStringLiteral("edit.insert_time") << int(Qt::Key_I)
                                 << Qt::KeyboardModifiers(Qt::ControlModifier | Qt::ShiftModifier)
                                 << true;
    QTest::newRow("duplicate-time") << QStringLiteral("roll.duplicate_time") << int(Qt::Key_D)
                                    << Qt::KeyboardModifiers(Qt::ControlModifier) << true;
    QTest::newRow("lengthen-note") << QStringLiteral("roll.lengthen_note") << int(Qt::Key_Right)
                                   << Qt::KeyboardModifiers(Qt::ShiftModifier) << true;
    QTest::newRow("plain-right-not-lengthen")
        << QStringLiteral("roll.lengthen_note") << int(Qt::Key_Right)
        << Qt::KeyboardModifiers(Qt::NoModifier) << false;
    QTest::newRow("shorten-note") << QStringLiteral("roll.shorten_note") << int(Qt::Key_Left)
                                  << Qt::KeyboardModifiers(Qt::ShiftModifier) << true;
    QTest::newRow("plain-left-not-shorten")
        << QStringLiteral("roll.shorten_note") << int(Qt::Key_Left)
        << Qt::KeyboardModifiers(Qt::NoModifier) << false;
}

void KeymapCheckTest::defaultMatching()
{
    QFETCH(QString, id);
    QFETCH(int, key);
    QFETCH(Qt::KeyboardModifiers, modifiers);
    QFETCH(bool, expected);

    QCOMPARE(matches(id, key, modifiers), expected);
}

void KeymapCheckTest::overrideReplacesDefaultAndPersists()
{
    auto &registry = keymap::Registry::instance();
    const QString transposeUp = QStringLiteral("roll.transpose_up");
    registry.setBinding(transposeUp, QKeySequence(QStringLiteral("Alt+T")));
    QVERIFY(matches(transposeUp, Qt::Key_T, Qt::AltModifier));
    QVERIFY(!matches(transposeUp, Qt::Key_Up, Qt::NoModifier));
    QVERIFY(registry.isOverridden(transposeUp));
    QCOMPARE(QSettings().value(QStringLiteral("keymap/") + transposeUp).toString(),
             QStringLiteral("Alt+T"));
    QVERIFY(!QSettings().contains(QStringLiteral("keymap/roll.transpose_down")));

    const QString duplicateTime = QStringLiteral("roll.duplicate_time");
    registry.setBinding(duplicateTime, QKeySequence(QStringLiteral("Alt+D")));
    QCOMPARE(registry.bindings(duplicateTime),
             QList<QKeySequence>{QKeySequence(QStringLiteral("Alt+D"))});
    QCOMPARE(QSettings().value(QStringLiteral("keymap/") + duplicateTime).toString(),
             QStringLiteral("Alt+D"));
    QVERIFY(keymap::Registry::instance()
                .conflicts(duplicateTime, keymap::Context::Global,
                           QKeySequence(QStringLiteral("Alt+D")))
                .isEmpty());
    registry.resetBinding(duplicateTime);
    QVERIFY(!registry.isOverridden(duplicateTime));
    QVERIFY(matches(duplicateTime, Qt::Key_D, Qt::ControlModifier));
}

void KeymapCheckTest::unbindPersistsEmptyDelta()
{
    auto &registry = keymap::Registry::instance();
    const QString nudgeLeft = QStringLiteral("roll.nudge_left");
    registry.setBinding(nudgeLeft, QKeySequence());
    QVERIFY(!matches(nudgeLeft, Qt::Key_Left, Qt::NoModifier));
    QVERIFY(registry.bindings(nudgeLeft).isEmpty());
    QVERIFY(QSettings().contains(QStringLiteral("keymap/") + nudgeLeft));
}

void KeymapCheckTest::resetSemantics()
{
    auto &registry = keymap::Registry::instance();
    const QString transposeUp = QStringLiteral("roll.transpose_up");
    registry.setBinding(transposeUp, QKeySequence(QStringLiteral("Alt+T")));
    registry.resetBinding(transposeUp);
    QVERIFY(matches(transposeUp, Qt::Key_Up, Qt::NoModifier));
    QVERIFY(!QSettings().contains(QStringLiteral("keymap/") + transposeUp));

    registry.setBinding(QStringLiteral("view.event_list"),
                        QKeySequence(QStringLiteral("Ctrl+Shift+E")));
    QVERIFY(!QSettings().contains(QStringLiteral("keymap/view.event_list")));
    registry.setBinding(QStringLiteral("roll.nudge_left"), QKeySequence());
    registry.resetAll();
    QVERIFY(!QSettings().contains(QStringLiteral("keymap/roll.nudge_left")));
    QVERIFY(matches(QStringLiteral("roll.nudge_left"), Qt::Key_Left, Qt::NoModifier));
}

void KeymapCheckTest::snapshotRestore()
{
    auto &registry = keymap::Registry::instance();
    QSettings settings;
    settings.setValue(QStringLiteral("keymap/future.command"), QString());
    settings.sync();
    const keymap::Registry::OverrideSnapshot snapshot = registry.snapshotOverrides();

    registry.setBinding(QStringLiteral("roll.nudge_left"),
                        QKeySequence(QStringLiteral("Alt+Left")));
    settings.setValue(QStringLiteral("keymap/future.command"), QStringLiteral("changed"));
    settings.setValue(QStringLiteral("keymap/added.later"), QStringLiteral("Ctrl+9"));
    settings.sync();
    registry.restoreOverrides(snapshot);
    settings.sync();

    QVERIFY(matches(QStringLiteral("roll.nudge_left"), Qt::Key_Left, Qt::NoModifier));
    QVERIFY(settings.contains(QStringLiteral("keymap/future.command")));
    QCOMPARE(settings.value(QStringLiteral("keymap/future.command")).toString(), QString());
    QVERIFY(!settings.contains(QStringLiteral("keymap/added.later")));
}

void KeymapCheckTest::attachedActionTracksBinding()
{
    auto &registry = keymap::Registry::instance();
    auto action = std::make_unique<QAction>(QStringLiteral("Go to Start"));
    registry.attach(QStringLiteral("transport.go_to_start"), action.get());
    QCOMPARE(action->shortcut(), QKeySequence(Qt::Key_Home));

    registry.setBinding(QStringLiteral("transport.go_to_start"),
                        QKeySequence(QStringLiteral("Ctrl+Home")));
    QCOMPARE(action->shortcut(), QKeySequence(QStringLiteral("Ctrl+Home")));
    action.reset();
    registry.resetBinding(QStringLiteral("transport.go_to_start"));
}

void KeymapCheckTest::conflicts_data()
{
    QTest::addColumn<QString>("id");
    QTest::addColumn<int>("context");
    QTest::addColumn<QKeySequence>("sequence");
    QTest::addColumn<QString>("expectedConflict");

    QTest::newRow("global-overlaps-piano-roll")
        << QStringLiteral("roll.copy") << int(keymap::Context::PianoRoll)
        << QKeySequence(QStringLiteral("Ctrl+S")) << QStringLiteral("file.save_song");
    QTest::newRow("same-context-overlaps")
        << QStringLiteral("roll.cut") << int(keymap::Context::PianoRoll)
        << QKeySequence(QStringLiteral("Ctrl+C")) << QStringLiteral("roll.copy");
    QTest::newRow("unused-sequence")
        << QStringLiteral("roll.copy") << int(keymap::Context::PianoRoll)
        << QKeySequence(QStringLiteral("Alt+9")) << QString();
}

void KeymapCheckTest::conflicts()
{
    QFETCH(QString, id);
    QFETCH(int, context);
    QFETCH(QKeySequence, sequence);
    QFETCH(QString, expectedConflict);

    const QStringList conflicts =
        keymap::Registry::instance().conflicts(id, static_cast<keymap::Context>(context), sequence);
    if (expectedConflict.isEmpty())
        QVERIFY(conflicts.isEmpty());
    else
        QVERIFY(conflicts.contains(expectedConflict));
}

void KeymapCheckTest::routedCommandConflicts_data()
{
    QTest::addColumn<QString>("id");
    QTest::addColumn<bool>("conflictsInEventList");

    struct RoutedCommand {
        const char *id;
        bool conflictsWithEventList;
    };
    // Every shared timeline command overlaps Piano Roll, Velocity, and
    // Automation. Only window-owned Copy and Solo (Global) also overlap the
    // Event List; the global Insert Time command stays here to prove its own
    // scope.
    // One row per command: the test binds the command once to the temporary
    // probe key and checks conflicts() for all four routed contexts against
    // the expectations derived from this flag.
    static constexpr std::array routedCommands = {
        RoutedCommand{"roll.copy", true},
        RoutedCommand{"roll.cut", false},
        RoutedCommand{"roll.duplicate_time", false},
        RoutedCommand{"roll.paste", false},
        RoutedCommand{"roll.select_all", false},
        RoutedCommand{"roll.delete", false},
        RoutedCommand{"roll.pitch_bend", false},
        RoutedCommand{"roll.transpose_up", false},
        RoutedCommand{"roll.transpose_down", false},
        RoutedCommand{"roll.transpose_up_octave", false},
        RoutedCommand{"roll.transpose_down_octave", false},
        RoutedCommand{"roll.nudge_left", false},
        RoutedCommand{"roll.nudge_right", false},
        RoutedCommand{"roll.mute_tracks", false},
        RoutedCommand{"roll.grid_narrow", false},
        RoutedCommand{"roll.grid_widen", false},
        RoutedCommand{"roll.grid_triplet", false},
        RoutedCommand{"roll.solo_tracks", true},
        RoutedCommand{"edit.insert_time", true},
    };
    for (const RoutedCommand &command : routedCommands)
        QTest::newRow(command.id) << QString(QLatin1String(command.id))
                                  << command.conflictsWithEventList;
}

void KeymapCheckTest::routedCommandConflicts()
{
    QFETCH(QString, id);
    QFETCH(bool, conflictsInEventList);

    auto &registry = keymap::Registry::instance();
    const QString probeId = QStringLiteral("keymapcheck.temporary_probe");
    const QKeySequence temporaryBinding(QStringLiteral("Alt+9"));
    struct ProbedContext {
        keymap::Context context;
        const char *name;
    };
    static constexpr std::array probedContexts = {
        ProbedContext{keymap::Context::PianoRoll, "piano-roll"},
        ProbedContext{keymap::Context::Velocity, "velocity"},
        ProbedContext{keymap::Context::Automation, "automation"},
        ProbedContext{keymap::Context::EventList, "event-list"},
    };
    const auto probeConflicts = [&registry, &probeId,
                                 &temporaryBinding](keymap::Context context) -> QStringList {
        return registry.conflicts(probeId, context, temporaryBinding);
    };

    // Before the temporary bind the probe key must be free in every probed scope.
    for (const ProbedContext &probed : probedContexts) {
        QVERIFY2(probeConflicts(probed.context).isEmpty(),
                 qPrintable(QStringLiteral("Alt+9 probe is already in use in the %1 context")
                                .arg(QString::fromLatin1(probed.name))));
    }

    registry.setBinding(id, temporaryBinding);

    for (const ProbedContext &probed : probedContexts) {
        const bool expectedConflict =
            probed.context == keymap::Context::EventList ? conflictsInEventList : true;
        const QStringList conflicts = probeConflicts(probed.context);
        QVERIFY2(
            conflicts.contains(id) == expectedConflict,
            qPrintable(QStringLiteral("%1 bound to Alt+9 in the %2 context: expected %3, got %4")
                           .arg(id, QString::fromLatin1(probed.name),
                                expectedConflict ? QStringLiteral("a conflict")
                                                 : QStringLiteral("no conflict"),
                                conflicts.isEmpty() ? QStringLiteral("none")
                                                    : conflicts.join(QLatin1String(", ")))));
    }

    registry.resetBinding(id);
    QVERIFY2(!registry.isOverridden(id),
             qPrintable(QStringLiteral("temporary binding on %1 was not restored").arg(id)));
    for (const ProbedContext &probed : probedContexts) {
        QVERIFY2(
            probeConflicts(probed.context).isEmpty(),
            qPrintable(QStringLiteral("Alt+9 probe remained in use in the %1 context after reset")
                           .arg(QString::fromLatin1(probed.name))));
    }
}

void KeymapCheckTest::modifierChords()
{
    auto &registry = keymap::Registry::instance();
    const QString dragId = QStringLiteral("roll.velocity_drag");
    const QString unlockId = QStringLiteral("velocity.detent_unlock");

    QVERIFY(registry.command(dragId).modifier);
    QCOMPARE(registry.modifierBinding(dragId), Qt::ControlModifier);
    QVERIFY(registry.bindings(dragId).isEmpty());
    QVERIFY(!matches(dragId, Qt::Key_C, Qt::ControlModifier));

    registry.setModifierBinding(dragId, Qt::AltModifier);
    QCOMPARE(registry.modifierBinding(dragId), Qt::AltModifier);
    QVERIFY(registry.matchesModifier(Qt::AltModifier, dragId));
    QVERIFY(registry.isOverridden(dragId));
    QCOMPARE(QSettings().value(QStringLiteral("keymap/") + dragId).toString(),
             QStringLiteral("Alt"));
    registry.setModifierBinding(dragId, Qt::ControlModifier);
    QVERIFY(!registry.isOverridden(dragId));

    registry.setModifierBinding(dragId, Qt::NoModifier);
    QCOMPARE(registry.modifierBinding(dragId), Qt::NoModifier);
    QVERIFY(registry.isOverridden(dragId));
    registry.resetBinding(dragId);
    QCOMPARE(registry.modifierBinding(dragId), Qt::ControlModifier);

    registry.setModifierBinding(dragId, Qt::AltModifier);
    const keymap::Registry::OverrideSnapshot snapshot = registry.snapshotOverrides();
    registry.setModifierBinding(dragId, Qt::ShiftModifier);
    registry.restoreOverrides(snapshot);
    QCOMPARE(registry.modifierBinding(dragId), Qt::AltModifier);
    registry.resetAll();
    QCOMPARE(registry.modifierBinding(dragId), Qt::ControlModifier);

    QSettings().setValue(QStringLiteral("keymap/") + dragId, QStringLiteral("Ctrl+F5"));
    QCOMPARE(registry.modifierBinding(dragId), Qt::ControlModifier);
    registry.resetBinding(dragId);

    QCOMPARE(keymap::Registry::modifierFromText(QStringLiteral("ctrl+shift")),
             Qt::ControlModifier | Qt::ShiftModifier);
    QCOMPARE(keymap::Registry::modifierText(Qt::ControlModifier | Qt::ShiftModifier),
             QStringLiteral("Ctrl+Shift"));
    QCOMPARE(keymap::Registry::modifierFromText(QStringLiteral("Ctrl+F5")), Qt::NoModifier);

    QVERIFY(registry.command(unlockId).modifier);
    const auto detent = registry.command(unlockId);
    QCOMPARE(registry.modifierBinding(unlockId), Qt::ControlModifier);
    QVERIFY(registry.bindings(unlockId).isEmpty());
    QVERIFY(!matches(unlockId, Qt::Key_C, Qt::ControlModifier));
    QVERIFY(!registry.modifierConflicts(unlockId, detent.context, Qt::ControlModifier)
                 .contains(dragId));
    QVERIFY(registry.modifierConflicts(unlockId, keymap::Context::Global, Qt::ControlModifier)
                .contains(dragId));

    registry.setModifierBinding(unlockId, Qt::AltModifier);
    QCOMPARE(registry.modifierBinding(unlockId), Qt::AltModifier);
    QCOMPARE(QSettings().value(QStringLiteral("keymap/") + unlockId).toString(),
             QStringLiteral("Alt"));
    registry.setModifierBinding(unlockId, Qt::ControlModifier);
    QVERIFY(!registry.isOverridden(unlockId));
    registry.setModifierBinding(unlockId, Qt::NoModifier);
    QCOMPARE(registry.modifierBinding(unlockId), Qt::NoModifier);
    registry.resetBinding(unlockId);
    QCOMPARE(registry.modifierBinding(unlockId), Qt::ControlModifier);
}
