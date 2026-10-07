# Native voicegroup loader behavioral spec

Reference for the Swift `PorydawVoicegroup` module. Every rule cites the C
source line it restates. Sources: `voicegroup_loader.c` (3932 lines),
`voicegroup_load_session.c` (614), `voicegroup_asset_batch.c` (1006),
`voicegroup_asset_batch.h` (70), `voicegroup_loader.h`,
`voicegroup/voicegroup_types.h` (62). All `voicegroup_loader.c:NNN`
citations refer to `external/poryaaaa/packages/poryaaaa/plugin/voicegroup_loader.c`;
other files are cited with their filename prefix.

Public constants: `VOICEGROUP_SIZE 128` (`voicegroup_loader.h:9`),
`VG_MAX_PATH_LEN 512` (`voicegroup_loader.h:10`), `VG_VOICE_NAME_LEN 48`
(`voicegroup_loader.h:11`), `VG_CONFIG_PATH_CAP 8` (`voicegroup_loader.h:12`),
`VG_MAX_SYMBOL_LEN 256` (`voicegroup_loader.h:13`). Private constants:
`MAX_LINE 1024` (`voicegroup_loader.c:107`), `MAX_PATH_LEN 512`
(`voicegroup_loader.c:108`), `MAX_SYMBOL_LEN 256` (`voicegroup_loader.c:110`),
`INITIAL_CAPACITY 64` (`voicegroup_loader.c:112`), `MAX_DISCOVERED_PATHS 32`
(`voicegroup_loader.c:114`). `PATH_SEP` is `'\\'` on `_WIN32`, `'/'` otherwise
(`voicegroup_loader.c:23`, `voicegroup_loader.c:25`).

## 1. Discovery

`ProjectDiscovery` fields in order (`voicegroup_loader.c:152-164`):
`directSoundDataFiles`, `progWaveDataFiles`, `keySplitTableFiles`,
`voicegroupDirs`, `monolithicVGFiles`, `wavSampleDirs` (all `PathList`),
then `projectRoot[MAX_PATH_LEN]`, borrowed `const VoicegroupLoaderConfig* cfg`,
`int deepScanned` (lazy-deep-scan once-flag). `PathList` is
`char paths[MAX_DISCOVERED_PATHS][MAX_PATH_LEN]` plus `int count`
(`voicegroup_loader.c:146-150`).

- `pathlist_add` silently drops the add when `count >= MAX_DISCOVERED_PATHS`
  (32) (`voicegroup_loader.c:617-620`) or on case-sensitive `strcmp` duplicate
  (`voicegroup_loader.c:621-625`); else `strncpy` capped at `MAX_PATH_LEN-1`
  with forced NUL and `count++` (`voicegroup_loader.c:626-628`).
- `build_path(dest, destSize, base, relative)` joins
  `base + PATH_SEP + relative` (`voicegroup_loader.c:570-572`), then normalizes
  every `/` and `\\` in the result to `PATH_SEP` (`voicegroup_loader.c:573-579`).
  NULL/zero args empty `dest` and return false (`voicegroup_loader.c:555-562`);
  `baseLen + 1 + relLen >= destSize` empties `dest` and returns false, so an
  exact fit with no NUL room still fails (`voicegroup_loader.c:565-569`).
  Truncation is a hard failure, never an alias (`voicegroup_loader.c:551-552`).
- `file_exists` is `stat == 0 && S_ISREG` (symlinks followed)
  (`voicegroup_loader.c:584-587`). `is_directory` is stat `S_ISDIR`, 0 on stat
  failure (`voicegroup_loader.c:591-596`). `dirent_is_dir` returns 1 for
  `DT_DIR`, 0 for `DT_REG` with no stat (`voicegroup_loader.c:607-610`); for
  `DT_UNKNOWN`/`DT_LNK` it joins parent+name and stats via `is_directory`
  (`voicegroup_loader.c:611-613`).
- `str_ends_with_ci` returns 0 when the suffix is longer than the string
  (`voicegroup_loader.c:636-637`), else `tolower` tail comparison
  (`voicegroup_loader.c:639-642`).

`discover_project(projectRoot, cfg, out)` (`voicegroup_loader.c:1261`):
`memset(out, 0)` (`voicegroup_loader.c:1263`), `snprintf` of `projectRoot`
(`voicegroup_loader.c:1264`), borrows `cfg` (`voicegroup_loader.c:1265`),
then in fixed order: `discover_config_paths` (`voicegroup_loader.c:1269`),
`discover_standard_data_files`, `discover_standard_voicegroup_dirs`,
`discover_standard_monolithic_file`, and the eager shallow scan of the
project tree. Config paths therefore precede standard paths in every list.

- `discover_config_paths` with NULL `cfg` returns immediately
  (`voicegroup_loader.c:1196-1197`). Each `soundDataPaths[i]` joined to root
  with `file_exists` is added to `directSoundDataFiles`
  (`voicegroup_loader.c:1199-1205`); each `voicegroupPaths[i]` goes through
  `discover_config_voicegroup_path` (`voicegroup_loader.c:1206-1208`); each
  `sampleDirs[i]` with `is_directory` is added to `wavSampleDirs`. Counts are
  clamped by `config_path_count`: `< 0` becomes 0, `> VG_CONFIG_PATH_CAP`
  becomes the cap (`voicegroup_loader.c:1144-1151`).
- `discover_config_voicegroup_path` (`voicegroup_loader.c:1176`): join
  (`voicegroup_loader.c:1179`); if a directory, add to `voicegroupDirs`, scan
  it for monolithic files, `probe_keysplit_data_in_dir`, return
  (`voicegroup_loader.c:1180-1186`); if a regular file, add to
  `monolithicVGFiles` only if `is_monolithic_voicegroup_file` passes.
- `discover_standard_data_files` probes in fixed order
  (`voicegroup_loader.c:1226-1232`): `sound/direct_sound_data.inc` then
  `sound/direct_sound_synth_data.inc`, both into `directSoundDataFiles`
  (`voicegroup_loader.c:1228-1229`); `sound/programmable_wave_data.inc` into
  `progWaveDataFiles` (`voicegroup_loader.c:1230`);
  `sound/keysplit_tables.inc` into `keySplitTableFiles`. Each via
  `discover_standard_data_file`: join plus `file_exists` gate
  (`voicegroup_loader.c:1218-1224`).
- `discover_standard_voicegroup_dirs` (`voicegroup_loader.c:1234`): joins
  `sound/voicegroups`; not a directory means return with nothing added
  (`voicegroup_loader.c:1238-1239`); else adds it to `voicegroupDirs`
  (`voicegroup_loader.c:1240`), adds `keysplits` under it to `voicegroupDirs`
  (not to `keySplitTableFiles`) when it is a directory
  (`voicegroup_loader.c:1241-1244`), and likewise `drumsets` under it.
- `discover_standard_monolithic_file` (`voicegroup_loader.c:1250`) probes
  exactly `sound/voice_groups.inc` (`voicegroup_loader.c:1253`), returns on
  miss (`voicegroup_loader.c:1255-1256`), and adds it to `monolithicVGFiles`
  only if the monolithic gate passes (`voicegroup_loader.c:1257-1258`).

Directory facts: `DirFacts` holds `hasWavOrAif`, `hasKeysplitTablesInc`
(entry exactly `"keysplit_tables.inc"`), `hasKeysplitTablesS` (exactly
`"keysplit_tables.s"`), `hasKeysplitsSubdir` (dir exactly `"keysplits"`),
`macroCandidates[5][MAX_DIRENT_NAME]` plus count (first 5 `.inc`/`.s` files in
readdir order), and a heap `subdirs` list in readdir order
(`voicegroup_loader.c:923-933`).

- `collect_dir_fact` (`voicegroup_loader.c:961`): dotfiles skipped, true
  (`voicegroup_loader.c:963-964`). Directories: exact `"keysplits"` sets
  `hasKeysplitsSubdir` (`voicegroup_loader.c:967-968`); every directory is
  appended to `subdirs` and its result returned (`voicegroup_loader.c:969`).
  Files: `.wav`/`.aif` (case-insensitive) set `hasWavOrAif`
  (`voicegroup_loader.c:971-974`); exact-name keysplit tables set their flags;
  `.inc`/`.s` files fill `macroCandidates` up to 5.
- `collect_dir_facts` (`voicegroup_loader.c:991`): `opendir` failure returns
  true with zeroed facts (`voicegroup_loader.c:993-995`); a false (subdir OOM)
  frees `subdirs`, NULLs it, closes, returns false
  (`voicegroup_loader.c:1001-1005`).
- `discover_dir_facts` applies parent facts first in fixed order
  (`voicegroup_loader.c:1048-1065`): `discover_macro_directory`
  (`voicegroup_loader.c:1050`); `hasWavOrAif` adds the dir to `wavSampleDirs`
  (`voicegroup_loader.c:1051-1052`); `hasKeysplitTablesInc` joins
  `"keysplit_tables.inc"` into `keySplitTableFiles`
  (`voicegroup_loader.c:1054-1058`), likewise `"keysplit_tables.s"`
  (`voicegroup_loader.c:1059-1063`); `hasKeysplitsSubdir` runs
  `discover_keysplit_subdir` (`voicegroup_loader.c:1064-1065`).
- `discover_macro_directory` (`voicegroup_loader.c:1011`): for each of the at
  most 5 candidates in order, join and gate on `file_has_voice_macros`
  (`voicegroup_loader.c:1016-1018`); the first hit adds the directory (not the
  file) to `voicegroupDirs` and returns (`voicegroup_loader.c:1019-1020`).
- `file_has_voice_macros` (`voicegroup_loader.c:852`): missing file is 0
  (`voicegroup_loader.c:854-856`); scans the first 50 lines
  (`voicegroup_loader.c:857-859`); any `strstr` of `"voice_directsound"`,
  `"voice_square"`, `"voice_programmable_wave"`, `"voice_noise"`,
  `"voice_keysplit"` (`voicegroup_loader.c:861-862`) or `"voice_group"`
  (`voicegroup_loader.c:863`) returns 1. No comment stripping.
- `discover_keysplit_subdir` (`voicegroup_loader.c:1024`): joins
  `dirPath + "keysplits"`; `opendir` failure returns
  (`voicegroup_loader.c:1026-1030`); dotfiles skipped
  (`voicegroup_loader.c:1035-1036`); only `.s`/`.inc` kept
  (`voicegroup_loader.c:1037-1041`); each joined and added to
  `keySplitTableFiles` without a `file_exists` recheck
  (`voicegroup_loader.c:1042-1043`).
