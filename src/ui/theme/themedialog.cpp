#include "themedialog.h"

#include <QSlider>

#include <QButtonGroup>
#include <QCloseEvent>
#include <QFontMetrics>
#include <QFormLayout>
#include <QHBoxLayout>
#include <QLabel>
#include <QPushButton>
#include <QRadioButton>
#include <QSignalBlocker>
#include <QVBoxLayout>

namespace themes {

void ThemeDialog::addModeButton(QVBoxLayout &layout, QWidget &parent, ThemeMode mode,
                                const QString &label, const QString &objectName)
{
    const auto id = static_cast<int>(mode);
    Q_ASSERT(m_modeButtons->button(id) == nullptr);
    auto *button = new QRadioButton(label, &parent);
    if (!objectName.isEmpty())
        button->setObjectName(objectName);
    m_modeButtons->addButton(button, id);
    button->setAttribute(Qt::WA_LayoutUsesWidgetRect);
    layout.addWidget(button);
}

void ThemeDialog::setCheckedMode(ThemeMode mode)
{
    auto *button = m_modeButtons->button(static_cast<int>(mode));
    Q_ASSERT(button);
    button->setChecked(true);
}

ThemeDialog::ThemeDialog(ThemeController &controller, QWidget *parent)
    : QDialog(parent)
    , m_controller(controller)
    , m_draft{}
{
    setWindowTitle(tr("Theme"));
    setModal(false);
    setAttribute(Qt::WA_DeleteOnClose, false);

    auto *modeGroup = new QWidget(this);
    auto *modeLayout = new QVBoxLayout(modeGroup);
    modeLayout->setContentsMargins(0, 0, 0, 0);
    m_modeButtons = new QButtonGroup(this);
    m_modeButtons->setExclusive(true);
    addModeButton(*modeLayout, *modeGroup, ThemeMode::Vanilla, tr("Vanilla"),
                  QStringLiteral("vanillaModeButton"));
    addModeButton(*modeLayout, *modeGroup, ThemeMode::DarkNeutralHigh, tr("Dark Neutral High"),
                  QStringLiteral("darkNeutralHighModeButton"));
    addModeButton(*modeLayout, *modeGroup, ThemeMode::Immaterial, tr("Immaterial"),
                  QStringLiteral("immaterialModeButton"));

    m_gridLineContrastSlider = new QSlider(Qt::Horizontal, this);
    m_gridLineContrastSlider->setObjectName(QStringLiteral("gridLineContrastSlider"));
    m_gridLineContrastSlider->setRange(0, 100);
    m_gridLineContrastSlider->setValue(defaultGridLineContrast);
    m_gridLineContrastSlider->setTickPosition(QSlider::TicksBelow);
    m_gridLineContrastSlider->setTickInterval(10);
    m_gridLineContrastSlider->setAccessibleName(tr("Grid Line Contrast"));
    m_gridLineContrastSlider->setToolTip(
        tr("50 uses the theme default. Lower values soften grid lines; higher "
           "values strengthen them."));
    m_gridLineContrastValueLabel = new QLabel(QString::number(defaultGridLineContrast), this);
    m_gridLineContrastValueLabel->setMinimumWidth(QFontMetrics(m_gridLineContrastValueLabel->font())
                                                      .horizontalAdvance(QStringLiteral("100")));
    auto *contrastRow = new QHBoxLayout;
    contrastRow->setContentsMargins(0, 0, 0, 0);
    contrastRow->addWidget(m_gridLineContrastSlider, 1);
    contrastRow->addWidget(m_gridLineContrastValueLabel);
    auto *contrastLayout = new QFormLayout;
    contrastLayout->setLabelAlignment(Qt::AlignRight | Qt::AlignVCenter);
    contrastLayout->addRow(tr("Grid Line Contrast:"), contrastRow);

    m_applyButton = new QPushButton(tr("Apply"), this);
    m_applyButton->setObjectName(QStringLiteral("themeApplyButton"));
    m_closeButton = new QPushButton(tr("Close"), this);
    m_closeButton->setObjectName(QStringLiteral("themeCloseButton"));
    auto *buttons = new QHBoxLayout;
    buttons->addStretch(1);
    buttons->addWidget(m_applyButton);
    buttons->addWidget(m_closeButton);

    auto *layout = new QVBoxLayout(this);
    layout->addWidget(modeGroup);
    layout->addLayout(contrastLayout);
    layout->addLayout(buttons);

    connect(m_modeButtons, &QButtonGroup::idClicked, this, [this](int id) {
        const auto mode = static_cast<ThemeMode>(id);
        if (mode != m_draft.mode)
            modeChanged(mode);
    });
    connect(m_gridLineContrastSlider, &QSlider::valueChanged, this, [this](int value) {
        m_draft.gridLineContrast = value;
        m_gridLineContrastValueLabel->setText(QString::number(value));
        schedulePreview();
    });
    connect(m_applyButton, &QPushButton::clicked, this, &ThemeDialog::applyClicked);
    connect(m_closeButton, &QPushButton::clicked, this, &ThemeDialog::closeClicked);

    resetDraftToCommitted();
    setCheckedMode(m_draft.mode);
    resize(sizeHint());
}

void ThemeDialog::schedulePreview()
{
    m_controller.preview(m_draft);
}

void ThemeDialog::modeChanged(ThemeMode mode)
{
    m_draft.mode = mode;
    schedulePreview();
}

void ThemeDialog::applyClicked()
{
    if (!m_controller.commit(m_draft))
        return;
    resetDraftToCommitted();
}

void ThemeDialog::resetDraftToCommitted()
{
    const auto &committed = m_controller.committedSelection();
    m_draft = committed;
    const QSignalBlocker blocker(m_gridLineContrastSlider);
    m_gridLineContrastSlider->setValue(m_draft.gridLineContrast);
    m_gridLineContrastValueLabel->setText(QString::number(m_draft.gridLineContrast));
}

void ThemeDialog::rollbackToCommitted()
{
    m_controller.discardPreview();
    resetDraftToCommitted();
    setCheckedMode(m_draft.mode);
}

void ThemeDialog::reject()
{
    rollbackToCommitted();
    QDialog::reject();
}

void ThemeDialog::closeEvent(QCloseEvent *event)
{
    rollbackToCommitted();
    QDialog::closeEvent(event);
}

void ThemeDialog::closeClicked()
{
    reject();
}

} // namespace themes
