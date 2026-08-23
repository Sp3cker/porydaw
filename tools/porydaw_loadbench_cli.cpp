// porydaw_loadbench_cli — times the four legacy loader workflows used by
// the voicegroup-core migration comparison. Each invocation runs one explicit
// old-surface analog; run this executable afresh for the cold metric.
//
// Usage:
//   porydaw_loadbench_cli <projectRoot> <mode> [options]
//
// Modes:
//   cold-saved-bank  voicegroup_load with the snapshot cache disabled
//   warm-saved-bank  steady-state voicegroup_load with the snapshot cached
//   preview          voicegroup_load through the legacy temp-shadow/config path
//   picker-row       voicegroup_load_samples with exactly one sample symbol
//
// Options:
//   --iterations N       timed repetitions (default: 10)
//   --voicegroup NAME    voicegroup for the preview mode
//   --preview-source P   project-relative source to shadow for preview
//   --symbol NAME        DirectSound symbol for the picker-row mode

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <numeric>
#include <string>
#include <system_error>
#ifdef _WIN32
#include <io.h>
#else
#include <unistd.h>
#endif

extern "C" {
#include "voicegroup_loader.h"
}

namespace {

using Clock = std::chrono::steady_clock;
namespace fs = std::filesystem;

enum class Mode {
    ColdSavedBank,
    WarmSavedBank,
    Preview,
    PickerRow,
};

double msSince(Clock::time_point t0)
{
    return std::chrono::duration<double, std::milli>(Clock::now() - t0).count();
}

void report(const char *what, const std::vector<double> &samples)
{
    if (samples.empty())
        return;
    std::vector<double> s = samples;
    std::sort(s.begin(), s.end());
    const double sum = std::accumulate(s.begin(), s.end(), 0.0);
    printf("%-28s n=%zu  min=%.2f  med=%.2f  mean=%.2f  max=%.2f ms\n", what, s.size(), s.front(),
           s[s.size() / 2], sum / double(s.size()), s.back());
}

bool parseMode(const char *text, Mode *mode)
{
    if (!strcmp(text, "cold-saved-bank")) {
        *mode = Mode::ColdSavedBank;
        return true;
    }
    if (!strcmp(text, "warm-saved-bank")) {
        *mode = Mode::WarmSavedBank;
        return true;
    }
    if (!strcmp(text, "preview")) {
        *mode = Mode::Preview;
        return true;
    }
    if (!strcmp(text, "picker-row")) {
        *mode = Mode::PickerRow;
        return true;
    }
    return false;
}

void unsetCacheEnvironment()
{
#ifdef _WIN32
    _putenv_s("PORYDAW_DISABLE_INDEX_CACHE", "");
#else
    unsetenv("PORYDAW_DISABLE_INDEX_CACHE");
#endif
}

bool loadZeroSymbolSet(const char *projectRoot)
{
    LoadedSampleSet *set =
        voicegroup_load_samples(projectRoot, nullptr, 0, nullptr, 0, nullptr, nullptr, 0, nullptr);
    if (!set)
        return false;
    voicegroup_free_samples(set);
    return true;
}

bool loadOneSample(const char *projectRoot, const char *symbol)
{
    const char *sampleSymbols[] = {symbol};
    LoadedSampleSet *set = voicegroup_load_samples(projectRoot, sampleSymbols, 1, nullptr, 0,
                                                   nullptr, nullptr, 0, nullptr);
    if (!set)
        return false;
    voicegroup_free_samples(set);
    return true;
}

bool loadVoicegroup(const char *projectRoot, const char *voicegroup,
                    const VoicegroupLoaderConfig *config)
{
    LoadedVoiceGroup *vg = voicegroup_load(projectRoot, voicegroup, config);
    if (!vg)
        return false;
    voicegroup_free(vg);
    return true;
}

bool readBytes(const fs::path &path, std::string *bytes)
{
    std::ifstream input(path, std::ios::binary);
    if (!input)
        return false;
    bytes->assign(std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>());
    return !input.bad();
}

bool writeBytes(const fs::path &path, const std::string &bytes)
{
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    if (!output)
        return false;
    output.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
    return bool(output);
}

bool isRegularFile(const fs::path &path)
{
    std::error_code ec;
    const bool regular = fs::is_regular_file(path, ec);
    return regular && !ec;
}

fs::path findPreviewSource(const fs::path &projectRoot, const char *voicegroup,
                           const char *sourceOverride)
{
    if (sourceOverride) {
        fs::path source(sourceOverride);
        if (source.is_relative())
            source = projectRoot / source;
        return isRegularFile(source) ? source : fs::path();
    }

    const std::string name(voicegroup);
    const fs::path candidates[] = {
        projectRoot / "sound/voicegroups" / (name + ".inc"),
        projectRoot / "sound/voicegroups" / (name + ".s"),
        projectRoot / "sound" / (name + ".inc"),
        projectRoot / "sound" / (name + ".s"),
        projectRoot / "sound/voice_groups.inc",
        projectRoot / "sound/voicegroups.inc",
    };
    for (const fs::path &candidate : candidates) {
        if (isRegularFile(candidate))
            return candidate;
    }
    return fs::path();
}

// This mirrors MainWindow::reloadVoicegroupPreview: the preview source is
// written under .porydaw/vgpreview and that directory is prepended through
// VoicegroupLoaderConfig. Existing user files are restored by the destructor.
class PreviewShadow
{
  public:
    PreviewShadow() = default;
    bool prepare(const fs::path &projectRoot, const char *voicegroup, const char *sourceOverride,
                 std::string *error)
    {
        m_parent = projectRoot / ".porydaw";
        m_dir = m_parent / "vgpreview";
        m_file = m_dir / (std::string(voicegroup) + ".inc");
        const fs::path source = findPreviewSource(projectRoot, voicegroup, sourceOverride);
        if (source.empty()) {
            *error = "cannot find preview source; pass --preview-source";
            return false;
        }
        if (!readBytes(source, &m_shadowBytes)) {
            *error = "cannot read preview source " + source.string();
            return false;
        }

        std::error_code ec;
        const bool parentExists = fs::exists(m_parent, ec);
        if (ec) {
            *error = "cannot inspect preview parent: " + m_parent.string();
            return false;
        }
        if (parentExists && !fs::is_directory(m_parent, ec)) {
            *error = "preview parent is not a directory: " + m_parent.string();
            return false;
        }
        m_hadParentDir = parentExists;

        ec.clear();
        const bool dirExists = fs::exists(m_dir, ec);
        if (ec) {
            *error = "cannot inspect preview directory: " + m_dir.string();
            return false;
        }
        if (dirExists && !fs::is_directory(m_dir, ec)) {
            *error = "preview path is not a directory: " + m_dir.string();
            return false;
        }
        m_hadDir = dirExists;

        ec.clear();
        const bool fileExists = fs::exists(m_file, ec);
        if (ec) {
            *error = "cannot inspect preview file: " + m_file.string();
            return false;
        }
        if (fileExists && !isRegularFile(m_file)) {
            *error = "preview path is not a regular file: " + m_file.string();
            return false;
        }
        m_hadFile = fileExists;
        if (m_hadFile && !readBytes(m_file, &m_originalBytes)) {
            *error = "cannot save existing preview file " + m_file.string();
            return false;
        }

        m_ready = true;
        if (!m_hadDir) {
            fs::create_directories(m_dir, ec);
            if (ec) {
                *error = "cannot create preview directory: " + m_dir.string();
                restore();
                return false;
            }
        }
        if (!writeBytes(m_file, m_shadowBytes)) {
            *error = "cannot write preview file: " + m_file.string();
            restore();
            return false;
        }
        return true;
    }

