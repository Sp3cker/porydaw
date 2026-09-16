#include "m4asemantics.h"

#include <QObject>
#include <algorithm>

extern "C" {
#include "m4a_engine.h"
}

M4aCcInfo m4aClassifyCc(uint8_t cc)
{
    switch (cc) {
    // CCs the poryaaaa engine renders unconditionally -> audible lanes.
    case 0x01:
        return {M4aEventClass::AudibleLane, M4aLane::Mod, "MOD", "Modulation"};
    case 0x07:
        return {M4aEventClass::AudibleLane, M4aLane::Volume, "VOL", "Volume"};
    case 0x0A:
        return {M4aEventClass::AudibleLane, M4aLane::Pan, "PAN", "Pan"};
    case 0x14:
        return {M4aEventClass::AudibleLane, M4aLane::BendRange, "BENDR", "Bend range"};
    case 0x15:
        return {M4aEventClass::AudibleLane, M4aLane::LfoSpeed, "LFOS", "LFO speed"};

    // Valid m4a commands the engine treats as opt-in or no-op -> advanced.
    case 0x05:
        return {M4aEventClass::Advanced, M4aLane::Mod, "PORTAMENTO", "Portamento"};
    case 0x16:
        return {M4aEventClass::Advanced, M4aLane::Mod, "MODT", "LFO type"};
    case 0x17:
        return {M4aEventClass::Advanced, M4aLane::Mod, "PWMC", "Pulse-width pattern"};
    case 0x18:
        return {M4aEventClass::Advanced, M4aLane::Mod, "TUNE", "Fine tune"};
    case 0x19:
        return {M4aEventClass::Advanced, M4aLane::Mod, "PWMS", "Pulse-width speed"};
    case 0x1A:
        return {M4aEventClass::Advanced, M4aLane::Mod, "LFODL", "LFO delay"};

    // MEMACC / label / XCMD / priority plumbing -> advanced.
    case 0x0C:
    case 0x10:
        return {M4aEventClass::Advanced, M4aLane::Mod, "MEMACC", "Memory op"};
    case 0x0D:
        return {M4aEventClass::Advanced, M4aLane::Mod, "MEMACC op", "Memory op select"};
    case 0x0E:
        return {M4aEventClass::Advanced, M4aLane::Mod, "MEMACC p1", "Memory op param 1"};
    case 0x0F:
        return {M4aEventClass::Advanced, M4aLane::Mod, "MEMACC p2", "Memory op param 2"};
    case 0x11:
        return {M4aEventClass::Advanced, M4aLane::Mod, "Label", "Loop label"};
    case 0x1D:
    case 0x1F:
        return {M4aEventClass::Advanced, M4aLane::Mod, "XCMD", "Pseudo-echo"};
    case 0x1E:
        return {M4aEventClass::Advanced, M4aLane::Mod, "XCMD op", "Pseudo-echo select"};
    case 0x21:
    case 0x27:
        return {M4aEventClass::Advanced, M4aLane::Mod, "PRIO", "Priority"};

    default:
        return {M4aEventClass::Advanced, M4aLane::Mod, "CC", "Controller"};
    }
}

M4aExportSupport m4aExportSupport(uint8_t cc)
{
    // Every row audited against the bundled converter. midi.cpp turns each
    // SMF controller (0xB0) into EventType::Controller with param1 = CC and
    // param2 = value, unfiltered; PrintAgbTrack routes those straight into
    // PrintControllerOp's switch on event.param1, so the CC number alone
    // picks the branch cited below.
    switch (cc) {
    // PrintOp branches -> real game command bytes. MODT/TUNE/LFODL and the
    // PRIO pair present as Advanced (m4aClassifyCc) but still export.
    case 0x01: // PrintControllerOp -> PrintOp "MOD   "
    case 0x07: // PrintControllerOp -> PrintOp "VOL   "
    case 0x0A: // PrintControllerOp -> PrintOp "PAN   "
    case 0x14: // PrintControllerOp -> PrintOp "BENDR "
    case 0x15: // PrintControllerOp -> PrintOp "LFOS  "
    case 0x16: // PrintControllerOp -> PrintOp "MODT  "
    case 0x18: // PrintControllerOp -> PrintOp "TUNE  "
    case 0x1A: // PrintControllerOp -> PrintOp "LFODL "
    case 0x21: // PrintControllerOp -> PrintByte "PRIO  , " + PrintWait
    case 0x27:
        return M4aExportSupport::Supported;

    // No case in PrintControllerOp -> default branch -> PrintWait only:
    // PORTAMENTO/PWMC/PWMS never reach the byte stream. Same fate for any
    // unmapped CC.
    case 0x05:
    case 0x17:
    case 0x19:
        return M4aExportSupport::NotExported;

    // MEMACC execute: PrintControllerOp routes 0x0C/0x10 to PrintMemAcc,
    // which emits "MEMACC, mem_*" only for the stored op 0x00-0x05; ops
    // 0x06+ are "// TODO: everything else" stubs, so the verdict depends on
    // incomplete protocol traffic.
    case 0x0C:
    case 0x10:
        return M4aExportSupport::NeedsReview;

    // MEMACC op/params: PrintControllerOp stores s_memaccOp/Param1/Param2
    // and PrintWait — a bare CC byte produces no game bytes. The coupled
    // execution verdict lives at 0x0C/0x10 above.
    case 0x0D:
    case 0x0E:
    case 0x0F:
        return M4aExportSupport::NotExported;

    // Loop-label protocol: PrintControllerOp writes an asm label, PrintWait,
    // and ResetTrackVars, but the MEMACC jump ops that consume labels are
    // TODO stubs in PrintMemAcc -> incomplete protocol traffic.
    case 0x11:
        return M4aExportSupport::NeedsReview;

    // XCMD plumbing: PrintControllerOp routes 0x1D/0x1F to PrintExtendedOp,
    // which emits xIECV/xIECL only when the selector stored by 0x1E is
    // 0x08/0x09, else PrintWait; 0x1E stores s_extendedCommand with no
    // output at all. Coupled traffic — the logical echo verdict belongs to
    // the xcmd phase, not to a bare CC number.
    case 0x1D:
    case 0x1E:
    case 0x1F:
        return M4aExportSupport::NeedsReview;

    // PrintControllerOp default branch: PrintWait only, nothing exported.
    default:
        return M4aExportSupport::NotExported;
    }
}

