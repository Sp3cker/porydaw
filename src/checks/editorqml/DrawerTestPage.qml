// Test-owned drawer page item: the QML half of the real hosting seam.
//
// The lane's Swift DrawerTestPage resolves its contentUrl at this file, so the
// production EditorDrawer loads it through exactly the path a production page
// will use -- a Loader created with setSource(url, {"applicationSession": ...}).
// This is a real page item, not a suite file: it is never discovered by the test
// runner (only tst_EditorDrawer.qml is) and it never ships in the application.
//
// It is the page contract in miniature: a FocusScope that fills its loader,
// takes the injected session, maps its content from the same shared gutter the
// roll renders with, and reports its own lifecycle and focus so the lane can
// observe hosting rather than assume it.
import QtQuick

FocusScope {
    id: page

    objectName: "drawerTestPage"

    required property QtObject applicationSession

    // The page's plot origin comes from the session's grid, which is the same
    // gutter the container publishes as plotOrigin and the roll draws at.
    readonly property real plotOrigin: page.applicationSession.gridPresenter().keyboardWidth

    // Observable lifecycle: the container loads this item through the production
    // seam, so the lane can see that a scene teardown destroys the hosted content
    // while the page's Swift owner stays alive until its own release.
    signal pageDestroyed()

    // Observable focus: the container focuses this item's scope, never a
    // handler it re-declares for the page.
    readonly property bool pageFocused: page.activeFocus

    Rectangle {
        anchors.fill: parent
        color: "#20404040"
    }

    Component.onDestruction: page.pageDestroyed()
}