    ~PreviewShadow() { restore(); }

    bool write() { return m_ready && writeBytes(m_file, m_shadowBytes); }

    const fs::path &file() const { return m_file; }

    PreviewShadow(const PreviewShadow &) = delete;
    PreviewShadow &operator=(const PreviewShadow &) = delete;

  private:
    void restore()
    {
        if (!m_ready)
            return;
        if (m_hadFile)
            writeBytes(m_file, m_originalBytes);
        else {
            std::error_code ec;
            fs::remove(m_file, ec);
        }
        if (!m_hadDir) {
            std::error_code ec;
            fs::remove(m_dir, ec);
        }
        if (!m_hadParentDir) {
            std::error_code ec;
            fs::remove(m_parent, ec);
        }
        m_ready = false;
    }

    fs::path m_parent;
    fs::path m_dir;
    fs::path m_file;
    std::string m_shadowBytes;
    std::string m_originalBytes;
    bool m_hadParentDir = false;
    bool m_hadDir = false;
    bool m_hadFile = false;
    bool m_ready = false;
};

// The loader prints to stderr for expected probe failures; keep timed loops
// quiet without touching the loader.
class QuietStderr
{
  public:
    QuietStderr()
    {
        fflush(stderr);
#ifdef _WIN32
        m_fd = _dup(_fileno(stderr));
        if (m_fd >= 0)
            freopen("NUL", "w", stderr);
#else
        m_fd = dup(2);
        if (m_fd >= 0)
            freopen("/dev/null", "w", stderr);
#endif
    }
    ~QuietStderr()
    {
        if (m_fd < 0)
            return;
        fflush(stderr);
#ifdef _WIN32
        _dup2(m_fd, _fileno(stderr));
        _close(m_fd);
#else
        dup2(m_fd, 2);
        close(m_fd);
#endif
    }
    QuietStderr(const QuietStderr &) = delete;
    QuietStderr &operator=(const QuietStderr &) = delete;

