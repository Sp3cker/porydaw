#include "checks/keyboard/tst_keymapcheck.h"

#include <QKeyEvent>
#include <QSettings>
#include <QStringList>
#include <QtTest>

void KeymapCheckTest::initTestCase()
{
    QVERIFY2(m_settingsDirectory.isValid(), "could not create isolated QSettings directory");
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_settingsDirectory.path());
    QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, m_settingsDirectory.path());
    QSettings settings;
    settings.setValue(QStringLiteral("keymap/roll.transpose_up"), QStringLiteral("Ctrl+Alt+U"));
    settings.setValue(QStringLiteral("keymap/transport.play_pause"), QString());
    settings.setValue(QStringLiteral("keymap/roll.velocity_drag"), QStringLiteral("Shift"));
    settings.setValue(QStringLiteral("keymap/velocity.detent_unlock"), QString());
    settings.sync();
}

bool KeymapCheckTest::matches(const QString &id, int key, Qt::KeyboardModifiers modifiers) const
{
    QKeyEvent event(QEvent::KeyPress, key, modifiers);
    return keymap::Registry::instance().matches(&event, id);
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
}

void KeymapCheckTest::defaultMatching()
{
    QFETCH(QString, id);
    QFETCH(int, key);
    QFETCH(Qt::KeyboardModifiers, modifiers);
    QFETCH(bool, expected);

    QCOMPARE(matches(id, key, modifiers), expected);
}

void KeymapCheckTest::modifierChords()
{
    const auto &registry = keymap::Registry::instance();
    const QString dragId = QStringLiteral("roll.velocity_drag");
    const QString detentId = QStringLiteral("velocity.detent_unlock");

    QVERIFY(registry.matchesModifier(Qt::ControlModifier, detentId));

    QVERIFY(registry.matchesModifier(Qt::ControlModifier, dragId));
    QVERIFY(registry.matchesModifier(Qt::ControlModifier | Qt::KeypadModifier, dragId));
    QVERIFY(!registry.matchesModifier(Qt::ControlModifier | Qt::ShiftModifier, dragId));
}

int runKeymapCheck(const QStringList &qtArguments)
{
    KeymapCheckTest test;
    QStringList arguments{QStringLiteral("keymapcheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
