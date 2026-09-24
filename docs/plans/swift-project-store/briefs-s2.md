# Seam S2 — SongRegistry live-surface port (Tasks 6–9)

## Task 6: SongModel + SongFlags pure flag mapping

### Context
Ports the seam-reachable flag core: `SongCfg` (`src/project/decompproject.h:19-33`), `cfgFromFlags` (`src/project/decompproject.cpp:495-532`), and `SongRegistry::mergeCfgFlags` (`src/project/songregistry.cpp:1445-1476`). This is the only flag logic that crosses the seam: `swift_project_service.cpp:425` always passes `{}` for synth definitions, and every consumer in `ProjectService.swift` (`LoadedSong.config: SongConfig`, `source: SongSource`) is fed from these two functions. No new config/source types are introduced; the existing `SongConfig`/`SongSource` in `src/swift/core/SongDocument.swift:3-38` are reused as-is.

### Exact write set
- `src/swift/project/SongModel.swift` (new): `kDefaultReverb` constant, `SongFlags.fromRaw(_:) -> SongConfig`, `SongFlags.merge(_:) -> [String]`.
- `src/checks/projectstore/SongModelChecks.swift` (new): pure unit checks for `fromRaw`/`merge` (no fixture, no disk).

### Prerequisites
- Tasks 1–5 landed: `PorydawProject` target at `src/swift/project/` builds and `SongConfig` is visible to it (see plan.md Global Constraints for module wiring).

### Interface contract
- `public let kDefaultReverb: Int = 50`; never stored into `SongConfig.reverb` (absent flag stays `nil`).
- `public enum SongFlags { public static func fromRaw(_ flags: [String]) -> SongConfig; public static func merge(_ cfg: SongConfig) -> [String] }`.
- `fromRaw` preserves `rawFlags` verbatim (pre-expanded spellings, order, duplicates kept); parses case-insensitively on the letter after `-`; last `-G` wins; `-V` defaults 127; `-R` absent stays `nil`; `-P` defaults 0; `-E`/`-X`/`-N` default false; `-L` and unknown letters are ignored for parsing but retained in `rawFlags`.
- `merge` starts from `cfg.rawFlags`, updates or inserts `-<letter><value>` in place (first case-insensitive letter match), appends missing letters at the end in fixed order `E R G V P X N`, keeps unknown flags and original order intact, removes a letter when its value is absent (`-E` absent, `-R` nil, `-G` empty, `-P` zero, `-X`/`-N` false), and formats `-V` as exactly 3 zero-padded digits.

### Implementation steps
1. Define `kDefaultReverb = 50` in `SongModel.swift`.
2. Implement `fromRaw` as a direct port of `cfgFromFlags`: skip entries shorter than 2 chars or not starting with `-`; uppercase the option letter; switch `G` (take `mid(2)` verbatim), `V`/`R` (clamped helper), `P` (`Int` conversion), `E`/`X`/`N` (set true); ignore everything else.
3. Implement the clamp helper as `min(127, max(0, Int(arg) ?? 0))`, replicating `qBound(0, arg.toInt(), 127)` including the `toInt()` failure mode.
4. Implement `merge` as a direct port of `mergeCfgFlags`: `setValue` matches `flags[i][1].uppercased() == letter` on the first hit, replaces in place or appends `-letter+value`, removes on nil value; `setBool` writes empty value or nil; apply in order `E, R, G, V (3-digit `%03d`), P, X, N`.
5. Write `SongModelChecks.swift` covering: round-trip `merge(fromRaw(flags))` stability, unknown-flag retention and order, case-insensitive match (`-v080` updates `-V080`), `-V` zero-padding, absent-`-R` removal vs `nil`, empty-`-G` removal.

### Acceptance predicate
- `merge(fromRaw(["-E", "-R50", "-G_abandoned_ship", "-V080"]))` returns the flags unchanged in order; unknown `-Lfoo` survives a merge untouched and in place; `-V` of volume 5 formats as `-V005`; absent reverb removes `-R` from the list.
- Named checks: `deno task verify --filter projectstore-songmodel --verbose` covers `fromRaw` parsing and `merge` ordering/removal/formatting (pure unit, no fixture).

