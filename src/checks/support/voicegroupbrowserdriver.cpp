#include "checks/support/voicegroupbrowserdriver.h"

#include <QComboBox>
#include <QCoreApplication>
#include <QDockWidget>
#include <QImage>
#include <QLabel>
#include <QLineEdit>
#include <QMetaObject>
#include <QPixmap>
#include <QPoint>
#include <QSpinBox>
#include <QToolButton>
#include <QTreeWidget>
#include <QTreeWidgetItemIterator>
#include <QWidget>

#include "ui/dragspinbox.h"
#include "ui/samplepicker.h"
#include "ui/voicegroupbrowser.h"
#include "ui/workspaceui.h"

namespace {

bool activateComboIndex(QComboBox *combo, int index)
{
    if (!combo || index < 0 || index >= combo->count())
        return false;
    combo->setCurrentIndex(index);
    return QMetaObject::invokeMethod(combo, "activated", Qt::DirectConnection, Q_ARG(int, index));
}

} // namespace

namespace checks {

VoicegroupBrowserDriver::VoicegroupBrowserDriver(WorkspaceUi &workspace) noexcept
    : m_workspace(workspace)
{}

bool VoicegroupBrowserDriver::isAvailable() const noexcept
{
    return browser() && dock();
}

bool VoicegroupBrowserDriver::isLoading() const noexcept
{
    QComboBox *const selector = voicegroupSelector();
    DragSpinBox *const release = releaseSpinBox();
    const QString loading = QCoreApplication::translate("VoicegroupBrowser", "Loading...");
    const QStringList firstRow = slotRowText(0);
    return selector && !selector->isEnabled() && selector->currentText() == loading &&
           firstRow.size() == 3 && firstRow.constFirst().contains(loading) &&
           (!release || !release->isEnabled());
}

QComboBox *VoicegroupBrowserDriver::voicegroupSelector() const
{
    VoicegroupBrowser *const root = browser();
    return root ? root->findChild<QComboBox *>(QStringLiteral("vgArgCombo")) : nullptr;
}

DragSpinBox *VoicegroupBrowserDriver::releaseSpinBox() const
{
    VoicegroupBrowser *const root = browser();
    if (!root)
        return nullptr;
    for (DragSpinBox *spin : root->findChildren<DragSpinBox *>()) {
        if (spin->toolTip() == QStringLiteral("Release"))
            return spin;
    }
    return nullptr;
}

QLineEdit *VoicegroupBrowserDriver::releaseField() const
{
    DragSpinBox *const spin = releaseSpinBox();
    return spin ? spin->findChild<QLineEdit *>() : nullptr;
}

QStringList VoicegroupBrowserDriver::slotRowText(int slot) const
{
    QTreeWidget *const tree = slotTree();
    QTreeWidgetItem *const item = tree ? tree->topLevelItem(slot) : nullptr;
    return item ? QStringList{item->text(0), item->text(1), item->text(2)} : QStringList();
}

bool VoicegroupBrowserDriver::slotIsMarkedUsed(int slot) const
{
    QTreeWidget *const tree = slotTree();
    QTreeWidgetItem *const item = tree ? tree->topLevelItem(slot) : nullptr;
    return item && item->background(0).style() != Qt::NoBrush;
}

QString VoicegroupBrowserDriver::editorNoticeText() const
{
    VoicegroupBrowser *const root = browser();
    QLabel *const notice =
        root ? root->findChild<QLabel *>(QStringLiteral("voicegroupEditorNotice")) : nullptr;
    return notice ? notice->text() : QString();
}

bool VoicegroupBrowserDriver::editorNoticeIsHidden() const
{
    VoicegroupBrowser *const root = browser();
    QLabel *const notice =
        root ? root->findChild<QLabel *>(QStringLiteral("voicegroupEditorNotice")) : nullptr;
    return notice && notice->isHidden();
}

bool VoicegroupBrowserDriver::sampleActionButtonsHaveMatchingFixedSize() const
{
    VoicegroupBrowser *const root = browser();
    if (!root)
        return false;
    QToolButton *const newButton =
        root->findChild<QToolButton *>(QStringLiteral("vgNewSampleButton"));
    QToolButton *const editButton =
        root->findChild<QToolButton *>(QStringLiteral("vgEditSampleButton"));
    return newButton && editButton && newButton->size() == editButton->size() &&
           newButton->minimumSize() == newButton->maximumSize() &&
           editButton->minimumSize() == editButton->maximumSize();
}

int VoicegroupBrowserDriver::visibleVoiceTypeData() const
{
    QComboBox *const combo = visibleTypeCombo();
    return combo ? combo->currentData().toInt() : -1;
}

bool VoicegroupBrowserDriver::activateVoiceType(VgMacro macro) const
{
    QComboBox *const combo = visibleTypeCombo();
    return combo && activateComboIndex(combo, combo->findData(int(macro)));
}

bool VoicegroupBrowserDriver::activateSynthType() const
{
    QComboBox *const combo = visibleTypeCombo();
    if (!combo)
        return false;
    for (int index = 0; index < combo->count(); ++index) {
        if (combo->itemText(index) == QStringLiteral("Synth (Golden Sun)"))
            return activateComboIndex(combo, index);
    }
    return false;
}

bool VoicegroupBrowserDriver::visibleSymbolComboContains(const QString &symbol) const
{
    QComboBox *const combo = visibleSymbolCombo();
    return combo && combo->findText(symbol) >= 0;
}

bool VoicegroupBrowserDriver::activateSynthWave(int index) const
{
    return activateComboIndex(visibleSynthWaveCombo(), index);
}

bool VoicegroupBrowserDriver::hasSynthEditorControls() const
{
    QComboBox *const typeCombo = visibleTypeCombo();
    bool hasSynthType = false;
    if (typeCombo) {
        for (int index = 0; index < typeCombo->count(); ++index)
            hasSynthType =
                hasSynthType || typeCombo->itemText(index) == QStringLiteral("Synth (Golden Sun)");
    }
    return hasSynthType && editorSymbolCombo() && synthWaveCombo() && synthDutyField() &&
           synthStepField() && synthDepthField() && synthPhaseField();
}

bool VoicegroupBrowserDriver::setSynthParameterValues(int duty, int step, int depth,
                                                      int phase) const
{
    QSpinBox *field = synthDutyField();
    if (!field)
        return false;
    field->setValue(duty);

    field = synthStepField();
    if (!field)
        return false;
    field->setValue(step);

    field = synthDepthField();
    if (!field)
        return false;
    field->setValue(depth);

    field = synthPhaseField();
    if (!field)
        return false;
    field->setValue(phase);
    return true;
}

QSize VoicegroupBrowserDriver::browserMinimumSizeHint() const
{
    VoicegroupBrowser *const root = browser();
    return root ? root->minimumSizeHint() : QSize();
}

QRect VoicegroupBrowserDriver::dockGeometry() const
{
    QDockWidget *const voicegroupDock = dock();
    return voicegroupDock ? voicegroupDock->geometry() : QRect();
}

void VoicegroupBrowserDriver::hideDock() const
{
    if (QDockWidget *const voicegroupDock = dock())
        voicegroupDock->hide();
}

bool VoicegroupBrowserDriver::dockIsHidden() const
{
    QDockWidget *const voicegroupDock = dock();
    return voicegroupDock && voicegroupDock->isHidden();
}

bool VoicegroupBrowserDriver::hasSamplePickerEditor() const
{
    return samplePicker() && editorSymbolCombo();
}
bool VoicegroupBrowserDriver::samplePickerReplacesSymbolCombo() const
{
    SamplePickerButton *const picker = samplePicker();
    QComboBox *const symbolCombo = editorSymbolCombo();
    return picker && symbolCombo && picker->isVisible() && !symbolCombo->isVisible();
}

bool VoicegroupBrowserDriver::samplePickerIsVisible() const
{
    SamplePickerButton *const picker = samplePicker();
    return picker && picker->isVisible();
}

QString VoicegroupBrowserDriver::samplePickerCurrentSymbol() const
{
    SamplePickerButton *const picker = samplePicker();
    return picker ? picker->currentSymbol() : QString();
}

void VoicegroupBrowserDriver::openSamplePickerPopup() const
{
    if (SamplePickerButton *const picker = samplePicker())
        picker->openPopup();
}

bool VoicegroupBrowserDriver::samplePickerPopupIsVisible() const
{
    SamplePickerButton *const picker = samplePicker();
    return picker && picker->popupVisible();
}

QLineEdit *VoicegroupBrowserDriver::samplePickerFilterField() const
{
    SamplePickerButton *const picker = samplePicker();
    return picker ? picker->findChild<QLineEdit *>(QStringLiteral("vgSamplePickerSearch"))
                  : nullptr;
}

QColor VoicegroupBrowserDriver::samplePickerPopupCornerColor() const
{
    SamplePickerButton *const picker = samplePicker();
    QWidget *const popup =
        picker ? picker->findChild<QWidget *>(QStringLiteral("vgSamplePickerPopup")) : nullptr;
    return popup ? popup->grab().toImage().pixelColor(QPoint()) : QColor();
}

int VoicegroupBrowserDriver::samplePickerSymbolRowCount() const
{
    QTreeWidget *const tree = pickerTree();
    if (!tree)
        return 0;
    int rows = 0;
    for (QTreeWidgetItemIterator it(tree); *it; ++it)
        rows += (*it)->data(0, Qt::UserRole).toString().isEmpty() ? 0 : 1;
    return rows;
}

int VoicegroupBrowserDriver::samplePickerBadgedRowCount() const
{
    QTreeWidget *const tree = pickerTree();
    if (!tree)
        return 0;
    int badges = 0;
    for (QTreeWidgetItemIterator it(tree); *it; ++it) {
        if (!(*it)->data(0, Qt::UserRole).toString().isEmpty() && !(*it)->text(1).isEmpty())
            ++badges;
    }
    return badges;
}

bool VoicegroupBrowserDriver::selectFirstKeysplitPickerRow() const
{
    QTreeWidget *const tree = pickerTree();
    if (!tree)
        return false;
    for (QTreeWidgetItemIterator it(tree); *it; ++it) {
        if ((*it)->data(0, Qt::UserRole + 1).toBool()) {
            tree->setCurrentItem(*it);
            return true;
        }
    }
    return false;
}

QString VoicegroupBrowserDriver::firstAlternatePlainPickerSymbol(const QString &excluded) const
{
    QTreeWidget *const tree = pickerTree();
    if (!tree)
        return {};
    for (QTreeWidgetItemIterator it(tree); *it; ++it) {
        const QString symbol = (*it)->data(0, Qt::UserRole).toString();
        if (!symbol.isEmpty() && symbol != excluded && !(*it)->data(0, Qt::UserRole + 1).toBool()) {
            return symbol;
        }
    }
    return {};
}

QString VoicegroupBrowserDriver::currentPickerRowSymbol() const
{
    QTreeWidgetItem *const item = currentPickerRow();
    return item ? item->data(0, Qt::UserRole).toString() : QString();
}

void VoicegroupBrowserDriver::clickCurrentPickerRow() const
{
    QTreeWidget *const tree = pickerTree();
    QTreeWidgetItem *const item = tree ? tree->currentItem() : nullptr;
    if (item)
        tree->itemClicked(item, 0);
}

QString VoicegroupBrowserDriver::firstAlternatePickerSymbol(const QString &excluded) const
{
    QTreeWidget *const tree = pickerTree();
    if (!tree)
        return {};
    for (QTreeWidgetItemIterator it(tree); *it; ++it) {
        const QString symbol = (*it)->data(0, Qt::UserRole).toString();
        if (!symbol.isEmpty() && symbol != excluded)
            return symbol;
    }
    return {};
}

QStringList VoicegroupBrowserDriver::pickerSymbols() const
{
    QStringList symbols;
    QTreeWidget *const tree = pickerTree();
    if (!tree)
        return symbols;
    for (QTreeWidgetItemIterator it(tree); *it; ++it) {
        const QString symbol = (*it)->data(0, Qt::UserRole).toString();
        if (!symbol.isEmpty())
            symbols.append(symbol);
    }
    return symbols;
}

bool VoicegroupBrowserDriver::pickerRowsShowFullSymbols() const
{
    QTreeWidget *const tree = pickerTree();
    if (!tree)
        return false;
    for (QTreeWidgetItemIterator it(tree); *it; ++it) {
        const QString symbol = (*it)->data(0, Qt::UserRole).toString();
        if (!symbol.isEmpty() && (*it)->text(0) != symbol)
            return false;
    }
    return true;
}

void VoicegroupBrowserDriver::hideSamplePickerPopup() const
{
    SamplePickerButton *const picker = samplePicker();
    QWidget *const popup =
        picker ? picker->findChild<QWidget *>(QStringLiteral("vgSamplePickerPopup")) : nullptr;
    if (popup)
        popup->hide();
}

bool VoicegroupBrowserDriver::saveSamplePickerPopup(const QString &path) const
{
    SamplePickerButton *const picker = samplePicker();
    QWidget *const popup =
        picker ? picker->findChild<QWidget *>(QStringLiteral("vgSamplePickerPopup")) : nullptr;
    return popup && popup->grab().save(path);
}

bool VoicegroupBrowserDriver::saveBrowser(const QString &path) const
{
    VoicegroupBrowser *const root = browser();
    return root && root->grab().save(path);
}

VoicegroupBrowser *VoicegroupBrowserDriver::browser() const noexcept
{
    return m_workspace.m_voicegroupBrowser;
}

QDockWidget *VoicegroupBrowserDriver::dock() const noexcept
{
    return m_workspace.m_voicegroupDock;
}

QTreeWidget *VoicegroupBrowserDriver::slotTree() const
{
    VoicegroupBrowser *const root = browser();
    return root ? root->findChild<QTreeWidget *>(QString(), Qt::FindDirectChildrenOnly) : nullptr;
}

QComboBox *VoicegroupBrowserDriver::visibleTypeCombo() const
{
    VoicegroupBrowser *const root = browser();
    if (!root)
        return nullptr;
    for (QComboBox *combo : root->findChildren<QComboBox *>()) {
        if (!combo->isHidden() && combo->findData(int(VgMacro::Square1)) >= 0)
            return combo;
    }
    return nullptr;
}

QComboBox *VoicegroupBrowserDriver::editorSymbolCombo() const
{
    VoicegroupBrowser *const root = browser();
    if (!root)
        return nullptr;
    for (QComboBox *combo : root->findChildren<QComboBox *>()) {
        if (combo->isEditable() && combo != voicegroupSelector())
            return combo;
    }
    return nullptr;
}

QComboBox *VoicegroupBrowserDriver::visibleSymbolCombo() const
{
    QComboBox *const combo = editorSymbolCombo();
    return combo && !combo->isHidden() ? combo : nullptr;
}

QComboBox *VoicegroupBrowserDriver::synthWaveCombo() const
{
    VoicegroupBrowser *const root = browser();
    if (!root)
        return nullptr;
    for (QComboBox *combo : root->findChildren<QComboBox *>()) {
        if (combo->findText(QStringLiteral("Sawtooth")) >= 0)
            return combo;
    }
    return nullptr;
}

QComboBox *VoicegroupBrowserDriver::visibleSynthWaveCombo() const
{
    QComboBox *const combo = synthWaveCombo();
    return combo && !combo->isHidden() ? combo : nullptr;
}

QSpinBox *VoicegroupBrowserDriver::synthDutyField() const
{
    VoicegroupBrowser *const root = browser();
    if (!root)
        return nullptr;
    for (QSpinBox *spin : root->findChildren<QSpinBox *>()) {
        if (spin->toolTip().startsWith(QStringLiteral("Base duty")))
            return spin;
    }
    return nullptr;
}

QSpinBox *VoicegroupBrowserDriver::synthStepField() const
{
    VoicegroupBrowser *const root = browser();
    if (!root)
        return nullptr;
    for (QSpinBox *spin : root->findChildren<QSpinBox *>()) {
        if (spin->toolTip().startsWith(QStringLiteral("Duty LFO step")))
            return spin;
    }
    return nullptr;
}

QSpinBox *VoicegroupBrowserDriver::synthDepthField() const
{
    VoicegroupBrowser *const root = browser();
    if (!root)
        return nullptr;
    for (QSpinBox *spin : root->findChildren<QSpinBox *>()) {
        if (spin->toolTip().startsWith(QStringLiteral("Modulation")))
            return spin;
    }
    return nullptr;
}

QSpinBox *VoicegroupBrowserDriver::synthPhaseField() const
{
    VoicegroupBrowser *const root = browser();
    if (!root)
        return nullptr;
    for (QSpinBox *spin : root->findChildren<QSpinBox *>()) {
        if (spin->toolTip().startsWith(QStringLiteral("Duty LFO phase")))
            return spin;
    }
    return nullptr;
}

SamplePickerButton *VoicegroupBrowserDriver::samplePicker() const
{
    VoicegroupBrowser *const root = browser();
    return root ? root->findChild<SamplePickerButton *>() : nullptr;
}

QTreeWidget *VoicegroupBrowserDriver::pickerTree() const
{
    SamplePickerButton *const picker = samplePicker();
    return picker ? picker->findChild<QTreeWidget *>(QStringLiteral("vgSamplePickerList"))
                  : nullptr;
}

QTreeWidgetItem *VoicegroupBrowserDriver::currentPickerRow() const
{
    QTreeWidget *const tree = pickerTree();
    return tree ? tree->currentItem() : nullptr;
}

} // namespace checks
