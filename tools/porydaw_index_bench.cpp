// porydaw_index_bench — profiles decomp project indexing (DecompProject::
// open) against a real checkout, defaulting to the hearth-usb stick.
//
// Read-only by contract: it never writes to the indexed project or its
// volume (the FAT32 stick has no room for stray artifacts); persistent-index
// experiments write under a caller-provided scratch dir instead. It collects
// no traces — timing is in-process, results are METRIC lines on stdout.
//
// Usage:
//   porydaw_index_bench [--root DIR] [--runs N]
//       [--backend none|sqlite|json] [--cache-dir DIR]
//
// Metrics (consumed by autoresearch.sh):
//   METRIC project_open_ms       median wall time of one full open
//   METRIC project_first_open_ms first open (cold OS caches)
//   METRIC project_open_min_ms   fastest open
//   METRIC project_open_max_ms   slowest open
//   METRIC index_songs           songs in the assembled index
//   METRIC index_store_bytes     bytes of the persistent store, 0 when none
//
// Every run's index is digested (FNV-1a over the full SongInfo/player
// content); a mismatch between runs aborts — the benchmark refuses to time
// nondeterministic indexing, and later cache-backed variants must reproduce
// the scan's digest exactly.

#include <QCoreApplication>
#include <QElapsedTimer>
#include <QFileInfo>
#include <QString>
#include <QVector>

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <vector>

#include "project/decompproject.h"
#include "project/projectindex.h"

