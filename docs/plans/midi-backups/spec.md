# Behavior and shared interfaces

## Storage
Porydaw app-data Backups root: macOS ~/Library/Application Support/porydaw/Backups; Windows local application-data porydaw/Backups; Linux $XDG_DATA_HOME/porydaw/Backups (default ~/.local/share). Resolve platform paths, never current working directory. A PORYDAW_BACKUP_ROOT environment override is solely a deterministic harness/smoke isolation seam; explicit initializer root wins.

Each song uses one folder named for its song label. Its files are `<song-name><increment>.mid`, starting at 1; e.g. `mus_route1/mus_route11.mid`, `mus_route1/mus_route12.mid`. Derive the next increment from existing files, not a counter. Preserve Unicode and spaces; replace filesystem-forbidden characters without truncation and reject empty/dot-only names. Same-named songs intentionally share a folder, including across projects. No JSON, manifests, source-path identity, build versions, kind tags, UUID bucket names, or per-backup subdirectories.

Keep file 1 permanently. It contains the first raw source bytes when a source exists; if a new song has no source yet, its first captured bytes occupy file 1 instead. Keep the union of the 10 highest remaining increments and the first-created snapshot for each of the newest 30 active UTC dates, grouping by file modification times. Increment order keeps fresh backups protected even if the clock moves backwards. Consecutive identical bytes do not consume another file; an unreadable previous file must not prevent a fresh backup. Days without backups do not age anything out. File 1 does not consume recent/daily slots.

Commit complete MIDI atomically without overwriting an existing destination, then prune only regular files whose names exactly match this song's canonical positive increment format. A private temporary file during an atomic write is not a persisted record; remove it on failure. Ignore foreign files, directories and symlinks. No exit/startup expiry. Failed creation never prunes prior files. Leave any old-layout directories untouched; no migration or compatibility reader.

Public `PorydawBackups` contract in `src/swift/backups/MidiBackupStore.swift`:
- public actor MidiBackupStore; public static let shared: MidiBackupStore
- public init(root: URL? = nil)
- public func directory() throws -> URL (create and return root)
- public func preserveOriginal(songName: String, bytes: [UInt8], at: Date = Date()) throws
- public func record(songName: String, bytes: [UInt8], at: Date = Date()) throws
The package depends only on Foundation and treats MIDI as opaque bytes. Explicit roots allow independent use; Porydaw app-data defaults remain for app callers. A local Package.swift and the app's CMake target compile the same source. Swift Testing exercises the public interface without Qt, fixtures from Porydaw, or any Porydaw module. Service callers supply `snapshot.destination.label`; source-path identity is not part of storage.
The actor serializes filesystem operations. `preserveOriginal` writes file 1 only when no first file exists; it never replaces one. `at` sets the MIDI file modification date for deterministic retention. Errors must have meaningful context. No stored sequence, metadata or identity record.

## Lifecycle
ProjectService retains init(backups: MidiBackupStore = .shared) and backup(_ snapshot: SaveSnapshot). Periodic capture preserves existing raw source bytes first when available, then records captured bytes. Before an actual MIDI overwrite, record the current raw disk bytes after the existing bank stage. Remove the obsolete kind arguments, preserving cancellation, store-identity revalidation, conflicts, bank ordering and missing-source behavior.

DocumentSession gains public func backupNow() async throws using captureSave without didSave, and public var onBackupFailure: ((String) -> Void)?. Skip clean/unchanged documents, but do not let a failed backup mark the revision backed up. Run backupNow from one retained weak-self task every 60 seconds for each session, including background tabs. Cancel on close and deinit; avoid retaining the session across sleep. Closed sessions do no new capture/write work. ApplicationSession installs failure handling for each opened session using its existing status/failure surface; avoid repeated modal storms for an unchanged persistent failure.

Final UX review refinement: periodic backup failures publish only through `onStatusMessage`, never `lastSaveError`; a concurrent successful save must not be mislabeled Save Failed. Pre-save backup refusal continues through the real save error path.

Preserve per-session source identity across tab/project switches. Autosaves do not overwrite originals or alter undo/dirty state. Expose deterministic explicit backupNow for tests; production interval remains 60 seconds.

## Menu
Action id file.open_backups, label Open Backups..., no shortcut, enabled without a project whenever the shell is active. It creates/opens the shared root, not a selected-song folder. Use ShellActionCatalog and existing dispatcher. ShellPresenter requests URL via @QtSignal public func backupsFolderRequested(url: String); a production QML Connections handler calls Qt.openUrlExternally(url). On false result, show existing critical/error surface. Task handles retained/cancelled action work. No shell command interpolation, new native code, or second dispatcher.

## Verification
Controller: deno task build:checks; deno task checks --filter swiftcore-projectsession --verbose; deno task checks --filter projectstore-save --verbose; deno task checks:shell --filter shell-menus --verbose; deno task checks:bridge; deno task checks:qml-aot; deno task proof check; deno task lsp:swift; deno task format --check. Run with isolated PORYDAW_BACKUP_ROOT. Actual app smoke must activate File > Open Backups... and observe Finder at the matching directory; edit a scratch fixture, observe a periodic .mid snapshot and pre-save raw bytes. Never modify the user's actual project. Native desktop access is required for visual evidence.

For the standalone-module revision, the covering gates are `deno task checks:backups` (SwiftPM only), `deno task build:checks`, `deno task checks --filter swiftcore-projectsession --verbose`, `deno task checks --no-windowing-checks`, `deno task build:app`, `deno task format --check`, and `deno task proof check`. Exercise the built module through a throwaway external consumer as runtime smoke. Menu/QML behavior is unchanged. Record a warm one-source incremental app-build comparison in docs/BUILDING.md; no Qt build is needed to run the package tests.
