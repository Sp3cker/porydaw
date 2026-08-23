#include "voicegroupproject.h"

#include <QByteArray>
#include <QDir>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QSet>

#include <algorithm>
#include <utility>

namespace porydaw {
namespace {
class ProjectResultOwner
{
  public:
    ProjectResultOwner() = default;
    ~ProjectResultOwner() { voicegroup_project_result_free(&value); }

    VoicegroupProjectResult value{};
};

class LoadResultOwner
{
  public:
    explicit LoadResultOwner(VoicegroupLoadResult result) : value(result) {}
    LoadResultOwner(LoadResultOwner &&other) noexcept
        : value(std::exchange(other.value, VoicegroupLoadResult{}))
    {}
    ~LoadResultOwner() { voicegroup_load_result_free(&value); }

    LoadResultOwner(const LoadResultOwner &) = delete;
    LoadResultOwner &operator=(const LoadResultOwner &) = delete;

    VoicegroupLoadResult value{};
};

class AssetResultOwner
{
  public:
    explicit AssetResultOwner(VoicegroupAssetResult result) : value(result) {}
    AssetResultOwner(AssetResultOwner &&other) noexcept
        : value(std::exchange(other.value, VoicegroupAssetResult{}))
    {}
    ~AssetResultOwner() { voicegroup_asset_result_free(&value); }

    AssetResultOwner(const AssetResultOwner &) = delete;
    AssetResultOwner &operator=(const AssetResultOwner &) = delete;

    VoicegroupAssetResult value{};
};

QString copyString(const char *text)
{
    return text ? QString::fromUtf8(text) : QString{};
}

QStringList copyStrings(const char *const *values, size_t count)
{
    auto result = QStringList{};
    result.reserve(qsizetype(count));
    for (auto i = size_t{0}; i < count; ++i)
        result.push_back(copyString(values[i]));
    return result;
}

QVector<VoicegroupProject::Diagnostic> copyDiagnostics(const VoicegroupDiagnostic *values,
                                                       size_t count)
{
    auto result = QVector<VoicegroupProject::Diagnostic>{};
    result.reserve(qsizetype(count));
    for (auto i = size_t{0}; i < count; ++i) {
        const auto &value = values[i];
        auto diagnostic = VoicegroupProject::Diagnostic{
            .code = copyString(value.code),
            .message = copyString(value.message),
            .scope = static_cast<VoicegroupProject::DiagnosticScope>(value.scope),
            .sourcePath = copyString(value.source_path),
            .assetPath = copyString(value.asset_path),
        };
        if (value.has_range) {
            diagnostic.range = VoicegroupProject::SourceRange{
                .startLine = value.start_line,
                .startColumn = value.start_column,
                .endLine = value.end_line,
                .endColumn = value.end_column,
            };
        }
        if (value.has_slot)
            diagnostic.slot = value.slot;
        result.push_back(std::move(diagnostic));
    }
    return result;
}

VoicegroupProject::Snapshot copySnapshot(const VoicegroupProjectResult &result)
{
    auto snapshot = VoicegroupProject::Snapshot{
        .succeeded = result.succeeded,
        .diagnostics = copyDiagnostics(result.diagnostics, result.diagnostic_count),
        .synthMacroWords = copyStrings(result.synth_macro_words, result.synth_macro_word_count),
        .contentPaths = copyStrings(result.content_paths, result.content_path_count),
        .dependencyPaths = copyStrings(result.dependency_paths, result.dependency_path_count),
        .watchPaths = copyStrings(result.watch_paths, result.watch_path_count),
    };
    snapshot.familyAdsr.reserve(qsizetype(result.family_adsr_count));
    for (auto i = size_t{0}; i < result.family_adsr_count; ++i) {
        const auto &value = result.family_adsr[i];
        snapshot.familyAdsr.push_back({
            .family = copyString(value.family),
            .adsr = {value.adsr[0], value.adsr[1], value.adsr[2], value.adsr[3]},
        });
    }
    snapshot.catalog.reserve(qsizetype(result.catalog_count));
    for (auto i = size_t{0}; i < result.catalog_count; ++i) {
        const auto &value = result.catalog[i];
        auto entry = VoicegroupProject::CatalogEntry{
            .kind = static_cast<VoicegroupProject::CatalogKind>(value.kind),
            .symbol = copyString(value.symbol),
            .displayName = copyString(value.display_name),
            .sourcePath = copyString(value.source_path),
            .assetPath = copyString(value.asset_path),
            .dependencyPaths = copyStrings(value.dependency_paths, value.dependency_path_count),
            .subgroup = copyString(value.subgroup),
            .table = copyString(value.table),
            .drumkit = copyString(value.drumkit),
        };
        if (value.has_adsr) {
            entry.adsr =
                std::array<uint8_t, 4>{value.adsr[0], value.adsr[1], value.adsr[2], value.adsr[3]};
        }
        if (value.has_synth) {
            auto descriptor = std::array<uint8_t, 6>{};
            std::copy_n(value.synth_desc, descriptor.size(), descriptor.begin());
            entry.synthDescriptor = descriptor;
        }
        snapshot.catalog.push_back(std::move(entry));
    }
    return snapshot;
}

VoicegroupAssetKind toCAssetKind(VoicegroupProject::AssetKind kind)
{
    switch (kind) {
    case VoicegroupProject::AssetKind::DirectSound:
        return VG_ASSET_DIRECT_SOUND;
    case VoicegroupProject::AssetKind::ProgrammableWave:
        return VG_ASSET_PROG_WAVE;
    case VoicegroupProject::AssetKind::Keysplit:
        return VG_ASSET_KEYSPLIT;
    }
    return VG_ASSET_DIRECT_SOUND;
}

} // namespace

struct VoicegroupProject::LoadResult::Impl {
    explicit Impl(LoadResultOwner value)
        : result(std::move(value))
        , copiedDiagnostics(
              copyDiagnostics(result.value.diagnostics, result.value.diagnostic_count))
    {}

