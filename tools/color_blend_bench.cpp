// Microbenchmark for songview::mixTowardOklab and songview::ghostNoteColor.
//
// Measures only the color-space algorithms — no painting, widgets, or layout.
// Theme is applied once up front so ghostNoteColor's role lookups hit the
// already-resolved table (the same steady state paint paths see).
//
// Delineation is Instruments Points of Interest only (os_signpost). There is
// no stdout from the timed path — printf would pollute both chrono and the
// POI intervals.
//
// Build (Release):
//   cmake --build build --target porydaw_color_blend_bench -j
// Run under Instruments (Points of Interest + Time Profiler), or:
//   QT_QPA_PLATFORM=offscreen ./build/porydaw_color_blend_bench
//   ./build/porydaw_color_blend_bench --iters 2000000 --trials 11

#include "ui/songview.h"
#include "ui/theme/themeresolver.h"
#include "ui/theme/themeruntime.h"
#include "ui/theme/trackidentitycolors.h"

#include <QApplication>
#include <QColor>
#include <QStringList>

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <vector>

#if defined(__APPLE__)
#include <os/log.h>
#include <os/signpost.h>
#endif

namespace {

// Prevent the optimizer from deleting timed work. Reads the value as an input
// constraint and issues a memory clobber so surrounding stores stay live.
template <typename T> void doNotOptimize(const T &value) {
#if defined(__GNUC__) || defined(__clang__)
  asm volatile("" : : "r,m"(value) : "memory");
#else
  volatile const T *sink = &value;
  (void)sink;
#endif
}

// Keep a running sink the optimizer cannot prove unused across loop iterations.
void consumeColor(QColor color, std::uint64_t &sink) {
  // rgba() packs the result into a single integer — cheap, deterministic, and
  // forces the full QColor construction to complete.
  sink ^= static_cast<std::uint64_t>(color.rgba());
  doNotOptimize(sink);
}

// Instruments Points of Interest: os_signpost intervals on
// OS_LOG_CATEGORY_POINTS_OF_INTEREST. Nested begin/end pairs use a stack of
// signpost IDs so group + case intervals nest correctly. No I/O.
#if defined(__APPLE__)
os_log_t poiLog() {
  static const os_log_t log =
      os_log_create("com.porydaw.color_blend_bench",
                    OS_LOG_CATEGORY_POINTS_OF_INTEREST);
  return log;
}

struct PoiFrame {
  os_signpost_id_t id;
  const char *label;
};

constexpr int kPoiStackMax = 8;
PoiFrame g_poiStack[kPoiStackMax];
int g_poiDepth = 0;

void poiBegin(const char *label) {
  if (g_poiDepth >= kPoiStackMax)
    return;
  const os_log_t log = poiLog();
  const os_signpost_id_t id = os_signpost_id_generate(log);
  // Interval name is the stable category in Instruments; the message carries
  // the case label. %{public}s so labels are not redacted.
  os_signpost_interval_begin(log, id, "color_blend", "%{public}s", label);
  g_poiStack[g_poiDepth++] = {id, label};
}

void poiEnd(const char *label) {
  if (g_poiDepth <= 0)
    return;
  const PoiFrame frame = g_poiStack[--g_poiDepth];
  os_signpost_interval_end(poiLog(), frame.id, "color_blend", "%{public}s",
                           label);
}
#else
void poiBegin(const char *) {}
void poiEnd(const char *) {}
#endif

// Run `body(i, sink)` for `iters` iterations. Index is independent of the sink
// so rotating inputs do not serialize through the consume dependency.
template <typename Body>
void runIters(std::uint64_t iters, Body &&body) {
  std::uint64_t sink = 0;
  body(0, sink);
  doNotOptimize(sink);
  for (std::uint64_t i = 0; i < iters; ++i)
    body(i, sink);
  doNotOptimize(sink);
}

template <typename Body>
void bench(const char *name, std::uint64_t iters, int trials, Body &&body) {
  poiBegin(name);
  // Warmup + measured trials: all pure algorithm work under the case POI.
  runIters(iters / 8 + 1, body);
  for (int t = 0; t < trials; ++t)
    runIters(iters, body);
  poiEnd(name);
}

struct Args {
  std::uint64_t iters = 500'000;
  int trials = 9;
};

Args parseArgs(const QStringList &argv) {
  Args args;
  for (int i = 1; i < argv.size(); ++i) {
    const QString &a = argv[i];
    if ((a == QLatin1String("--iters") || a == QLatin1String("-n")) &&
        i + 1 < argv.size()) {
      args.iters = argv[++i].toULongLong();
    } else if ((a == QLatin1String("--trials") || a == QLatin1String("-t")) &&
               i + 1 < argv.size()) {
      args.trials = argv[++i].toInt();
    } else if (a == QLatin1String("--help") || a == QLatin1String("-h")) {
      std::fprintf(
          stderr,
          "Usage: porydaw_color_blend_bench [--iters N] [--trials N]\n"
          "  Algorithm microbench for mixTowardOklab / ghostNoteColor.\n"
          "  Delineated only via Instruments Points of Interest "
          "(os_signpost).\n");
      std::exit(0);
    } else {
      std::fprintf(stderr, "unknown argument: %s\n", qPrintable(a));
      std::exit(2);
    }
  }
  if (args.iters < 1000)
    args.iters = 1000;
  if (args.trials < 1)
    args.trials = 1;
  return args;
}

} // namespace

