#include "checks/samplecheck/fixtures.h"
#include "checks/samplecheck/samplecheck.h"

#include <QApplication>
#include <QDialogButtonBox>
#include <QLineEdit>
#include <QPushButton>
#include <QTreeWidget>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <vector>

#include "audio/sampledoc.h"
#include "audio/sampleimport.h"
#include "audio/sf2reader.h"
#include "ui/sf2zonepicker.h"

namespace {
constexpr double kPi = 3.14159265358979323846;
}

namespace samplecheck {

void runSoundFontChecks(Reporter &reporter)
{
    // ---- SoundFont (phase 5): harness-synthesized minimal .sf2 — zone
    // metadata → ImportedSample, reader/front-door refusals, and the zone
    // picker driven offscreen ----
    {
        const int before = reporter.failureCount();
        QString error;

        // 600-frame 16-bit pool: a 441 Hz half-scale sine (frames 0-399,
        // zone "Test Tone") and a linear ramp (frames 400-599, shared by
        // the left-linked and unpitched zones).
        std::vector<qint16> poolRef;
        for (int i = 0; i < 400; i++)
            poolRef.push_back(
                qint16(std::lround(16383.0 * std::sin(2.0 * kPi * 441.0 * i / 22050.0))));
        for (int i = 0; i < 200; i++)
            poolRef.push_back(qint16(i * 100 - 10000));
        QByteArray pool;
        for (const qint16 s : poolRef)
            putU16(&pool, quint16(s));

        auto chunk = [](const char *id, const QByteArray &body) {
            QByteArray c(id, 4);
            putU32(&c, quint32(body.size()));
            c += body;
            if (body.size() & 1)
                c += '\0';
            return c;
        };
        auto list = [&chunk](const char *type, const QByteArray &subs) {
            return chunk("LIST", QByteArray(type, 4) + subs);
        };
        auto name20 = [](QByteArray *out, const char *name) {
            char buf[20] = {};
            std::strncpy(buf, name, 19);
            out->append(buf, 20);
        };
        auto shdrRec = [&name20](QByteArray *out, const char *name, quint32 start, quint32 end,
                                 quint32 loopStart, quint32 loopEndExcl, quint32 rate, quint8 pitch,
                                 qint8 corr, quint16 type) {
            name20(out, name);
            putU32(out, start);
            putU32(out, end);
            putU32(out, loopStart);
            putU32(out, loopEndExcl);
            putU32(out, rate);
            out->append(char(pitch)).append(char(corr));
            putU16(out, 0); // sampleLink
            putU16(out, type);
        };
        // One preset ("TestPreset") over one instrument ("TestInst") whose
        // single zone references sample 0 — enough pdta to prove the
        // grouping-label walk (phdr/pbag/pgen → inst/ibag/igen → shdr).
        auto buildSf2 = [&](const QByteArray &shdr) {
            QByteArray phdr;
            name20(&phdr, "TestPreset");
            putU16(&phdr, 0); // wPreset
            putU16(&phdr, 0); // wBank
            putU16(&phdr, 0); // wPresetBagNdx
            putU32(&phdr, 0);
            putU32(&phdr, 0);
            putU32(&phdr, 0);
            name20(&phdr, "EOP");
            putU16(&phdr, 0);
            putU16(&phdr, 0);
            putU16(&phdr, 1);
            putU32(&phdr, 0);
            putU32(&phdr, 0);
            putU32(&phdr, 0);
            QByteArray pbag;
            putU16(&pbag, 0);
            putU16(&pbag, 0);
            putU16(&pbag, 1);
            putU16(&pbag, 0);
            QByteArray pgen;
            putU16(&pgen, 41); // instrument generator
            putU16(&pgen, 0);
            putU16(&pgen, 0);
            putU16(&pgen, 0);
            QByteArray instData;
            name20(&instData, "TestInst");
            putU16(&instData, 0);
            name20(&instData, "EOI");
            putU16(&instData, 1);
            QByteArray ibag;
            putU16(&ibag, 0);
            putU16(&ibag, 0);
            putU16(&ibag, 1);
            putU16(&ibag, 0);
            QByteArray igen;
            putU16(&igen, 53); // sampleID generator
            putU16(&igen, 0);
            putU16(&igen, 0);
            putU16(&igen, 0);
            QByteArray ifil;
            putU16(&ifil, 2);
            putU16(&ifil, 1);
            QByteArray body("sfbk", 4);
            body +=
                list("INFO", chunk("ifil", ifil) + chunk("INAM", QByteArray("samplecheck\0", 12)));
            body += list("sdta", chunk("smpl", pool));
            body += list("pdta", chunk("phdr", phdr) + chunk("pbag", pbag) +
                                     chunk("pmod", QByteArray(10, '\0')) + chunk("pgen", pgen) +
                                     chunk("inst", instData) + chunk("ibag", ibag) +
                                     chunk("imod", QByteArray(10, '\0')) + chunk("igen", igen) +
                                     chunk("shdr", shdr));
            QByteArray sf2("RIFF", 4);
            putU32(&sf2, quint32(body.size()));
            sf2 += body;
            return sf2;
        };

        QByteArray shdr;
        shdrRec(&shdr, "Test Tone", 0, 400, 100, 300, 22050, 69, -20, 1);
        shdrRec(&shdr, "PadL", 400, 600, 400, 400, 32000, 60, 50, 4);
        shdrRec(&shdr, "RomTone", 0, 400, 0, 0, 22050, 60, 0, 0x8001);
        shdrRec(&shdr, "Unpitched", 400, 600, 0, 0, 22050, 255, 0, 1);
        shdrRec(&shdr, "EOS", 0, 0, 0, 0, 0, 0, 0, 0);
        const QByteArray sf2Bytes = buildSf2(shdr);

        reporter.expect(sf2Magic(sf2Bytes), "sf2 magic sniffs");
        Sf2File font;
        reporter.expect(readSf2Bytes(sf2Bytes, QStringLiteral("f/test.sf2"), &font, &error),
                        "sf2 fixture reads");
        reporter.expect(font.zones.size() == 3, "ROM sample and EOS terminator are skipped");
        if (font.zones.size() == 3) {
            const Sf2Zone &tone = font.zones[0];
            reporter.expect(tone.name == QStringLiteral("Test Tone") &&
                                tone.instrument == QStringLiteral("TestInst") &&
                                tone.preset == QStringLiteral("TestPreset"),
                            "grouping labels resolve through the pdta index arrays");
            reporter.expect(font.zones[1].name == QStringLiteral("PadL") &&
                                font.zones[1].stereoPair() && font.zones[1].instrument.isEmpty(),
                            "left-linked zone flags as a stereo pair, ungrouped");

            ImportedSample z0;
            reporter.expect(extractSf2Zone(font, 0, &z0, &error), "zone 0 extracts");
            reporter.expect(z0.sourceKind == ImportedSample::Sf2 && z0.sourceChannels == 1 &&
                                z0.sourceBits == 16 && !z0.gbaReady && z0.warnings.isEmpty(),
                            "zone 0 structure");
            reporter.expect(z0.frameCount() == 400 && z0.playLength == 400 &&
                                z0.sampleRate == 22050.0,
                            "zone 0 pool segment bounds");
            reporter.expect(z0.hasPitchMetadata && z0.baseKey == 68 &&
                                std::abs(z0.fracSemitone - 0.8) < 1e-9,
                            "negative pitchCorrection renormalizes below the unity "
                            "key");
            reporter.expect(z0.hasLoop && z0.loopStart == 100 && z0.loopEndIncl == 299,
                            "sf2 exclusive loop end converts to inclusive");
            reporter.expect(z0.suggestedName == QStringLiteral("test_tone"),
                            "zone name sanitizes into the suggested name");
            bool bytesMatch = z0.frameCount() == 400;
            for (int i = 0; i < 400 && bytesMatch; i++)
                bytesMatch = z0.buffer[size_t(i)] == float(double(poolRef[size_t(i)]) / 32768.0);
            reporter.expect(bytesMatch, "zone 0 audio matches the pool segment");

            ImportedSample z1;
            reporter.expect(extractSf2Zone(font, 1, &z1, &error), "zone 1 extracts");
            reporter.expect(z1.warnings.join(QLatin1Char(' '))
                                .contains(QStringLiteral("stereo pair — imported one channel.")),
                            "stereo-pair zone carries the one-channel warning");
            reporter.expect(z1.frameCount() == 200 && !z1.hasLoop && z1.hasPitchMetadata &&
                                z1.baseKey == 60 && std::abs(z1.fracSemitone - 0.5) < 1e-9 &&
                                z1.buffer[0] == float(double(poolRef[400]) / 32768.0),
                            "positive pitchCorrection becomes the semitone fraction");

            ImportedSample z2;
            reporter.expect(extractSf2Zone(font, 2, &z2, &error), "zone 2 extracts");
            reporter.expect(!z2.hasPitchMetadata && z2.baseKey == 60,
                            "unpitched (255) zone defers to pitch detection");

            // Downstream is untouched: an sf2 zone runs the ordinary
            // pipeline to final s8 bytes.
            SampleDocument doc(z0);
            doc.setParams(SampleDocument::defaultParams(z0));
            const ProcessedSample &out = doc.processed();
            reporter.expect(!out.s8.isEmpty() && out.size == quint32(out.s8.size()) &&
                                out.freq > 0 && out.looped,
                            "sf2 zone renders through the pipeline");
        }

        // Refusals: the single-stream front door, a truncated container,
        // and a font whose only sample is a skipped ROM sample.
        ImportedSample junk;
        reporter.expect(!importAudioBytes(sf2Bytes, QStringLiteral("f/test.sf2"), &junk, &error),
                        "sf2 refused by the single-stream front door");
        reporter.expectError(error,
                             QStringLiteral("SoundFont files hold multiple samples — "
                                            "pick a zone with the SoundFont zone "
                                            "picker."),
                             "sf2 front-door refusal text");
        Sf2File bad;
        reporter.expect(!readSf2Bytes(sf2Bytes.left(200), QStringLiteral("f/t.sf2"), &bad, &error),
                        "truncated sf2 refused");
        reporter.expectError(error, QStringLiteral("the SoundFont file is corrupt or truncated."),
                             "sf2 corrupt text");
        QByteArray romOnly;
        shdrRec(&romOnly, "RomTone", 0, 400, 0, 0, 22050, 60, 0, 0x8001);
        shdrRec(&romOnly, "EOS", 0, 0, 0, 0, 0, 0, 0, 0);
        reporter.expect(!readSf2Bytes(buildSf2(romOnly), QStringLiteral("f/r.sf2"), &bad, &error),
                        "ROM-only font refused");
        reporter.expectError(error, QStringLiteral("the SoundFont contains no importable samples."),
                             "no-importable-samples text");

        // The picker, offscreen: grouping, search filter, selection arming
        // OK, and accept returning the picked zone index.
        {
            Sf2ZonePicker picker(font);
            picker.resize(720, 480);
            picker.show();
            QApplication::processEvents();
            auto *tree = picker.findChild<QTreeWidget *>(QStringLiteral("sf2ZoneTree"));
            auto *searchEdit = picker.findChild<QLineEdit *>(QStringLiteral("sf2SearchEdit"));
            auto *buttons = picker.findChild<QDialogButtonBox *>(QStringLiteral("sf2ButtonBox"));
            reporter.expect(tree && searchEdit && buttons, "picker widgets found");
            if (tree && searchEdit && buttons) {
                QPushButton *ok = buttons->button(QDialogButtonBox::Ok);
                reporter.expect(tree->topLevelItemCount() == 2,
                                "zones group under instrument and (no instrument)");
                QTreeWidgetItem *grp0 = tree->topLevelItem(0);
                QTreeWidgetItem *grp1 = tree->topLevelItem(1);
                reporter.expect(grp0 && grp0->text(0) == QStringLiteral("TestInst — TestPreset") &&
                                    grp0->childCount() == 1,
                                "group label names the instrument and preset");
                reporter.expect(grp1 && grp1->childCount() == 2,
                                "unreferenced zones fall under (no instrument)");
                reporter.expect(ok && !ok->isEnabled() && picker.selectedZone() == -1,
                                "nothing picked until a zone row is chosen");
                tree->setCurrentItem(grp0->child(0));
                reporter.expect(picker.selectedZone() == 0 && ok->isEnabled(),
                                "selecting a zone row arms OK");
                tree->setCurrentItem(grp0);
                reporter.expect(picker.selectedZone() == -1 && !ok->isEnabled(),
                                "group rows are not pickable");
                searchEdit->setText(QStringLiteral("pad"));
                reporter.expect(tree->topLevelItemCount() == 1 &&
                                    tree->topLevelItem(0)->childCount() == 1,
                                "search filters to matching zones");
                tree->setCurrentItem(tree->topLevelItem(0)->child(0));
                reporter.expect(picker.selectedZone() == 1,
                                "filtered pick maps to the right zone index");
                searchEdit->clear();
                reporter.expect(tree->topLevelItemCount() == 2,
                                "clearing the search restores every zone");
                tree->setCurrentItem(tree->topLevelItem(0)->child(0));
                ok->click();
                reporter.expect(picker.result() == QDialog::Accepted && picker.selectedZone() == 0,
                                "OK accepts with the picked zone");
            }
        }
        if (reporter.failureCount() == before)
            std::printf("samplecheck: soundfont OK\n");
    }
}

} // namespace samplecheck
