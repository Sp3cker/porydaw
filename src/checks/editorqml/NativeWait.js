.pragma library

// Single authoritative waitForNative loop for the rollqml/editorqml lanes.
//
// Every tst_*.qml suite keeps a thin `function waitForNative(predicate,
// timeoutMs)` wrapper (so existing call sites stay byte-identical) that
// delegates here. The loop itself — deadline over `Date.now()`, one
// `bootstrap.pumpMainRunLoop()` plus a 10 ms TestCase `wait` per iteration,
// then a final `predicate()` verdict — lives only in this file.
//
// The TestCase-scope `wait(ms)` is not visible to library code, so each
// wrapper passes a small closure capturing its own scope:
//     function waitForNative(predicate, timeoutMs) {
//         return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
//     }
//
// Resolution: both QML lanes run with `-input <tst file>` under a test
// directory that IS the source directory (EditorQmlPaths/RollQmlPaths
// `testDirectory`), and Qt Quick Test resolves a relative `"x.js"` import
// against the importing file's directory — never the scratch cwd — so no
// manifest fixture staging is needed. editorqml suites import
// `"NativeWait.js"`; rollqml suites import `"../editorqml/NativeWait.js"`.
function waitForNative(bootstrap, waitFn, predicate, timeoutMs) {
    var deadline = Date.now() + timeoutMs
    while (!predicate() && Date.now() < deadline) {
        bootstrap.pumpMainRunLoop()
        waitFn(10)
    }
    return predicate()
}