    LoadResultOwner result;
    QVector<Diagnostic> copiedDiagnostics;
};

VoicegroupProject::LoadResult::LoadResult(VoicegroupLoadResult result)
{
    auto owner = LoadResultOwner(result);
    m_impl = std::make_unique<Impl>(std::move(owner));
}

VoicegroupProject::LoadResult::LoadResult(LoadResult &&other) noexcept = default;
VoicegroupProject::LoadResult &
VoicegroupProject::LoadResult::operator=(LoadResult &&other) noexcept = default;
VoicegroupProject::LoadResult::~LoadResult() = default;

LoadedVoiceGroup *VoicegroupProject::LoadResult::take()
{
    return m_impl ? voicegroup_load_result_take(&m_impl->result.value) : nullptr;
}

bool VoicegroupProject::LoadResult::succeeded() const
{
    return m_impl && m_impl->result.value.succeeded;
}

const QVector<VoicegroupProject::Diagnostic> &VoicegroupProject::LoadResult::diagnostics() const
{
    static const auto empty = QVector<Diagnostic>{};
    return m_impl ? m_impl->copiedDiagnostics : empty;
}

struct VoicegroupProject::AssetResult::Impl {
    explicit Impl(AssetResultOwner value)
        : result(std::move(value))
        , copiedSymbol(copyString(result.value.symbol))
        , copiedDiagnostics(
              copyDiagnostics(result.value.diagnostics, result.value.diagnostic_count))
    {}

