#pragma once

#include <QColor>
#include <QRect>
#include <QSize>
#include <QString>
#include <QStringList>

class DragSpinBox;
class QComboBox;
class QDockWidget;
struct LoadedBankView;
class SamplePickerButton;
struct VgVoice;
class QLineEdit;
class QSpinBox;
class QTreeWidget;
class QTreeWidgetItem;
class VoicegroupBrowser;
class WorkspaceUi;
enum class VgMacro;

namespace checks {

// Checks-only interaction driver for WorkspaceUi's production voicegroup
// chrome. It borrows the widgets and resolves editor/popup children on every
// call because source changes can rebuild their presentation.
class VoicegroupBrowserDriver final
{
  public:
    explicit VoicegroupBrowserDriver(WorkspaceUi &workspace) noexcept;

    bool isAvailable() const noexcept;
    bool isLoading() const noexcept;

    // The selected tab's published bank view (128 slot voices, dirty flag,
    // load name), or nullptr when no tab is bound. The pointer borrows the
    // workspace's cache entry: re-fetch it after every bank event.
    const LoadedBankView *selectedBankView() const;

    // Submits one picker edit for the selected slot through WorkspaceUi's
    // production edit entry (the browser's own voiceEditRequested path).
    void submitPickerEdit(int slot, const VgVoice &voice) const;

    // The browser tree's rows and its two selection seams (the editor panel
    // and jump-from-context reveal drive the same rows).
    QStringList slotRowText(int slot) const;
    int currentSlot() const;
    void selectSlot(int slot) const;
    void revealSlot(int slot) const;
    bool slotIsMarkedUsed(int slot) const;

    QComboBox *voicegroupSelector() const;
    DragSpinBox *releaseSpinBox() const;
    QLineEdit *releaseField() const;
    // The synth parameter spin boxes, in voice order: base duty, duty LFO
    // step, modulation depth, phase.
    QSpinBox *synthParameterField(int index) const;
    QString editorNoticeText() const;
    bool editorNoticeIsHidden() const;
    bool sampleActionButtonsHaveMatchingFixedSize() const;
    int visibleVoiceTypeData() const;
    bool activateVoiceType(VgMacro macro) const;
    bool activateSynthType() const;
    bool visibleSymbolComboContains(const QString &symbol) const;
    bool activateSynthWave(int index) const;
    bool hasSynthEditorControls() const;

    QSize browserMinimumSizeHint() const;
    QRect dockGeometry() const;
    void hideDock() const;
    bool dockIsHidden() const;

    bool hasSamplePickerEditor() const;
    bool samplePickerReplacesSymbolCombo() const;
    bool samplePickerIsVisible() const;
    QString samplePickerCurrentSymbol() const;
    void openSamplePickerPopup() const;
    bool samplePickerPopupIsVisible() const;
    QLineEdit *samplePickerFilterField() const;
    QColor samplePickerPopupCornerColor() const;
    int samplePickerSymbolRowCount() const;
    int samplePickerBadgedRowCount() const;
    bool selectFirstKeysplitPickerRow() const;
    QString firstAlternatePlainPickerSymbol(const QString &excluded) const;
    QString currentPickerRowSymbol() const;
    void clickCurrentPickerRow() const;
    QString firstAlternatePickerSymbol(const QString &excluded) const;
    QStringList pickerSymbols() const;
    bool pickerRowsShowFullSymbols() const;
    void hideSamplePickerPopup() const;
    bool saveSamplePickerPopup(const QString &path) const;
    bool saveBrowser(const QString &path) const;

  private:
    VoicegroupBrowser *browser() const noexcept;
    QDockWidget *dock() const noexcept;
    QTreeWidget *slotTree() const;
    QComboBox *visibleTypeCombo() const;
    QComboBox *editorSymbolCombo() const;
    QComboBox *visibleSymbolCombo() const;
    QComboBox *synthWaveCombo() const;
    QComboBox *visibleSynthWaveCombo() const;
    QSpinBox *synthDutyField() const;
    QSpinBox *synthStepField() const;
    QSpinBox *synthDepthField() const;
    QSpinBox *synthPhaseField() const;
    SamplePickerButton *samplePicker() const;
    QTreeWidget *pickerTree() const;
    QTreeWidgetItem *currentPickerRow() const;

    WorkspaceUi &m_workspace;
};

} // namespace checks
