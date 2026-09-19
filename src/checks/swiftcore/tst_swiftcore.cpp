#include "tst_swiftcore.h"

#include "core_check.h"
#include "oracle_check.h"

#include <QDebug>
#include <QFile>
#include <QtTest/QTest>

namespace {

void reportSwiftCheck(void *, int failed, const char *cppId, const char *message)
{
    const QString identity = QString::fromUtf8(cppId ? cppId : "swiftcore/unknown");
    const QString detail = QString::fromUtf8(message ? message : "");
    if (failed) {
        const QString failure = QStringLiteral("cppId=%1: %2").arg(identity, detail);
        QTest::qFail(qPrintable(failure), cppId ? cppId : "swiftcore", 0);
        return;
    }
    qInfo().noquote() << QStringLiteral("swiftcore PASS cppId=%1: %2").arg(identity, detail);
}

} // namespace

void SwiftCoreTest::midiCodec()
{
    pdc_suite_run(PDC_SUITE_MIDI_CODEC, reportSwiftCheck, this);
}

void SwiftCoreTest::musicalSemantics()
{
    pdc_suite_run(PDC_SUITE_MUSICAL_SEMANTICS, reportSwiftCheck, this);
}

void SwiftCoreTest::playback()
{
    pdc_suite_run(PDC_SUITE_PLAYBACK, reportSwiftCheck, this);
}

int runSwiftCoreCheck(const QString &fixtureRoot, const QStringList &qtArguments)
{
    const QByteArray encodedRoot = QFile::encodeName(fixtureRoot);
    oracle_check_set_fixture_root(encodedRoot.constData());
    SwiftCoreTest test;
    // qExec treats arguments[0] as the program name; without it the first
    // payload token is consumed and function selection silently stops.
    QStringList arguments{QStringLiteral("swiftcore")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
