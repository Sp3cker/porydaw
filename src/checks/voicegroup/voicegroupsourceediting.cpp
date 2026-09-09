#include "checks/voicegroup/tst_voicegroupsource.h"

#include <cstring>
#include <optional>
#include <utility>

#include <QDir>
#include <QTemporaryDir>
#include <QtTest>

#include "checks/voicegroup/voicegrouptestfixture.h"
#include "core/m4asemantics.h"
#include "project/songregistry.h"

namespace {

int changedLineCount(const QByteArray &before, const QByteArray &after)
{
    const QList<QByteArray> beforeLines = before.split('\n');
    const QList<QByteArray> afterLines = after.split('\n');
    if (beforeLines.size() != afterLines.size())
        return -1;
    int changed = 0;
    for (qsizetype line = 0; line < beforeLines.size(); ++line)
        changed += beforeLines[line] != afterLines[line];
    return changed;
}

int firstSlot(const VoicegroupSource &source, bool (*matches)(VgMacro))
{
    for (int slot = 0; slot < VOICEGROUP_SIZE; ++slot) {
        const VgVoice *const voice = source.voiceAt(slot);
        if (voice && matches(voice->macro))
            return slot;
    }
    return -1;
}

int firstMacro(const VoicegroupSource &source, VgMacro macro)
{
    for (int slot = 0; slot < VOICEGROUP_SIZE; ++slot) {
        const VgVoice *const voice = source.voiceAt(slot);
        if (voice && voice->macro == macro)
            return slot;
    }
    return -1;
}

int firstMacroWithSymbol(const VoicegroupSource &source, VgMacro macro, const QString &symbol,
                         int exceptSlot)
{
    for (int slot = 0; slot < VOICEGROUP_SIZE; ++slot) {
        const VgVoice *const voice = source.voiceAt(slot);
        if (slot != exceptSlot && voice && voice->macro == macro && voice->symbol == symbol)
            return slot;
    }
    return -1;
}

} // namespace

VoicegroupSourceTest::VoicegroupSourceTest(QString stagedRoot, QString songLabel)
    : m_songLabel(std::move(songLabel))
    , m_stagedRoot(std::move(stagedRoot))
{}

VoicegroupSourceTest::~VoicegroupSourceTest() = default;

void VoicegroupSourceTest::init()
{
    QString error;
    m_session = voicegroup_test::openSession(m_stagedRoot, m_songLabel, error);
    QVERIFY2(m_session, qPrintable(error));
}

void VoicegroupSourceTest::blankSlotCreateAndRestore()
{
    QVERIFY(m_session);
    VoicegroupSource &source = m_session->source;
    auto blankSlot = -1;
    for (int slot = 0; slot < VOICEGROUP_SIZE; ++slot) {
        if (source.kindAt(slot) == VgLineKind::None) {
            blankSlot = slot;
            break;
        }
    }
    QVERIFY2(blankSlot >= 0, "fixture_rich must retain a materializable blank slot");

    const QByteArray before = source.sourceBytes();
    VgVoice created;
    created.macro = VgMacro::Square1;
    created.sustain = 15;
    const std::optional<VgVoiceDraft> draft = source.voiceDraft(blankSlot, created);
    QVERIFY(draft.has_value());
    QVERIFY(draft->materializesBlank);
    QCOMPARE(draft->voice, created);
    QVERIFY(source.setVoice(blankSlot, created));
    QVERIFY(source.voiceAt(blankSlot));
    QCOMPARE(*source.voiceAt(blankSlot), created);
    QVERIFY(source.dirty());
    QVERIFY(source.restoreSourceBytes(before));
    QCOMPARE(source.kindAt(blankSlot), VgLineKind::None);
    QCOMPARE(source.sourceBytes(), before);
    QVERIFY(!source.dirty());
}

