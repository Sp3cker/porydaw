import Foundation
import PorydawApp
import PorydawBankLease
import QtBridge

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(ucrt)
    import ucrt
#endif
#if !canImport(Darwin)
    @_spi(ExperimentalCustomExecutors) import _Concurrency
#endif

@main
struct PorydawShellApp: QApp {
    let qmlFileName = "PorydawApplication"
    let instantiableTypes = PorydawQmlTypes.instantiable
    let uncreatableTypes = PorydawQmlTypes.uncreatable

    init() {
        pd_startup_trace_mark("app-init")
        #if !canImport(Darwin)
            _createExecutors(factory: PorydawExecutorFactory.self)
        #endif
        let arguments = CommandLine.arguments.dropFirst()
        if arguments.contains("--help") || arguments.contains("-h") {
            print(
                """
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