  private:
    int m_fd = -1;
};

int runSavedBank(const char *projectRoot, const char *voicegroup, Mode mode, int iterations)
{
    const bool cold = mode == Mode::ColdSavedBank;
    unsetCacheEnvironment();
    voicegroup_loader_set_snapshot_cache_enabled(cold ? 0 : 1);
    printf("mode: %s; voicegroup=%s; snapshot-cache=%s; "
           "PORYDAW_DISABLE_INDEX_CACHE=unset\n",
           cold ? "cold-saved-bank" : "warm-saved-bank", voicegroup, cold ? "disabled" : "enabled");

    if (!cold && !loadVoicegroup(projectRoot, voicegroup, nullptr)) {
        fprintf(stderr, "loadbench: warm saved-bank setup failed\n");
        return 1;
    }

    std::vector<double> loadMs;
    for (int i = 0; i < iterations; i++) {
        const Clock::time_point t0 = Clock::now();
        const bool ok = loadVoicegroup(projectRoot, voicegroup, nullptr);
        const double ms = msSince(t0);
        if (!ok) {
            fprintf(stderr, "loadbench: %s saved-bank iteration %d failed\n",
                    cold ? "cold" : "warm", i);
            return 1;
        }
        loadMs.push_back(ms);
    }
    report(cold ? "cold saved-bank load" : "warm saved-bank load", loadMs);
    return 0;
}

int runPreview(const char *projectRoot, const char *voicegroup, const char *sourceOverride,
               int iterations)
{
    unsetCacheEnvironment();
    voicegroup_loader_set_snapshot_cache_enabled(1);

    PreviewShadow shadow;
    std::string error;
    if (!shadow.prepare(fs::path(projectRoot), voicegroup, sourceOverride, &error)) {
        fprintf(stderr, "loadbench: %s\n", error.c_str());
        return 1;
    }

    VoicegroupLoaderConfig config;
    std::memset(&config, 0, sizeof(config));
    std::strncpy(config.voicegroupPaths[0], ".porydaw/vgpreview", VG_MAX_PATH_LEN - 1);
    config.voicegroupPathCount = 1;
    printf("mode: preview; voicegroup=%s; temp-shadow=%s; snapshot-cache=enabled; "
           "PORYDAW_DISABLE_INDEX_CACHE=unset\n",
           voicegroup, shadow.file().string().c_str());

    // Keep discovery and symbol-map setup outside the timed preview
    // materialization, matching the steady-state comparison on the new side.
    if (!loadVoicegroup(projectRoot, voicegroup, &config)) {
        fprintf(stderr, "loadbench: preview setup failed for voicegroup '%s'\n", voicegroup);
        return 1;
    }

    std::vector<double> loadMs;
    for (int i = 0; i < iterations; i++) {
        bool wrote = false;
        bool loaded = false;
        LoadedVoiceGroup *vg = nullptr;
        double ms = 0.0;
        {
            QuietStderr quiet;
            const Clock::time_point t0 = Clock::now();
            wrote = shadow.write();
            if (wrote)
                vg = voicegroup_load(projectRoot, voicegroup, &config);
            ms = msSince(t0);
            loaded = vg != nullptr;
        }
        if (!wrote) {
            fprintf(stderr, "loadbench: preview iteration %d could not write shadow\n", i);
            return 1;
        }
        if (!loaded) {
            fprintf(stderr, "loadbench: preview iteration %d failed\n", i);
            return 1;
        }
        voicegroup_free(vg);
        loadMs.push_back(ms);
    }
    report("preview temp-shadow/config", loadMs);
    return 0;
}

int runPickerRow(const char *projectRoot, const char *symbol, int iterations)
{
    unsetCacheEnvironment();
    voicegroup_loader_set_snapshot_cache_enabled(1);
    printf("mode: picker-row; symbol=%s; exactly-one-symbol; snapshot-cache=enabled; "
           "PORYDAW_DISABLE_INDEX_CACHE=unset\n",
           symbol);

    // The picker is entered after the project snapshot is already warm.
    if (!loadZeroSymbolSet(projectRoot)) {
        fprintf(stderr, "loadbench: picker-row setup failed\n");
        return 1;
    }

    std::vector<double> loadMs;
    for (int i = 0; i < iterations; i++) {
        const Clock::time_point t0 = Clock::now();
        const bool ok = loadOneSample(projectRoot, symbol);
        const double ms = msSince(t0);
        if (!ok) {
            fprintf(stderr, "loadbench: picker-row iteration %d failed for '%s'\n", i, symbol);
            return 1;
        }
        loadMs.push_back(ms);
    }
    report("first picker-row one-symbol", loadMs);
    return 0;
}

} // namespace

