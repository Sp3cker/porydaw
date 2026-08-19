export type ScratchKind =
  | "existing-directory"
  | "must-not-exist-path"
  | "unused";

export type FixtureRootKind = "decomp-project" | "songs-mk-project" | "none";

export interface CheckManifestEntry {
  readonly name: string;
  readonly argv: readonly string[];
  readonly scratchKind: ScratchKind;
  readonly envGate?: string;
  readonly fixtureRootKind: FixtureRootKind;
  readonly fixtureFiles: readonly string[];
}

// Optional argv placeholders are omitted when their environment variable is
// unset or empty. Required placeholders are resolved by the runner itself.
export const OPTIONAL_ARG_ENV: Readonly<Record<string, string>> = {
  "{sample-corpus?}": "PORYDAW_SAMPLE_CORPUS",
};

const decompProjectFiles = [
  "sound/song_table.inc",
  "sound/songs/midi/midi.cfg",
] as const;

const decompMidiFiles = [
  "sound/songs/midi/mus_caught.mid",
  "sound/songs/midi/mus_dummy.mid",
  "sound/songs/midi/mus_gsc_route38.mid",
  "sound/songs/midi/mus_gym.mid",
  "sound/songs/midi/mus_littleroot_test.mid",
  "sound/songs/midi/mus_oldale.mid",
  "sound/songs/midi/mus_petalburg.mid",
  "sound/songs/midi/mus_route101.mid",
  "sound/songs/midi/mus_route102.mid",
  "sound/songs/midi/mus_surf.mid",
  "sound/songs/midi/mus_victory_wild.mid",
  "sound/songs/midi/se_fanfare_1trk.mid",
  "sound/songs/midi/se_pc_login.mid",
  "sound/songs/midi/se_use_item.mid",
] as const;

// The fixture_rich voicegroup's complete recursive load set: its four sample
// binaries, two programmable waves, two keysplit tables, and four child
// voicegroups.
const richVoicegroupFiles = [
  "sound/direct_sound_data.inc",
  "sound/direct_sound_samples/fixture_bass.bin",
  "sound/direct_sound_samples/fixture_drum.bin",
  "sound/direct_sound_samples/fixture_loop.bin",
  "sound/direct_sound_samples/fixture_pluck.bin",
  "sound/programmable_wave_data.inc",
  "sound/programmable_wave_samples/fixture_pulse.pcm",
  "sound/programmable_wave_samples/fixture_saw.pcm",
  "sound/keysplit_tables.inc",
  "sound/voicegroups/fixture_rich.inc",
  "sound/voicegroups/fixture_keys.inc",
  "sound/voicegroups/fixture_bass.inc",
  "sound/voicegroups/fixture_drums_a.inc",
  "sound/voicegroups/fixture_drums_b.inc",
] as const;

// Voicegroup editor checks enumerate the whole checked-in catalog, create a
// new file through its include hub, and exercise synth wiring through the
// project's assembly owner.
const voicegroupEditorFiles = [
  ...richVoicegroupFiles,
  "sound/voice_groups.inc",
  "sound/voicegroups/dummy.inc",
  "sound/voicegroups/fixture_alt.inc",
] as const;