- `probe_keysplit_data_in_dir` (`voicegroup_loader.c:886`) probes
  `<dir>/keysplit_tables.inc` then `<dir>/keysplit_tables.s`, each
  join-plus-`file_exists` into `keySplitTableFiles`
  (`voicegroup_loader.c:890-895`); then enumerates `<dir>/keysplits` gated on
  `is_directory` (`voicegroup_loader.c:897-899`), skipping dot entries
  (`voicegroup_loader.c:901-908`), keeping `.s`/`.inc`
  (`voicegroup_loader.c:909-910`), joining and adding without recheck
  (`voicegroup_loader.c:911-913`).

Tree walk: `discover_scan_tree` zeroes facts, collects them (OOM returns
leaking nothing) (`voicegroup_loader.c:1083-1086`), then
`discover_dir_facts` followed by `discover_subdirectories`, so parents add
before children (`voicegroup_loader.c:1087-1088`), then frees `subdirs`
(`voicegroup_loader.c:1089`). `discover_subdirectories` returns without
recursing when `depth >= maxDepth` (`voicegroup_loader.c:1071-1072`), else
joins each readdir-order subdir and recurses at `depth+1`
(`voicegroup_loader.c:1073-1078`).

- `is_monolithic_voicegroup_file` (`voicegroup_loader.c:1097`): missing file
  is 0 (`voicegroup_loader.c:1099-1101`); scans at most 500 lines
  (`voicegroup_loader.c:1109`); per line `strip_comment`, `rtrim`, `ltrim`
  (`voicegroup_loader.c:1111-1113`); `labelCount++` when the line contains
  `"::"` with a first char that is neither `'.'` nor NUL
  (`voicegroup_loader.c:1115-1118`); `voiceMacroCount++` on `strstr` of the six
  voice macros (`voicegroup_loader.c:1119-1124`); `includeCount++` on
  `strstr(trimmed, ".include")` (`voicegroup_loader.c:1125-1128`); returns 1
  iff `labelCount >= 2 && voiceMacroCount > 0 && voiceMacroCount > includeCount`
  (`voicegroup_loader.c:1135-1139`).
- `discover_config_monolithic_files` (`voicegroup_loader.c:1153`): `opendir`
  failure returns (`voicegroup_loader.c:1155-1157`); dotfiles skipped
  (`voicegroup_loader.c:1161-1162`); only `.inc`/`.s` kept
  (`voicegroup_loader.c:1163-1167`); join plus monolithic gate into
  `monolithicVGFiles` (`voicegroup_loader.c:1168-1171`).

Lazy deep scan: `discovery_ensure_deep_scan` is once-only via
`if (disc->deepScanned) return; disc->deepScanned = 1`
(`voicegroup_loader.c:1289-1291`); it runs
`discover_scan_tree(soundDir, 0, 3, disc)` when `<root>/sound` is a directory,
so levels 0, 1, 2 are visited and depth 3 stops it
(`voicegroup_loader.c:1293-1296`). It appends after eager entries, so
first-hit-wins consumers resolve identically for stock projects
(`voicegroup_loader.c:1275-1286`). Trigger sites: `find_voicegroup` re-probes
after it on a miss (`voicegroup_loader.c:2225-2229`);
`search_sample_directories` runs it before iterating `wavSampleDirs`
(`voicegroup_loader.c:1913-1914`); the keysplit-table lookup short-circuits
when deep-scanned and `parsedFileCount >= keySplitTableFiles.count`.

## 2. Sound data maps

`SymbolMapping` record (`voicegroup_loader.c:177-184`): `size_t recordSize`,
`size_t pathOffset`, `uint8_t isSynth`, `uint8_t synthDesc[6]`, `char text[]`
holding the NUL-terminated symbol followed by the NUL-terminated path.
`SymbolMap` is a single owned `unsigned char* entries` allocation with
`size`, `capacity`, `int count` (`voicegroup_loader.c:186-192`).

- `symbol_map_init` zeroes the map (`voicegroup_loader.c:714-717`).
  `symbol_map_free` frees `entries` and zeroes the map, freeing names, paths,
  and synth descriptors together (`voicegroup_loader.c:720-724`).
- `symbol_map_append(map, symbol, path, synthDesc)` (`voicegroup_loader.c:727`)
  refuses when `count == INT_MAX` (`voicegroup_loader.c:729-730`), truncates
  the symbol to `MAX_SYMBOL_LEN-1` (`voicegroup_loader.c:733-734`) and the path
  to `MAX_PATH_LEN-1` (`voicegroup_loader.c:735-736`); `recordSize` is
  `sizeof(SymbolMapping) + symbolLength + pathLength + 2`
  (`voicegroup_loader.c:737`), rounded up to `_Alignof(SymbolMapping)`.
- `symbol_map_add` stores a file record (`isSynth = 0`) with a NULL descriptor
  (`voicegroup_loader.c:777-780`); `symbol_map_add_synth` stores an inline
  synth record (`isSynth = 1`) with an empty path plus the 6-byte descriptor
  (`voicegroup_loader.c:783-786`).
- Lookup is first-definition-wins: `symbol_map_find_entry` walks records and
  returns the first `strcmp` hit (`voicegroup_loader.c:789-799`); later
  duplicates are appended but unreachable. `symbol_map_find` returns the path
  only for non-synth entries, else NULL (`voicegroup_loader.c:803-807`);
  `symbol_map_find_synth` returns `synthDesc` only for synth entries, else NULL
  (`voicegroup_loader.c:811-815`). Both views are borrowed until the next
  append or destruction.

`parse_synth_macro_line(trimmed, desc[6])` (`voicegroup_loader.c:1313`)
returns 1 on match, 0 otherwise. Table (`voicegroup_loader.c:1320-1327`):
`"set_synth_custom"` type 0 with params (`voicegroup_loader.c:1321`),
`"set_synth_pulse"` type 0 with params (`voicegroup_loader.c:1322`),
`"set_synth_25"` type 1 no params (`voicegroup_loader.c:1323`),
`"set_synth_saw"` type 1 no params (`voicegroup_loader.c:1324`),
`"set_synth_50"` type 2 no params (`voicegroup_loader.c:1325`),
`"set_synth_triangle"` type 2 no params (`voicegroup_loader.c:1326`). Matching
is `strncmp` plus a boundary check requiring the next char to be NUL, space, or
tab (`voicegroup_loader.c:1332-1336`); a comma directly after the name does
NOT match. Byte layout: `memset(desc, 0, 6); desc[0] = 0x80; desc[1] = type`
(`voicegroup_loader.c:1338-1340`). With params, up to 4 comma/space-separated
base-0 ints fill `desc[2+n]` (`voicegroup_loader.c:1344-1351`); missing params
stay 0, a 5th param is silently ignored, values truncate to `uint8_t` with no
range check. No-param macros leave `desc[2..5]` zero.

