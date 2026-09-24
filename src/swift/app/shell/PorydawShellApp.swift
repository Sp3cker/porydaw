#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(ucrt)
import ucrt
#endif
import Foundation
import PorydawApp
import QtBridge
#if !canImport(Darwin)
@_spi(ExperimentalCustomExecutors) import _Concurrency
#endif

@main
struct PorydawShellApp: QApp {
    let qmlFileName = "PorydawApplication"
    let instantiableTypes: [QmlInstantiable.Type] = [ShellPresenter.self, ApplicationSession.self]

    init() {
        #if !canImport(Darwin)
        _createExecutors(factory: PorydawExecutorFactory.self)
        #endif
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
            print("porydaw \(porydawBuildVersion)")
            exit(EXIT_SUCCESS)
        }
    }
}
