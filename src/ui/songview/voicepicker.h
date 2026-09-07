#pragma once

#include <QAbstractListModel>
#include <QByteArray>
#include <QHash>
#include <QObject>
#include <QString>
#include <QVariant>
#include <QVariantMap>

#include <array>
#include <cstdint>
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

    void setFilter(const QString &filter);
    int firstProgram() const noexcept;
    int programAt(int row) const noexcept;
    int rowForProgram(int program) const noexcept;

  private:
    struct Entry {
        int program = 0;
        QString label;
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
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged FINAL)
    Q_PROPERTY(int currentRow READ currentRow NOTIFY currentRowChanged FINAL)
    Q_PROPERTY(bool hasMatch READ hasMatch NOTIFY filterChanged FINAL)

  public:
    VoicePicker(SongView &owner, QString title, int initialVoice, QObject *parent = nullptr);
    ~VoicePicker() override;

    QAbstractItemModel *voicePickerModel() { return &m_model; }
    QString voicePickerTitle() const { return m_title; }
    QVariantMap voicePickerAppearance() const;
    QString filter() const { return m_filter; }
    int currentRow() const noexcept;
    bool hasMatch() const noexcept;

    Q_INVOKABLE void setFilter(const QString &filter);
    Q_INVOKABLE void selectRow(int row);
    Q_INVOKABLE void pressAndHold(int program);
    Q_INVOKABLE void releaseHeld();
    Q_INVOKABLE void accept();
    Q_INVOKABLE void cancel();

  signals:
    void filterChanged();
    void currentRowChanged();
    void accepted(int program);
    void rejected();

  private:
    void setCurrentProgram(int program);

    SongView &m_owner;
    VoicePickerModel m_model;
    QString m_title;
    QString m_filter;
    QVariantMap m_appearance;
    int m_currentProgram = -1;
    int m_soundingProgram = -1;
};

} // namespace songview
