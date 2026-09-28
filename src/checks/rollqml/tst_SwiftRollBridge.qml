// The mounted BridgeProbe audit, run by the rollqml lane:
//
//     roll_qml_tests {scratch} -input tst_SwiftRollBridge.qml
//
// The prototype swiftqtml lane is deleted, but its presenter is live Swift in
// this lane: this suite mounts the same BridgeProbe.qml fixture through a
// Loader and drives every fork clause on the real QtBridge path — presenter
// property binding, QListModel mutation/replacement/insert/remove/reset with
// delegate identity, returned-object retention, null selection, action log.
// The object-argument slot stays out: the pinned QtBridge cannot pass objects
// into slots, and the fork never executes that probe either.
import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "SwiftRollBridge"
    when: windowShown
    width: 320
    height: 240
    visible: true

    Loader {
        id: probeLoader
        source: "../swiftqtml/BridgeProbe.qml"
        active: true
    }

    function fixture() { return probeLoader.item }
    function probe() { return findChild(fixture(), "bridgeProbe") }
    function probeState() { return findChild(fixture(), "probeState") }
    function delegateProbe() { return findChild(fixture(), "delegateProbe") }
    function textItem(name) { return findChild(fixture(), name) }

    function delegateByKey(key) {
        var delegates = delegateProbe()
        if (!delegates) return null
        for (var slot = 0; slot < delegates.count; ++slot) {
            var delegate = delegates.itemAt(slot)
            if (delegate && delegate.domainKey === key) return delegate
        }
        return null
    }

    function textByKey(key) { return textItem("rowText_" + key) }

    function textShown(name) {
        var item = textItem(name)
        return item ? item.text : undefined
    }

    // Real QML entry into a fixture or presenter slot: false only when the
    // call itself throws, so the predicate observes dispatch, not a re-read.
    function dispatched(target, method, argument) {
        try {
            if (argument === undefined) target[method]()
            else target[method](argument)
            return true
        } catch (error) { return false }
    }

    function delegateCount() {
        var delegates = delegateProbe()
        return delegates ? delegates.count : -1
    }

    function initTestCase() {
        wait(0)
        verify(probeLoader.status === Loader.Ready,
               "the BridgeProbe fixture mounts in the roll lane")
    }

    // Fork testPresenterPropertyBinding: the presenter property binds through.
    function test_presenterPropertyBinding() {
        compare(textShown("statusText"), "idle",
                "A004: status binds idle on mount")
        verify(dispatched(probe(), "setStatusText", "ready"),
               "A005: setStatusText ready dispatches on the mounted probe")
        tryCompare(textItem("statusText"), "text", "ready", 5000,
                   "A006: status follows setStatusText ready")
    }

    // Fork testInPlaceRowMutation: silent in-place edits keep the delegate.
    function test_inPlaceRowMutation() {
        var item = fixture()
        verify(dispatched(item, "seedDefaultRows"),
               "the probe seeds its default rows before in-place mutation")
        tryVerify(function() { return textByKey(202) !== null }, 5000,
                  "A010: seeded middle row text exists")
        compare(textShown("rowText_202"), "Beta:20",
                "A011: seeded middle row renders Beta:20")
        var originalSerial = delegateByKey(202).delegateSerial
        verify(dispatched(item, "mutateMiddleDirect"),
               "A012: mutateMiddleDirect dispatches on the mounted probe")
        tryVerify(function() {
            var text = textByKey(202)
            return text && text.text === "Beta:20"
        }, 5000, "A013: in-place mutation leaves the copied delegate text Beta:20")
        tryVerify(function() {
            var delegate = delegateByKey(202)
            return delegate && delegate.delegateSerial === originalSerial
        }, 5000, "A014: in-place mutation keeps the delegate instance")
        verify(dispatched(item, "replaceMiddleSameRow"),
               "A015: replaceMiddleSameRow dispatches on the mounted probe")
        tryVerify(function() {
            var text = textByKey(202)
            return text && text.text === "Beta direct:20"
        }, 5000, "A016: same-row replacement publishes Beta direct:20")
        tryVerify(function() {
            var delegate = delegateByKey(202)
            return delegate && delegate.delegateSerial === originalSerial
        }, 5000, "A017: same-row replacement reuses the delegate instance")
    }

    // Fork testRowReplacement: a new row reuses the delegate slot.
    function test_rowReplacement() {
        var item = fixture()
        verify(dispatched(item, "seedDefaultRows"),
               "A019: seedDefaultRows dispatches on the mounted probe")
        tryVerify(function() { return delegateByKey(202) !== null }, 5000,
                  "A020: seeded middle delegate exists before replacement")
        var originalSerial = delegateByKey(202).delegateSerial
        verify(dispatched(item, "replaceMiddleWithNewRow"),
               "A021: replaceMiddleWithNewRow dispatches on the mounted probe")
        tryVerify(function() { return delegateByKey(404) !== null }, 5000,
                  "A022: replacement delegate exists")
        tryVerify(function() { return textByKey(404) !== null }, 5000,
                  "A023: replacement row text exists")
        tryCompare(textByKey(404), "text", "Delta:44", 5000,
                   "A024: replacement delegate renders Delta:44")
        tryVerify(function() {
            var delegate = delegateByKey(404)
            return delegate && delegate.delegateSerial === originalSerial
        }, 5000, "A025: replacement reuses the delegate slot")
        verify(dispatched(probe(), "actViaSelectedRow"),
               "A026: actViaSelectedRow dispatches on the mounted probe")
        tryCompare(textItem("actionLogText"), "text", "202:Beta", 5000,
                   "A027: selected-row action logs 202:Beta")
        tryCompare(textByKey(404), "text", "Delta:44", 5000,
                   "A028: replacement text still Delta:44 after the action")
    }

    // Fork testInsertRemovePreservesTargets: survivors keep their delegates.
    function test_insertRemovePreservesTargets() {
        var item = fixture()
        verify(dispatched(item, "seedDefaultRows"),
               "the probe seeds its default rows before insert and remove")
        tryVerify(function() { return delegateByKey(101) !== null }, 5000,
                  "A031: seeded alpha delegate exists")
        tryVerify(function() { return delegateByKey(303) !== null }, 5000,
                  "A032: seeded gamma delegate exists")
        var alphaSerial = delegateByKey(101).delegateSerial
        var gammaSerial = delegateByKey(303).delegateSerial
        verify(dispatched(item, "insertHeadRemoveMiddle"),
               "A033: insertHeadRemoveMiddle dispatches on the mounted probe")
        tryVerify(function() { return delegateCount() === 3 }, 5000,
                  "A035: insert plus remove leaves three delegates")
        tryVerify(function() { return delegateByKey(100) !== null }, 5000,
                  "A036: inserted head delegate exists")
        tryVerify(function() { return delegateByKey(101) !== null }, 5000,
                  "A037: alpha delegate survives insert and remove")
        tryVerify(function() { return delegateByKey(303) !== null }, 5000,
                  "A038: gamma delegate survives insert and remove")
        tryVerify(function() {
            var delegate = delegateByKey(100)
            return delegate && delegate.index === 0
        }, 5000, "A039: head delegate sits at index 0")
        tryVerify(function() {
            var delegate = delegateByKey(101)
            return delegate && delegate.index === 1
        }, 5000, "A040: alpha delegate sits at index 1")
        tryVerify(function() {
            var delegate = delegateByKey(303)
            return delegate && delegate.index === 2
        }, 5000, "A041: gamma delegate sits at index 2")
        tryVerify(function() { return delegateByKey(202) === null }, 5000,
                  "A042: removed middle delegate is gone")
        tryVerify(function() {
            var delegate = delegateByKey(101)
            return delegate && delegate.delegateSerial === alphaSerial
        }, 5000, "A043: alpha keeps its delegate across insert and remove")
        tryVerify(function() {
            var delegate = delegateByKey(303)
            return delegate && delegate.delegateSerial === gammaSerial
        }, 5000, "A044: gamma keeps its delegate across insert and remove")
        verify(dispatched(probe(), "actViaSelectedRow"),
               "A045: actViaSelectedRow dispatches after insert and remove")
        tryCompare(textItem("actionLogText"), "text", "303:Gamma", 5000,
                   "A046: retained selection logs 303:Gamma")
    }

    // Fork testReorderTargetsIntendedRow: the move retargets, then recreates.
    function test_reorderTargetsIntendedRow() {
        var item = fixture()
        verify(dispatched(item, "seedDefaultRows"),
               "the probe seeds its default rows before the move")
        tryVerify(function() { return delegateByKey(101) !== null }, 5000,
                  "A049: seeded alpha delegate exists")
        var originalSerial = delegateByKey(101).delegateSerial
        verify(dispatched(item, "removeInsertFirstToLast"),
               "A050: removeInsertFirstToLast dispatches on the mounted probe")
        tryVerify(function() { return delegateByKey(202) !== null }, 5000,
                  "A051: beta delegate exists after the move")
        tryVerify(function() { return delegateByKey(303) !== null }, 5000,
                  "A052: gamma delegate exists after the move")
        tryVerify(function() { return delegateByKey(101) !== null }, 5000,
                  "A053: alpha delegate exists after the move")
        tryVerify(function() {
            var delegate = delegateByKey(202)
            return delegate && delegate.index === 0
        }, 5000, "A054: beta delegate sits at index 0 after the move")
        tryVerify(function() {
            var delegate = delegateByKey(303)
            return delegate && delegate.index === 1
        }, 5000, "A055: gamma delegate sits at index 1 after the move")
        tryVerify(function() {
            var delegate = delegateByKey(101)
            return delegate && delegate.index === 2
        }, 5000, "A056: alpha delegate sits at index 2 after the move")
        tryVerify(function() {
            var delegate = delegateByKey(101)
            return delegate && delegate.delegateSerial !== originalSerial
        }, 5000, "A057: moved alpha renders through a new delegate")
        verify(dispatched(probe(), "actViaSelectedRow"),
               "A058: actViaSelectedRow dispatches after the move")
        tryCompare(textItem("actionLogText"), "text", "101:Alpha", 5000,
                   "A059: moved selection logs 101:Alpha")
    }

    // Fork testResetWithStaleQmlReference: the stale row still acts, calmly.
    function test_resetWithStaleQmlReference() {
        var item = fixture()
        verify(dispatched(item, "seedDefaultRows"),
               "A061: seedDefaultRows dispatches before the reset")
        verify(dispatched(item, "resetWithFreshRows"),
               "A062: resetWithFreshRows dispatches on the mounted probe")
        tryVerify(function() { return delegateByKey(202) === null }, 5000,
                  "A063: reset drops the stale middle delegate")
        tryVerify(function() { return textByKey(901) !== null }, 5000,
                  "A064: fresh first row text exists")
        tryVerify(function() { return textByKey(902) !== null }, 5000,
                  "A065: fresh second row text exists")
        tryCompare(textByKey(901), "text", "Fresh A:91", 5000,
                   "A066: fresh first row renders Fresh A:91")
        tryCompare(textByKey(902), "text", "Fresh B:92", 5000,
                   "A067: fresh second row renders Fresh B:92")
        verify(dispatched(probe(), "actViaSelectedRow"),
               "A068: actViaSelectedRow dispatches after the reset")
        tryCompare(textItem("actionLogText"), "text", "202:Beta", 5000,
                   "A069: stale selection still logs 202:Beta after the reset")
        tryCompare(textByKey(901), "text", "Fresh A:91", 5000,
                   "A070: fresh first row still Fresh A:91 after the action")
        tryCompare(textByKey(902), "text", "Fresh B:92", 5000,
                   "A071: fresh second row still Fresh B:92 after the action")
        verify(probeLoader.status === Loader.Ready,
               "A072: mounted scene stays ready after the reset")
        probe().selectedIndex = 99
        verify(probe().selectedRow() === null,
               "A073: out-of-range selection yields no row on the mounted probe")
    }

    // Fork testPendingMutationThenTeardown: a remount starts clean and silent.
    function test_pendingMutationThenTeardown() {
        var item = fixture()
        verify(dispatched(item, "seedDefaultRows"),
               "A075: seedDefaultRows dispatches before teardown")
        verify(dispatched(item, "mutateMiddleDirect"),
               "A077: mutateMiddleDirect dispatches before teardown")
        tryVerify(function() { return delegateCount() === 3 }, 5000,
                  "three delegates mount before the refusal")
        probe().removeRow(99)
        tryVerify(function() { return delegateCount() === 3 }, 5000,
                  "A079: out-of-range removal leaves three delegates")
        probeLoader.active = false
        tryVerify(function() { return probeLoader.status === Loader.Null }, 5000,
                  "the probe unmounts for the teardown")
        probeLoader.active = true
        tryVerify(function() { return probeLoader.status === Loader.Ready }, 10000,
                  "the probe remounts fresh for the teardown")
        item = fixture()
        verify(dispatched(item, "seedDefaultRows"),
               "A081: seedDefaultRows dispatches on the remounted probe")
        tryVerify(function() { return textByKey(202) !== null }, 5000,
                  "A082: remounted middle row text exists")
        tryCompare(textByKey(202), "text", "Beta:20", 5000,
                   "A083: remounted middle row renders Beta:20")
        tryCompare(textItem("actionLogText"), "text", "", 5000,
                   "A084: remounted action log starts empty")
        probe().selectedIndex = -1
        verify(probe().selectedRow() === null,
               "null selection reads back null before the refusal")
        probe().actViaSelectedRow()
        tryCompare(textItem("actionLogText"), "text", "", 5000,
                   "A085: action with null selection logs nothing")
    }

    // Fork testObjectReturnCapability: returns retain, absence reads as null.
    function test_objectReturnCapability() {
        var item = fixture()
        verify(dispatched(item, "seedDefaultRows"),
               "A087: seedDefaultRows dispatches before the return probe")
        verify(dispatched(item, "inspectMadeRow"),
               "A088: inspectMadeRow dispatches on the mounted probe")
        tryCompare(textItem("returnedTitleText"), "text", "Returned", 5000,
                   "A089: returned row renders its title")
        verify(dispatched(item, "inspectSelectedPresent"),
               "A091: inspectSelectedPresent dispatches on the mounted probe")
        tryVerify(function() {
            var state = probeState()
            return state && state.selectedIsNull === false
        }, 5000, "A092: present selection is not null")
        tryCompare(textItem("selectedTitleText"), "text", "Beta", 5000,
                   "A093: present selection renders Beta")
        verify(dispatched(item, "inspectSelectedMissing"),
               "A094: inspectSelectedMissing dispatches on the mounted probe")
        tryVerify(function() {
            var state = probeState()
            return state && state.selectedIsNull === true
        }, 5000, "A095: missing selection is null")
        tryCompare(textItem("selectedTitleText"), "text", "<null>", 5000,
                   "A096: missing selection renders null")
        tryVerify(function() { return delegateCount() === 3 }, 5000,
                  "three delegates mount before the insertion refusal")
        probe().insertRowWithNew(99, "Bogus", 1, 999)
        tryVerify(function() { return delegateCount() === 3 }, 5000,
                  "A097: out-of-range insertion leaves three delegates")
    }
}
