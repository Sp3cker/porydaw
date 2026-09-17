#pragma once
#include "core/m4asemantics.h"
#include "voicepickermodel.h"


#include <QAbstractListModel>
#include <QByteArray>
#include <QHash>
#include <QObject>
#include <QString>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

#include <array>
#include <cstdint>
#include <optional>
#include <vector>

class QModelIndex;
class SongView;

namespace songview {

class VoicePickerModel final : public QAbstractListModel
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(VoicePickerModel)

  public:
    static constexpr std::size_t cVoiceCount = 128;

    enum Role : int {
        Program = Qt::UserRole + 1,
        Label,
    };

    explicit VoicePickerModel(SongView &owner, QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    void setFilters(const QString &filter, std::optional<VoiceFamily> family, bool usedOnly,
                    bool namedOnly);
    int firstProgram() const noexcept;
    int programAt(int row) const noexcept;
    int rowForProgram(int program) const noexcept;
    int matchingCount() const noexcept { return int(m_visiblePrograms.size()); }
    int familyCount(VoiceFamily family) const;
    int namedCount() const noexcept;
    int usedCount() const noexcept;

  private:
    struct Entry {
        int program = 0;
        QString label;
        QString displayName;
        VoiceFamily family = VoiceFamily::Sample;
        bool used = false;
    };
    std::array<Entry, cVoiceCount> m_entries;
    std::vector<int> m_visiblePrograms;
};

class ProjectVoicePickerModel final : public QAbstractListModel
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(ProjectVoicePickerModel)

  public:
    enum Role : int {
        Program = Qt::UserRole + 1,
        Label,
    };

    explicit ProjectVoicePickerModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    void setProject(VoicePickerProjectData project);
    void setFilters(const QString &query, std::optional<VoiceFamily> family,
                    ProjectVoiceMembership membership);
    int sourceRowAt(int row) const noexcept;
    int matchingCount() const noexcept { return int(m_visibleRows.size()); }
    int familyCount(VoiceFamily family) const;
    const VoicePickerProjectData &project() const noexcept { return m_project; }
    const VoicePickerProjectVoice *voiceAt(int row) const noexcept;

  private:
    void rebuild();
    VoicePickerProjectData m_project;
    std::vector<VoicePickerProjectVoice> m_voices;
    std::vector<int> m_visibleRows;
    QString m_query;
    std::optional<VoiceFamily> m_family;
    ProjectVoiceMembership m_membership = ProjectVoiceMembership::All;
};

// Typed, per-session bridge for the shared Quick popup. It owns the fixed
// program list and the held voice preview; SongView owns the pending callback
// and document/revision lifetime guard.
class VoicePicker final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(VoicePicker)

    Q_PROPERTY(QAbstractItemModel *voicePickerModel READ voicePickerModel NOTIFY modelChanged FINAL)
    Q_PROPERTY(QString voicePickerTitle READ voicePickerTitle CONSTANT FINAL)
    Q_PROPERTY(QVariantMap voicePickerAppearance READ voicePickerAppearance CONSTANT FINAL)
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filtersChanged FINAL)
    Q_PROPERTY(int selectedFamily READ selectedFamily WRITE setSelectedFamily NOTIFY filtersChanged
                   FINAL)
    Q_PROPERTY(bool usedOnly READ usedOnly WRITE setUsedOnly NOTIFY filtersChanged FINAL)
    Q_PROPERTY(bool namedOnly READ namedOnly WRITE setNamedOnly NOTIFY filtersChanged FINAL)
    Q_PROPERTY(QVariantList familyFacets READ familyFacets NOTIFY filtersChanged FINAL)
    Q_PROPERTY(int matchingCount READ matchingCount NOTIFY filtersChanged FINAL)
    Q_PROPERTY(int currentRow READ currentRow NOTIFY currentRowChanged FINAL)
    Q_PROPERTY(bool hasMatch READ hasMatch NOTIFY filtersChanged FINAL)
    Q_PROPERTY(bool projectAvailable READ projectAvailable CONSTANT FINAL)
    Q_PROPERTY(bool projectMode READ projectMode WRITE setProjectMode NOTIFY projectModeChanged FINAL)
    Q_PROPERTY(int projectMembership READ projectMembership WRITE setProjectMembership
                   NOTIFY filtersChanged FINAL)
    Q_PROPERTY(QVariantList tradeTargets READ tradeTargets CONSTANT FINAL)
    Q_PROPERTY(int tradeTarget READ tradeTarget WRITE setTradeTarget NOTIFY tradeTargetChanged FINAL)
    Q_PROPERTY(bool tradePending READ tradePending NOTIFY tradePendingChanged FINAL)

  public:
    VoicePicker(SongView &owner, QString title, int initialVoice, VoicePickerServices services,
                QObject *parent = nullptr);
    ~VoicePicker() override;
    QAbstractItemModel *voicePickerModel();
    QString voicePickerTitle() const { return m_title; }
    QVariantMap voicePickerAppearance() const;
    QString filter() const { return m_filter; }
    int selectedFamily() const noexcept { return m_selectedFamily; }
    bool usedOnly() const noexcept { return m_usedOnly; }
    bool namedOnly() const noexcept { return m_namedOnly; }
    QVariantList familyFacets() const;
    int matchingCount() const noexcept;
    int currentRow() const noexcept;
    bool hasMatch() const noexcept;
    bool projectAvailable() const noexcept { return !m_projectModel.project().slotViews.isEmpty(); }
    bool projectMode() const noexcept { return m_projectMode; }
    int projectMembership() const noexcept { return int(m_projectMembership); }
    QVariantList tradeTargets() const;
    int tradeTarget() const noexcept { return m_tradeTarget; }
    bool tradePending() const noexcept { return m_tradePending; }

    Q_INVOKABLE void setFilter(const QString &filter);
    Q_INVOKABLE void setSelectedFamily(int family);
    Q_INVOKABLE void setUsedOnly(bool enabled);
    Q_INVOKABLE void setNamedOnly(bool enabled);
    Q_INVOKABLE void clearFilters();
    Q_INVOKABLE void setProjectMode(bool enabled);
    Q_INVOKABLE void setProjectMembership(int membership);
    Q_INVOKABLE void setTradeTarget(int slot);
    Q_INVOKABLE void tradeSelectedProjectVoice();
    Q_INVOKABLE void selectRow(int row);
    Q_INVOKABLE void pressAndHold(int program);
    Q_INVOKABLE void releaseHeld();
    Q_INVOKABLE void accept();
    Q_INVOKABLE void cancel();

  signals:
    void modelChanged();
    void filtersChanged();
    void currentRowChanged();
    void projectModeChanged();
    void tradeTargetChanged();
    void tradePendingChanged();
    void selectionChanged(int program);
    void accepted(int program);
    void rejected();

  private:
    void applyFilters();
    void setCurrentProgram(int program);
    void setCurrentProjectRow(int row);
    SongView &m_owner;
    VoicePickerModel m_model;
    ProjectVoicePickerModel m_projectModel;
    VoicePickerServices m_services;
    QString m_title;
    QString m_filter;
    QVariantMap m_appearance;
    int m_selectedFamily = -1;
    bool m_usedOnly = false;
    bool m_namedOnly = false;
    int m_currentProgram = -1;
    int m_currentProjectRow = -1;
    bool m_projectMode = false;
    ProjectVoiceMembership m_projectMembership = ProjectVoiceMembership::All;
    int m_tradeTarget = -1;
    bool m_tradePending = false;
    int m_soundingProgram = -1;
};

} // namespace songview
