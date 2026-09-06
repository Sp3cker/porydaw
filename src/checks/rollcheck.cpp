#include "checks/fwd.hpp"
#include "checks/rollcheck/tst_pianoroll.h"

#include <QtTest>

#include <optional>
#include <utility>

#include "checks/rollcheck/rollcheck.h"
#include "checks/support/songfixture.h"
#include "core/tracklimits.h"
#include "project/projectidentity.h"
#include "ui/songtab.h"

PianoRollTest::PianoRollTest(const QString &projectRoot, const QString &songLabel)
    : m_projectRoot(projectRoot)
    , m_songLabel(songLabel)
{}

PianoRollTest::~PianoRollTest() = default;

void PianoRollTest::init()
{
    QString error;
    m_project = checks::ProjectFixture::copyOf(m_projectRoot, error);
    QVERIFY2(m_project, qPrintable(error));

    const std::unique_ptr<checks::LoadedSong> loaded =
        checks::LoadedSong::load(m_project->root(), m_songLabel, error);
    QVERIFY2(loaded, qPrintable(error));

    const std::optional<SongName> name = SongName::create(m_songLabel);
    QVERIFY(name.has_value());
    m_bank = std::make_unique<LoadedVoiceGroup>();
    m_bank->voices[0].type = VOICE_DIRECTSOUND;
    m_bank->voices[1].type = VOICE_SQUARE_1;
    m_bank->voices[2].type = VOICE_PROGRAMMABLE_WAVE;
    m_bank->voices[3].type = VOICE_NOISE;

    m_tab = std::make_unique<SongTab>(std::move(*name));
    m_tab->setSampleRate(48000.0);
    m_tab->applyMidiStage(loaded->songInfo(), loaded->document().smf(),
                          track_limits::kHardwareCapacity);
    QVERIFY2(m_tab->presentationError().isEmpty(), qPrintable(m_tab->presentationError()));

    const std::optional<VoicegroupId> bankId =
        VoicegroupId::create(QStringLiteral("sound/voicegroups/rollcheck.inc"), QString());
    QVERIFY(bankId.has_value());
    m_tab->applyBankView(LoadedBankView{*bankId, borrowVoicegroupLease(m_bank.get()), QString()});
    m_tab->applyVoicegroupBound(*bankId);
    QTRY_VERIFY(m_tab->isReady());

    m_fixture = std::make_unique<checks::rollcheck::PianoRollFixture>(*m_tab, m_songLabel);
    QVERIFY(m_fixture->prepare());
}

void PianoRollTest::cleanup()
{
    m_fixture.reset();
    m_tab.reset();
    m_bank.reset();
    m_project.reset();
}

// Aggregate rollback disposition: removed.  Each transactional row below owns
// its post-seed undo baseline and proves byte-for-byte SMF restoration locally.
// Identity/remap/header rows use isolated documents; interlock and selection
// raster are explicitly undo-neutral; scale rows retain their own lifecycle
// probes and now also restore their local byte baseline.  No slot depends on
// another slot's mutations.
// B3 disposition: retain the legacy device-pixel samples and their documented
// tolerances in the raster rows.  They already use the captured image DPR;
// no new theme or DPR permutation is added because it would be new coverage,
// not a migration of a legacy contract.

int runRollCheck(const QString &projectRoot, const QString &songLabel,
                 const QStringList &qtArguments)
{
    PianoRollTest test(projectRoot, songLabel);
    QStringList arguments{QStringLiteral("rollcheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