void VoicegroupSourceTest::sparseInsertionsSerializeAtBothEnds()
{
    QTemporaryDir temporary;
    QVERIFY(temporary.isValid());
    const QString voices = temporary.filePath(QStringLiteral("sound/voicegroups"));
    QVERIFY(QDir().mkpath(voices));
    QString error;
    QVERIFY2(
        voicegroup_test::writeFile(voices + QStringLiteral("/sparse.inc"),
                                   QByteArrayLiteral("voice_group sparse, 36\n"
                                                     "\tvoice_square_1 60, 0, 0, 2, 0, 0, 15, 0\n"),
                                   error),
        qPrintable(error));

    VoicegroupSource source;
    QVERIFY2(source.open(temporary.path(), QStringLiteral("_sparse"), &error), qPrintable(error));
    VgVoice beforeFirst;
    beforeFirst.macro = VgMacro::Square2;
    beforeFirst.sustain = 15;
    VgVoice afterLast;
    afterLast.macro = VgMacro::Noise;
    afterLast.sustain = 15;
    afterLast.release = 3;
    const VgVoice original = *source.voiceAt(36);
    QCOMPARE(source.kindAt(12), VgLineKind::None);
    QCOMPARE(source.kindAt(80), VgLineKind::None);
    QVERIFY(source.setVoice(12, beforeFirst));
    QVERIFY(source.voiceAt(12));
    QCOMPARE(*source.voiceAt(12), beforeFirst);
    QVERIFY(source.voiceAt(36));
    QCOMPARE(*source.voiceAt(36), original);
    QVERIFY(source.setVoice(80, afterLast));
    QVERIFY(source.voiceAt(80));
    QCOMPARE(*source.voiceAt(80), afterLast);
    QVERIFY2(source.save(&error), qPrintable(error));
    QVERIFY(!source.dirty());

    VoicegroupSource reloaded;
    QVERIFY2(reloaded.open(temporary.path(), QStringLiteral("_sparse"), &error), qPrintable(error));
    QVERIFY(reloaded.voiceAt(12));
    QCOMPARE(*reloaded.voiceAt(12), beforeFirst);
    QVERIFY(reloaded.voiceAt(36));
    QCOMPARE(*reloaded.voiceAt(36), original);
    QVERIFY(reloaded.voiceAt(80));
    QCOMPARE(*reloaded.voiceAt(80), afterLast);
    const QByteArray root = temporary.path().toLocal8Bit();
    LoadedVoiceGroup *const loaded = voicegroup_load(root.constData(), "sparse", nullptr);
    QVERIFY(loaded);
    QCOMPARE(loaded->voices[12].type, uint8_t(VOICE_SQUARE_2));
    QCOMPARE(loaded->voices[36].type, uint8_t(VOICE_SQUARE_1));
    QCOMPARE(loaded->voices[80].type, uint8_t(VOICE_NOISE));
    voicegroup_free(loaded);
}

void VoicegroupSourceTest::editedFamiliesPreviewSaveReloadAndCreate_data()
{
    QTest::addColumn<int>("family");
    QTest::newRow("direct-sound") << 0;
    QTest::newRow("square-1") << 1;
    QTest::newRow("noise") << 2;
    QTest::newRow("programmable-wave") << 3;
    QTest::newRow("keysplit") << 4;
    QTest::newRow("drumkit-swap") << 5;
    QTest::newRow("drumkit-conversion") << 6;
}