namespace {

constexpr const char *kDefaultRoot = "/Volumes/ESD-USB/hearth-usb";
constexpr int kDefaultRuns = 7;

constexpr uint64_t kFnv1aInit = 0xcbf29ce484222325ull;
constexpr uint64_t kFnv1aPrime = 0x100000001b3ull;

uint64_t hashBytes(uint64_t h, const void *data, size_t len)
{
    const auto *bytes = static_cast<const uint8_t *>(data);
    for (size_t i = 0; i < len; ++i) {
        h ^= bytes[i];
        h *= kFnv1aPrime;
    }
    return h;
}

uint64_t hashText(uint64_t h, const QString &text)
{
    for (const QChar c : text) {
        const char16_t unit = c.unicode();
        h = hashBytes(h, &unit, sizeof(unit));
    }
    const uint8_t sep = 0xff;
    return hashBytes(h, &sep, 1);
}

template <typename T>
uint64_t hashPod(uint64_t h, const T &value)
{
    return hashBytes(h, &value, sizeof(T));
}

uint64_t hashSong(uint64_t h, const SongInfo &song)
{
    h = hashText(h, song.label);
    h = hashText(h, song.constant);
    h = hashText(h, song.player);
    h = hashText(h, song.midPath);
    h = hashPod(h, song.id);
    h = hashPod(h, song.hasMid);
    h = hashPod(h, song.hasCfg);
    h = hashPod(h, song.registered);
    h = hashText(h, song.registrationGaps.join(u','));
    h = hashText(h, song.cfg.rawFlags.join(u','));
    h = hashText(h, song.cfg.voicegroupArg);
    h = hashPod(h, song.cfg.masterVolume);
    h = hashPod(h, song.cfg.reverb);
    h = hashPod(h, song.cfg.priority);
    h = hashPod(h, song.cfg.exactGate);
    h = hashPod(h, song.cfg.extendedClocks);
    h = hashPod(h, song.cfg.noCompression);
    return h;
}

double medianOf(std::vector<double> values)
{
    std::sort(values.begin(), values.end());
    const size_t n = values.size();
    if (n == 0)
        return 0.0;
    if (n % 2 == 1)
        return values[n / 2];
    return 0.5 * (values[n / 2 - 1] + values[n / 2]);
}

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);

    QString root = QString::fromLatin1(kDefaultRoot);
    if (const QString envRoot = qEnvironmentVariable("PORYDAW_BENCH_ROOT"); !envRoot.isEmpty())
        root = envRoot;
    int runs = kDefaultRuns;

    QString backendName = QStringLiteral("none");
    QString cacheDir;

    const QStringList args = app.arguments();
    for (int i = 1; i < args.size(); ++i) {
        if (args[i] == QLatin1String("--root") && i + 1 < args.size()) {
            root = args[++i];
        } else if (args[i] == QLatin1String("--runs") && i + 1 < args.size()) {
            runs = args[++i].toInt();
        } else if (args[i] == QLatin1String("--backend") && i + 1 < args.size()) {
            backendName = args[++i];
        } else if (args[i] == QLatin1String("--cache-dir") && i + 1 < args.size()) {
            cacheDir = args[++i];
        } else {
            fprintf(stderr, "usage: porydaw_index_bench [--root DIR] [--runs N]"
                            " [--backend none|sqlite|json] [--cache-dir DIR]\n");
            return 2;
        }
    }
    if (runs < 1) {
        fprintf(stderr, "index_bench: --runs must be >= 1\n");
        return 2;
    }
    ProjectIndex::Backend backend = ProjectIndex::Backend::Sqlite;
    if (backendName == QLatin1String("sqlite")) {
        backend = ProjectIndex::Backend::Sqlite;
    } else if (backendName == QLatin1String("json")) {
        backend = ProjectIndex::Backend::Json;
    } else if (backendName != QLatin1String("none")) {
        fprintf(stderr, "index_bench: unknown --backend %s\n", qPrintable(backendName));
        return 2;
    }

    DecompProject project;
    if (!cacheDir.isEmpty() && backendName != QLatin1String("none"))
        project.setIndexCache(cacheDir, backend);

    QString error;
    std::vector<double> elapsedMs;
    elapsedMs.reserve(runs);
    uint64_t expectedDigest = 0;
    int songs = -1;
    int registered = 0;

    for (int i = 0; i < runs; ++i) {
        QElapsedTimer timer;
        timer.start();
        const bool ok = project.open(root, &error);
        const double ms = double(timer.nsecsElapsed()) / 1e6;
        if (!ok) {
            fprintf(stderr, "index_bench: open failed: %s\n", qPrintable(error));
            return 1;
        }

        const QVector<SongInfo> &indexed = project.songs();
        uint64_t digest = kFnv1aInit;
        digest = hashPod(digest, uint64_t(indexed.size()));
        registered = 0;
        for (const SongInfo &song : indexed) {
            digest = hashSong(digest, song);
            if (song.registered)
                ++registered;
        }
        if (i == 0) {
            expectedDigest = digest;
            songs = int(indexed.size());
        } else if (digest != expectedDigest) {
            fprintf(stderr,
                    "index_bench: run %d produced a different index than run 1 "
                    "(digest mismatch) — refusing to report\n",
                    i + 1);
            return 1;
        }

        fprintf(stderr, "run %d/%d: %.1f ms (%d songs)\n", i + 1, runs, ms, int(indexed.size()));
        elapsedMs.push_back(ms);
    }

    double minMs = elapsedMs.front();
    double maxMs = elapsedMs.front();
    for (const double ms : elapsedMs) {
        minMs = std::min(minMs, ms);
        maxMs = std::max(maxMs, ms);
    }

    printf("METRIC project_open_ms=%.2f\n", medianOf(elapsedMs));
    printf("METRIC project_first_open_ms=%.2f\n", elapsedMs.front());
    printf("METRIC project_open_min_ms=%.2f\n", minMs);
    printf("METRIC project_open_max_ms=%.2f\n", maxMs);
    printf("METRIC index_songs=%d\n", songs);
    const qint64 storeBytes = backendName == QLatin1String("none")
                                  ? 0
                                  : QFileInfo(ProjectIndex::storePath(backend, cacheDir)).size();
    printf("METRIC index_store_bytes=%lld\n", (long long)storeBytes);
    printf("ASI runs=%d\n", runs);
    printf("ASI root=%s\n", qPrintable(root));
    printf("ASI backend=%s\n", qPrintable(backendName));
    printf("ASI registered=%d\n", registered);
    printf("ASI checksum=%016llx\n", (unsigned long long)expectedDigest);
    return 0;
}