int main(int argc, char *argv[])
{
    if (argc < 3) {
        fprintf(stderr,
                "Usage: %s <projectRoot> <mode> [--iterations N] [--voicegroup NAME] "
                "[--preview-source PATH] [--symbol NAME]\n",
                argv[0]);
        return 1;
    }

    const char *projectRoot = argv[1];
    Mode mode;
    if (!parseMode(argv[2], &mode)) {
        fprintf(stderr,
                "Unknown mode '%s' (expected cold-saved-bank, warm-saved-bank, preview, or "
                "picker-row)\n",
                argv[2]);
        return 1;
    }

    int iterations = 10;
    const char *voicegroup = nullptr;
    const char *previewSource = nullptr;
    const char *symbol = nullptr;
    for (int i = 3; i < argc; i++) {
        if (!strcmp(argv[i], "--iterations") && i + 1 < argc)
            iterations = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--voicegroup") && i + 1 < argc)
            voicegroup = argv[++i];
        else if (!strcmp(argv[i], "--preview-source") && i + 1 < argc)
            previewSource = argv[++i];
        else if (!strcmp(argv[i], "--symbol") && i + 1 < argc)
            symbol = argv[++i];
        else {
            fprintf(stderr, "Unknown or incomplete option: %s\n", argv[i]);
            return 1;
        }
    }
    if (iterations <= 0) {
        fprintf(stderr, "loadbench: --iterations must be positive\n");
        return 1;
    }

    if ((mode == Mode::ColdSavedBank || mode == Mode::WarmSavedBank || mode == Mode::Preview) &&
        !voicegroup) {
        fprintf(stderr, "loadbench: this mode requires --voicegroup NAME\n");
        return 1;
    }
    if (mode == Mode::PickerRow && !symbol) {
        fprintf(stderr, "loadbench: picker-row requires --symbol NAME\n");
        return 1;
    }

    switch (mode) {
    case Mode::ColdSavedBank:
    case Mode::WarmSavedBank:
        return runSavedBank(projectRoot, voicegroup, mode, iterations);
    case Mode::Preview:
        return runPreview(projectRoot, voicegroup, previewSource, iterations);
    case Mode::PickerRow:
        return runPickerRow(projectRoot, symbol, iterations);
    }
    return 1;
}