void VoicegroupSourceTest::editedFamiliesPreviewSaveReloadAndCreate()
{
    QVERIFY(m_session);
    QFETCH(int, family);
    VoicegroupSource &source = m_session->source;
    const QByteArray fileBefore = voicegroup_test::readFile(source.filePath());

    int slot = -1;
    VgVoice edited;
    QByteArray expectedName;
    bool expectsSubgroup = false;
    int aggregateOracleSlot = -1;
    int auditionKey = 60;
    if (family == 0) {
        slot = firstSlot(source, voicegroup_test::isDirectSound);
        QVERIFY2(slot >= 0, "fixture_rich must retain a DirectSound voice");
        edited = *source.voiceAt(slot);
        edited.key = 61;
        edited.attack = 200;
        edited.decay = 100;
        edited.sustain = 50;
        edited.release = 25;
        const int donor = 1;
        QVERIFY(source.voiceAt(donor));
        edited.symbol = source.voiceAt(donor)->symbol;
        expectedName = voicegroup_test::snapshot(*m_session->baseline, donor).name;
    } else if (family == 1) {
        slot = firstSlot(source, voicegroup_test::isSquare1);
        QVERIFY2(slot >= 0, "fixture_rich must retain a Square 1 voice");
        edited = *source.voiceAt(slot);
        edited.duty = 3;
        edited.sustain = 15;
        edited.sweep = 7;
        expectedName = voicegroup_test::snapshot(*m_session->baseline, slot).name;
    } else if (family == 2) {
        slot = firstSlot(source, voicegroup_test::isNoise);
        QVERIFY2(slot >= 0, "fixture_rich must retain a Noise voice");
        edited = *source.voiceAt(slot);
        edited.period = 1 - (edited.period & 1);
        expectedName = voicegroup_test::snapshot(*m_session->baseline, slot).name;
    } else if (family == 3) {
        slot = firstSlot(source, voicegroup_test::isProgWave);
        QVERIFY2(slot >= 0, "fixture_rich must retain a programmable-wave voice");
        edited = *source.voiceAt(slot);
        edited.release = (edited.release & 7) == 5 ? 6 : 5;
        expectedName = voicegroup_test::snapshot(*m_session->baseline, slot).name;
    } else if (family == 4) {
        slot = firstMacro(source, VgMacro::Keysplit);
        const int donor = slot + 1;
        QVERIFY2(slot >= 0 && source.voiceAt(donor) &&
                     source.voiceAt(donor)->macro == VgMacro::Keysplit,
                 "fixture_rich must retain two Keysplit voices");
        edited = *source.voiceAt(slot);
        edited.symbol = source.voiceAt(donor)->symbol;
        edited.keysplitTable = source.voiceAt(donor)->keysplitTable;
        expectedName = voicegroup_test::snapshot(*m_session->baseline, donor).name;
        expectsSubgroup = true;
        aggregateOracleSlot = donor;
    } else {
        const QStringList drumkits = VoicegroupSource::drumkitInstruments(m_session->root());
        QVERIFY2(drumkits.size() >= 2, "fixture must retain two drumkit definitions");
        if (family == 5) {
            slot = firstMacro(source, VgMacro::KeysplitAll);
            QVERIFY(slot >= 0);
            edited = *source.voiceAt(slot);
            edited.symbol = drumkits.last();
        } else {
            slot = 4;
            QVERIFY(source.voiceAt(slot));
            edited = {};
            edited.macro = VgMacro::KeysplitAll;
            edited.symbol = drumkits.first();
        }
        expectedName = voicegroup_test::loaderVoiceName(edited.symbol);
        expectsSubgroup = true;
        aggregateOracleSlot =
            firstMacroWithSymbol(source, VgMacro::KeysplitAll, edited.symbol, slot);
        QVERIFY2(aggregateOracleSlot >= 0,
                 "fixture must retain the selected drumkit as an existing aggregate");
        auditionKey = 36;
    }

    QVERIFY(source.setVoice(slot, edited));
    QVERIFY(source.dirty());
    const QByteArray previewDirectory = QByteArrayLiteral(".porydaw/vgpreview");
    QVERIFY(QDir().mkpath(m_session->root() + QLatin1Char('/') +
                          QString::fromLatin1(previewDirectory)));
    const QString previewPath = m_session->root() + QLatin1Char('/') +
                                QString::fromLatin1(previewDirectory) + QLatin1Char('/') +
                                source.loadName() + QStringLiteral(".inc");
    QString error;
    QVERIFY2(voicegroup_test::writeFile(previewPath, source.renderPreview(), error),
             qPrintable(error));
    VoicegroupLoaderConfig config{};
    std::strncpy(config.voicegroupPaths[0], previewDirectory.constData(), VG_MAX_PATH_LEN - 1);
    config.voicegroupPathCount = 1;
    const QByteArray root = m_session->rootUtf8();
    const QByteArray loadName = m_session->loadNameUtf8();
    LoadedVoiceGroup *const preview =
        voicegroup_load(root.constData(), loadName.constData(), &config);
    QVERIFY(preview);
    QCOMPARE(voicegroup_test::snapshot(*preview, slot).name, expectedName);
    QCOMPARE(preview->voices[slot].type, vgMacroVoiceType(edited.macro));
    if (expectsSubgroup) {
        QVERIFY(voicegroup_test::sameResolvedTone(
            preview->voices[slot], m_session->baseline->voices[aggregateOracleSlot], auditionKey));
    }
    QVERIFY(voicegroup_test::sameVoiceFields(*source.voiceAt(slot), edited));
    voicegroup_free(preview);
    QCOMPARE(voicegroup_test::readFile(source.filePath()), fileBefore);

    QVERIFY2(source.save(&error), qPrintable(error));
    QVERIFY(!source.dirty());
    QCOMPARE(changedLineCount(fileBefore, voicegroup_test::readFile(source.filePath())), 1);
    LoadedVoiceGroup *const reloaded =
        voicegroup_load(root.constData(), loadName.constData(), nullptr);
    QVERIFY(reloaded);
    const ToneData &tone = reloaded->voices[slot];
    // Keysplit/drumkit records carry no playable key or envelope of their
    // own. Their serialized contract is the aggregate type/name plus the
    // child tone that the engine resolves for a representative MIDI key.
    QCOMPARE(tone.type, vgMacroVoiceType(edited.macro));
    if (expectsSubgroup) {
        QVERIFY(tone.subGroup);
        if (family == 4)
            QVERIFY(tone.keySplitTable);
        QVERIFY(voicegroup_test::sameResolvedTone(
            tone, m_session->baseline->voices[aggregateOracleSlot], auditionKey));
    } else {
        QCOMPARE(tone.key, uint8_t(edited.key));
        QCOMPARE(tone.attack, uint8_t(edited.attack));
        QCOMPARE(tone.decay, uint8_t(edited.decay));
        QCOMPARE(tone.sustain, uint8_t(edited.sustain));
        QCOMPARE(tone.release, uint8_t(edited.release));
        // Sweep rides panSweep and duty packs into wavePointer for square 1;
        // period packs into wavePointer for noise; the pan flag packs into
        // panSweep for the sample/wave families.
        if (family == 0 || family == 3)
            QCOMPARE(tone.panSweep, edited.pan ? uint8_t(0x80 | edited.pan) : uint8_t(0));
        if (family == 1) {
            QCOMPARE(tone.panSweep, uint8_t(edited.sweep));
            QCOMPARE(uintptr_t(tone.wavePointer), uintptr_t(edited.duty & 0x03));
        } else if (family == 2) {
            QCOMPARE(uintptr_t(tone.wavePointer), uintptr_t(edited.period & 0x01));
        }
    }
    QCOMPARE(voicegroup_test::snapshot(*reloaded, slot).name, expectedName);
    for (int untouched = 0; untouched < VOICEGROUP_SIZE; ++untouched) {
        if (untouched != slot)
            QCOMPARE(voicegroup_test::snapshot(*reloaded, untouched),
                     voicegroup_test::snapshot(*m_session->baseline, untouched));
    }
    voicegroup_free(reloaded);

    VoicegroupSource roundTrip;
    QVERIFY2(roundTrip.open(m_session->root(), m_session->song.cfg.voicegroupArg, &error),
             qPrintable(error));
    QVERIFY(!roundTrip.dirty());
    QVERIFY(roundTrip.voiceAt(slot));
    QVERIFY(voicegroup_test::sameVoiceFields(*roundTrip.voiceAt(slot), edited));

    const QString createdName = QStringLiteral("voicegroup_qtest_copy");
    const QString hub = m_session->root() + QStringLiteral("/sound/voice_groups.inc");
    const QByteArray hubBefore = voicegroup_test::readFile(hub);
    QVERIFY2(VoicegroupSource::createVoicegroup(m_session->root(), createdName, source.filePath(),
                                                source.sectionLabel(), &error),
             qPrintable(error));
    QVERIFY2(VoicegroupSource::appendIncludeLine(m_session->root(), createdName, &error),
             qPrintable(error));
    LoadedVoiceGroup *const created =
        voicegroup_load(root.constData(), createdName.toLocal8Bit().constData(), nullptr);
    QVERIFY(created);
    QCOMPARE(voicegroup_test::snapshot(*created, slot).name, expectedName);
    if (expectsSubgroup) {
        QVERIFY(voicegroup_test::sameResolvedTone(
            created->voices[slot], m_session->baseline->voices[aggregateOracleSlot], auditionKey));
    }
    voicegroup_free(created);
    QVERIFY(SongRegistry::voicegroupArgs(m_session->root())
                .contains(QStringLiteral("_voicegroup_qtest_copy")));
    QCOMPARE(voicegroup_test::readFile(hub).split('\n').size(), hubBefore.split('\n').size() + 1);
}

void VoicegroupSourceTest::displayNamesAreStable()
{
    QCOMPARE(vgMacroDisplayName(VgMacro::DirectSound), QStringLiteral("Sample"));
    QCOMPARE(vgMacroDisplayName(VgMacro::DirectSoundNoResample),
             QStringLiteral("Sample (fixed pitch)"));
    QCOMPARE(vgMacroDisplayName(VgMacro::DirectSoundAlt), QStringLiteral("Sample (reverse)"));
    QCOMPARE(m4aVoiceTypeName(VOICE_DIRECTSOUND_NO_RESAMPLE),
             QStringLiteral("Sample (fixed pitch)"));
    QCOMPARE(m4aVoiceTypeName(VOICE_DIRECTSOUND_ALT), QStringLiteral("Sample (reverse)"));
    QCOMPARE(m4aVoiceTypeName(VOICE_KEYSPLIT), QStringLiteral("Sample"));
}
