#include "tst_swiftcore.h"

#include "core_check.h"
#include "native_check.h"

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

void SwiftCoreTest::noteEdits()
{
    pdc_suite_run(PDC_SUITE_NOTE_EDITS, reportSwiftCheck, this);
}

void SwiftCoreTest::documentHistory()
{
    pdc_suite_run(PDC_SUITE_DOCUMENT_HISTORY, reportSwiftCheck, this);
}

void SwiftCoreTest::eventEdits()
{
    pdc_suite_run(PDC_SUITE_EVENT_EDITS, reportSwiftCheck, this);
}

void SwiftCoreTest::xcmdEdits()
{
    pdc_suite_run(PDC_SUITE_XCMD_EDITS, reportSwiftCheck, this);
}

void SwiftCoreTest::midiImport()
{
    pdc_suite_run(PDC_SUITE_MIDI_IMPORT, reportSwiftCheck, this);
}

void SwiftCoreTest::timeEdits()
{
    pdc_suite_run(PDC_SUITE_TIME_EDITS, reportSwiftCheck, this);
}

void SwiftCoreTest::projectSession()
{
    pdc_suite_run(PDC_SUITE_PROJECT_SESSION, reportSwiftCheck, this);
}

void SwiftCoreTest::bankHistory()
{
    pdc_suite_run(PDC_SUITE_BANK_HISTORY, reportSwiftCheck, this);
}

void SwiftCoreTest::projectIdentity()
{
    pdc_suite_run(PDC_SUITE_PROJECT_IDENTITY, reportSwiftCheck, this);
}

void SwiftCoreTest::songModel()
{
    pdc_suite_run(PDC_SUITE_SONG_MODEL, reportSwiftCheck, this);
}

void SwiftCoreTest::midiCfg()
{
    pdc_suite_run(PDC_SUITE_MIDI_CFG, reportSwiftCheck, this);
}

void SwiftCoreTest::songsMk()
{
    pdc_suite_run(PDC_SUITE_SONGS_MK, reportSwiftCheck, this);
}

void SwiftCoreTest::songCatalog()
{
    pdc_suite_run(PDC_SUITE_SONG_CATALOG, reportSwiftCheck, this);
}

void SwiftCoreTest::synthCatalog()
{
    pdc_suite_run(PDC_SUITE_SYNTH_CATALOG, reportSwiftCheck, this);
}

void SwiftCoreTest::voicegroupValues()
{
    pdc_suite_run(PDC_SUITE_VOICE_VALUES, reportSwiftCheck, this);
}

void SwiftCoreTest::saveCore()
{
    pdc_suite_run(PDC_SUITE_SAVECORE, reportSwiftCheck, this);
}

void SwiftCoreTest::voicegroupEditing()
{
    pdc_suite_run(PDC_SUITE_VOICE_EDITING, reportSwiftCheck, this);
}

void SwiftCoreTest::catalogAbsent()
{
    pdc_suite_run(PDC_SUITE_CATALOG_ABSENT, reportSwiftCheck, this);
}

void SwiftCoreTest::projectStoreChecks()
{
    pdc_suite_run(PDC_SUITE_PROJECTSTORE_CHECKS, reportSwiftCheck, this);
}

void SwiftCoreTest::voicegroupContext()
{
    pdc_suite_run(PDC_SUITE_VOICE_CONTEXT, reportSwiftCheck, this);
}

void SwiftCoreTest::voicegroupBankLogic()
{
    pdc_suite_run(PDC_SUITE_VOICE_BANKLOGIC, reportSwiftCheck, this);
}

void SwiftCoreTest::projectStoreActor()
{
    pdc_suite_run(PDC_SUITE_PROJECTSTORE_ACTOR, reportSwiftCheck, this);
}

void SwiftCoreTest::projectStoreOpen()
{
    pdc_suite_run(PDC_SUITE_PROJECTSTORE_OPEN, reportSwiftCheck, this);
}

void SwiftCoreTest::projectStoreReads()
{
    pdc_suite_run(PDC_SUITE_PROJECTSTORE_READS, reportSwiftCheck, this);
}

void SwiftCoreTest::projectStoreLoadBank()
{
    pdc_suite_run(PDC_SUITE_PROJECTSTORE_LOADBANK, reportSwiftCheck, this);
}

void SwiftCoreTest::projectStoreEdit()
{
    pdc_suite_run(PDC_SUITE_PROJECTSTORE_EDIT, reportSwiftCheck, this);
}

void SwiftCoreTest::projectStoreSave()
{
    pdc_suite_run(PDC_SUITE_PROJECTSTORE_SAVE, reportSwiftCheck, this);
}

void SwiftCoreTest::bankLeases()
{
    pdc_suite_run(PDC_SUITE_BANK_LEASES, reportSwiftCheck, this);
}

int runSwiftCoreCheck(const QString &fixtureRoot, const QStringList &qtArguments)
{
    const QByteArray encodedRoot = QFile::encodeName(fixtureRoot);
    pdc_check_set_fixture_root(encodedRoot.constData());

    QStringList selectedArguments = qtArguments;
    const QString compilerPrefix = QStringLiteral("--pdc-mid2agb=");
    if (!selectedArguments.isEmpty() && selectedArguments.front().startsWith(compilerPrefix)) {
        const QByteArray encodedCompiler =
            QFile::encodeName(selectedArguments.takeFirst().mid(compilerPrefix.size()));
        pdc_check_set_mid2agb_path(encodedCompiler.constData());
    } else {
        pdc_check_set_mid2agb_path(nullptr);
    }

    SwiftCoreTest test;
    // qExec treats arguments[0] as the program name; without it the first
    // payload token is consumed and function selection silently stops.
    QStringList arguments{QStringLiteral("swiftcore")};
    arguments.append(selectedArguments);
    return QTest::qExec(&test, arguments);
}