### Task-specific constraints
- `qBound` clamp on non-numeric input: Qt `arg.toInt()` yields `0` for non-numeric (`-Vabc` → 0, `-R` empty → 0); the Swift helper MUST use `Int(arg) ?? 0` before clamping, never `nil`-propagation or a thrown error.
- `merge` letter comparison is case-insensitive (`flags[i][1].toUpper() == letter`); the replacement spelling always uses the canonical uppercase letter (`-v080` becomes `-V080`); value comparison for SongsMk spelling preservation (Task 9) is separate and MUST NOT leak into this file.

## Task 7: MidiCfg parse + writeMidiCfgLine + writeSongFlags routing

### Context
Ports midi.cfg read and write: `DecompProject::parseMidiCfg` (`src/project/decompproject.cpp:534-568`), `SongRegistry::writeMidiCfgLine` (`src/project/songregistry.cpp:1478-1533`), and `SongRegistry::writeSongFlags` routing (`src/project/songregistry.cpp:1535-1545`). Read side uses `QIODevice::Text` (CRLF stripped before parsing); write side is binary byte-conservative including CRLF (vanilla midi.cfg is CRLF). `removeSongFlags`/`removeMidiCfgLine` are dead and do not port. Proof rows ported: `proof.save.txt` A013 (line-count equality after a save touching another song) and A014 (per-line byte equality for every non-song line), adapted to direct `writeMidiCfgLine` round-trips without the `SongDocument`/undo scaffolding.

### Exact write set
- `src/swift/project/MidiCfg.swift` (new): `parseMidiCfg(_:)->[String: SongConfig`, `writeMidiCfgLine(midiDir:label:flags:) throws`, `writeSongFlags(midiDir:label:flags:) throws`.
- `src/checks/projectstore/MidiCfgChecks.swift` (new): byte-conservation checks (A013/A014 equivalents) plus routing checks.

### Prerequisites
- Task 6 landed (`SongFlags.fromRaw`/`merge`).
- Task 9 landed (`SongsMk.writeRule`, `SongsMk.path`) — `writeSongFlags` routes to it.

### Interface contract
- `public enum MidiCfg { public static func parse(_ bytes: Data) -> [String: SongConfig]; public static func writeMidiCfgLine(midiDir: URL, label: String, flags: [String]) throws; public static func writeSongFlags(midiDir: URL, label: String, flags: [String]) throws }`.
- `parse`: decode bytes as UTF-8 lossily per line; trim; strip `#` comments (cut at first `#`, re-trim); split at first `:` (skip lines with `colon <= 0`); trim the name, chop a trailing `.mid` case-insensitively; value is `split(separator: " ", omittingEmptySubsequences: true)` fed to `SongFlags.fromRaw`. Last duplicate label wins.
- `writeMidiCfgLine`: exact algorithm — read raw `Data` (missing file = empty content); `endsWithNewline = content.isEmpty || content.last == 0x0A`; `crlf = content.contains(\r\n)`; split on `0x0A`, drop the trailing empty piece when `endsWithNewline`; match lines whose pre-colon trimmed text equals `<label>.mid`; preserve the original name-column padding (keep `text.left(flagStart)` through post-colon spaces); replace flags with `flags.joined(" ")`; preserve per-line `\r`; when no line matches, append `<label>.mid: <flags>` with `\r` iff `crlf`; rejoin with `\n`, restore the trailing newline iff `endsWithNewline`; write atomically per plan.md Global Constraints.
- `writeSongFlags`: if `<midiDir>/midi.cfg` does not exist and `<root>/songs.mk` (via `SongsMk.path`, `root = midiDir/../../..` cleaned) exists, delegate to `SongsMk.writeRule`; otherwise `writeMidiCfgLine` (which creates a fresh midi.cfg when neither exists).

