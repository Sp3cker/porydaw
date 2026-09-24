import QtQuick

// QCoreApplication's noncopyable C++ type is unavailable to Swift. Establish
// its identity through public Qt.application before any shell Settings exist.
Loader {
    active: false
    sourceComponent: ShellWindow {}

    Component.onCompleted: {
        Qt.application.name = "porydaw"
        Qt.application.organization = "sp3cker"
        Qt.application.domain = ""
        active = true
    }
}
