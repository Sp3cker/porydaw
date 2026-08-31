#pragma once
#include "core/m4asemantics.h"


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

// Typed, per-session bridge for the shared Quick popup. It owns the fixed
// program list and the held voice preview; SongView owns the pending callback
// and document/revision lifetime guard.
class VoicePicker final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(VoicePicker)

    Q_PROPERTY(QAbstractItemModel *voicePickerModel READ voicePickerModel CONSTANT FINAL)
    Q_PROPERTY(QString voicePickerTitle READ voicePickerTitle CONSTANT FINAL)
    Q_PROPERTY(QVariantMap voicePickerAppearance READ voicePickerAppearance CONSTANT FINAL)
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filtersChanged FINAL)
    Q_PROPERTY(int selectedFamily READ selectedFamily WRITE setSelectedFamily NOTIFY filtersChanged
                   FINAL)
    Q_PROPERTY(bool usedOnly READ usedOnly WRITE setUsedOnly NOTIFY filtersChanged FINAL)
    Q_PROPERTY(bool namedOnly READ namedOnly WRITE setNamedOnly NOTIFY filtersChanged FINAL)
    Q_PROPERTY(QVariantList familyFacets READ familyFacets CONSTANT FINAL)
    Q_PROPERTY(int matchingCount READ matchingCount NOTIFY filtersChanged FINAL)
    Q_PROPERTY(int currentRow READ currentRow NOTIFY currentRowChanged FINAL)
    Q_PROPERTY(bool hasMatch READ hasMatch NOTIFY filtersChanged FINAL)

  public:
    VoicePicker(SongView &owner, QString title, int initialVoice, QObject *parent = nullptr);
    ~VoicePicker() override;
    QAbstractItemModel *voicePickerModel() { return &m_model; }
    QString voicePickerTitle() const { return m_title; }
    QVariantMap voicePickerAppearance() const;
    QString filter() const { return m_filter; }
    int selectedFamily() const noexcept { return m_selectedFamily; }
    bool usedOnly() const noexcept { return m_usedOnly; }
    bool namedOnly() const noexcept { return m_namedOnly; }
    QVariantList familyFacets() const;
    int matchingCount() const noexcept { return m_model.matchingCount(); }
    int currentRow() const noexcept;
    bool hasMatch() const noexcept;

    Q_INVOKABLE void setFilter(const QString &filter);
    Q_INVOKABLE void setSelectedFamily(int family);
    Q_INVOKABLE void setUsedOnly(bool enabled);
    Q_INVOKABLE void setNamedOnly(bool enabled);
    Q_INVOKABLE void clearFilters();
    Q_INVOKABLE void selectRow(int row);
    Q_INVOKABLE void pressAndHold(int program);
    Q_INVOKABLE void releaseHeld();
    Q_INVOKABLE void accept();
    Q_INVOKABLE void cancel();

  signals:
    void filtersChanged();
    void currentRowChanged();
    void selectionChanged(int program);
    void accepted(int program);
    void rejected();

  private:
    void applyFilters();
    void setCurrentProgram(int program);
    SongView &m_owner;
    VoicePickerModel m_model;
    QString m_title;
    QString m_filter;
    QVariantMap m_appearance;
    int m_selectedFamily = -1;
    bool m_usedOnly = false;
    bool m_namedOnly = false;
    int m_currentProgram = -1;
    int m_soundingProgram = -1;
};

} // namespace songview
