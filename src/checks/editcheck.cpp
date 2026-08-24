#include <QElapsedTimer>

#include <cstdio>

#include "editcheck/support.h"

// --editcheck <projectRoot>: M2 undo-integrity check. For every song with a
// MIDI source, performs a scripted pass over every edit-operation type, then
// verifies that undoing everything restores the SMF byte-for-byte, that redo
// reproduces the edited state deterministically, and that event ticks stay
// sorted after each mutation. Complements --roundtrip (which proves the
// unedited writer) by proving the editing layer can always get back to that
// pristine state.

int runEditCheck(const QString &projectRoot)
{
    DecompProject project;
    QString error;
    if (!project.open(projectRoot, &error)) {
        std::fprintf(stderr, "editcheck: %s\n", qUtf8Printable(error));
        return 1;
    }

    QElapsedTimer timer;
    timer.start();

    int checked = 0, failures = 0;
    for (const SongInfo &song : project.songs())
        editcheck::runSongRoundTrip(song, checked, failures);

    failures += editcheck::format0ConvertFailures();
    failures += editcheck::markerVsNameFailures();
    failures += editcheck::sameTickDuplicateFailures();
    failures += editcheck::documentContractFailures();
    failures += editcheck::timeRangeContractFailures();

    std::printf("editcheck: %d songs in %lld ms\n", checked, (long long)timer.elapsed());
    std::printf("editcheck: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures ? 1 : 0;
}