int main(int argc, char *argv[]) {
  QApplication app(argc, argv);
  themes::initialize(app);
  themes::apply(app, themes::vanilla());

  const Args args = parseArgs(app.arguments());

  // Inputs match paint-path usage. Built once so allocation/lookup of QColor
  // constants is not part of the timed algorithm.
  const QColor trackFill = themes::trackIdentityColor(0);
  const QColor black = Qt::black;
  const QColor white = Qt::white;
  const QColor backdrop =
      themes::color(themes::Role::song_view_piano_roll_background);
  const double tStem = 1.0 / 3.0;
  const double tHeader = 0.6;

  struct GhostInput {
    int track;
    bool accidental;
  };
  std::vector<GhostInput> ghostInputs;
  ghostInputs.reserve(themes::trackIdentityColorCount * 2);
  for (std::size_t i = 0; i < themes::trackIdentityColorCount; ++i) {
    ghostInputs.push_back({static_cast<int>(i), false});
    ghostInputs.push_back({static_cast<int>(i), true});
  }

  struct MixInput {
    QColor color;
    QColor backdrop;
    double t;
  };
  std::vector<MixInput> mixInputs;
  mixInputs.reserve(themes::trackIdentityColorCount * 2);
  for (std::size_t i = 0; i < themes::trackIdentityColorCount; ++i) {
    const QColor &fill = themes::trackIdentityColor(i);
    mixInputs.push_back({fill, black, tStem});
    mixInputs.push_back({fill, backdrop, tHeader});
  }

  poiBegin("mixTowardOklab");
  bench("mixTowardOklab/fixed", args.iters, args.trials,
        [&](std::uint64_t /*i*/, std::uint64_t &sink) {
          consumeColor(songview::mixTowardOklab(trackFill, black, tStem), sink);
        });
  bench("mixTowardOklab/rotate", args.iters, args.trials,
        [&](std::uint64_t i, std::uint64_t &sink) {
          const auto &in =
              mixInputs[static_cast<std::size_t>(i) % mixInputs.size()];
          consumeColor(songview::mixTowardOklab(in.color, in.backdrop, in.t),
                       sink);
        });
  bench("mixTowardOklab/t=0", args.iters, args.trials,
        [&](std::uint64_t /*i*/, std::uint64_t &sink) {
          consumeColor(songview::mixTowardOklab(trackFill, white, 0.0), sink);
        });
  bench("mixTowardOklab/t=1", args.iters, args.trials,
        [&](std::uint64_t /*i*/, std::uint64_t &sink) {
          consumeColor(songview::mixTowardOklab(trackFill, white, 1.0), sink);
        });
  poiEnd("mixTowardOklab");

  poiBegin("ghostNoteColor");
  bench("ghostNoteColor/fixed", args.iters, args.trials,
        [&](std::uint64_t /*i*/, std::uint64_t &sink) {
          consumeColor(songview::ghostNoteColor(0, false), sink);
        });
  bench("ghostNoteColor/rotate", args.iters, args.trials,
        [&](std::uint64_t i, std::uint64_t &sink) {
          const auto &in =
              ghostInputs[static_cast<std::size_t>(i) % ghostInputs.size()];
          consumeColor(songview::ghostNoteColor(in.track, in.accidental), sink);
        });
  poiEnd("ghostNoteColor");

  return 0;
}