export const CHECK_MANIFEST: readonly CheckManifestEntry[] = [
  {
    name: "roundtrip",
    argv: ["--roundtrip", "{scratch}", "{mid2agb}"],
    scratchKind: "existing-directory",
    fixtureRootKind: "decomp-project",
    fixtureFiles: [...decompProjectFiles, ...decompMidiFiles],
  },
  {
    name: "editcheck",
    argv: ["--editcheck", "{scratch}"],
    scratchKind: "existing-directory",
    fixtureRootKind: "decomp-project",
    fixtureFiles: [...decompProjectFiles, ...decompMidiFiles],
  },
  {
    name: "scalecheck",
    argv: ["--scalecheck", "{scratch}"],
    scratchKind: "existing-directory",
    fixtureRootKind: "none",
    fixtureFiles: [],
  },
  {
    name: "viewcheck",
    argv: ["--viewcheck", "{scratch}"],
    scratchKind: "existing-directory",
    fixtureRootKind: "decomp-project",
    fixtureFiles: [...decompProjectFiles, ...decompMidiFiles],
  },
  {
    name: "selftest",
    argv: ["--selftest", "{scratch}", "mus_littleroot_test"],
    scratchKind: "existing-directory",
    fixtureRootKind: "decomp-project",
    fixtureFiles: [
      ...decompProjectFiles,
      "sound/songs/midi/mus_littleroot_test.mid",
      ...richVoicegroupFiles,
    ],
  },
  {
    name: "savecheck",
    argv: ["--savecheck", "{scratch}", "mus_route101", "{mid2agb}"],
    scratchKind: "existing-directory",
    fixtureRootKind: "decomp-project",
    fixtureFiles: [
      ...decompProjectFiles,
      "sound/songs/midi/mus_route101.mid",
    ],
  },
  {
    name: "onboardcheck",
    argv: ["--onboardcheck", "{scratch}", "{mid2agb}"],
    scratchKind: "existing-directory",
    fixtureRootKind: "decomp-project",
    fixtureFiles: [
      ...decompProjectFiles,
      "sound/music_player_table.inc",
      "include/constants/songs.h",
      "ld_script.ld",
      "charmap.txt",
      "src/debug.c",
      "sound/voice_groups.inc",
      "sound/voicegroups/dummy.inc",
      "test_midis/external_import.mid",
      "test_midis/duplicate_setters.mid",
    ],
  },
  {
    name: "vgcheck",
    argv: ["--vgcheck", "{scratch}", "mus_gym"],
    scratchKind: "existing-directory",
    fixtureRootKind: "decomp-project",
    fixtureFiles: [
      ...decompProjectFiles,
      "sound/songs/midi/mus_gym.mid",
      ...voicegroupEditorFiles,
    ],
  },
  {
    name: "vgsavecheck",
    argv: ["--vgsavecheck", "{scratch}", "mus_route101"],
    scratchKind: "existing-directory",
    fixtureRootKind: "decomp-project",
    fixtureFiles: [
      ...decompProjectFiles,
      "sound/songs/midi/mus_route101.mid",
      ...voicegroupEditorFiles,
      "data/sound_data.s",
    ],
  },
  {
    name: "exportcheck-loop",
    argv: ["--exportcheck", "{scratch}", "mus_route101"],
    scratchKind: "existing-directory",
    fixtureRootKind: "decomp-project",
    fixtureFiles: [
      ...decompProjectFiles,
      "sound/songs/midi/mus_route101.mid",
      ...richVoicegroupFiles,
    ],
  },
  {
    name: "exportcheck-tail",
    argv: ["--exportcheck", "{scratch}", "mus_route102"],
    scratchKind: "existing-directory",
    fixtureRootKind: "decomp-project",
    fixtureFiles: [
      ...decompProjectFiles,
      "sound/songs/midi/mus_route102.mid",
      ...richVoicegroupFiles,
    ],
  },
  {
    name: "sessioncheck",
    argv: ["--sessioncheck", "{scratch}", "mus_route101"],
    scratchKind: "existing-directory",
    fixtureRootKind: "decomp-project",
    fixtureFiles: [
      ...decompProjectFiles,
      "sound/songs/midi/mus_route101.mid",
      ...richVoicegroupFiles,
    ],
  },
  {
    name: "tabcheck",
    argv: ["--tabcheck", "{scratch}", "mus_route101", "mus_petalburg"],
    scratchKind: "existing-directory",
    fixtureRootKind: "decomp-project",
    fixtureFiles: [
      ...decompProjectFiles,
      "sound/songs/midi/mus_route101.mid",
      "sound/songs/midi/mus_petalburg.mid",
      ...richVoicegroupFiles,
      "sound/voicegroups/fixture_alt.inc",
    ],
  },
  {
    name: "eventviewcheck",
    argv: ["--eventviewcheck", "{scratch}"],
    scratchKind: "existing-directory",
    fixtureRootKind: "decomp-project",
    fixtureFiles: [...decompProjectFiles, ...decompMidiFiles],
  },
  {
    name: "rollcheck",
    argv: ["--rollcheck", "{scratch}", "mus_route101"],
    scratchKind: "existing-directory",
    fixtureRootKind: "decomp-project",
    fixtureFiles: [
      ...decompProjectFiles,
      "sound/songs/midi/mus_route101.mid",
    ],
  },
  {
    name: "mkcheck",
    argv: ["--mkcheck", "{scratch}", "mus_aqua_magma_hideout"],
    scratchKind: "existing-directory",
    fixtureRootKind: "songs-mk-project",
    fixtureFiles: ["sound/song_table.inc", "songs.mk"],
  },
  {
    name: "loopcheck",
    argv: ["--loopcheck"],
    scratchKind: "unused",
    fixtureRootKind: "none",
    fixtureFiles: [],
  },
  {
    name: "ignorecheck",
    argv: ["--ignorecheck", "{scratch}"],
    scratchKind: "must-not-exist-path",
    fixtureRootKind: "none",
    fixtureFiles: [],
  },
  {
    name: "primecheck",
    argv: ["--primecheck"],
    scratchKind: "unused",
    fixtureRootKind: "none",
    fixtureFiles: [],
  },
  {
    name: "smfcheck",
    argv: ["--smfcheck"],
    scratchKind: "unused",
    fixtureRootKind: "none",
    fixtureFiles: [],
  },
  {
    name: "smfstresscheck",
    argv: ["--smfstresscheck"],
    scratchKind: "unused",
    envGate: "PORYDAW_SMF_STRESS",
    fixtureRootKind: "none",
    fixtureFiles: [],
  },
  {
    name: "transportcheck",
    argv: ["--transportcheck"],
    scratchKind: "unused",
    fixtureRootKind: "none",
    fixtureFiles: [],
  },
  {
    name: "audiocheck",
    argv: ["--audiocheck"],
    scratchKind: "unused",
    fixtureRootKind: "none",
    fixtureFiles: [],
  },
  {
    name: "clickcheck",
    argv: ["--clickcheck"],
    scratchKind: "unused",
    fixtureRootKind: "none",
    fixtureFiles: [],
  },
  {
    name: "resonancecheck",
    argv: ["--resonancecheck"],
    scratchKind: "unused",
    fixtureRootKind: "none",
    fixtureFiles: [],
  },
  {
    name: "trackactivitycheck",
    argv: ["--trackactivitycheck"],
    scratchKind: "unused",
    fixtureRootKind: "none",
    fixtureFiles: [],
  },
  {
    name: "trackactivitymetercheck",
    argv: ["--trackactivitymetercheck"],
    scratchKind: "unused",
    fixtureRootKind: "none",
    fixtureFiles: [],
  },
  {
    name: "keymapcheck",
    argv: ["--keymapcheck"],
    scratchKind: "unused",
    fixtureRootKind: "none",
    fixtureFiles: [],
  },
  {
    name: "polycheck",
    argv: ["--polycheck"],
    scratchKind: "unused",
    fixtureRootKind: "none",
    fixtureFiles: [],
  },
  {
    name: "samplecheck",
    argv: ["--samplecheck", "{scratch}", "{sample-corpus?}"],
    scratchKind: "must-not-exist-path",
    fixtureRootKind: "none",
    fixtureFiles: [],
  },
  {
    name: "noteidcheck",
    argv: ["--check-note-identity", "{scratch}"],
    scratchKind: "existing-directory",
    fixtureRootKind: "none",
    fixtureFiles: [],
  },
];
