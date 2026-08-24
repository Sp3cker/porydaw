// porydaw_loadbench_core_cli — times the modular VoicegroupProject workflows
// used by the voicegroup-core migration comparison.
//
// Usage:
//   porydaw_loadbench_core_cli <projectRoot> <mode> [options]
//
// Modes:
//   cold-saved-bank  open, first refresh, and saved-bank load on a new handle
//   warm-saved-bank  saved-bank load on a persistent, warmed Fresh handle
//   preview          source-bank load from full-file bytes on a Fresh handle
//   picker-row       first one-symbol asset load on a newly refreshed handle

#include <algorithm>
#include <charconv>
#include <chrono>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <memory>
#include <numeric>
#include <string>
#include <string_view>
#include <system_error>
#include <vector>

extern "C" {
#include "voicegroup/voicegroup_project.h"
#include "voicegroup_core.h"
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

struct Options {
    fs::path projectRoot;
    Mode mode = Mode::ColdSavedBank;
    size_t iterations = 10;
    std::string voicegroup = "fixture_rich";
    fs::path previewSource = "sound/voicegroups/fixture_rich.inc";
    std::string symbol = "DirectSoundWaveData_fixture_loop";
};

class ProjectResult final
{
  public:
    ProjectResult() = default;
    ~ProjectResult() { voicegroup_project_result_free(&value); }

    ProjectResult(const ProjectResult &) = delete;
    ProjectResult &operator=(const ProjectResult &) = delete;

    VoicegroupProjectResult value = {};
};

class LoadResult final
{
  public:
    explicit LoadResult(VoicegroupLoadResult result) : value(result) {}
    ~LoadResult() { voicegroup_load_result_free(&value); }

    LoadResult(const LoadResult &) = delete;
    LoadResult &operator=(const LoadResult &) = delete;

    VoicegroupLoadResult value = {};
};

class AssetResult final
{
  public:
    explicit AssetResult(VoicegroupAssetResult result) : value(result) {}
    ~AssetResult() { voicegroup_asset_result_free(&value); }

    AssetResult(const AssetResult &) = delete;
    AssetResult &operator=(const AssetResult &) = delete;

    VoicegroupAssetResult value = {};
};

using ProjectPtr = std::unique_ptr<VoicegroupProject, decltype(&voicegroup_project_free)>;
using BankPtr = std::unique_ptr<LoadedVoiceGroup, decltype(&voicegroup_free)>;

constexpr auto STATE_FRESH = "Fresh";

void printUsage(const char *program)
{
    fprintf(stderr,
            "Usage: %s <projectRoot> <mode> [--iterations N] [--voicegroup NAME] "
            "[--preview-source PATH] [--symbol NAME]\n"
            "Modes: cold-saved-bank, warm-saved-bank, preview, picker-row\n",
            program);
}

bool parseMode(std::string_view text, Mode &mode)
{
    if (text == "cold-saved-bank") {
        mode = Mode::ColdSavedBank;
        return true;
    }
    if (text == "warm-saved-bank") {
        mode = Mode::WarmSavedBank;
        return true;
    }
    if (text == "preview") {
        mode = Mode::Preview;
        return true;
    }
    if (text == "picker-row") {
        mode = Mode::PickerRow;
        return true;
    }
    return false;
}

bool parseIterations(const char *text, size_t &iterations)
{
    const auto input = std::string_view(text);
    if (input.empty() || input.front() == '-')
        return false;
    auto parsed = size_t{0};
    const auto [end, error] = std::from_chars(input.data(), input.data() + input.size(), parsed);
    if (error != std::errc{} || end != input.data() + input.size() || parsed == 0)
        return false;
    iterations = parsed;
    return true;
}

bool parseArguments(int argc, char *argv[], Options &options)
{
    if (argc < 3) {
        printUsage(argv[0]);
        return false;
    }
    options.projectRoot = argv[1];
    if (!parseMode(argv[2], options.mode)) {
        fprintf(stderr, "loadbench: unknown mode '%s'\n", argv[2]);
        printUsage(argv[0]);
        return false;
    }
    for (auto i = 3; i < argc; ++i) {
        const auto option = std::string_view(argv[i]);
        if (option != "--iterations" && option != "--voicegroup" && option != "--preview-source" &&
            option != "--symbol") {
            fprintf(stderr, "loadbench: unknown option '%s'\n", argv[i]);
            return false;
        }
        if (++i == argc) {
            fprintf(stderr, "loadbench: option '%s' requires a value\n", argv[i - 1]);
            return false;
        }
        if (option == "--iterations") {
            if (!parseIterations(argv[i], options.iterations)) {
                fprintf(stderr, "loadbench: --iterations must be a positive integer\n");
                return false;
            }
        } else if (option == "--voicegroup") {
            options.voicegroup = argv[i];
            if (options.voicegroup.empty()) {
                fprintf(stderr, "loadbench: --voicegroup must not be empty\n");
                return false;
            }
        } else if (option == "--preview-source") {
            options.previewSource = argv[i];
            if (options.previewSource.empty()) {
                fprintf(stderr, "loadbench: --preview-source must not be empty\n");
                return false;
            }
        } else {
            options.symbol = argv[i];
            if (options.symbol.empty()) {
                fprintf(stderr, "loadbench: --symbol must not be empty\n");
                return false;
            }
        }
    }
    std::error_code error;
    if (!fs::is_directory(options.projectRoot, error) || error) {
        fprintf(stderr, "loadbench: project root is not a readable directory: %s\n",
                options.projectRoot.string().c_str());
        return false;
    }
    return true;
}

void printDiagnostic(const char *operation, const VoicegroupDiagnostic &diagnostic)
{
    fprintf(stderr, "loadbench: %s: %s: %s", operation,
            diagnostic.code ? diagnostic.code : "diagnostic",
            diagnostic.message ? diagnostic.message : "(no message)");
    if (diagnostic.source_path)
        fprintf(stderr, " [source=%s]", diagnostic.source_path);
    if (diagnostic.asset_path)
        fprintf(stderr, " [asset=%s]", diagnostic.asset_path);
    if (diagnostic.has_range)
        fprintf(stderr, " [range=%zu:%zu-%zu:%zu]", diagnostic.start_line, diagnostic.start_column,
                diagnostic.end_line, diagnostic.end_column);
    if (diagnostic.has_slot)
        fprintf(stderr, " [slot=%zu]", diagnostic.slot);
    fputc('\n', stderr);
}

void printDiagnostics(const char *operation, const VoicegroupDiagnostic *diagnostics, size_t count)
{
    for (auto i = size_t{0}; i < count; ++i)
        printDiagnostic(operation, diagnostics[i]);
}

ProjectPtr openProject(const std::string &root)
{
    return ProjectPtr(voicegroup_project_open(root.data(), root.size()), &voicegroup_project_free);
}

bool refreshProject(VoicegroupProject *project, const char *operation)
{
    auto result = ProjectResult{};
    voicegroup_project_refresh(project, &result.value);
    printDiagnostics(operation, result.value.diagnostics, result.value.diagnostic_count);
    if (!result.value.succeeded)
        fprintf(stderr, "loadbench: %s failed\n", operation);
    return result.value.succeeded;
}

VoicegroupLoadRequest savedRequest(const std::string &voicegroup)
{
    auto request = VoicegroupLoadRequest{};
    request.mode = VG_LOAD_SAVED;
    request.bank_name = voicegroup.data();
    request.bank_name_len = voicegroup.size();
    return request;
}

bool finishLoad(LoadResult &result, const char *operation)
{
    printDiagnostics(operation, result.value.diagnostics, result.value.diagnostic_count);
    if (!result.value.succeeded) {
        fprintf(stderr, "loadbench: %s failed\n", operation);
        return false;
    }
    auto bank = BankPtr(voicegroup_load_result_take(&result.value), &voicegroup_free);
    if (!bank) {
        fprintf(stderr, "loadbench: %s succeeded without a bank\n", operation);
        return false;
    }
    return true;
}

double millisecondsSince(Clock::time_point start)
{
    return std::chrono::duration<double, std::milli>(Clock::now() - start).count();
}

void report(std::string_view mode, std::string_view state, const std::vector<double> &samples)
{
    auto sorted = samples;
    std::sort(sorted.begin(), sorted.end());
    const auto count = sorted.size();
    const auto middle = count / 2;
    const auto median =
        count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2.0 : sorted[middle];
    const auto total = std::accumulate(sorted.begin(), sorted.end(), 0.0);
    printf("mode=%.*s state=%.*s n=%zu min=%.3f med=%.3f mean=%.3f max=%.3f ms\n",
           static_cast<int>(mode.size()), mode.data(), static_cast<int>(state.size()), state.data(),
           count, sorted.front(), median, total / static_cast<double>(count), sorted.back());
}

int runColdSavedBank(const Options &options, const std::string &root)
{
    const auto request = savedRequest(options.voicegroup);
    auto samples = std::vector<double>{};
    samples.reserve(options.iterations);
    for (auto iteration = size_t{0}; iteration < options.iterations; ++iteration) {
        const auto start = Clock::now();
        auto project = openProject(root);
        auto refresh = ProjectResult{};
        if (project)
            voicegroup_project_refresh(project.get(), &refresh.value);
        const auto refreshed = project && refresh.value.succeeded;
        auto load = LoadResult(refreshed ? voicegroup_project_load(project.get(), &request)
                                         : VoicegroupLoadResult{});
        const auto elapsed = millisecondsSince(start);
        if (!project) {
            fprintf(stderr, "loadbench: cold iteration %zu could not open project\n", iteration);
            return 1;
        }
        printDiagnostics("cold refresh", refresh.value.diagnostics, refresh.value.diagnostic_count);
        if (!refreshed) {
            fprintf(stderr, "loadbench: cold refresh failed in iteration %zu\n", iteration);
            return 1;
        }
        if (!finishLoad(load, "cold saved-bank load")) {
            fprintf(stderr, "loadbench: cold iteration %zu failed\n", iteration);
            return 1;
        }
        samples.push_back(elapsed);
    }
    report("cold-saved-bank", STATE_FRESH, samples);
    return 0;
}

int runWarmSavedBank(const Options &options, const std::string &root)
{
    auto project = openProject(root);
    if (!project) {
        fprintf(stderr, "loadbench: could not open project for warm saved-bank mode\n");
        return 1;
    }
    if (!refreshProject(project.get(), "warm refresh"))
        return 1;
    const auto request = savedRequest(options.voicegroup);
    {
        auto warmup = LoadResult(voicegroup_project_load(project.get(), &request));
        if (!finishLoad(warmup, "warm saved-bank warmup"))
            return 1;
    }
    auto samples = std::vector<double>{};
    samples.reserve(options.iterations);
    for (auto iteration = size_t{0}; iteration < options.iterations; ++iteration) {
        const auto start = Clock::now();
        auto load = LoadResult(voicegroup_project_load(project.get(), &request));
        const auto elapsed = millisecondsSince(start);
        if (!finishLoad(load, "warm saved-bank load")) {
            fprintf(stderr, "loadbench: warm iteration %zu failed\n", iteration);
            return 1;
        }
        samples.push_back(elapsed);
    }
    report("warm-saved-bank", STATE_FRESH, samples);
    return 0;
}

bool resolvePreviewSource(const Options &options, fs::path &absolute, std::string &relative)
{
    std::error_code error;
    const auto root = fs::weakly_canonical(options.projectRoot, error);
    if (error) {
        fprintf(stderr, "loadbench: could not resolve project root: %s\n", error.message().c_str());
        return false;
    }
    auto requested = options.previewSource;
    if (requested.is_relative())
        requested = root / requested;
    absolute = fs::weakly_canonical(requested, error);
    if (error || !fs::is_regular_file(absolute, error) || error) {
        fprintf(stderr, "loadbench: preview source is not a readable file: %s\n",
                requested.string().c_str());
        return false;
    }
    auto relativePath = fs::relative(absolute, root, error);
    if (error || relativePath.empty() || relativePath.is_absolute() ||
        *relativePath.begin() == "..") {
        fprintf(stderr, "loadbench: preview source must be inside the project root: %s\n",
                absolute.string().c_str());
        return false;
    }
    relative = relativePath.generic_string();
    return true;
}

bool readFile(const fs::path &path, std::string &bytes)
{
    auto input = std::ifstream(path, std::ios::binary | std::ios::ate);
    if (!input)
        return false;
    const auto end = input.tellg();
    if (end < 0)
        return false;
    bytes.resize(static_cast<size_t>(end));
    input.seekg(0);
    if (!bytes.empty())
        input.read(bytes.data(), static_cast<std::streamsize>(bytes.size()));
    return input.good() ||
           (input.eof() && input.gcount() == static_cast<std::streamsize>(bytes.size()));
}

int runPreview(const Options &options, const std::string &root)
{
    auto sourcePath = fs::path{};
    auto relativePath = std::string{};
    if (!resolvePreviewSource(options, sourcePath, relativePath))
        return 1;
    auto sourceBytes = std::string{};
    if (!readFile(sourcePath, sourceBytes)) {
        fprintf(stderr, "loadbench: could not read full preview source: %s\n",
                sourcePath.string().c_str());
        return 1;
    }
    auto project = openProject(root);
    if (!project) {
        fprintf(stderr, "loadbench: could not open project for preview mode\n");
        return 1;
    }
    if (!refreshProject(project.get(), "preview refresh"))
        return 1;
    auto request = VoicegroupLoadRequest{};
    request.mode = VG_LOAD_SOURCE;
    request.bank_name = options.voicegroup.data();
    request.bank_name_len = options.voicegroup.size();
    request.relative_path = relativePath.data();
    request.relative_path_len = relativePath.size();
    request.source_bytes = sourceBytes.data();
    request.source_len = sourceBytes.size();
    auto samples = std::vector<double>{};
    samples.reserve(options.iterations);
    for (auto iteration = size_t{0}; iteration < options.iterations; ++iteration) {
        const auto start = Clock::now();
        auto load = LoadResult(voicegroup_project_load(project.get(), &request));
        const auto elapsed = millisecondsSince(start);
        if (!finishLoad(load, "source preview load")) {
            fprintf(stderr, "loadbench: preview iteration %zu failed\n", iteration);
            return 1;
        }
        samples.push_back(elapsed);
    }
    report("preview", STATE_FRESH, samples);
    return 0;
}

int runPickerRow(const Options &options, const std::string &root)
{
    auto samples = std::vector<double>{};
    samples.reserve(options.iterations);
    for (auto iteration = size_t{0}; iteration < options.iterations; ++iteration) {
        auto project = openProject(root);
        if (!project) {
            fprintf(stderr, "loadbench: picker iteration %zu could not open project\n", iteration);
            return 1;
        }
        if (!refreshProject(project.get(), "picker refresh"))
            return 1;
        const auto start = Clock::now();
        auto asset = AssetResult(voicegroup_project_load_asset(
            project.get(), VG_ASSET_DIRECT_SOUND, options.symbol.data(), options.symbol.size()));
        const auto elapsed = millisecondsSince(start);
        printDiagnostics("picker-row asset load", asset.value.diagnostics,
                         asset.value.diagnostic_count);
        if (asset.value.diagnostic_count != 0 ||
            (!asset.value.payload && !asset.value.synth_desc)) {
            fprintf(stderr, "loadbench: picker iteration %zu failed for symbol '%s'\n", iteration,
                    options.symbol.c_str());
            return 1;
        }
        samples.push_back(elapsed);
    }
    report("picker-row", STATE_FRESH, samples);
    return 0;
}

} // namespace

int main(int argc, char *argv[])
{
    auto options = Options{};
    if (!parseArguments(argc, argv, options))
        return 1;
    const auto runtimeAbi = voicegroup_core_abi_version();
    if (runtimeAbi != VOICEGROUP_CORE_ABI_VERSION) {
        fprintf(stderr, "loadbench: voicegroup-core ABI mismatch: header=%u runtime=%u\n",
                static_cast<unsigned>(VOICEGROUP_CORE_ABI_VERSION),
                static_cast<unsigned>(runtimeAbi));
        return 1;
    }
    std::error_code error;
    const auto normalizedRoot = fs::weakly_canonical(options.projectRoot, error);
    if (error) {
        fprintf(stderr, "loadbench: could not resolve project root: %s\n", error.message().c_str());
        return 1;
    }
    options.projectRoot = normalizedRoot;
    const auto root = normalizedRoot.string();
    switch (options.mode) {
    case Mode::ColdSavedBank:
        return runColdSavedBank(options, root);
    case Mode::WarmSavedBank:
        return runWarmSavedBank(options, root);
    case Mode::Preview:
        return runPreview(options, root);
    case Mode::PickerRow:
        return runPickerRow(options, root);
    }
    return 1;
}