### Implementation steps
1. Implement `parse` exactly as above; no comment preservation (comments are dropped from the parsed map, matching the original which re-trims after `#` cut).
2. Implement `writeMidiCfgLine` on `Data`/`[Data]` throughout — decode a line to `String` only for colon/padding comparison, then rebuild as bytes; never round-trip the whole file through `String`.
3. Implement per-line `\r` handling: strip one trailing `\r` before comparison, re-append exactly one after rewrite; detect `crlf` once from the whole content for the append path only.
4. Implement `writeSongFlags` routing with `FileManager.fileExists` checks only (no `replaceItem`; atomic write per plan.md Global Constraints).
5. Write `MidiCfgChecks.swift`: other-song line bytes preserved (A013: line count equal; A014: every non-song line byte-equal after rewriting one song's volume), CRLF fixture preservation, missing-file creation, and routing (midi.cfg absent + songs.mk present → rule written, no midi.cfg created).

### Acceptance predicate
- Rewriting one song's flags changes exactly its own line; every other line is byte-identical including `\r`; line count is unchanged; CRLF files stay CRLF; fresh projects gain a `label.mid: flags` line.
- Named checks: `deno task verify --filter projectstore-midicfg --verbose` covers A013/A014 byte-conservation equivalents, CRLF preservation, creation, and songs.mk routing.

### Task-specific constraints
- Byte-conservation is `Data`-level: a whole-file `String` decode/encode round-trip is PROHIBITED (it normalizes CRLF and trailing newlines); the `endsWithNewline`/`crlf`/per-line-`\r` triple MUST be replicated exactly as in `writeMidiCfgLine`.
- Name-column padding belongs to the file: `text.left(flagStart)` (name + colon + original spaces) is kept verbatim; only the flag bytes after it change.
- Windows first-party rules per plan.md Global Constraints: no `FileManager.replaceItem`, no `CryptoKit`, no `Dispatch`, no `NSString` path helpers; path arithmetic with `URL`/`NSString`-free standard library only; C++ shim (if any) MUST be MSVC-clean.

## Task 8: SongTable / songs.h / discovery / players / SongCatalog

### Context
Ports project song discovery: `parseSongTable` (`src/project/decompproject.cpp:392-435`), `parseSongConstants` (`437-464`), `discoverUnregisteredSongs` (`466-493`), `SongRegistry::musicPlayers` (`src/project/songregistry.cpp:503-549`), `constantForLabel` (`551-554`), `DecompProject::voicegroupCandidates` (`src/project/decompproject.cpp:596-609`), and `playableSong` (`613-620`). `checkRegistrations`/`applyRegistrationGaps` are DROPPED (registrationGaps never cross the seam — `PdSongMeta` has no gaps field) and do not port. `voicegroupArgs`/`deletableVoicegroup`/the `src/`+`include/` symbol scan are dead (zero live callers) and do not port.

### Exact write set
- `src/swift/project/SongCatalog.swift` (new): `ProjectSong` and `MusicPlayer` value structs, `SongCatalog` parsing/discovery/lookup.
- `src/checks/projectstore/SongCatalogChecks.swift` (new): table/constants/discovery/players/playable checks.

### Prerequisites
- Task 6 landed (`SongConfig` shape, `kDefaultReverb`).
- `ProjectFileStore` from S1 tasks for file reads (see plan.md Global Constraints for the read path).

### Interface contract
- `public struct ProjectSong: Sendable, Equatable { id: Int; label: String; constant: String; player: String; midPath: String?; hasMid: Bool; hasCfg: Bool; registered: Bool; cfg: SongConfig }` with `isPlayable == hasMid`.
- `public struct MusicPlayer: Sendable, Equatable { name: String; number: Int; trackCount: Int }` (`trackCount -1` = unknown, no limit assumed).
- `public struct SongCatalog: Sendable { songs: [ProjectSong]; players: [MusicPlayer]; static func load(root: URL, store: ProjectFileStore) -> SongCatalog; func playableSong(label: String) -> ProjectSong?; static func constantForLabel(_ label: String) -> String; static func voicegroupCandidates(cfg: SongConfig) -> [String] }`.
- `load` order: parse `sound/song_table.inc` (ids = running index, `midPath` set only when the `.mid` exists); attach `include/constants/songs.h` constants by id (first definition wins); append unregistered `.mid` files (label-derived constant, `MUSIC_PLAYER_BGM`, `registered = false`, id continues the sequence); attach cfgs from the caller-provided midi.cfg/songs.mk map (Task 7/9 own the parse); load players.
- `playableSong` returns the first song with `hasMid && label == name`, else `nil`.

### Implementation steps
1. Port `parseSongTable` with regex `^\s*song\s+(\w+)\s*,\s*(\w+)\s*,\s*(\w+)` (`NSRegularExpression`, anchored); skip non-matching lines; empty table is an error.
2. Port `parseSongConstants` with regex `^\s*#define\s+([A-Z0-9_]+)\s+(\d+)\s*$` — decimal digits only; map id → first constant; attach by song id.
3. Port `discoverUnregisteredSongs`: enumerate `sound/songs/midi/*.mid` sorted by name; strip only the LAST suffix (`completeBaseName` = `deletingPathExtension().lastPathComponent`); skip labels already known; append with `registered = false`, `hasMid = true`, `hasCfg = false`, default `SongConfig()`.
4. Port `musicPlayers`: `.equiv (\w+),(\d+)` lines from `sound/song_table.inc` in file order; default `[{MUSIC_PLAYER_BGM, 0}]` when empty; budgets from `sound/music_player_table.inc` — `.equiv` symbols then ordered `music_player` third-column args (integer literal or symbol lookup, `-1` when unresolvable), clamped with `min(count, 16)` while `0` stays `0`; assign `players[number].trackCount` when `number` is in range.
5. Port `constantForLabel` as `label.uppercased()` and `voicegroupCandidates` as: `arg = cfg.voicegroupArgument.isEmpty ? "_dummy" : arg`; `symbol = "voicegroup" + arg`; if `symbol` has prefix `voicegroup_` append `symbol.dropFirst(11)`; append `symbol`; append `arg` if non-empty and not already present.
6. Write `SongCatalogChecks.swift`: table parse with comment/blank lines skipped, constants attached by id with first-wins, unregistered `.mid` discovered sorted with defaults, players with budgets and the empty-table default, `playableSong` hit/miss/unplayable.

### Acceptance predicate
- A fixture with a registered song, an unregistered `.mid`, and a `music_player_table.inc` budget yields: registered song with constant and budget attached; unregistered song with derived constant, default player, `registered == false`; `playableSong` finds mid-backed labels only.
- Named checks: `deno task verify --filter projectstore-catalog --verbose` covers table/constants/discovery/players/playable behavior above.

### Task-specific constraints
- Hex sentinels never match: `songs.h` aliases like `0xFFFF`/`0xFF` do not satisfy `(\d+)`, so they are ignored by construction; the Swift regex MUST use decimal `\d+` only, never a hex-tolerant pattern.
- Sorted enumeration: `QDir::entryList(QDir::Name)` is sorted; the Swift `.mid` enumeration MUST sort by filename before assigning ids — unsorted `FileManager` order is a correctness bug (id drift).
- `NSRegularExpression` `\w` is ASCII `[_0-9A-Za-z]` plus Unicode word chars depending on configuration; anchor patterns with `^...` and test against labels containing non-ASCII to confirm they are skipped exactly like Qt (no accidental extra matches).
- `completeBaseName` strips the LAST suffix only: `deletingPathExtension().lastPathComponent` — `mus_foo.mid` → `mus_foo`; never strip two suffixes.

## Task 9: SongsMk path/parseFlags/writeRule + SongsMkChecks

### Context
Ports the pre-midi.cfg flag backend: `SongsMk::path`/`parseFlags`/`writeRule` (`src/project/songsmk.h`, `src/project/songsmk.cpp:75-219`). `removeRule` (`songsmk.cpp:221-270`) is dead and does NOT port — nothing may reference it. Proof rows ported from `proof.mk.txt`: A007–A014 (expanded parse has no `$`, volume-111 write succeeds, no midi.cfg created, line count equal, exactly one recipe line changed after the target line, changed line contains `$(MID)`), A025 (`-R$(STD_REVERB)` spelling preserved alongside `-V099`), A030 (append write for a new label succeeds), A031 (parse of the appended rule equals the written flags). Dropped with reasons: fixture guards (A001–A002, A020, A026–A027: `mkOnly`/`open`/`copyOf` scaffolding — the Swift checks use direct temp-dir files), `DecompProject` conjunctions (A003–A006, A015–A019, A022–A024, A028–A029: open/song-lookup/reopen value comparisons — covered by Tasks 7/8 seams, not re-proved here), and the `removeRule` tail (A032–A036: `removeSongFlags`/byte-exact restoration/double-remove — the removed function under test is dead).

### Exact write set
- `src/swift/project/SongsMk.swift` (new): `path(root:)`, `parseFlags(mkFile:)`, `writeRule(mkFile:label:flags:) throws`.
- `src/checks/projectstore/SongsMkChecks.swift` (new): A007–A014, A025, A030–A031 equivalents as temp-dir checks.

### Prerequisites
- Task 6 landed (`SongFlags` helpers are used by the checks to build new flag lists).
- Task 7 landed (`writeSongFlags` routing target exists; this task provides the callee).

### Interface contract
- `public enum SongsMk { public static func path(root: URL) -> URL; public static func parseFlags(mkFile: URL) -> [String: [String]]; public static func writeRule(mkFile: URL, label: String, flags: [String]) throws }`.
- `path` = `<root>/songs.mk`.
- `parseFlags`: Text-mode read (lossy UTF-8, newline-split); variable assignments `^([A-Za-z_][A-Za-z0-9_]*)\s*[:?+]?=\s*(.*)$` after `#`-comment cut (collected from non-recipe lines only); rule lines `^(?:\$\(MID_SUBDIR\)|sound/songs/midi)/(\w+)\.s\s*:` set the pending label; tab-prefixed lines are recipes — when a recipe contains `$(MID)` it is recorded for the pending label via `flagsFromRecipe` (whitespace-split, keep `-`-prefixed tokens, `expandVars` each) and the pending label clears; any other line clears the pending label and collects variables. Missing file → empty map.
- `writeRule`: binary in/out like `writeMidiCfgLine` (`endsWithNewline`/`crlf` detection, per-line `\r` preservation, rejoin with `\n`); missing file is a thrown error (songs.mk is never created from scratch); variables collected from non-tab lines; first rule matching `label` wins; the `$(MID)` recipe line is rewritten keeping the `$@` prefix (`text` up to and including `$@`, else `\t$(MID) $< $@`) and keeping any existing spelling whose expanded value equals the new flag case-insensitively; a rule without a `$(MID)` recipe gains one; a missing rule appends `$(MID_SUBDIR)/<label>.s: %.s: %.mid` plus the recipe with a blank separator line matching the file's EOL style.
- `expandVars`: `$(NAME)` substitution, unknown names → `""`, depth cap 8 iterations.

### Implementation steps
1. Implement `path` as a pure append of `songs.mk` to the project root.
2. Implement `parseFlags` exactly as above; recipe detection is `hasPrefix("\t")` — spaces do NOT count.
3. Implement `expandVars` with the `\$\(([A-Za-z_][A-Za-z0-9_]*)\)` regex, looping at most 8 passes and breaking when no `$` remains or no reference matches.
4. Implement `writeRule` on `Data` lines: collect vars first (non-tab lines only), locate the first rule for `label`, rewrite only the `$(MID)` recipe line with the spelling-preservation map keyed by uppercased flag letter, preserve that line's `\r`; implement the two append branches (recipe-less rule vs missing rule) with `crlf`-style EOL.
5. Write `SongsMkChecks.swift` on temp-dir fixtures (written inline, not `ProjectFixture` copies): parsed expanded flags contain no `$` (A007); volume write via `MidiCfg.writeSongFlags` changes exactly one recipe line with `$(MID)` after the target line and creates no midi.cfg (A008–A014); `-R$(STD_REVERB)` spelling survives a `-V099` rewrite (A025); appending `mus_mkcheck_new` with `-E -R50 -G<arg> -V100` parses back equal (A030–A031).

### Acceptance predicate
- Expanded parse contains no `$`; a volume rewrite touches exactly one recipe line and creates no midi.cfg; `-R$(STD_REVERB)` spelling is preserved; an appended rule round-trips through `parseFlags` with identical flags.
- Named checks: `deno task verify --filter projectstore-songsmk --verbose` covers the A007–A014, A025, A030–A031 equivalents listed above (A032–A036 removeRule tail explicitly not ported — dead surface).

### Task-specific constraints
- Tab preservation: recipe lines are tab-prefixed (`hasPrefix("\t")`); the rewrite MUST emit a leading `\t` and MUST NOT convert tabs to spaces or strip trailing whitespace elsewhere; every non-recipe line stays byte-identical.
- Variable-spelling preservation compares expanded values case-insensitively (`it->second.compare(flag, CaseInsensitive) == 0` keeps `it->first`); the map key is the uppercased flag letter; `-v080`-style case drift in the new flags MUST NOT create duplicate letters.
- `NSRegularExpression` `\w` in `ruleRe` matches the Qt `\w` class for ASCII labels; verify with labels containing dots/dashes (must NOT match) and document any Unicode divergence in a code comment.
- `removeRule` is dead: the word `removeRule`/`removeSongFlags` MUST NOT appear in `SongsMk.swift` or `SongsMkChecks.swift`; the doubly-appended blank-separator cleanup logic ports nowhere.
- Windows first-party rules per plan.md Global Constraints (no `FileManager.replaceItem`, `CryptoKit`, `Dispatch`, `NSString` path helpers; MSVC-clean C++ if touched).