M4aLane m4aLaneForXcmdSelector(uint8_t selector)
{
    switch (selector) {
    case 0x08:
        return M4aLane::EchoVolume;
    case 0x09:
        return M4aLane::EchoLength;
    default:
        break;
    }
    // A descriptor selector outside this table would be a protocol addition
    // the view layer has not registered yet.
    Q_ASSERT_X(false, "m4aLaneForXcmdSelector", "unregistered XCMD descriptor selector");
    return M4aLane::EchoVolume;
}

QString m4aLaneName(M4aLane lane)
{
    switch (lane) {
    case M4aLane::Mod:
        return QStringLiteral("Modulation");
    case M4aLane::Volume:
        return QStringLiteral("Volume");
    case M4aLane::Pan:
        return QStringLiteral("Pan");
    case M4aLane::BendRange:
        return QStringLiteral("Bend range");
    case M4aLane::LfoSpeed:
        return QStringLiteral("LFO speed");
    case M4aLane::PitchBend:
        return QStringLiteral("Pitch bend");
    case M4aLane::EchoVolume:
        return QStringLiteral("Echo volume");
    case M4aLane::EchoLength:
        return QStringLiteral("Echo length");
    case M4aLane::Tempo:
        return QStringLiteral("Tempo");
    }
    return QString();
}

QString m4aFormatCcValue(uint8_t cc, uint8_t value)
{
    switch (cc) {
    case 0x0A: // PAN
    case 0x18: // TUNE
        return QStringLiteral("c_v%1%2")
            .arg(value >= 64 ? QStringLiteral("+") : QString())
            .arg(int(value) - 64);
    default:
        return QString::number(value);
    }
}

QString m4aFormatBend(int bend14)
{
    return QStringLiteral("%1%2").arg(bend14 > 0 ? QStringLiteral("+") : QString()).arg(bend14);
}

QString m4aAdvancedCcLabel(uint8_t cc, uint8_t value)
{
    const M4aCcInfo info = m4aClassifyCc(cc);
    if (qstrcmp(info.name, "CC") == 0)
        return QStringLiteral("CC %1 = %2 (no m4a meaning)").arg(cc).arg(value);
    return QStringLiteral("%1 %2").arg(QLatin1String(info.name), m4aFormatCcValue(cc, value));
}

QString m4aVoiceTypeName(uint8_t type)
{
    if (type == VOICE_KEYSPLIT_ALL)
        return QObject::tr("Drumkit");
    if (type == VOICE_DIRECTSOUND_NO_RESAMPLE)
        return QObject::tr("Sample (fixed pitch)");
    if (type == VOICE_DIRECTSOUND_ALT)
        return QObject::tr("Sample (reverse)");
    // VOICE_KEYSPLIT deliberately falls through to "Sample": keysplit
    // instruments live in the Sample dropdown, so the UI never distinguishes
    // them by type.
    switch (type & VOICE_TYPE_CGB_MASK) {
    case VOICE_SQUARE_1:
        return QObject::tr("Square 1");
    case VOICE_SQUARE_2:
        return QObject::tr("Square 2");
    case VOICE_PROGRAMMABLE_WAVE:
        return QObject::tr("Wave");
    case VOICE_NOISE:
        return QObject::tr("Noise");
    default:
        return QObject::tr("Sample");
    }
}

QString midiKeyName(int key)
{
    static const char *const names[] = {"C",  "C#", "D",  "D#", "E",  "F",
                                        "F#", "G",  "G#", "A",  "A#", "B"};
    return QStringLiteral("%1%2").arg(QLatin1String(names[key % 12])).arg(key / 12 - 1);
}

QString midiTimeSigLabel(int numerator, int denomPow2)
{
    return QStringLiteral("%1/%2").arg(numerator).arg(1 << std::min(denomPow2, 6));
}
