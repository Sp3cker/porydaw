// ---------------------------------------------------------- VoicePickerDialog

// Modal instrument picker (SPEC §4.2): the voicegroup's 128 entries, the same
// list the import wizard's mapping combo renders. Press-and-hold auditions
// through the preview engine; double-click chooses.

#include "ui/songview/voicepicker.h"

#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"

#include <QAbstractItemView>
#include <QDialogButtonBox>
#include <QEvent>
#include <QLineEdit>
#include <QListWidget>
#include <QListWidgetItem>
#include <QObject>
#include <QPushButton>
#include <QVBoxLayout>

#include <algorithm>
#include <utility>

namespace lyt = ::layout;

namespace songview {
using namespace songview::detail;

VoicePickerDialog::Geometry VoicePickerDialog::Geometry::resolve()
{
    return {lyt::fontPx(30.0), lyt::fontPx(110.0 / 3.0)};
}

void VoicePickerDialog::refreshGeometry()
{
    m_geometry = Geometry::resolve();
    resize(m_geometry.width, m_geometry.height);
}

VoicePickerDialog::VoicePickerDialog(SongView *sv, const QString &title, int initialVoice,
                                     std::function<void(int, int)> audition)
    : QDialog(sv)
    , m_geometry(Geometry::resolve())
    , m_audition(std::move(audition))
{
    setWindowTitle(title);
    resize(m_geometry.width, m_geometry.height);
    auto *dialogLayout = new QVBoxLayout(this);
    auto *searchField = new QLineEdit(this);
    searchField->setPlaceholderText(tr("Search voices..."));
    searchField->setClearButtonEnabled(true);
    dialogLayout->addWidget(searchField);
    m_list = new QListWidget(this);
    m_list->setUniformItemSizes(true);
    m_list->setToolTip(SongView::tr("Click and hold to audition (middle C)."));
    for (int v = 0; v < VOICEGROUP_SIZE; v++)
        m_list->addItem(QStringLiteral("%1  %2")
                            .arg(v, 3, 10, QLatin1Char('0'))
                            .arg(sv->voiceShortName(uint8_t(v))));
    m_list->setCurrentRow(std::clamp(initialVoice, 0, VOICEGROUP_SIZE - 1));
    m_list->scrollToItem(m_list->currentItem(), QAbstractItemView::PositionAtCenter);
    dialogLayout->addWidget(m_list, 1);

    auto *dialogButtons =
        new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, this);
    connect(dialogButtons, &QDialogButtonBox::accepted, this, &QDialog::accept);
    connect(dialogButtons, &QDialogButtonBox::rejected, this, &QDialog::reject);
    dialogLayout->addWidget(dialogButtons);
    connect(
        searchField, &QLineEdit::textChanged, this, [this, dialogButtons](const QString &query) {
            QListWidgetItem *firstMatchingVoice = nullptr;
            for (int voiceIndex = 0; voiceIndex < m_list->count(); ++voiceIndex) {
                QListWidgetItem *voiceItem = m_list->item(voiceIndex);
                const bool matchesQuery = voiceItem->text().contains(query, Qt::CaseInsensitive);
                voiceItem->setHidden(!matchesQuery);
                if (matchesQuery && !firstMatchingVoice)
                    firstMatchingVoice = voiceItem;
            }
            m_list->setCurrentItem(firstMatchingVoice);
            dialogButtons->button(QDialogButtonBox::Ok)->setEnabled(firstMatchingVoice);
        });
    searchField->setFocus();

    connect(m_list, &QListWidget::itemPressed, this, [this](QListWidgetItem *item) {
        releaseVoice();
        if (item) {
            m_sounding = m_list->row(item);
            m_audition(m_sounding, kVoiceAuditionVel);
        }
    });
    connect(m_list, &QListWidget::itemDoubleClicked, this, [this] { accept(); });
    m_list->viewport()->installEventFilter(this);
}

VoicePickerDialog::~VoicePickerDialog()
{
    releaseVoice();
}

int VoicePickerDialog::selectedVoice() const
{
    return std::max(0, m_list->currentRow());
}

bool VoicePickerDialog::event(QEvent *event)
{
    const bool handled = QDialog::event(event);
    if (event->type() == QEvent::FontChange)
        refreshGeometry();
    return handled;
}

bool VoicePickerDialog::eventFilter(QObject *watched, QEvent *event)
{
    if (watched == m_list->viewport() && event->type() == QEvent::MouseButtonRelease)
        releaseVoice();
    return QDialog::eventFilter(watched, event);
}

void VoicePickerDialog::releaseVoice()
{
    if (m_sounding < 0)
        return;
    m_audition(m_sounding, 0);
    m_sounding = -1;
}

} // namespace songview