`parse_sample_label` (`voicegroup_loader.c:1366`): a leading run of
`[A-Za-z0-9_]` (`voicegroup_loader.c:1373) of length > 0 immediately followed
by `':'` (`voicegroup_loader.c:1376`). Both `Name::` and `Name:` are labels;
the second colon is leftover, ignored (`voicegroup_loader.c:1359-1364`).
Overflow (`nameLen >= outSize`) returns -1; success returns 1, else 0
(`voicegroup_loader.c:1376-1382`). No whitespace tolerance before the colon; a
line `Label: .align 2` IS a label.

`parse_direct_sound_data_file` (`voicegroup_loader.c:1389`): opens text mode,
per line `strip_comment`, `rtrim`, `ltrim` (`voicegroup_loader.c:1404-1406`),
with a pending `currentSymbol` cursor initially empty. Label lines
(`lab == 1`) continue, leaving the label pending; `lab == -1` closes and
returns -1 (`voicegroup_loader.c:1409-1416`). The `.incbin` branch requires a
pending symbol and a `strstr(trimmed, ".incbin")` substring match anywhere
(`voicegroup_loader.c:1418`); the path is the text between the first and
second `"` (`voicegroup_loader.c:1420-1427`); single quotes are unsupported; a
line with no quotes is silently ignored but still clears `currentSymbol`
(`voicegroup_loader.c:1435`). The path is stored as-is (`(void)projectRoot`,
`voicegroup_loader.c:1391`) via `symbol_map_add`; failure closes and returns
-1 (`voicegroup_loader.c:1428-1432`). Otherwise, with a pending symbol, a
`set_synth_*` line stores via `symbol_map_add_synth`
(`voicegroup_loader.c:1438-1449`). A pending label followed (possibly after
ignored lines, since the pending symbol survives them) by a synth line becomes
a synth record with an empty path; followed by `.incbin` it becomes a file
record; after either consumption the cursor is cleared. There is no `.bin` /
`.aif` / `.wav` directive handling, no cries exclusion, and no `.include` /
`.align` handling in this function: those lines are ignored and the pending
symbol survives them.

`parse_programmable_wave_data_file` (`voicegroup_loader.c:1460`): identical
label logic and `.incbin` quote logic, but no synth-macro branch, so
`set_synth_*` lines are ignored and a pending symbol survives them; only
label-plus-`.incbin` calls `symbol_map_add`.

`parse_all_direct_sound_data` loops `disc->directSoundDataFiles.paths[i]` and
fails on the first nonzero parse result (`voicegroup_loader.c:1761-1773`
region); `parse_all_programmable_wave_data` does the same over
`progWaveDataFiles`. `parse_keysplit_tables_range(disc, map, fromIndex)`
parses `keySplitTableFiles[fromIndex..count)` then sets
`map->parsedFileCount = disc->keySplitTableFiles.count`
(`voicegroup_loader.c:1785-1796`); `parse_all_keysplit_tables` is the range
from 0 (`voicegroup_loader.c:1798-1801`). `keysplit_map_find_or_rescan_checked`
(`voicegroup_loader.c:1804`): linear find first; on a hit, or a NULL `disc`,
return out plus true (`voicegroup_loader.c:1806-1814` region); when deep
scanned and `parsedFileCount >= keySplitTableFiles.count`, nothing new is
possible, so out NULL plus true; else run the deep scan, parse only the
new-file range, restore count on zero new entries, and re-find.

## 3. Keysplit tables

`KeySplitDef` is `name[MAX_SYMBOL_LEN]`, `startingNote`, `table[128]`,
`maxNote` (`voicegroup_loader.c:194-200`), zero-initialised at begin
(`voicegroup_loader.c:1564-1567` region). `KeySplitMap` is
`entries/count/capacity/parsedFileCount` (`voicegroup_loader.c:202-210`):
`parsedFileCount` counts how many discovery `keySplitTableFiles` entries have
been parsed into the map. `keysplit_map_init` zeroes all four fields
(`voicegroup_loader.c:821-826`); `keysplit_map_free` frees entries and zeroes
all four (`voicegroup_loader.c:828-834`); `keysplit_map_find` is a linear
`strcmp` returning the first equal entry or NULL
(`voicegroup_loader.c:836-844`), so duplicate table names are first-win on
lookup. `keysplit_map_next` grows with `newCap = capacity ? capacity*2 :
INITIAL_CAPACITY`, `realloc`, NULL on OOM (`voicegroup_loader.c:1541-1551`),
and returns `&entries[count]` WITHOUT incrementing; the caller increments
after filling (both begins do, `voicegroup_loader.c:1576/1598`).

- `keysplit_begin_macro(parser, name, startNote)` (`voicegroup_loader.c:1555`):
  rejects `strlen(name) >= MAX_SYMBOL_LEN - 9` (room for the 9-char
  `"keysplit_"` prefix plus NUL) and `startNote` outside `0..127`
  (`voicegroup_loader.c:1557-1562`); `rtrim(name)`, takes a slot, `memset`s it,
  `snprintf`s `"keysplit_%s"`, and sets `startingNote`, `current`,
  `lastNote = startNote` (`voicegroup_loader.c:1564-1578`). Macro-form
  `keysplit Foo, 60` is therefore stored as `keysplit_Foo`.
- `keysplit_begin_set(parser, name, startNote)` (`voicegroup_loader.c:1580`):
  rejects overlong names and `startNote` outside `0..127`
  (`voicegroup_loader.c:1582-1587`); `rtrim`, slot, `memset`, verbatim `strncpy`
  plus NUL with NO prefix added (`voicegroup_loader.c:1588-1594`); same
  `startingNote`/`lastNote`/`count++` bookkeeping
  (`voicegroup_loader.c:1595-1598`).
- `parse_keysplit_macro_line` (`voicegroup_loader.c:1602`): requires the
  literal `"keysplit "` (9 chars incl. exactly one space; tab or extra spaces
  do not match) then UNHANDLED (`voicegroup_loader.c:1604`); comma-symbol via
  `vg_extract_comma_symbol`, nonzero means INVALID (`voicegroup_loader.c:1608`
  with `vg_extract_comma_symbol` at `voicegroup_loader.c:325`);
  `vg_parse_next_int` for the base-0 start note (`voicegroup_loader.c:389`),
  then `vg_line_finished` strictness (`voicegroup_loader.c:1610-1614`);
  `keysplit_begin_macro` failure is INVALID (`voicegroup_loader.c:1615`).
- `keysplit_split_values_are_valid(index, endNote, lastNote)`
  (`voicegroup_loader.c:1620`): `0 <= index <= 127`
  (`voicegroup_loader.c:1622-1625`), `0 <= endNote <= 128`
  (`voicegroup_loader.c:1626-1629`), `0 <= lastNote <= 128`
  (`voicegroup_loader.c:1630-1633`), and `endNote >= lastNote`
  (`voicegroup_loader.c:1634`). `endNote` may be 128 (exclusive upper bound,
  filling through note 127).
- `parse_keysplit_split_line` (`voicegroup_loader.c:1637`): literal `"split "`
  (6 chars, single space) (`voicegroup_loader.c:1639`); no current table means
  HANDLED no-op (`voicegroup_loader.c:1641-1642`); else int, comma
  (`vg_expect_comma`, `voicegroup_loader.c:420`), int, line-finished
  (`voicegroup_loader.c:1644-1653`); validation against
  `lastNote = parser->lastNote` (`voicegroup_loader.c:1654`); fills
  `table[note] = (uint8_t)index` for `note` in `[lastNote, endNote)`
  (`voicegroup_loader.c:1656-1657`); `lastNote = endNote`
  (`voicegroup_loader.c:1658`); `maxNote = max(maxNote, endNote)`
  (`voicegroup_loader.c:1659-1660`).
- `parse_keysplit_set_line` (`voicegroup_loader.c:1664`): literal `".set "`
  (5 chars) (`voicegroup_loader.c:1666`); comma-symbol name, then after spaces
  a literal `'.'`, spaces, a literal `'-'`, then the start-note int, then
  line-finished (`voicegroup_loader.c:1669-1683`), i.e.
  `.set <name>, . - <startNote>`; any deviation is INVALID; success calls
  `keysplit_begin_set` with the verbatim name (`voicegroup_loader.c:1684`).
- `parse_keysplit_bytes_line` (`voicegroup_loader.c:1689`): literal `".byte "`
  (6 chars) (`voicegroup_loader.c:1691`); no current table means HANDLED no-op
  (`voicegroup_loader.c:1693-1694`); else loops skipping `' '`, `'\t'`, `','`
  and breaking at NUL (`voicegroup_loader.c:1696-1701`); each
  `vg_parse_next_int` value with `0 <= value <= 127` else INVALID
  (`voicegroup_loader.c:1703-1708`); `lastNote` outside `0..127` is INVALID
  (`voicegroup_loader.c:1709-1712`); stores
  `table[lastNote] = (uint8_t)value`, bumps `maxNote` when exceeded, and
  `lastNote++` (`voicegroup_loader.c:1713-1716`).
- `parse_keysplit_line` tries macro, split, set, bytes in order; the first
  non-UNHANDLED wins (`voicegroup_loader.c:1721-1733`). Anything else
  (labels, `.align`, `.global`, blank lines) falls to bytes-line `strncmp`
  failure and is UNHANDLED (ignored).
- `parse_keysplit_tables_file` (`voicegroup_loader.c:1735`): `fopen`, NULL
  means stderr plus return -1 (`voicegroup_loader.c:1737-1742`); parser init
  `{map, NULL, 0}`; per line `strip_comment`/`rtrim`/`ltrim` then
  `parse_keysplit_line`; INVALID closes and returns -1
  (`voicegroup_loader.c:1745-1754`); `current`/`lastNote` carry across the
  whole file (multiple tables per file; no per-table close directive). No
  dedupe: every `keysplit`/`.set` begin appends a new `KeySplitDef`.

`vg_skip_horizontal_space` skips `' '` and `'\t'` only
(`voicegroup_loader.c:1529-1534`); `vg_line_finished(p)` is true iff the rest
after spaces/tabs is `'\0'` (`voicegroup_loader.c:1536-1539`).

## 4. Voicegroup location

`VoicegroupLocation` is `filePath[MAX_PATH_LEN]`, `label[MAX_SYMBOL_LEN]`
(non-empty inside a monolithic file), `int found`
(`voicegroup_loader.c:166-171`). `set_voicegroup_file_location` zeroes the
struct (`voicegroup_loader.c:1970`), `strncpy`s the path (`voicegroup_loader.c:1971`),
sets `found = 1`, and does NOT set the label (`voicegroup_loader.c:1972`).

- `find_voicegroup_file(dirPath, subdir, prefix, name, location)`
  (`voicegroup_loader.c:1975`): builds `dir/subdir/prefix+name.inc` (or
  `dir/prefix+name.inc` without subdir) with `PATH_SEP`
  (`voicegroup_loader.c:1980-1982`); `file_exists` sets the location and
  returns true (`voicegroup_loader.c:1983-1987`); else rebuilds with `.s`
  (`voicegroup_loader.c:1988-1991`); a miss returns false
  (`voicegroup_loader.c:1992-1993`). Extension order is `.inc` first, then `.s`.
- `find_voicegroup_in_directories` linearly scans directories in order with no
  subdir and the given prefix; first hit wins (`voicegroup_loader.c:1998-2007`).
- `find_sub_voicegroup_in_directories(dirs, subdir, name, loc)`
  (`voicegroup_loader.c:2011`): pass 1 tries every dir as `dir+subdir` with
  prefix `""` (`voicegroup_loader.c:2017-2020`); pass 2 tries only dirs whose
  last component equals `subdir` (`dir_last_component_is`) with `subdir=NULL`
  and prefix `""` (`voicegroup_loader.c:2021-2027`).
- `dir_last_component_is(dirPath, name)` (`voicegroup_loader.c:1950`):
  longer name than path is 0 (`voicegroup_loader.c:1952-1955`); tail mismatch
  is 0 (`voicegroup_loader.c:1956-1958`); tail at start is 1
  (`voicegroup_loader.c:1959-1960`); else the preceding char must be `/` or
  `\\` (`voicegroup_loader.c:1961-1962`).
- `make_keysplit_voicegroup_name(vgName, baseName[MAX_SYMBOL_LEN])`
  (`voicegroup_loader.c:2031`): `strstr(vgName, "_keysplit")` takes the FIRST
  occurrence (`voicegroup_loader.c:2033`); absent is false
  (`voicegroup_loader.c:2034-2035`); empty base is false
  (`voicegroup_loader.c:2036-2038`); base at/over `MAX_SYMBOL_LEN` is false
  (`voicegroup_loader.c:2039-2040`); else copies the base plus NUL and returns
  true (`voicegroup_loader.c:2041-2043`). Everything from the first
  `"_keysplit"` onward is truncated.
- `make_drumset_voicegroup_name(vgName, baseName)` (`voicegroup_loader.c:2046`):
  `strstr(vgName, "_drumset")` first occurrence (`voicegroup_loader.c:2048`);
  absent is false (`voicegroup_loader.c:2049-2050`); tail is the text after the
  8-char infix (`voicegroup_loader.c:2052`); empty base is false
  (`voicegroup_loader.c:2053-2054`); `baseLength + strlen(tail)` at/over
  `MAX_SYMBOL_LEN` is false (`voicegroup_loader.c:2055-2056`); else copies base
  then appends the tail (`voicegroup_loader.c:2057-2058`), so e.g.
  `foo_drumset2` becomes `foo2`.
- `find_keysplit_voicegroup` derives the base (else false,
  `voicegroup_loader.c:2064-2066`) and delegates to subdir `"keysplits"`
  (`voicegroup_loader.c:2067`); `find_drumset_voicegroup` likewise with
  `"drumsets"` (`voicegroup_loader.c:2070-2075`).
- `monolithic_voicegroup_has_label(file, label, labelLength)`
  (`voicegroup_loader.c:2078`): `fgets` loop (`voicegroup_loader.c:2081`);
  `strip_comment` then `ltrim` (`voicegroup_loader.c:2083-2084`); `strncmp`
  mismatch continues (`voicegroup_loader.c:2085-2086`); a NUL
  (`voicegroup_loader.c:2088-2089`) or whitespace
  (`voicegroup_loader.c:2090-2091`) trailing char is true. The label must be a
  whole token prefix.
- `find_monolithic_voicegroup(files, vgName, loc)` (`voicegroup_loader.c:2096`):
  `strlen(vgName) >= MAX_SYMBOL_LEN` is false (`voicegroup_loader.c:2098-2099`);
  label is `snprintf("%s::", vgName)` (`voicegroup_loader.c:2100-2101`);
  format failure or truncation is false (`voicegroup_loader.c:2102-2105`); per
  file `fopen "r"`, skip on failure (`voicegroup_loader.c:2108-2110`); label
  check (`voicegroup_loader.c:2111`); `fclose` (`voicegroup_loader.c:2112`);
  skip when absent (`voicegroup_loader.c:2113-2114`); else set the file
  location, `strncpy` the bare `vgName` (no `"::"`) as the label, true
  (`voicegroup_loader.c:2115-2117`).
- `file_declares_voice_group(file, name)` (`voicegroup_loader.c:2127`): empty
  or overlong name is false (`voicegroup_loader.c:2130-2131`); per line
  `strip_comment`, `ltrim` (`voicegroup_loader.c:2135-2136`); `strncmp`
  `"voice_group"` (11 chars, `voicegroup_loader.c:2137-2138`); the next char
  must be NUL or space, rejecting longer macro names
  (`voicegroup_loader.c:2139-2141`); the declared name after `ltrim` must match
  with a NUL, comma, or space tail (`voicegroup_loader.c:2142-2147`).
- `find_declared_voicegroup` (`voicegroup_loader.c:2161`): for each
  `voicegroupDirs` entry in order (`voicegroup_loader.c:2164`), `opendir`,
  skip on failure (`voicegroup_loader.c:2167-2169`); skips directories
  (`voicegroup_loader.c:2173-2174`); keeps only `.inc`/`.s`
  case-insensitive (`voicegroup_loader.c:2175-2176`); joins, skips on
  truncation (`voicegroup_loader.c:2177-2178`); opens and declaration-checks
  each file (`voicegroup_loader.c:2179-2183`); first declarative hit sets an
  UNLABELED file location and returns true (`voicegroup_loader.c:2186-2188`).
  This finds groups whose file name is only a convention (e.g. a drumset file
  declaring its own group), and runs last
  (`voicegroup_loader.c:2152-2160`).

`find_voicegroup_probe` order (`voicegroup_loader.c:2198-2216`):
1. plain filename in `voicegroupDirs` with prefix `""`
   (`voicegroup_loader.c:2204`); 2. keysplit-subdir search
   (`voicegroup_loader.c:2206`); 3. drumset-subdir search
   (`voicegroup_loader.c:2208`); 4. `vg_`-prefixed filename in
   `voicegroupDirs` (`voicegroup_loader.c:2210`); 5. monolithic label search
   (`voicegroup_loader.c:2212`); 6. declared-name search
   (`voicegroup_loader.c:2214`), whose result is returned as-is.
`find_voicegroup` probes, and on a miss with no deep scan yet runs
`discovery_ensure_deep_scan` and probes exactly once more
(`voicegroup_loader.c:2222-2230`).

`path_basename` returns the text after the last `/` or `\\`, or the whole
input (`voicegroup_loader.c:2236-2245`). `next_included_voicegroup`
(`voicegroup_loader.c:2254`) tries index files `sound/voice_groups.inc` then
`sound/voicegroups.inc` in order (`voicegroup_loader.c:2256`); joins each to
the root (`voicegroup_loader.c:2262`); `fopen` failure moves to the next index
(`voicegroup_loader.c:2263-2265`); per line `strip_comment`, `ltrim`, then
`sscanf(trimmed, ".include \"%511[^\"]\"", incPath)` (`voicegroup_loader.c:2269-2275`);
after the line whose include basename equals the current file's basename
(`voicegroup_loader.c:2290-2291`), the next included file that exists on disk
is copied to `outPath` (capped at `outSize - 1` plus NUL) for return 1
(`voicegroup_loader.c:2276-2286`); a missing next file breaks with contiguity
unknowable (`voicegroup_loader.c:2287-2288`); locating the current file ends
index search (`voicegroup_loader.c:2294-2295`); else 0
(`voicegroup_loader.c:2297`).

## 5. Voicegroup line loop and per-macro semantics

Voice types (`voicegroup/voicegroup_types.h:8-23`): `VOICE_DIRECTSOUND 0x00`,
`VOICE_SQUARE_1 0x01`, `VOICE_SQUARE_2 0x02`, `VOICE_PROGRAMMABLE_WAVE 0x03`,
`VOICE_NOISE 0x04`, `VOICE_DIRECTSOUND_NO_RESAMPLE 0x08`,
`VOICE_SQUARE_1_ALT 0x09`, `VOICE_SQUARE_2_ALT 0x0A`,
`VOICE_PROGRAMMABLE_WAVE_ALT 0x0B`, `VOICE_NOISE_ALT 0x0C`,
`VOICE_TYPE_REV 0x10`, `VOICE_DIRECTSOUND_ALT 0x10`, `VOICE_CRY 0x20`,
`VOICE_CRY_REVERSE 0x30`, `VOICE_KEYSPLIT 0x40`, `VOICE_KEYSPLIT_ALL 0x80`.
`ToneData` fields (`voicegroup_types.h:40-60`): `uint8 type, key, length,
panSweep`; union `WaveData* wav` / `uint32_t* wavePointer` / `void* subGroup`;
union `uint8_t* keySplitTable`; `uint8 attack, decay, sustain, release`. No
voice parser below writes `length`; destination arrays are `calloc`'d, so
`length` stays 0.

`VoiceParseContext` (`voicegroup_loader.c:2485-2498`): `projectRoot`, `voices`,
`names`, `registry`, `session`, `directSoundMap`, `programmableWaveMap`,
`keysplitMap`, `discovery`, `waveCache`, `noSubRecurse`.
`VoiceParseProgress` (`voicegroup_loader.c:2500-2505`): `voiceIndex`,
`voicesParsedInSection`, `inContinuation`. `VoicegroupSection`
(`voicegroup_loader.c:2507-2515`): `startLabel`, `searchLabel`, `searchLength`,
`inSection`, `labelFound`, `contiguousFill`. Line results
(`voicegroup_loader.c:2517-2524`): `VG_LINE_UNHANDLED`, `VG_LINE_METADATA`,
`VG_LINE_CONSUMED`, `VG_LINE_HARD_FAIL`, `VG_LINE_STOP`. Argument results
(`voicegroup_loader.c:2526-2531`): `VG_ARGUMENTS_SOFT_MISS`,
`VG_ARGUMENTS_VALID`, `VG_ARGUMENTS_HARD_FAIL`. `SampleVoiceArguments`
(`voicegroup_loader.c:2533-2542`): ints `key, pan, attack, decay, sustain,
release` plus `symbol[MAX_SYMBOL_LEN]`.

- `initialize_voicegroup_section` (`voicegroup_loader.c:2985`): zeroes,
  stores `startLabel` and `contiguousFill` (`voicegroup_loader.c:2987-2989`);
  NULL `startLabel` means whole-file mode: `inSection = 1`, `labelFound = 1`,
  true (`voicegroup_loader.c:2990-2994`); else validates via
  `vg_section_label_valid` (rejects overlong labels and labels containing
  space, `:`, or `,`, `voicegroup_loader.c:434-454`), builds
  `searchLabel = "<startLabel>::"`, and fails on `snprintf` error or
  truncation (`voicegroup_loader.c:2996-3004`).
- `voicegroup_line_is_section_label` (`voicegroup_loader.c:3007`): zero search
  length is false (`voicegroup_loader.c:3009-3010`); prefix match required
  (`voicegroup_loader.c:3011-3012`); the trailing char must be NUL
  (`voicegroup_loader.c:3014-3015`) or whitespace
  (`voicegroup_loader.c:3016`).
- `voicegroup_line_is_section_boundary` (`voicegroup_loader.c:3019`): true
  when the line contains `"::"` with a non-space first char and something
  before the separator (`voicegroup_loader.c:3021-3029`); also true when the
  line starts with the 6 chars `".align"` (`voicegroup_loader.c:3030`), which
  covers `".align 2"`.
- `advance_voicegroup_section` (`voicegroup_loader.c:3033`): NULL `startLabel`
  is always METADATA (`voicegroup_loader.c:3036-3037`); outside the section,
  a section-label line sets `inSection`/`labelFound` and every pre-label line
  is UNHANDLED (`voicegroup_loader.c:3038-3045`); with zero voices parsed in
  the section, every line is METADATA (`voicegroup_loader.c:3047-3048`); in
  continuation, every line is METADATA (`voicegroup_loader.c:3049-3050`); a
  non-boundary line is METADATA (`voicegroup_loader.c:3051-3052`); a boundary
  with `contiguousFill` off is STOP (`voicegroup_loader.c:3053-3054`), with it
  on sets `inContinuation = 1` and is METADATA (`voicegroup_loader.c:3055-3056`).
- `parse_voice_group_metadata` (`voicegroup_loader.c:2956`): non
  `"voice_group "` prefix is UNHANDLED (`voicegroup_loader.c:2959-2960`); in
  continuation or with `noSubRecurse` it is STOP
  (`voicegroup_loader.c:2961-2964`); overlong name symbol is HARD_FAIL
  (`voicegroup_loader.c:2967-2969`); with a valid comma-symbol, an optional
  following int `startingNote` with `0 < startingNote < VOICEGROUP_SIZE` is an
  absolute jump assigning `progress->voiceIndex`
  (`voicegroup_loader.c:2972-2978`); 0/negative/out-of-range values leave the
  index unchanged; always METADATA on success (`voicegroup_loader.c:2982`).
- `parse_voicegroup_content_line` (`voicegroup_loader.c:3058`): section first
  (`voicegroup_loader.c:3063`); UNHANDLED/STOP propagate
  (`voicegroup_loader.c:3064-3067`); non-UNHANDLED metadata returns directly
  (`voicegroup_loader.c:3068-3070`); else `parse_voice_macro` at
  `progress->voiceIndex` with `inContinuation`
  (`voicegroup_loader.c:3071`); HARD_FAIL propagates
  (`voicegroup_loader.c:3072-3073`); CONSUMED increments both `voiceIndex` and
  `voicesParsedInSection` (`voicegroup_loader.c:3074-3078`); returns UNHANDLED
  (`voicegroup_loader.c:3079`).
- `parse_voicegroup_file_session` (`voicegroup_loader.c:3089`): `fopen`
  failure prints stderr and returns -1 (`voicegroup_loader.c:3109-3113`);
  section-init failure closes and returns -1
  (`voicegroup_loader.c:3115-3120`); context carries `noSubRecurse`
  (`voicegroup_loader.c:3121-2133` sic `voicegroup_loader.c:3121-3133`);
  progress starts `{startIndex, 0, 0}` (`voicegroup_loader.c:3134`); per `fgets`
  line it breaks at `voiceIndex >= VOICEGROUP_SIZE`, the 128 cap
  (`voicegroup_loader.c:3139-3140`), strips comment/`rtrim`/`ltrim`
  (`voicegroup_loader.c:3141-3143`), skips empties
  (`voicegroup_loader.c:3144-3145`), dispatches
  (`voicegroup_loader.c:3146`); HARD_FAIL sets the flag and breaks
  (`voicegroup_loader.c:3147-3151`); STOP breaks (`voicegroup_loader.c:3152-3153`).
  Exit closes the file (`voicegroup_loader.c:3159`); hard failure returns -1
  (`voicegroup_loader.c:3160-3161`); a missing section (non-NULL `startLabel`
  never found, `voicegroup_loader.c:3082-3087`) returns -1
  (`voicegroup_loader.c:3162-3163`); else returns `progress.voiceIndex`, the
  slot after the last parsed voice
  (`voicegroup_loader.c:3164`, contract `voicegroup_loader.c:2470-2471`).

Slot-advance rule: increments happen ONLY in `parse_voicegroup_content_line`
on `VG_LINE_CONSUMED` (`voicegroup_loader.c:3075-3077`).

| Line kind | Result | `voiceIndex` advances? |
|---|---|---|
| Valid voice macro, any type | `VG_LINE_CONSUMED` | YES (+1, `voicesParsedInSection` +1) |
| Malformed voice line (bad int list; soft-miss args; missing keysplit/cry symbol), e.g. `voicegroup_loader.c:2682-2683`, `voicegroup_loader.c:2771-2772`, `voicegroup_loader.c:2659-2660`, `voicegroup_loader.c:2752-2753`, `voicegroup_loader.c:2847-2848`, `voicegroup_loader.c:2867-2868`, `voicegroup_loader.c:2873-2874`, `voicegroup_loader.c:2917-2918` | `VG_LINE_CONSUMED` | YES (+1). A malformed voice line DOES advance the slot; the tone holds whatever the populate step wrote (often untouched/zero). |
| `voice_group` metadata incl. `startingNote` jump | `VG_LINE_METADATA` | NO (jump assigns directly, `voicegroup_loader.c:2978`) |
| Section-boundary/metadata passthrough, unknown line | `VG_LINE_UNHANDLED` | NO |
| `voice_group` in continuation / `noSubRecurse` mode; section end (non-contiguous) | `VG_LINE_STOP` | NO (ends the file loop) |
| Continuation boundary (`contiguousFill`) | `VG_LINE_METADATA` + `inContinuation = 1` | NO by itself |
| Hard fail (overlong symbol; wave/prog/subgroup/table/load error) | `VG_LINE_HARD_FAIL` | NO increment; aborts the whole session to -1 |
| 128 cap reached | loop break | NO further slots |

`vg_parse_next_int` (`voicegroup_loader.c:389`): skips spaces/tabs
(`voicegroup_loader.c:391-395`); empty is false (`voicegroup_loader.c:396-399`);
`strtol` base 0 (`voicegroup_loader.c:402`); no digits, `ERANGE`, or
out-of-`int` range is false (`voicegroup_loader.c:403-414`); advances `*p`
past the number (`voicegroup_loader.c:416`). `vg_expect_comma`
(`voicegroup_loader.c:420`) skips spaces/tabs and requires `','`
(`voicegroup_loader.c:422-432`). `vg_extract_comma_symbol`
(`voicegroup_loader.c:325`) trims spaces/tabs around the text before the first
comma; missing comma is 1, empty is 1 (`voicegroup_loader.c:333-351`),
overlong is -1 (`voicegroup_loader.c:352-355`), success copies and advances
past the comma (`voicegroup_loader.c:356-359`). `vg_extract_eol_symbol`
(`voicegroup_loader.c:362`) trims trailing whitespace to end of line; empty is
1 (`voicegroup_loader.c:375-377`), overlong is -1
(`voicegroup_loader.c:379-382`).
`vg_parse_int_list(p, values, count)` (`voicegroup_loader.c:2555`) parses
int/comma pairs, skipping the trailing comma after the last int
(`voicegroup_loader.c:2557-2566`).
`parse_sample_voice_arguments` (`voicegroup_loader.c:2569`) parses
`key , pan , symbol , attack , decay , sustain , release`
(`voicegroup_loader.c:2571-2590`): any int/comma/envelope failure is
`VG_ARGUMENTS_SOFT_MISS`; only an overlong symbol is
`VG_ARGUMENTS_HARD_FAIL` (`voicegroup_loader.c:2580-2583`).

`set_voice_display_name` (`voicegroup_loader.c:301`): NULL dest/symbol empties
dest (`voicegroup_loader.c:303-310`); strips at most ONE matching prefix in
order `"DirectSoundWaveData_"`, `"ProgrammableWaveData_"`, `"voicegroup_"`
(`voicegroup_loader.c:312-321`), only when a non-empty remainder follows
(`p[L]` check, `voicegroup_loader.c:316`); copies capped at
`VG_VOICE_NAME_LEN - 1` with NUL (`voicegroup_loader.c:322-323`).
`set_parsed_voice_name` (`voicegroup_loader.c:2544`) is a no-op for NULL
names, negative index, or index at/over `VOICEGROUP_SIZE`
(`voicegroup_loader.c:2546-2551`), else sets the display name
(`voicegroup_loader.c:2552`).

`parse_voice_macro` dispatch order (`voicegroup_loader.c:2932-2954`):
directsound (`voicegroup_loader.c:2935`), square (`voicegroup_loader.c:2938`),
programmable wave (`voicegroup_loader.c:2941`), noise
(`voicegroup_loader.c:2944`), `voice_keysplit_all`
(`voicegroup_loader.c:2947`), `voice_keysplit`
(`voicegroup_loader.c:2950`), cry (`voicegroup_loader.c:2953`); first
non-UNHANDLED wins. (`voice_group` is metadata, not a macro.)

Per macro (all prefixes are `strncmp` with a required trailing space):

- `parse_directsound_voice` (`voicegroup_loader.c:2633`):
  `"voice_directsound_no_resample "` (30 chars) maps to
  `VOICE_DIRECTSOUND_NO_RESAMPLE` (`voicegroup_loader.c:2637-2640`);
  `"voice_directsound_alt "` (22) maps to `VOICE_DIRECTSOUND_ALT`
  (`voicegroup_loader.c:2642-2645`); `"voice_directsound "` (18) keeps
  `VOICE_DIRECTSOUND` (`voicegroup_loader.c:2647-2650`); else UNHANDLED.
  HARD_FAIL args propagate (`voicegroup_loader.c:2657-2658`); soft miss is
  CONSUMED with no slot write (`voicegroup_loader.c:2659-2660`). Name set from
  the symbol (`voicegroup_loader.c:2661`); `type` as matched
  (`voicegroup_loader.c:2663`); `key = (uint8_t)arguments.key`
  (`voicegroup_loader.c:2664`); `panSweep = arguments.pan ?
  (0x80 | arguments.pan) : 0` (`voicegroup_loader.c:2665`); ADSR are raw
  `(uint8_t)` casts with NO masks (`voicegroup_loader.c:2666-2669`); resolve
  failure is HARD_FAIL (`voicegroup_loader.c:2670-2671`).
- `populate_square_voice` (`voicegroup_loader.c:2675`): 7 ints, 8 when
  square-1 (`voicegroup_loader.c:2678-2681`); parse failure is CONSUMED with no
  write and no advance beyond the standard CONSUMED increment
  (`voicegroup_loader.c:2682-2683`). `type` as passed
  (`voicegroup_loader.c:2685`); `key = values[0]`
  (`voicegroup_loader.c:2686`); `values[1]` is parsed but IGNORED. Square-1:
  `panSweep = values[2]` (`voicegroup_loader.c:2689`),
  `wavePointer = (values[3] & 0x03)` 2-bit duty mask
  (`voicegroup_loader.c:2690`), `attack = values[4] & 0x07`
  (`voicegroup_loader.c:2691`), `decay = values[5] & 0x07`
  (`voicegroup_loader.c:2692`), `sustain = values[6] & 0x0F` 4-bit
  (`voicegroup_loader.c:2693`), `release = values[7] & 0x07`
  (`voicegroup_loader.c:2694`). Square-2: `panSweep = 0` forced
  (`voicegroup_loader.c:2697`), `wavePointer = values[2] & 0x03`
  (`voicegroup_loader.c:2698`), `attack = values[3] & 0x07`
  (`voicegroup_loader.c:2699`), `decay = values[4] & 0x07`
  (`voicegroup_loader.c:2700`), `sustain = values[5] & 0x0F`
  (`voicegroup_loader.c:2701`), `release = values[6] & 0x07`
  (`voicegroup_loader.c:2702`). `parse_square_voice`
  (`voicegroup_loader.c:2706`) dispatches longest-first:
  `"voice_square_1_alt "` (19) to `VOICE_SQUARE_1_ALT`, square-1
  (`voicegroup_loader.c:2708-2709`); `"voice_square_1 "` (15) to
  `VOICE_SQUARE_1` (`voicegroup_loader.c:2710-2711`);
  `"voice_square_2_alt "` (19) to `VOICE_SQUARE_2_ALT`, not square-1
  (`voicegroup_loader.c:2712-2713`); `"voice_square_2 "` (15) to
  `VOICE_SQUARE_2` (`voicegroup_loader.c:2714-2715`).
- `parse_programmable_wave_voice` (`voicegroup_loader.c:2730`):
  `"voice_programmable_wave_alt "` (27) to `VOICE_PROGRAMMABLE_WAVE_ALT`
  (`voicegroup_loader.c:2735-2738`); `"voice_programmable_wave "` (23) to
  `VOICE_PROGRAMMABLE_WAVE` (`voicegroup_loader.c:2740-2743`); same
  `SampleVoiceArguments` flow: HARD_FAIL propagates
  (`voicegroup_loader.c:2750-2751`), soft miss is CONSUMED
  (`voicegroup_loader.c:2752-2753`). Name from symbol
  (`voicegroup_loader.c:2754`); `type`, `key` as usual
  (`voicegroup_loader.c:2756-2757`); `attack & 0x07`, `decay & 0x07`,
  `sustain & 0x0F`, `release & 0x07` (`voicegroup_loader.c:2758-2761`); no
  panSweep write; `wavePointer` only via resolve
  (`voicegroup_loader.c:2762-2763`).
- `populate_noise_voice` (`voicegroup_loader.c:2767`): exactly 7 ints
  (`voicegroup_loader.c:2770-2771`); failure is CONSUMED
  (`voicegroup_loader.c:2771-2772`). `type` as passed
  (`voicegroup_loader.c:2774`); `key = values[0]` (`voicegroup_loader.c:2775`);
  `values[1]` ignored; `wavePointer = values[2] & 0x01` 1-bit mask
  (`voicegroup_loader.c:2776`); `attack = values[3] & 0x07`
  (`voicegroup_loader.c:2777`); `decay = values[4] & 0x07`
  (`voicegroup_loader.c:2778`); `sustain = values[5] & 0x0F`
  (`voicegroup_loader.c:2779`); `release = values[6] & 0x07`
  (`voicegroup_loader.c:2780`); no panSweep write. `parse_noise_voice`
  (`voicegroup_loader.c:2784`): `"voice_noise_alt "` (16) to `VOICE_NOISE_ALT`
  (`voicegroup_loader.c:2786-2787`); `"voice_noise "` (12) to `VOICE_NOISE`
  (`voicegroup_loader.c:2788-2789`).
- `parse_keysplit_all_voice` (`voicegroup_loader.c:2837`): requires
  `"voice_keysplit_all "` (19) (`voicegroup_loader.c:2840-2841`); single
  EOL symbol; overlong is HARD_FAIL (`voicegroup_loader.c:2845-2846`),
  missing is CONSUMED (`voicegroup_loader.c:2847-2848`); name from symbol
  (`voicegroup_loader.c:2849`); `type = VOICE_KEYSPLIT_ALL (0x80)`
  (`voicegroup_loader.c:2851`); subgroup load failure is HARD_FAIL
  (`voicegroup_loader.c:2852-2853`). No keysplit table is attached.
- `parse_keysplit_voice` (`voicegroup_loader.c:2857`): requires
  `"voice_keysplit "` (15) (`voicegroup_loader.c:2860-2861`); comma-symbol
  subgroup then EOL-symbol table (`voicegroup_loader.c:2863-2874`); overlong
  either is HARD_FAIL, missing either is CONSUMED. Name from the SUBGROUP
  symbol, not the table symbol (`voicegroup_loader.c:2875`);
  `type = VOICE_KEYSPLIT (0x40)` (`voicegroup_loader.c:2877`); subgroup load
  then table copy, either failure HARD_FAIL
  (`voicegroup_loader.c:2878-2881`).
- `parse_cry_voice` (`voicegroup_loader.c:2896`): `"cry_reverse "` (12) maps
  to `VOICE_CRY_REVERSE (0x30)` (`voicegroup_loader.c:2900-2903`); `"cry "`
  (4) keeps `VOICE_CRY (0x20)` (`voicegroup_loader.c:2905-2908`); single EOL
  symbol, overlong HARD_FAIL, missing CONSUMED
  (`voicegroup_loader.c:2913-2918`); name from symbol
  (`voicegroup_loader.c:2919`); fixed fields `key = 60`
  (`voicegroup_loader.c:2922`), `attack = 0xFF`
  (`voicegroup_loader.c:2923`), `decay = 0`, `sustain = 0xFF`, `release = 0`
  (`voicegroup_loader.c:2924-2926`); no panSweep write; resolve failure is
  HARD_FAIL (`voicegroup_loader.c:2927-2928`).
## 6. Resolution (part 1: directsound, synth, cache, session)

`build_wave_abs_paths(projectRoot, samplePath, wavAbs, aifAbs, binAbs)`
(`voicegroup_loader.c:474`): `vg_make_bin_variant` replaces a trailing
`".bin"` (length check plus suffix compare, `voicegroup_loader.c:456-472`)
with `".wav"`/`".aif"`; non-`.bin` sources yield empty wav/aif outputs.
`binAbs` is always `projectRoot + samplePath`; wav/aif outputs are built from
their variants only when the variant exists, else emptied
(`voicegroup_loader.c:480-510`); any `build_path` failure returns false.

`resolve_directsound_wave` (`voicegroup_loader.c:2594`) lookup order:
1. synth descriptor via `symbol_map_find_synth`: build with
   `build_synth_wavedata(desc, symbol, registry, waveCache)` and return
   `tone->wav != NULL` (`voicegroup_loader.c:2596-2601`);
2. `dsMap` sample path via `symbol_map_find`: build the three absolute paths
   (false on truncation, `voicegroup_loader.c:2608-2609`) and record a session
   binding `vg_load_session_add_wave(session, &tone->wav, wav-or-NULL,
   aif-or-NULL, binPath)` (`voicegroup_loader.c:2610-2616`). The `.bin` path
   is ALWAYS a candidate even when the map path has no `.bin` suffix;
3. otherwise the legacy serial path `resolve_and_load_sample_serial`
   (`voicegroup_loader.c:2618-2630`): -1 is false, 1 assigns `tone->wav`,
   0 leaves it NULL and still returns true (soft miss,
   `voicegroup_loader.c:2626-2630`).

`build_synth_wavedata(desc[6], symbol, owner, cache)`
(`voicegroup_loader.c:273`): cache key is `"synth-macro:%s"` of the symbol
(`voicegroup_loader.c:277`); cache hit returns it
(`voicegroup_loader.c:278-282`). Else `calloc(1, sizeof(WaveData) + 17)`
(`voicegroup_loader.c:283`); NULL on OOM (`voicegroup_loader.c:284-285`);
`type = 0` (`voicegroup_loader.c:286`), `status = 0x4000`
(`voicegroup_loader.c:287`), `freq = 0x01058920`
(`voicegroup_loader.c:288`), `loopStart = 0` (`voicegroup_loader.c:289`),
`size = 0` (`voicegroup_loader.c:290`); `data` points past the header
(`voicegroup_loader.c:291`); the 6 descriptor bytes are copied in
(`voicegroup_loader.c:292`); register with the owner, freeing and NULL on
failure (`voicegroup_loader.c:293-297`); insert into the cache
(`voicegroup_loader.c:298`).

`WaveCache` (`voicegroup_load_session.h:20-33`): 128-entry
(`WAVE_CACHE_CAPACITY`, `voicegroup_load_session.h:17`) array of
`{absPath, WaveData*}` plus `count`; the cache never owns allocations and
entries past capacity stay bank-owned but uncached
(`voicegroup_load_session.h:15-16`). `wave_cache_find` is a linear `strcmp`
(`voicegroup_load_session.c:20-34`); `wave_cache_insert` ignores NULLs and
silently drops when full (`voicegroup_load_session.c:36-50`);
`wave_cache_init` zeroes the count (`voicegroup_load_session.c:12-18`).
Cache keys: `"synth-macro:<symbol>"` for synth waves; absolute path strings
for file waves (`voicegroup_loader.c:1880`, `voicegroup_loader.c:1902`).

Session planning (`voicegroup_load_session.h:91-119`,
`voicegroup_load_session.c:454-537`): `vg_load_session_add_wave` rejects NULL
session/slot and overlong (`>= VG_MAX_PATH_LEN`) paths
(`voicegroup_load_session.c:454-464`); NULL/empty paths per slot are allowed
and yield index -1 (`voicegroup_load_session.c:382-395`); bindings grow
8-at-a-time by doubling (`voicegroup_load_session.c:420-435`). `add_prog`
additionally requires a non-empty path (`voicegroup_load_session.c:486-500`).
`vg_load_session_execute` runs PCM rounds WAV, then AIFF, then BIN, then the
prog round (`voicegroup_load_session.c:527-533`); each round requests only the
union of candidates needed by unresolved bindings
(`voicegroup_load_session.c:243-274`); decoded waves are adopted immediately,
registered once with the owner, and shared by referring slots
(`voicegroup_load_session.c:186-240`); a second decode of the same path
reuses the cache and frees the duplicate
(`voicegroup_load_session.c:221-236`); a `hardFailure` from any decoder
aborts (`voicegroup_load_session.c:214-218`). Prog bindings resolve from
their single candidate with no PCM fallback and no cache
(`voicegroup_load_session.c:277-334`); several recorded definitions of one
destination bind only the first success (`voicegroup_load_session.c:327`).
On failure the caller MUST discard the whole bank/set, never publish partial
results or retry the session (`voicegroup_load_session.h:111-119`).
Checkpoints capture wave/prog counts plus the four dedup counts
(`voicegroup_load_session.c:539-553`); rollback truncates counts and dedups
(`voicegroup_load_session.c:555-569`). `VgDedup`
(`voicegroup_asset_batch.h:31-39`): `vg_dedup_add` returns the existing index
for duplicates (`voicegroup_asset_batch.c:885-887`), -1 past `INT_MAX`
(`voicegroup_asset_batch.c:888-889`); offsets grow 8-at-a-time by doubling,
text grows by doubling (`voicegroup_asset_batch.c:894-929`); `vg_dedup_path`
is borrowed until add/truncate/deinit (`voicegroup_asset_batch.c:931-936`);
`vg_dedup_truncate` drops the suffix and rewinds text
(`voicegroup_asset_batch.c:938-944`).

Serial sample path (used by sample-set loads and the directsound fallback):
`load_sample_candidate(path, isAif, vg, waveCache, outWd)`
(`voicegroup_loader.c:1877`) checks the cache first (hit writes out and
returns 1, `voicegroup_loader.c:1880-1886`); loads via `load_aif_from_path` /
`load_wav_from_path` (`voicegroup_loader.c:1887-1892`, wrappers at
`voicegroup_loader.c:1854-1861` delegating to
`vg_asset_load_aiff/wav_file`); hard failure returns -1
(`voicegroup_loader.c:1893-1894`); NULL wave is a soft 0
(`voicegroup_loader.c:1895-1896`); registers with the owner, freeing and -1
on OOM (`voicegroup_loader.c:1897-1901`); inserts into the cache keyed by the
absolute path (`voicegroup_loader.c:1902`). `search_sample_directories`
(`voicegroup_loader.c:1908`) deep-scans first when not yet scanned
(`voicegroup_loader.c:1913-1914`); per `wavSampleDirs` entry tries
`<dir>/<symbol>.wav` then `<dir>/<symbol>.aif`
(`voicegroup_loader.c:1915-1926`); first nonzero result wins, else 0
(`voicegroup_loader.c:1927`). No `.aiff`, no `.bin` in this search.
`resolve_synth_sample` (`voicegroup_loader.c:1863`): synth hit builds (NULL
is -1, `voicegroup_loader.c:1869-1871`), else 0
(`voicegroup_loader.c:1866-1868`). `resolve_and_load_sample_serial`
(`voicegroup_loader.c:1930`) NULLs `*outWd`
(`voicegroup_loader.c:1939-1940`), tries synth then directories
(`voicegroup_loader.c:1941-1944`); `projectRoot` is ignored
(`voicegroup_loader.c:1938`).

`resolve_programmable_wave` (`voicegroup_loader.c:2719`): missing symbol
returns true with `wavePointer` untouched/NULL
(`voicegroup_loader.c:2721-2723`); else joins root plus map path (false on
truncation, `voicegroup_loader.c:2725-2726`) and records
`vg_load_session_add_prog(session, &tone->wavePointer, absolutePath)`
(`voicegroup_loader.c:2727`). `resolve_cry_wave`
(`voicegroup_loader.c:2885`): `dsMap`-only lookup
(`voicegroup_loader.c:2887`); missing returns true with `wav` untouched
(`voicegroup_loader.c:2888-2889`); else joins root plus path (false on
truncation, `voicegroup_loader.c:2891-2892`) and records a BIN-ONLY session
binding with wav/aif NULL (`voicegroup_loader.c:2893`).
## 6. Resolution (part 2: keysplit, sub-voicegroups, top-level loads)

Keysplit attachment: `load_keysplit_subgroup`
(`voicegroup_loader.c:2793`) is a true no-op (returns true, `subGroup` left
NULL) when `noSubRecurse` (`voicegroup_loader.c:2796-2797`) or
`inContinuation` (`voicegroup_loader.c:2798-2799`); else loads via
`load_sub_voicegroup_session` (-1 is false, `voicegroup_loader.c:2811-2812`)
and assigns `tone->subGroup`, which may be NULL on the soft path
(`voicegroup_loader.c:2813`). `copy_keysplit_table`
(`voicegroup_loader.c:2817`): rescan-checked find, false on lookup failure
(`voicegroup_loader.c:2820-2821`); NULL definition is true with no table
(`voicegroup_loader.c:2822-2823`); else `malloc(128)` per voice (NOT shared,
`voicegroup_loader.c:2824-2826`), `memcpy` of the definition's 128 bytes
(`voicegroup_loader.c:2827`), register for ownership (free plus false on
failure, `voicegroup_loader.c:2828-2832`), assign `tone->keySplitTable`
(`voicegroup_loader.c:2833`).

Sub-voicegroups: `load_sub_voicegroup_session`
(`voicegroup_loader.c:2428`) NULLs `*outSub`
(`voicegroup_loader.c:2439-2440`), strips one `"voicegroup_"` prefix
(11 chars) for lookup (`voicegroup_loader.c:2442-2443`), `find_voicegroup`s
the remainder (`voicegroup_loader.c:2444`); not found prints stderr and
returns 0 (SOFT: `subGroup` stays NULL, not a hard fail,
`voicegroup_loader.c:2445-2449`). `load_sub_voicegroup_location`
(`voicegroup_loader.c:2382`) cycle-guards via
`vg_load_session_is_active(session, filePath, startLabel)` with stderr plus
-1 on a hit (`voicegroup_loader.c:2388-2395`); `calloc`s `ToneData[128]`
(`voicegroup_loader.c:2397`) and names `[128][VG_VOICE_NAME_LEN]`
(`voicegroup_loader.c:2400`); either OOM is -1
(`voicegroup_loader.c:2398-2405`); registers BOTH with the owner before
parsing (`voicegroup_loader.c:2406-2411`, freeing both on failure); pushes
the (file, label) location (`voicegroup_loader.c:2412-2413`, false is -1);
checkpoints the session (`voicegroup_loader.c:2414`); parses
(`voicegroup_loader.c:2415`); on parse failure rolls back the session
planning, pops, and returns -1 (`voicegroup_loader.c:2416-2421`); else pops
and publishes via `outSub` with return 1 (`voicegroup_loader.c:2422-2425`).
`parse_sub_voicegroup` (`voicegroup_loader.c:2354`) uses the location label
or NULL (`voicegroup_loader.c:2359`); first parse is `startIndex = 0,
contiguousFill = 1, noSubRecurse = 0` (`voicegroup_loader.c:2360-2374`);
`endIndex <= 0` returns as-is (`voicegroup_loader.c:2375-2376`); labeled
(monolithic) locations return `endIndex` directly
(`voicegroup_loader.c:2377-2378`); unlabeled (individual-file) locations
continue through the include chain (`voicegroup_loader.c:2379`).
`continue_sub_voicegroup` (`voicegroup_loader.c:2312`) walks at most
`VOICEGROUP_SIZE` hops (`voicegroup_loader.c:2321`), breaks at
`endIndex >= 128` (`voicegroup_loader.c:2323-2324`) or on
`next_included_voicegroup` failure (`voicegroup_loader.c:2326-2327`); each
next file parses with `startLabel = NULL, startIndex = endIndex,
contiguousFill = 0, noSubRecurse = 1` (`voicegroup_loader.c:2328-2342`); a
negative parse is -1 (`voicegroup_loader.c:2343-2344`); no forward progress
breaks (`voicegroup_loader.c:2345-2346`). There is NO numeric
recursion-depth limit; only the active-location stack (file plus label, cap
`VG_ACTIVE_LOC_CAP 32`, `voicegroup_load_session.h:40-44`) prevents infinite
loops, and continuation/cross-file voices set `inContinuation`/`noSubRecurse`
so nested keysplit loads do not recurse further (comment
`voicegroup_loader.c:2473-2482`). `vg_load_session_push_location` fails on
NULL session/path or a full stack (`voicegroup_load_session.c:571-576`),
copies `filePath`/`label` with NUL caps and NULL label becoming empty
(`voicegroup_load_session.c:577-588`); `pop_location` zeroes the popped slot
(`voicegroup_load_session.c:591-599`); `is_active` compares both strings with
NULL label treated as empty (`voicegroup_load_session.c:601-613`).
Sub-group `voiceNames` are filled through `set_parsed_voice_name` into the
calloc'd names array passed as `destNames`, registered alongside the subgroup
in `vg_register_subgroup` (`voicegroup_loader.c:2406`).

Top-level loads: `voicegroup_project_open(projectRoot, config, fileIo)`
(`voicegroup_loader.c:3376`) rejects missing/empty root
(`voicegroup_loader.c:3378-3382`), overlong root (`>= VG_MAX_PATH_LEN`,
`voicegroup_loader.c:3383-3387`), incomplete adapter (NULL `readBatch` or
`releaseBatch`, `voicegroup_loader.c:3388-3392`), and invalid config
(`voicegroup_loader.c:3393-3397`); `calloc`s the project
(`voicegroup_loader.c:3399-3401`); copies root/config/adapter, never borrows
(`voicegroup_loader.c:3403-3407`); heap-`calloc`s the ~96 KB discovery
(`voicegroup_loader.c:3409-3416`); runs eager discovery plus map init plus
`parse_all_*`, NULLing out on any parse failure
(`voicegroup_loader.c:3420-3441`). `voicegroup_project_free`
(`voicegroup_loader.c:3364`) frees dsMap, pwMap, ksMap, `disc`, then project,
in that order (`voicegroup_loader.c:3368-3372`); NULL is a return
(`voicegroup_loader.c:3366-3367`). `project_load_location`
(`voicegroup_loader.c:3468`) `calloc`s the bank, inits cache and session, and
pushes the target location. `voicegroup_project_load`
(`voicegroup_loader.c:3515`) rejects NULL project/target/path
(`voicegroup_loader.c:3517-3521`); empty `sectionLabel` becomes NULL
(`voicegroup_loader.c:3523`); an invalid section label (overlong or with
space/`:`/`,`) is NULL (`voicegroup_loader.c:3525-3529`); a missing target
file or missing requested section is a hard failure returning NULL, while
mapped asset misses stay soft (unresolved voices keep NULL samples) and only
allocation or adapter hard failure returns NULL
(`voicegroup_loader.h:260-268`). One-shot `voicegroup_load`
(`voicegroup_loader.c:3812`) opens a temp context over the stdio adapter and
delegates; nothing outlives the call except the self-contained bank.
Sample sets: `sample_set_allocation_count` maps `count <= 0` to 1 so every
array `calloc`s non-zero (`voicegroup_loader.c:3559-3563`);
`allocate_sample_set` (`voicegroup_loader.c:3566`) `calloc`s the set, an
internal container bank, and the waves/progWaves/keysplits pointer arrays.
Missing sample symbols stay NULL (soft); `populate_sample_set_wave` with an
unmapped symbol returns true leaving the slot NULL
(`voicegroup_loader.c:3655-3657`); keysplit entries pair subgroup and table
symbols with miss-able NULLs.
## 7. Decoders (`voicegroup_asset_batch.h/.c`)

Exact signatures (`voicegroup_asset_batch.h:18-26`):
`WaveData* vg_asset_decode_wav(const uint8_t* data, size_t size, const char*
debugPath, bool* hardFailure)`; same shape for `vg_asset_decode_aiff` and
`vg_asset_decode_bin`; `uint32_t* vg_asset_decode_prog(const uint8_t* data,
size_t size, const char* debugPath, bool* hardFailure)`; serial
`WaveData* vg_asset_load_wav_file(const char* absolutePath, bool*
hardFailure)` and `vg_asset_load_aiff_file` likewise. All decoders clear
`*hardFailure` first when non-NULL (`voicegroup_asset_batch.c:363-364`,
`:659-660`, `:699-700`, `:749-750`).

`hardFailure` contract: allocation failure sets it
(`voicegroup_asset_batch.c:398-404`, `:684-688`, `:727-733`, `:757-763`);
malformed input returns NULL WITHOUT setting it. `alloc_wavedata(size)`
(`voicegroup_asset_batch.c:48`) is a SINGLE `malloc(sizeof(WaveData) + size +
1)` with `data` pointing past the header (`voicegroup_asset_batch.c:54-58`)
and a `+1` guard byte zeroed (`voicegroup_asset_batch.c:59`); release is
plain `free()` by the owner. Decoders depend only on the byte span plus
`debugPath` (stderr messages only) and never touch loader globals or the log
path.

WAV (`vg_asset_decode_wav`, `voicegroup_asset_batch.c:361`): NULL/short
(`< 12`) or non-`RIFF....WAVE` is a soft NULL
(`voicegroup_asset_batch.c:365-374`); the scan limit clamps to `8 + riffSize`
when smaller (`voicegroup_asset_batch.c:375-379`); chunks walk from offset 12
with odd-length padding (`voicegroup_asset_batch.c:254-277`); `fmt ` needs
`chunkLen >= 16` (`voicegroup_asset_batch.c:229-230`); `smpl` needs
`chunkLen >= 32` (`voicegroup_asset_batch.c:197-202`); `data` records
offset/len and overwrites on repeat (`voicegroup_asset_batch.c:246-251`).
Accepted: `fmtTag` 1 (integer PCM) and 3 (IEEE float); anything else is a soft
NULL (`voicegroup_asset_batch.c:305-316`). Integer widths must be exact pairs
(blockAlign, bits): (1,8), (2,16), (3,24), (4,32)
(`voicegroup_asset_batch.c:279-292`); float widths: (4,32), (8,64)
(`voicegroup_asset_batch.c:294-303`). Conversion keeps the most significant
byte: 8-bit subtracts 128 (`voicegroup_asset_batch.c:67`), 16-bit `v >> 8`
(`voicegroup_asset_batch.c:70-71`), 24-bit sign-extended `v >> 16`
(`voicegroup_asset_batch.c:74-78`), 32-bit `v >> 24`
(`voicegroup_asset_batch.c:81-83`); float scales by 128.0, floors, and clamps
to [-128, 127] (`voicegroup_asset_batch.c:95-132`); non-finite float32/64
input samples become 0 (`voicegroup_asset_batch.c:118-129`). Missing `fmt` or
`data` is a soft NULL (`voicegroup_asset_batch.c:384-389`). `smpl` chunk:
`midiKey` clamped to 127 (`voicegroup_asset_batch.c:204-206`); exactly one
loop (`numLoops == 1` with 52 readable bytes) sets `smplLoopStart`,
inclusive-end-plus-one `smplLoopEnd`, and `loopEnabled`
(`voicegroup_asset_batch.c:208-215`). Loop end resolution: smpl end when
enabled else `numSamples`, clamped; nonzero `agbl` wins over both, clamped
(`voicegroup_asset_batch.c:318-332`). Frequency: `wav_resolve_freq`
(`voicegroup_asset_batch.c:334`) returns `agbPitch` when nonzero
(`voicegroup_asset_batch.c:337-338`); keynote 60 with zero fraction returns
`sampleRate * 1024.0` (`voicegroup_asset_batch.c:339-340`); else
`sampleRate * 2^((60-key)/12 + tuning/1200) * 1024` with
`tuning = pitchFraction / (2^32 * 100.0)` semitones
(`voicegroup_asset_batch.c:341-343`), via `clamp_freq` (non-finite/negative
to 0, over-`UINT32_MAX` saturates, `voicegroup_asset_batch.c:141-149`).
Header init: `type = 0`, `status = loopEnabled ? 0x4000 : 0`, `freq`,
`loopStart = smplLoopStart`, `size = wsize` (`voicegroup_asset_batch.c:152-159`,
`:405`). Materialization strides by bytes-per-sample; out-of-range samples
become 0; the guard byte repeats the last sample or 0 when empty
(`voicegroup_asset_batch.c:346-359`).

AIFF (`vg_asset_decode_aiff`, `voicegroup_asset_batch.c:657`): non
`FORM....AIFF` or short input is a soft NULL
(`voicegroup_asset_batch.c:659-666`); missing COMM or SSND is a soft NULL
(`voicegroup_asset_batch.c:670-676`). COMM rejects non-mono
(`voicegroup_asset_batch.c:444-451`) and non-8/16-bit sample sizes
(`voicegroup_asset_batch.c:452-459`) as soft misses; sampleRate is an 80-bit
extended float (`voicegroup_asset_batch.c:36-46`, `:443`). MARK keeps only the
first marker chunk (`voicegroup_asset_batch.c:489-512`); entries are id plus
big-endian position with padded Pascal names
(`voicegroup_asset_batch.c:464-486`). INST with nonzero loop type records
sustain start/end marker ids (`voicegroup_asset_batch.c:514-523`); chunks
need `>= 20` bytes (`voicegroup_asset_batch.c:557-558`). Loop resolution
(`voicegroup_asset_batch.c:608-631`): default start 0, disabled, length
`numFrames`; with a sustain loop, the start marker sets the loop; when the
end marker is found, `numSamples` becomes the end position, and a missing
start or an end before the start moves the start to the end and enables the
loop (`voicegroup_asset_batch.c:617-628`). `wsize = numSamples - 1`
(inclusive frame count drops one trailing sample), clamped to SSND-available
samples (`voicegroup_asset_batch.c:633-641`). `freq = sampleRate * 1024.0`
via `clamp_freq` (`voicegroup_asset_batch.c:690`). Materialization copies the
first byte of each frame (8-bit direct; 16-bit big-endian high byte),
zero-filling short reads, with the same guard-byte rule
(`voicegroup_asset_batch.c:643-655`).

BIN (`vg_asset_decode_bin`, `voicegroup_asset_batch.c:697`): under 16 bytes
is a soft NULL (`voicegroup_asset_batch.c:701-706`). GBA header layout, all
little-endian: u16 type (`voicegroup_asset_batch.c:707`), u16 status
(`voicegroup_asset_batch.c:708`), u32 freq (`voicegroup_asset_batch.c:709`),
u32 loopStart (`voicegroup_asset_batch.c:710`), u32 size
(`voicegroup_asset_batch.c:711`). `wsize == 0` copies at most 16 payload
bytes but keeps `wd->size = 0` (`voicegroup_asset_batch.c:715-719`,
`:734-738`); nonzero `wsize` beyond the payload is a soft NULL
(`voicegroup_asset_batch.c:722-723`); bytes copy verbatim with the guard rule
(`voicegroup_asset_batch.c:739-741`).

PROG (`vg_asset_decode_prog`, `voicegroup_asset_batch.c:747`): under 16
bytes is a soft NULL (`voicegroup_asset_batch.c:751-756`); else `malloc(16)`
and `memcpy` of the first 16 input bytes (`voicegroup_asset_batch.c:757-765`)
— text or binary, only the leading 16 bytes matter.

Serial helpers: `read_file_to_blob` clears `*hardFailure` first
(`voicegroup_asset_batch.c:818-819`); NULL args are hard
(`voicegroup_asset_batch.c:820-821`); `fopen` failure is a soft miss EXCEPT
non-`ENOENT`/`ENOTDIR` errno, which sets hard
(`voicegroup_asset_batch.c:778-785`); seek/tell failure, short reads, and
`ferror` are hard (`voicegroup_asset_batch.c:787-814`); zero-size files still
allocate 1 byte and succeed (`voicegroup_asset_batch.c:802-814`).
`vg_batch_read` validates (NULL paths/out with nonzero count, incomplete
adapter, count over `INT_MAX`, `voicegroup_asset_batch.c:956-972`), zeroes
all out blobs (`voicegroup_asset_batch.c:986-987`), and delegates to the
adapter (`voicegroup_asset_batch.c:990`); `vg_batch_release` calls the
adapter or frees blob data itself (`voicegroup_asset_batch.c:992-1006`).

## 8. Ownership and free

`LoadedVoiceGroup` (`voicegroup_loader.h:38-79`): inline
`voices[VOICEGROUP_SIZE]` (`voicegroup_loader.h:43`) and
`voiceNames[VOICEGROUP_SIZE][VG_VOICE_NAME_LEN]`
(`voicegroup_loader.h:50`); heap `waveDatas` plus counts
(`voicegroup_loader.h:53-55`); heap `progWaves` plus counts
(`voicegroup_loader.h:58-60`); heap `subGroups` plus counts
(`voicegroup_loader.h:63-65`); parallel heap `subGroupVoiceNames` sharing the
subgroup count/capacity, element `i` a calloc'd
`[VOICEGROUP_SIZE][VG_VOICE_NAME_LEN]` block owned alongside `subGroups[i]`,
never NULL while registered (`voicegroup_loader.h:68-73`); heap
`keySplitTables` plus counts (`voicegroup_loader.h:76-78`).

- `vg_register_wavedata` (`voicegroup_loader.c:647`): NULL guard
  (`voicegroup_loader.c:649-650`); grows on `count >= capacity` by doubling
  from `INITIAL_CAPACITY` 64 via `realloc`, false on OOM
  (`voicegroup_loader.c:651-658`); appends (`voicegroup_loader.c:660-661`).
- `vg_register_subgroup` (`voicegroup_loader.c:664`): NULL guard on all
  three args (`voicegroup_loader.c:666-667`); grows with parallel `malloc` of
  both arrays, freeing both and false if either fails
  (`voicegroup_loader.c:668-678`); `memcpy`s old entries, frees the old pair,
  publishes (`voicegroup_loader.c:679-688`); appends both, `count++`, true
  (`voicegroup_loader.c:690-693`).
- `vg_register_keysplittable` (`voicegroup_loader.c:697`): same doubling via
  `realloc` for `uint8_t*` tables (`voicegroup_loader.c:698-709`).
- Session registrars (`voicegroup_load_session.c:54-90`) are identical
  doubling appends starting from 64 (`VG_INITIAL_OWNER_CAP`,
  `voicegroup_load_session.c:8`).

`voicegroup_free` exact order (`voicegroup_loader.c:3886`): NULL returns
(`voicegroup_loader.c:3888-3889`); (1) `free(waveDatas[i])` for
`i < waveDataCount` (`voicegroup_loader.c:3891-3892`); (2) `free(waveDatas)`
(`voicegroup_loader.c:3893`); (3) `free(progWaves[i])` for
`i < progWaveCount` (`voicegroup_loader.c:3895-3896`); (4) `free(progWaves)`
(`voicegroup_loader.c:3897`); (5) per subgroup `free(subGroups[i])` then
`free(subGroupVoiceNames[i])`; (6) `free(subGroups)` then
`free(subGroupVoiceNames)`; (7) `free(keySplitTables[i])` for
`i < keySplitTableCount`; (8) `free(keySplitTables)`; (9) `free(vg)`.
`voices`/`voiceNames` are inline and never freed. Every element pointer is
bank-owned: tones borrow `wav`/`wavePointer`/`subGroup`/`keySplitTable`
without owning them.

`voicegroup_free_samples` order (`voicegroup_loader.c:3875`): NULL returns
(`voicegroup_loader.c:3877-3878`); (1) `voicegroup_free(set->container)`,
which frees all wave/prog/subgroup/table allocations including the `waves[]`
entries (`voicegroup_loader.c:3879`); (2) `free(set->waves)` pointer array
only (`voicegroup_loader.c:3880`); (3) `free(set->progWaves)` array only;
(4) per keysplit entry the subgroup/table memory is already freed via the
container; (5) `free(set->keysplits)`; (6) `free(set)`.

Borrowed views: `voicegroup_subgroup_names` (`voicegroup_loader.c:3914`)
returns NULL for NULL vg/subgroup, absent backing arrays, or a non-member
subgroup (`voicegroup_loader.c:3916-3917`); else pointer-equality scan for
the member and its names table (`voicegroup_loader.c:3918-3922`), valid until
`voicegroup_free`. `voicegroup_subgroup_slot_name`
(`voicegroup_loader.c:3926`) NULLs on out-of-range slots
(`voicegroup_loader.c:3928-3929`).