    AssetResultOwner result;
    QString copiedSymbol;
    QVector<Diagnostic> copiedDiagnostics;
};

VoicegroupProject::AssetResult::AssetResult(VoicegroupAssetResult result)
{
    auto owner = AssetResultOwner(result);
    m_impl = std::make_unique<Impl>(std::move(owner));
}

VoicegroupProject::AssetResult::AssetResult(AssetResult &&other) noexcept = default;
VoicegroupProject::AssetResult &
VoicegroupProject::AssetResult::operator=(AssetResult &&other) noexcept = default;
VoicegroupProject::AssetResult::~AssetResult() = default;

VoicegroupProject::AssetKind VoicegroupProject::AssetResult::kind() const
{
    return m_impl ? static_cast<AssetKind>(m_impl->result.value.kind) : AssetKind::DirectSound;
}

const QString &VoicegroupProject::AssetResult::symbol() const
{
    static const auto empty = QString{};
    return m_impl ? m_impl->copiedSymbol : empty;
}

std::span<const std::byte> VoicegroupProject::AssetResult::payload() const
{
    if (!m_impl || !m_impl->result.value.payload)
        return {};
    return {static_cast<const std::byte *>(m_impl->result.value.payload),
            m_impl->result.value.payload_len};
}

std::span<const uint8_t> VoicegroupProject::AssetResult::synthDescriptor() const
{
    if (!m_impl || !m_impl->result.value.synth_desc)
        return {};
    return {m_impl->result.value.synth_desc, size_t{6}};
}

std::span<const ToneData> VoicegroupProject::AssetResult::keysplitSubgroup() const
{
    if (!m_impl || !m_impl->result.value.keysplit.subgroup)
        return {};
    return {m_impl->result.value.keysplit.subgroup, m_impl->result.value.keysplit.subgroup_count};
}

std::span<const uint8_t> VoicegroupProject::AssetResult::keysplitTable() const
{
    if (!m_impl || !m_impl->result.value.keysplit.table)
        return {};
    return {m_impl->result.value.keysplit.table, m_impl->result.value.keysplit.table_count};
}

bool VoicegroupProject::AssetResult::hasLoop() const
{
    return m_impl && m_impl->result.value.has_loop;
}

size_t VoicegroupProject::AssetResult::loopStart() const
{
    return m_impl ? m_impl->result.value.loop_start : 0;
}

size_t VoicegroupProject::AssetResult::loopLength() const
{
    return m_impl ? m_impl->result.value.loop_length : 0;
}

uint32_t VoicegroupProject::AssetResult::sampleRate() const
{
    return m_impl ? m_impl->result.value.sample_rate : 0;
}

size_t VoicegroupProject::AssetResult::frameCount() const
{
    return m_impl ? m_impl->result.value.frame_count : 0;
}

const QVector<VoicegroupProject::Diagnostic> &VoicegroupProject::AssetResult::diagnostics() const
{
    static const auto empty = QVector<Diagnostic>{};
    return m_impl ? m_impl->copiedDiagnostics : empty;
}

struct VoicegroupProject::Impl {
    Impl()
    {
        QObject::connect(&watcher, &QFileSystemWatcher::fileChanged, &watcher,
                         [this](const QString &) { markStale(); });
        QObject::connect(&watcher, &QFileSystemWatcher::directoryChanged, &watcher,
                         [this](const QString &) { markStale(); });
    }

    ~Impl() { close(); }

    void close()
    {
        const auto paths = watcher.files() + watcher.directories();
        if (!paths.isEmpty())
            watcher.removePaths(paths);
        voicegroup_project_free(project);
        project = nullptr;
        root.clear();
    }

    void markStale()
    {
        if (!project)
            return;
        voicegroup_project_mark_stale(project);
        if (staleCallback)
            staleCallback();
    }

    void replaceWatches(const QStringList &relativePaths)
    {
        const auto previous = watcher.files() + watcher.directories();
        if (!previous.isEmpty())
            watcher.removePaths(previous);
        auto files = QSet<QString>{};
        auto directories = QSet<QString>{};
        for (const auto &path : relativePaths) {
            const auto absolutePath = QFileInfo(path).isAbsolute()
                                          ? QDir::cleanPath(path)
                                          : QDir::cleanPath(QDir(root).absoluteFilePath(path));
            files.insert(absolutePath);
            directories.insert(QFileInfo(absolutePath).absolutePath());
        }
        if (!files.isEmpty())
            watcher.addPaths(files.values());
        if (!directories.isEmpty())
            watcher.addPaths(directories.values());
    }

