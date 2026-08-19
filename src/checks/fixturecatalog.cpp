#include "fixturecatalog.hpp"

namespace checks::fixtures {

QStringList decompProjectFiles()
{
    return {
        QStringLiteral("sound/song_table.inc"),
        QStringLiteral("sound/songs/midi/midi.cfg"),
    };
}

QStringList decompMidiFiles()
{
    return {
        QStringLiteral("sound/songs/midi/mus_caught.mid"),
        QStringLiteral("sound/songs/midi/mus_dummy.mid"),
        QStringLiteral("sound/songs/midi/mus_gsc_route38.mid"),
        QStringLiteral("sound/songs/midi/mus_gym.mid"),
        QStringLiteral("sound/songs/midi/mus_littleroot_test.mid"),
        QStringLiteral("sound/songs/midi/mus_oldale.mid"),
        QStringLiteral("sound/songs/midi/mus_petalburg.mid"),
        QStringLiteral("sound/songs/midi/mus_route101.mid"),
        QStringLiteral("sound/songs/midi/mus_route102.mid"),
        QStringLiteral("sound/songs/midi/mus_surf.mid"),
        QStringLiteral("sound/songs/midi/mus_victory_wild.mid"),
        QStringLiteral("sound/songs/midi/se_fanfare_1trk.mid"),
        QStringLiteral("sound/songs/midi/se_pc_login.mid"),
        QStringLiteral("sound/songs/midi/se_use_item.mid"),
    };
}

QStringList richVoicegroupFiles()
{
    return {
        QStringLiteral("sound/direct_sound_data.inc"),
        QStringLiteral("sound/direct_sound_samples/fixture_bass.bin"),
        QStringLiteral("sound/direct_sound_samples/fixture_drum.bin"),
        QStringLiteral("sound/direct_sound_samples/fixture_loop.bin"),
        QStringLiteral("sound/direct_sound_samples/fixture_pluck.bin"),
        QStringLiteral("sound/programmable_wave_data.inc"),
        QStringLiteral("sound/programmable_wave_samples/fixture_pulse.pcm"),
        QStringLiteral("sound/programmable_wave_samples/fixture_saw.pcm"),
        QStringLiteral("sound/keysplit_tables.inc"),
        QStringLiteral("sound/voicegroups/fixture_rich.inc"),
        QStringLiteral("sound/voicegroups/fixture_keys.inc"),
        QStringLiteral("sound/voicegroups/fixture_bass.inc"),
        QStringLiteral("sound/voicegroups/fixture_drums_a.inc"),
        QStringLiteral("sound/voicegroups/fixture_drums_b.inc"),
    };
}

QStringList voicegroupEditorFiles()
{
    return richVoicegroupFiles() + QStringList{
                                       QStringLiteral("sound/voice_groups.inc"),
                                       QStringLiteral("sound/voicegroups/dummy.inc"),
                                       QStringLiteral("sound/voicegroups/fixture_alt.inc"),
                                   };
}

} // namespace checks::fixtures
