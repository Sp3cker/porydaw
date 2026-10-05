import Foundation
import PorydawBankLease

/// The startup project decision, made once from the CLI arguments and the saved
/// tab recipe. `--project` wins; a lone `--song` targets the saved project; no
/// CLI selection restores the recipe.
enum StartupSelection: Sendable {
    /// Restore the saved project with its ordered tabs and selected song.
    case restore(WorkspaceTabRecipe)
    /// Deliberately open a project, plus the one song to open when named.
    case open(path: String, song: String?)

    /// Nil when neither the CLI nor the recipe names a project.
    @MainActor
    static func resolve(arguments: [String], store: PreferencesStore) -> StartupSelection? {
        let cli = parseArguments(arguments)
        let recipe = EditorViewStateCodec.loadTabs(store: store)
        if cli.project.isEmpty && cli.song.isEmpty {
            return recipe.projectPath.isEmpty ? nil : .restore(recipe)
        }
        let path = cli.project.isEmpty ? recipe.projectPath : cli.project
        guard !path.isEmpty else { return nil }
        return .open(path: path, song: cli.song.isEmpty ? nil : cli.song)
    }

    var path: String {
        switch self {
        case .restore(let recipe): recipe.projectPath
        case .open(let path, _): path
        }
    }

    /// The one song worth reading off-main before the shell exists.
    var song: String? {
        switch self {
        case .restore(let recipe): recipe.startupSong
        case .open(_, let song): song
        }
    }

    /// Opens through the ordinary session entry points; `startProjectSwitch`
    /// adopts the parked read when its path matches.
    @MainActor
    func open(with session: ApplicationSession) {
        switch self {
        case .restore(let recipe): session.restoreStartup(recipe: recipe)
        case .open(let path, nil): session.openProject(path: path)
        case .open(let path, let song?): session.openProjectAndSong(path: path, label: song)
        }
    }

    private static func parseArguments(_ arguments: [String]) -> (project: String, song: String) {
        var project = ""
        var song = ""
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--project" || argument == "--song" {
                if index + 1 < arguments.count {
                    index += 1
                    if argument == "--project" { project = arguments[index] } else { song = arguments[index] }
                }
            } else if argument.hasPrefix("--project=") {
                project = String(argument.dropFirst("--project=".count))
            } else if argument.hasPrefix("--song=") {
                song = String(argument.dropFirst("--song=".count))
            }
            index += 1
        }
        return (project, song)
    }
}

/// The project read started in `PorydawShellApp.init`, before Qt exists, with the
/// selection it answers. Parked once per process until the first `ShellPresenter`
/// session adopts it; from then on the session owns the read and either matches
/// it in `startProjectSwitch` or closes its service.
public struct StartupPrefetch: Sendable {
    let selection: StartupSelection
    let read: Task<ProjectRead, Error>

    @MainActor
    static var parked: StartupPrefetch?

    /// Parses the CLI and loads the recipe once; a repeated call keeps the first read.
    @MainActor
    public static func start(arguments: [String]) {
        guard parked == nil,
            let selection = StartupSelection.resolve(arguments: arguments, store: PreferencesStore())
        else { return }
        pd_startup_trace_mark("project-read-start")
        let path = selection.path
        let song = selection.song
        parked = StartupPrefetch(
            selection: selection,
            read: Task { @concurrent in
                pd_startup_trace_mark("project-read-begin")
                defer { pd_startup_trace_mark("project-read-end") }
                return try await ProjectRead.load(path: path, song: song)
            })
    }
}