    ::VoicegroupProject *project = nullptr;
    QFileSystemWatcher watcher;
    QString root;
    StaleCallback staleCallback;
};

VoicegroupProject::VoicegroupProject() : m_impl(std::make_unique<Impl>()) {}
VoicegroupProject::VoicegroupProject(VoicegroupProject &&other) noexcept = default;
VoicegroupProject &VoicegroupProject::operator=(VoicegroupProject &&other) noexcept = default;
VoicegroupProject::~VoicegroupProject() = default;

VoicegroupProject::Snapshot VoicegroupProject::open(const QString &root)
{
    if (!m_impl)
        m_impl = std::make_unique<Impl>();
    m_impl->close();
    m_impl->root = QDir(root).absolutePath();
    const auto encodedRoot = m_impl->root.toUtf8();
    m_impl->project = voicegroup_project_open(encodedRoot.constData(), size_t(encodedRoot.size()));
    return refresh();
}

void VoicegroupProject::close()
{
    if (m_impl)
        m_impl->close();
}

void VoicegroupProject::markStale()
{
    if (m_impl)
        m_impl->markStale();
}

VoicegroupProject::Snapshot VoicegroupProject::refresh()
{
    auto result = ProjectResultOwner{};
    voicegroup_project_refresh(m_impl ? m_impl->project : nullptr, &result.value);
    auto snapshot = copySnapshot(result.value);
    if (m_impl && snapshot.succeeded)
        m_impl->replaceWatches(snapshot.watchPaths);
    return snapshot;
}

VoicegroupProject::LoadResult VoicegroupProject::loadSaved(const QString &bankName)
{
    const auto encodedName = bankName.toUtf8();
    const auto request = VoicegroupLoadRequest{
        .mode = VG_LOAD_SAVED,
        .bank_name = encodedName.constData(),
        .bank_name_len = size_t(encodedName.size()),
    };
    return LoadResult(voicegroup_project_load(m_impl ? m_impl->project : nullptr, &request));
}

VoicegroupProject::LoadResult VoicegroupProject::loadSource(const QString &bankName,
                                                            const QString &relativePath,
                                                            QByteArrayView source,
                                                            std::span<const SynthOverlay> overlays)
{
    const auto encodedName = bankName.toUtf8();
    const auto encodedPath = relativePath.toUtf8();
    auto overlay =
        std::unique_ptr<VoicegroupSynthOverlay, decltype(&voicegroup_synth_overlay_free)>(
            voicegroup_synth_overlay_create(), &voicegroup_synth_overlay_free);
    auto overlayNames = QVector<QByteArray>{};
    auto overlayDescriptors = QVector<std::array<uint8_t, 6>>{};
    overlayNames.reserve(qsizetype(overlays.size()));
    overlayDescriptors.reserve(qsizetype(overlays.size()));
    for (const auto &definition : overlays) {
        overlayNames.push_back(definition.name.toUtf8());
        overlayDescriptors.push_back(definition.descriptor);
        voicegroup_synth_overlay_add(overlay.get(), overlayNames.back().constData(),
                                     size_t(overlayNames.back().size()),
                                     overlayDescriptors.back().data());
    }
    const auto request = VoicegroupLoadRequest{
        .mode = VG_LOAD_SOURCE,
        .bank_name = encodedName.constData(),
        .bank_name_len = size_t(encodedName.size()),
        .relative_path = encodedPath.constData(),
        .relative_path_len = size_t(encodedPath.size()),
        .source_bytes = source.data(),
        .source_len = size_t(source.size()),
        .overlay = overlay.get(),
    };
    return LoadResult(voicegroup_project_load(m_impl ? m_impl->project : nullptr, &request));
}

VoicegroupProject::AssetResult VoicegroupProject::loadAsset(AssetKind kind, const QString &symbol)
{
    const auto encodedSymbol = symbol.toUtf8();
    return AssetResult(voicegroup_project_load_asset(m_impl ? m_impl->project : nullptr,
                                                     toCAssetKind(kind), encodedSymbol.constData(),
                                                     size_t(encodedSymbol.size())));
}

void VoicegroupProject::setStaleCallback(StaleCallback callback)
{
    if (!m_impl)
        m_impl = std::make_unique<Impl>();
    m_impl->staleCallback = std::move(callback);
}

bool VoicegroupProject::isOpen() const
{
    return m_impl && m_impl->project;
}

void VoicegroupProject::freeBank(LoadedVoiceGroup *bank) noexcept
{
    voicegroup_free(bank);
}

} // namespace porydaw
