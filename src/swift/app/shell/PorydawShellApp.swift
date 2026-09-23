import Darwin
import Foundation
import PorydawApp
import QtBridge

@main
struct PorydawShellApp: QApp {
    let qmlFileName = "PorydawApplication"
    let instantiableTypes: [QmlInstantiable.Type] = [ShellPresenter.self, ApplicationSession.self]

    init() {
        let arguments = CommandLine.arguments.dropFirst()
        if arguments.contains("--help") || arguments.contains("-h") {
            print("""
            Usage: porydaw [options]
            Porydaw

            Options:
              -h, --help        Displays help on commandline options.
              -v, --version     Displays version information.
              --project <path>  Open project root.
              --song <label>    Open song label.
            """)
            exit(EXIT_SUCCESS)
        }
        if arguments.contains("--version") || arguments.contains("-v") {
            guard let version = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
                fatalError("Missing application bundle version")
            }
            print("porydaw \(version)")
            exit(EXIT_SUCCESS)
        }
    }
}
