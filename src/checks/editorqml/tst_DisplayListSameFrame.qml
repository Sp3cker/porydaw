import QtQuick
import QtTest
import Porydaw.Ui
import EditorQmlCheck 1.0

Item {
    id: root
    width: 240
    height: 80
    property var samples: []
    property var pendingFrame: null
    property int missedFrames: 0

    DisplayListProbe { id: probe }

    DisplayList {
        id: display
        width: root.width
        height: root.height
        source: probe
        list: 0
        revision: probe.displayRevision
    }

    Repeater {
        id: carrier
        model: probe.rows
        delegate: Item {
            required property var model
            x: model.x
            width: 1
            height: 1
        }
    }

    Connections {
        id: frameObserver
        target: null
        function onAfterAnimating() {
            const row = carrier.itemAt(0)
            if (!row || probe.displayRevision === display.fetchedRevision)
                return
            if (root.pendingFrame !== null)
                root.missedFrames++
            root.pendingFrame = { x: row.x, published: probe.displayRevision }
        }
    }

    Connections {
        target: display
        function onFetchedRevisionChanged() {
            if (root.pendingFrame === null)
                return
            root.samples.push({ x: root.pendingFrame.x,
                                published: root.pendingFrame.published,
                                fetched: display.fetchedRevision,
                                faceX: display.face(42).x })
            root.pendingFrame = null
        }
    }

    TestCase {
        name: "DisplayListSameFrame"
        when: windowShown

        function test_rowAndPixelsShareEveryFrame() {
            verify(carrier.itemAt(0) !== null, "carrier mounted")
            verify(display.loopStartId !== display.loopEndId)
            frameObserver.target = display.Window.window
            waitForRendering(display)
            root.samples = []
            root.pendingFrame = null
            for (let step = 1; step <= 10; ++step) {
                const before = root.samples.length
                probe.advance()
                waitForRendering(display)
                compare(root.missedFrames, 0)
                verify(root.samples.length > before, "frame observed at step " + step)
                for (let index = before; index < root.samples.length; ++index) {
                    const sample = root.samples[index]
                    compare(sample.fetched, sample.published)
                    compare(sample.faceX, sample.x)
                    compare(sample.x, step * 10)
                }
                verify(Qt.colorEqual(display.face(42).fill, "#203040"))
                compare(display.face(43).x, step * 10 + 20)
            }
        }
    }
}
