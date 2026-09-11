#pragma once

#include "themecontroller.h"
#include <QDialog>
#include <QString>

class QButtonGroup;
class QCloseEvent;
class QSlider;
class QLabel;
class QPushButton;
class QVBoxLayout;
class QWidget;

namespace themes {

/// Modeless editor for a theme draft.
///
/// The dialog manages preset controls and draft state. ThemeController owns
/// applying, saving, and restoring the application's committed theme.
class ThemeDialog final : public QDialog
{
    Q_OBJECT

  public:
    ThemeDialog(ThemeController &controller, QWidget *parent = nullptr);

  protected:
    void reject() override;
    void closeEvent(QCloseEvent *event) override;

  private slots:
    void applyClicked();
    void closeClicked();

  private:
    void addModeButton(QVBoxLayout &layout, QWidget &parent, ThemeMode mode, const QString &label,
                       const QString &objectName = {});
    void setCheckedMode(ThemeMode mode);
    void modeChanged(ThemeMode mode);

    void schedulePreview();
    void rollbackToCommitted();
    void resetDraftToCommitted();

    ThemeController &m_controller;
    ThemeSelection m_draft;

    QButtonGroup *m_modeButtons = nullptr;
    QSlider *m_gridLineContrastSlider = nullptr;
    QLabel *m_gridLineContrastValueLabel = nullptr;
    QPushButton *m_applyButton = nullptr;
    QPushButton *m_closeButton = nullptr;
};
} // namespace themes
