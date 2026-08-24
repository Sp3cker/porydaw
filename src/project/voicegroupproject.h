#pragma once

extern "C" {
#include "voicegroup/voicegroup_project.h"
}

#include <QByteArrayView>
#include <QString>
#include <QStringList>
#include <QVector>

#include <array>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <span>

namespace porydaw {

class VoicegroupProject
{
  public:
    enum class DiagnosticScope : uint32_t {
        Structural = 0,
        Slot = 1,
        Materialization = 2,
    };

    enum class CatalogKind : uint32_t {
        VoiceGroup = 0,
        DirectSound = 1,
        ProgrammableWave = 2,
        Keysplit = 3,
        Drumkit = 4,
        Synth = 5,
    };

    enum class AssetKind {
        DirectSound,
        ProgrammableWave,
        Keysplit,
    };

    struct SourceRange {
        size_t startLine = 0;
        size_t startColumn = 0;
        size_t endLine = 0;
        size_t endColumn = 0;
    };

    struct Diagnostic {
        QString code;
        QString message;
        DiagnosticScope scope = DiagnosticScope::Structural;
        QString sourcePath;
        QString assetPath;
        std::optional<SourceRange> range;
        std::optional<size_t> slot;
    };

    struct CatalogEntry {
        CatalogKind kind = CatalogKind::VoiceGroup;
        QString symbol;
        QString displayName;
        QString sourcePath;
        QString assetPath;
        QStringList dependencyPaths;
        QString subgroup;
        QString table;
        QString drumkit;
        std::optional<std::array<uint8_t, 4>> adsr;
        std::optional<std::array<uint8_t, 6>> synthDescriptor;
    };

    struct FamilyAdsr {
        QString family;
        std::array<uint8_t, 4> adsr{};
    };

    struct Snapshot {
        // Whether the project index is available for loading. Catalog diagnostics do not make it
        // false.
        bool succeeded = false;
        QVector<Diagnostic> diagnostics;
        QVector<CatalogEntry> catalog;
        QVector<FamilyAdsr> familyAdsr;
        QStringList synthMacroWords;
        QStringList contentPaths;
        QStringList dependencyPaths;
        QStringList watchPaths;
    };

    struct SynthOverlay {
        QString name;
        std::array<uint8_t, 6> descriptor{};
    };

    class LoadResult
    {
      public:
        LoadResult(LoadResult &&other) noexcept;
        LoadResult &operator=(LoadResult &&other) noexcept;
        ~LoadResult();

        LoadResult(const LoadResult &) = delete;
        LoadResult &operator=(const LoadResult &) = delete;

        LoadedVoiceGroup *take();
        bool succeeded() const;
        const QVector<Diagnostic> &diagnostics() const;

      private:
        struct Impl;
        explicit LoadResult(VoicegroupLoadResult result);
        std::unique_ptr<Impl> m_impl;
        friend class VoicegroupProject;
    };

    class AssetResult
    {
      public:
        AssetResult(AssetResult &&other) noexcept;
        AssetResult &operator=(AssetResult &&other) noexcept;
        ~AssetResult();

        AssetResult(const AssetResult &) = delete;
        AssetResult &operator=(const AssetResult &) = delete;

        AssetKind kind() const;
        const QString &symbol() const;
        std::span<const std::byte> payload() const;
        std::span<const uint8_t> synthDescriptor() const;
        std::span<const ToneData> keysplitSubgroup() const;
        std::span<const uint8_t> keysplitTable() const;
        bool hasLoop() const;
        size_t loopStart() const;
        size_t loopLength() const;
        uint32_t sampleRate() const;
        size_t frameCount() const;
        const QVector<Diagnostic> &diagnostics() const;

      private:
        struct Impl;
        explicit AssetResult(VoicegroupAssetResult result);
        std::unique_ptr<Impl> m_impl;
        friend class VoicegroupProject;
    };

    using StaleCallback = std::function<void()>;

    VoicegroupProject();
    VoicegroupProject(VoicegroupProject &&other) noexcept;
    VoicegroupProject &operator=(VoicegroupProject &&other) noexcept;
    ~VoicegroupProject();

    VoicegroupProject(const VoicegroupProject &) = delete;
    VoicegroupProject &operator=(const VoicegroupProject &) = delete;

    Snapshot open(const QString &root);
    void close();
    void markStale();
    // Force a project-index rebuild, including retrying a failed refresh.
    Snapshot refresh();
    // Return the current snapshot, rebuilding only after open or markStale().
    const Snapshot &snapshot();
    LoadResult loadSaved(const QString &bankName);
    LoadResult loadSource(const QString &bankName, const QString &relativePath,
                          QByteArrayView source, std::span<const SynthOverlay> overlays = {});
    AssetResult loadAsset(AssetKind kind, const QString &symbol);
    static void freeBank(LoadedVoiceGroup *bank) noexcept;
    void setStaleCallback(StaleCallback callback);
    bool isOpen() const;

  private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace porydaw
