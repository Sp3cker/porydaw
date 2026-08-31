#pragma once

#include "ui/m4asemantics.h"
#include "voicegroup_loader.h"

#include <QDialog>
#include <QSet>
#include <QStringList>

#include <array>
#include <functional>
#include <optional>

class QButtonGroup;
class QCheckBox;
class QEvent;
class QLabel;
class QHBoxLayout;
class QListWidget;
class QListWidgetItem;
class QObject;
class QPushButton;
class QVBoxLayout;
class SongView;
class QString;
class QWidget;

namespace songview {

class VoicePickerDialog : public QDialog
{
    void refreshGeometry();
    void refreshVisibility();
    void clearFilters();

  public:
    // The parent chain lets SongView::cancelTransientInput() reject an active
    // picker synchronously before a document or song replacement.
    VoicePickerDialog(SongView *sv, const QString &title, int initialVoice,
                      std::function<void(int, int)> audition,
                      std::function<void(int)> onRowChange = {});
    ~VoicePickerDialog() override;

    // The current row in [0, 127], or -1 when filters leave no visible
    // selection; callers gate acceptance on -1 before committing.
    int selectedVoice() const;

  protected:
    bool event(QEvent *event) override;
    bool eventFilter(QObject *watched, QEvent *event) override;
    void accept() override;
    void reject() override;

  private:
    void releaseVoice();

    std::array<VoiceFamily, VOICEGROUP_SIZE> m_families{};
    QStringList m_displayNames;
    QSet<int> m_usedSlots;
    std::optional<VoiceFamily> m_family;
    bool m_usedOnly = false;
    bool m_namedOnly = false;
    QWidget *m_facetRail = nullptr;
    QHBoxLayout *m_dialogLayout = nullptr;
    QVBoxLayout *m_railLayout = nullptr;
    QHBoxLayout *m_resultsHeaderLayout = nullptr;
    QListWidget *m_list = nullptr;
    QLabel *m_matchingCount = nullptr;
    QLabel *m_emptyState = nullptr;
    QPushButton *m_okButton = nullptr;
    QButtonGroup *m_familyButtons = nullptr;
    QCheckBox *m_usedOnlyCheck = nullptr;
    QCheckBox *m_namedOnlyCheck = nullptr;
    std::function<void(int, int)> m_audition;
    std::function<void(int)> m_onRowChange;
    int m_sounding = -1;
};

} // namespace songview
