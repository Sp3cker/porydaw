// ---------------------------------------------------------- VoicePickerDialog

// Modal instrument picker: immutable voicegroup snapshots, facet filtering,
// press-and-hold audition, and optional live projection on row changes.

#include "ui/songview/voicepicker.h"

#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"

#include <QAbstractItemView>
#include <QButtonGroup>
#include <QCheckBox>
#include <QCoreApplication>
#include <QDialogButtonBox>
#include <QEvent>
#include <QFontMetrics>
#include <QHBoxLayout>
#include <QLabel>
#include <QListWidget>
#include <QListWidgetItem>
#include <QPainter>
#include <QPalette>
#include <QPen>
#include <QPushButton>
#include <QSignalBlocker>
#include <QSizePolicy>
#include <QStyle>
#include <QStyledItemDelegate>
#include <QToolButton>
#include <QVBoxLayout>
#include <QWidget>

#include <algorithm>
#include <array>
#include <utility>

namespace lyt = ::layout;
using Space = lyt::Space;

namespace {

constexpr std::array kFamilies = {
    VoiceFamily::Sample, VoiceFamily::Square1, VoiceFamily::Square2, VoiceFamily::Wave,
    VoiceFamily::Noise,  VoiceFamily::Drumkit, VoiceFamily::Synth,
};

struct PickerGeometry {
    int width;
    int height;
    int minimumWidth;
    int railWidth;
    int resultColumnWidth;
    int rootMargin;
    int rootSpacing;
    int railMargin;
    int sectionSpacing;
    int rowHeight;
    int facetRowHeight;
    int slotWidth;
    int swatchExtent;
    int tagHeight;
    int tagPadding;
    int rowPadding;
    int rowGap;
    int tagGap;
    qreal tagRadius;
};

PickerGeometry resolvePickerGeometry()
{
    const int rootMargin = lyt::space(Space::Four);
    const int rootSpacing = lyt::space(Space::Four);
    const int railWidth = lyt::fontPx(20.0);
    const int resultColumnWidth = lyt::fontPx(35.5);
    return {railWidth + resultColumnWidth + 2 * rootMargin + rootSpacing,
            lyt::fontPx(110.0 / 3.0),
            railWidth + resultColumnWidth + 2 * rootMargin + rootSpacing,
            railWidth,
            resultColumnWidth,
            rootMargin,
            rootSpacing,
            lyt::space(Space::Four),
            lyt::space(Space::Two),
            lyt::fontPx(3.0),
            lyt::fontPx(31.0 / 13.0),
            lyt::fontPx(10.0 / 3.0),
            lyt::fontPx(11.0 / 13.0),
            lyt::fontPx(20.0 / 13.0),
            lyt::space(Space::Two),
            lyt::space(Space::Two),
            lyt::space(Space::Two),
            lyt::space(Space::Two),
            lyt::fontPxF(0.25)};
}

QString pickerText(const char *source)
{
    return QCoreApplication::translate("VoicePickerDialog", source);
}

QString familyLabel(VoiceFamily family)
{
    switch (family) {
    case VoiceFamily::Sample:
        return pickerText("Sample");
    case VoiceFamily::Square1:
        return pickerText("Square 1");
    case VoiceFamily::Square2:
        return pickerText("Square 2");
    case VoiceFamily::Wave:
        return pickerText("Wave");
    case VoiceFamily::Noise:
        return pickerText("Noise");
    case VoiceFamily::Drumkit:
        return pickerText("Drumkit");
    case VoiceFamily::Synth:
        return pickerText("Synth (Golden Sun)");
    }
    return pickerText("Sample");
}

const QColor &familyColor(VoiceFamily family)
{
    static const QColor sample(0x63, 0x8a, 0xa6);
    static const QColor square1(0x95, 0x6b, 0xb7);
    static const QColor square2(0xb5, 0x6d, 0x91);
    static const QColor wave(0x36, 0x8f, 0x8d);
    static const QColor noise(0xae, 0x7d, 0x2b);
    static const QColor drumkit(0x9f, 0x5d, 0x4e);
    static const QColor synth(0x64, 0x74, 0x4d);
    switch (family) {
    case VoiceFamily::Sample:
        return sample;
    case VoiceFamily::Square1:
        return square1;
    case VoiceFamily::Square2:
        return square2;
    case VoiceFamily::Wave:
        return wave;
    case VoiceFamily::Noise:
        return noise;
    case VoiceFamily::Drumkit:
        return drumkit;
    case VoiceFamily::Synth:
        return synth;
    }
    return sample;
}

QString voiceSlotText(int voice)
{
    return QStringLiteral("%1").arg(voice, 3, 10, QLatin1Char('0'));
}

QString accessibleVoiceText(int voice, const QString &displayName, VoiceFamily family, bool used)
{
    const QString visibleName = displayName.isEmpty() ? familyLabel(family) : displayName;
    QString text =
        pickerText("%1 %2, %3").arg(voiceSlotText(voice)).arg(visibleName).arg(familyLabel(family));
    if (used)
        text += QStringLiteral(", ") + pickerText("Used in this song");
    return text;
}

void drawPillBadge(QPainter *painter, const QRect &rect, const QString &text,
                   const QColor &background, const QColor &border, qreal radius)
{
    const QPen textPen = painter->pen();
    painter->save();
    painter->setRenderHint(QPainter::Antialiasing);
    painter->setBrush(background);
    painter->setPen(QPen(border, lyt::singlePixel()));
    painter->drawRoundedRect(QRectF(rect).adjusted(0, 0, -lyt::singlePixel(), -lyt::singlePixel()),
                             radius, radius);
    painter->setPen(textPen);
    painter->drawText(rect, Qt::AlignCenter, text);
    painter->restore();
}

class FacetRail final : public QWidget
{
  public:
    using QWidget::QWidget;

  protected:
    void paintEvent(QPaintEvent *) override
    {
        QPainter painter(this);
        painter.save();
        painter.fillRect(rect(), themes::color(themes::Role::song_view_timeline_chrome_background));
        painter.setPen(QPen(themes::color(themes::Role::song_view_separator), lyt::singlePixel()));
        const int edge = width() - lyt::singlePixel();
        painter.drawLine(edge, 0, edge, height());
        painter.restore();
    }
};

class CountBadge final : public QLabel
{
  public:
    CountBadge(QString text, QString accessibleName, QString accessibleDescription, QWidget *parent)
        : QLabel(parent)
        , m_text(std::move(text))
    {
        setText(m_text);
        setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);
        setAccessibleName(std::move(accessibleName));
        setAccessibleDescription(std::move(accessibleDescription));
    }

    QSize sizeHint() const override
    {
        const auto geometry = resolvePickerGeometry();
        return {QFontMetrics(font()).horizontalAdvance(m_text) + 2 * geometry.tagPadding,
                geometry.tagHeight};
    }

  protected:
    void paintEvent(QPaintEvent *) override
    {
        const auto geometry = resolvePickerGeometry();
        QPainter painter(this);
        painter.save();
        painter.setPen(themes::color(themes::Role::song_view_secondary_text));
        drawPillBadge(&painter, rect(), m_text,
                      themes::color(themes::Role::song_view_piano_roll_background),
                      themes::color(themes::Role::song_view_separator), geometry.tagRadius);
        painter.restore();
    }

  private:
    QString m_text;
};

class FamilyButton final : public QToolButton
{
  public:
    FamilyButton(std::optional<VoiceFamily> family, QString label, int count, QWidget *parent)
        : QToolButton(parent)
        , m_family(family)
        , m_label(std::move(label))
        , m_count(count)
    {
        setCheckable(true);
        setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Fixed);
        setAccessibleName(m_label);
        setAccessibleDescription(
            pickerText("%1: %2 voices").arg(m_label).arg(QString::number(m_count)));
    }

    QSize sizeHint() const override
    {
        const auto geometry = resolvePickerGeometry();
        return {geometry.railWidth - 2 * geometry.railMargin, geometry.facetRowHeight};
    }

  protected:
    void paintEvent(QPaintEvent *) override
    {
        const auto geometry = resolvePickerGeometry();
        const auto background = themes::color(themes::Role::song_view_timeline_chrome_background);
        const auto selection = themes::color(themes::Role::song_view_selection_fill);
        QPainter painter(this);
        painter.save();
        painter.fillRect(rect(), isChecked()    ? selection
                                 : underMouse() ? songview::detail::mixTowardOklabImpl(
                                                      selection, background, 0.8)
                                                : background);
        if (isChecked() || hasFocus()) {
            painter.setPen(
                QPen(themes::color(themes::Role::song_view_selection_edge), lyt::singlePixel()));
            painter.drawRect(rect().adjusted(0, 0, -lyt::singlePixel(), -lyt::singlePixel()));
        }
        const QString countText = QString::number(m_count);
        const int badgeWidth =
            QFontMetrics(font()).horizontalAdvance(countText) + 2 * geometry.tagPadding;
        const int badgeY = rect().top() + (rect().height() - geometry.tagHeight) / 2;
        const QRect badge(rect().right() - geometry.rowPadding - badgeWidth + 1, badgeY, badgeWidth,
                          geometry.tagHeight);
        painter.setPen(themes::color(themes::Role::song_view_secondary_text));
        drawPillBadge(&painter, badge, countText,
                      themes::color(themes::Role::song_view_piano_roll_background),
                      themes::color(themes::Role::song_view_separator), geometry.tagRadius);
        int labelLeft = rect().left() + geometry.rowPadding;
        if (m_family) {
            const QRect swatch(labelLeft, rect().center().y() - geometry.swatchExtent / 2,
                               geometry.swatchExtent, geometry.swatchExtent);
            painter.fillRect(swatch, familyColor(*m_family));
            painter.setPen(
                QPen(themes::color(themes::Role::song_view_separator), lyt::singlePixel()));
            painter.drawRect(swatch.adjusted(0, 0, -lyt::singlePixel(), -lyt::singlePixel()));
            labelLeft = swatch.right() + geometry.rowGap + 1;
        }
        painter.setPen(themes::color(themes::Role::song_view_primary_text));
        painter.drawText(QRect(labelLeft, rect().top(), badge.left() - geometry.rowGap - labelLeft,
                               rect().height()),
                         Qt::AlignVCenter | Qt::AlignLeft, m_label);
        painter.restore();
    }

  private:
    std::optional<VoiceFamily> m_family;
    QString m_label;
    int m_count;
};

class VoiceRowDelegate final : public QStyledItemDelegate
{
  public:
    // Owns its snapshots by value: the delegate is a QObject child of the
    // list, so it outlives the dialog's C++ members during teardown. By
    // value it can never dangle on them.
    VoiceRowDelegate(std::array<VoiceFamily, VOICEGROUP_SIZE> families, QStringList displayNames,
                     QSet<int> usedSlots, QObject *parent)
        : QStyledItemDelegate(parent)
        , m_families(std::move(families))
        , m_displayNames(std::move(displayNames))
        , m_usedSlots(std::move(usedSlots))
    {}

    VoiceRowDelegate(const VoiceRowDelegate &) = delete;
    VoiceRowDelegate &operator=(const VoiceRowDelegate &) = delete;

    void paint(QPainter *painter, const QStyleOptionViewItem &option,
               const QModelIndex &index) const override
    {
        const int voice = index.row();
        if (voice < 0 || voice >= VOICEGROUP_SIZE)
            return;
        const auto geometry = resolvePickerGeometry();
        const QRect row = option.rect;
        const bool selected = option.state & QStyle::State_Selected;
        const bool focused = option.state & QStyle::State_HasFocus;
        const auto background = selected
                                    ? themes::color(themes::Role::song_view_selection_fill)
                                    : themes::color(themes::Role::song_view_piano_roll_background);
        painter->save();
        painter->fillRect(row, background);
        painter->setPen(
            QPen(themes::color(selected || focused ? themes::Role::song_view_selection_edge
                                                   : themes::Role::song_view_separator),
                 lyt::singlePixel()));
        if (selected || focused)
            painter->drawRect(row.adjusted(0, 0, -lyt::singlePixel(), -lyt::singlePixel()));
        else
            painter->drawLine(row.left(), row.bottom(), row.right(), row.bottom());
        const VoiceFamily family = m_families[static_cast<std::size_t>(voice)];
        const bool used = m_usedSlots.contains(voice);
        const QString familyText = familyLabel(family);
        QFont tagFont = typography::caption(option.font);
        const QFontMetrics tagMetrics(tagFont);
        int right = row.right() - geometry.rowPadding;
        const auto drawTag = [&painter, &right, &geometry, &background, &tagFont, &tagMetrics,
                              &row](const QString &text, const QColor &tagColor) {
            const int width = tagMetrics.horizontalAdvance(text) + 2 * geometry.tagPadding;
            const QRect badge(right - width + 1,
                              row.top() + (row.height() - geometry.tagHeight) / 2, width,
                              geometry.tagHeight);
            painter->setFont(tagFont);
            painter->setPen(themes::color(themes::Role::song_view_primary_text));
            drawPillBadge(painter, badge, text,
                          songview::detail::mixTowardOklabImpl(tagColor, background, 0.8), tagColor,
                          geometry.tagRadius);
            right = badge.left() - geometry.tagGap - 1;
        };
        if (used)
            drawTag(pickerText("Used in this song"),
                    themes::color(themes::Role::song_view_selection_edge));
        drawTag(familyText, familyColor(family));
        const QRect slot(row.left() + geometry.rowPadding, row.top(), geometry.slotWidth,
                         row.height());
        painter->setFont(typography::tableMono(option.font));
        painter->setPen(themes::color(themes::Role::song_view_secondary_text));
        painter->drawText(slot, Qt::AlignVCenter | Qt::AlignLeft, voiceSlotText(voice));
        const int nameLeft = slot.right() + geometry.rowGap + 1;
        const QRect nameRect(nameLeft, row.top(), std::max(0, right - nameLeft + 1), row.height());
        const QString &displayName = m_displayNames.at(voice);
        if (displayName.isEmpty()) {
            const QFont unnamedFont = typography::italic(option.font);
            painter->setFont(unnamedFont);
            painter->setPen(themes::color(themes::Role::song_view_secondary_text));
            painter->drawText(
                nameRect, Qt::AlignVCenter | Qt::AlignLeft,
                QFontMetrics(unnamedFont).elidedText(familyText, Qt::ElideRight, nameRect.width()));
        } else {
            painter->setFont(option.font);
            painter->setPen(themes::color(themes::Role::song_view_primary_text));
            painter->drawText(nameRect, Qt::AlignVCenter | Qt::AlignLeft,
                              QFontMetrics(option.font)
                                  .elidedText(displayName, Qt::ElideRight, nameRect.width()));
        }
        painter->restore();
    }

    QSize sizeHint(const QStyleOptionViewItem &, const QModelIndex &) const override
    {
        return {0, resolvePickerGeometry().rowHeight};
    }

  private:
    std::array<VoiceFamily, VOICEGROUP_SIZE> m_families;
    QStringList m_displayNames;
    QSet<int> m_usedSlots;
};

} // namespace

namespace songview::detail {

VisibleRows visibleVoiceRows(const std::array<VoiceFamily, VOICEGROUP_SIZE> &families,
                             const QStringList &displayNames, const QSet<int> &usedSlots,
                             std::optional<VoiceFamily> family, bool usedOnly, bool namedOnly,
                             int currentRow)
{
    VisibleRows result;
    int firstVisible = -1;
    for (int voice = 0; voice < VOICEGROUP_SIZE; ++voice) {
        const bool visible = (!family || families[voice] == *family) &&
                             (!usedOnly || usedSlots.contains(voice)) &&
                             (!namedOnly || !displayNames.at(voice).isEmpty());
        result.rows[voice] = visible;
        if (!visible)
            continue;
        ++result.matchingCount;
        if (firstVisible < 0)
            firstVisible = voice;
    }
    result.nextRow = currentRow >= 0 && currentRow < VOICEGROUP_SIZE &&
                             result.rows[static_cast<std::size_t>(currentRow)]
                         ? currentRow
                         : firstVisible;
    return result;
}

} // namespace songview::detail

namespace songview {
using namespace songview::detail;

void VoicePickerDialog::refreshGeometry()
{
    const auto geometry = resolvePickerGeometry();
    m_dialogLayout->setContentsMargins(geometry.rootMargin, geometry.rootMargin,
                                       geometry.rootMargin, geometry.rootMargin);
    m_dialogLayout->setSpacing(geometry.rootSpacing);
    m_railLayout->setContentsMargins(geometry.railMargin, geometry.railMargin, geometry.railMargin,
                                     geometry.railMargin);
    m_railLayout->setSpacing(geometry.sectionSpacing);
    m_resultsHeaderLayout->setContentsMargins(geometry.rowPadding, geometry.sectionSpacing,
                                              geometry.rowPadding, geometry.sectionSpacing);
    m_resultsHeaderLayout->setSpacing(geometry.rowGap);
    m_facetRail->setMinimumWidth(geometry.railWidth);
    m_list->setMinimumWidth(geometry.resultColumnWidth);
    setMinimumWidth(geometry.minimumWidth);
    resize(geometry.width, geometry.height);
    m_list->doItemsLayout();
}

VoicePickerDialog::VoicePickerDialog(SongView *sv, const QString &title, int initialVoice,
                                     std::function<void(int, int)> audition,
                                     std::function<void(int)> onRowChange)
    : QDialog(sv)
    , m_audition(std::move(audition))
    , m_onRowChange(std::move(onRowChange))
{
    setWindowTitle(title);
    m_displayNames.reserve(VOICEGROUP_SIZE);
    for (int voice = 0; voice < VOICEGROUP_SIZE; ++voice) {
        m_families[static_cast<std::size_t>(voice)] = sv->voiceFamily(static_cast<uint8_t>(voice));
        m_displayNames.append(sv->voiceDisplayName(static_cast<uint8_t>(voice)));
    }
    for (const int voice : sv->usedVoices()) {
        if (voice >= 0 && voice < VOICEGROUP_SIZE)
            m_usedSlots.insert(voice);
    }

    m_dialogLayout = new QHBoxLayout(this);
    const auto geometry = resolvePickerGeometry();
    m_dialogLayout->setContentsMargins(geometry.rootMargin, geometry.rootMargin,
                                       geometry.rootMargin, geometry.rootMargin);
    m_dialogLayout->setSpacing(geometry.rootSpacing);
    m_facetRail = new FacetRail(this);
    // This custom-painted grouping needs its own accessible context; its
    // buttons describe the individual filters and their count badges.
    m_facetRail->setAccessibleName(tr("Voice filters"));
    m_facetRail->setAccessibleDescription(
        tr("Filter voices by instrument family and availability."));
    m_facetRail->setMinimumWidth(geometry.railWidth);
    m_railLayout = new QVBoxLayout(m_facetRail);
    m_railLayout->setContentsMargins(geometry.railMargin, geometry.railMargin, geometry.railMargin,
                                     geometry.railMargin);
    m_railLayout->setSpacing(geometry.sectionSpacing);
    auto *familyHeading = new QLabel(tr("Instrument family"), m_facetRail);
    auto headingFont = familyHeading->font();
    headingFont.setBold(true);
    familyHeading->setFont(headingFont);
    m_railLayout->addWidget(familyHeading);
    m_familyButtons = new QButtonGroup(this);
    m_familyButtons->setExclusive(true);
    auto *allFamilies =
        new FamilyButton(std::nullopt, tr("All families"), VOICEGROUP_SIZE, m_facetRail);
    allFamilies->setChecked(true);
    m_familyButtons->addButton(allFamilies, 0);
    m_railLayout->addWidget(allFamilies);
    for (std::size_t index = 0; index < kFamilies.size(); ++index) {
        const VoiceFamily family = kFamilies[index];
        const int count = int(std::count(m_families.cbegin(), m_families.cend(), family));
        auto *button = new FamilyButton(family, familyLabel(family), count, m_facetRail);
        m_familyButtons->addButton(button, int(index) + 1);
        m_railLayout->addWidget(button);
    }
    auto *availabilityHeading = new QLabel(tr("Availability"), m_facetRail);
    availabilityHeading->setFont(headingFont);
    m_railLayout->addWidget(availabilityHeading);
    const int namedCount = int(std::count_if(m_displayNames.cbegin(), m_displayNames.cend(),
                                             [](const QString &name) { return !name.isEmpty(); }));
    const auto addAvailability = [this](QCheckBox **check, const QString &text, int count) {
        auto *row = new QWidget(m_facetRail);
        auto *layout = new QHBoxLayout(row);
        layout->setContentsMargins(0, 0, 0, 0);
        layout->setSpacing(0);
        *check = new QCheckBox(text, row);
        layout->addWidget(*check);
        layout->addStretch(1);
        auto *badge = new CountBadge(QString::number(count),
                                     tr("%1: %2 voices").arg(text).arg(count), text, row);
        layout->addWidget(badge);
        m_railLayout->addWidget(row);
    };
    addAvailability(&m_usedOnlyCheck, tr("Used in this song"), m_usedSlots.size());
    addAvailability(&m_namedOnlyCheck, tr("Named voices only"), namedCount);
    m_railLayout->addStretch(1);

    auto *results = new QWidget(this);
    auto *resultsLayout = new QVBoxLayout(results);
    resultsLayout->setContentsMargins(0, 0, 0, 0);
    resultsLayout->setSpacing(0);
    auto *resultsHeader = new QWidget(results);
    m_resultsHeaderLayout = new QHBoxLayout(resultsHeader);
    m_resultsHeaderLayout->setContentsMargins(geometry.rowPadding, geometry.sectionSpacing,
                                              geometry.rowPadding, geometry.sectionSpacing);
    m_resultsHeaderLayout->setSpacing(geometry.rowGap);
    m_matchingCount = new QLabel(resultsHeader);
    auto matchingFont = m_matchingCount->font();
    matchingFont.setBold(true);
    m_matchingCount->setFont(matchingFont);
    m_resultsHeaderLayout->addWidget(m_matchingCount);
    m_resultsHeaderLayout->addStretch(1);
    auto *clearFilters = new QPushButton(tr("Clear filters"), resultsHeader);
    clearFilters->setFlat(true);
    m_resultsHeaderLayout->addWidget(clearFilters);
    resultsLayout->addWidget(resultsHeader);
    m_list = new QListWidget(results);
    m_list->setUniformItemSizes(true);
    m_list->setSelectionMode(QAbstractItemView::SingleSelection);
    m_list->setFocusPolicy(Qt::StrongFocus);
    m_list->setToolTip(tr("Click and hold to audition (middle C)."));
    m_list->setMinimumWidth(geometry.resultColumnWidth);
    m_list->setItemDelegate(new VoiceRowDelegate(m_families, m_displayNames, m_usedSlots, m_list));
    for (int voice = 0; voice < VOICEGROUP_SIZE; ++voice) {
        auto *item = new QListWidgetItem;
        item->setData(Qt::AccessibleTextRole,
                      accessibleVoiceText(voice, m_displayNames.at(voice),
                                          m_families[static_cast<std::size_t>(voice)],
                                          m_usedSlots.contains(voice)));
        m_list->addItem(item);
    }
    resultsLayout->addWidget(m_list, 1);
    m_emptyState =
        new QLabel(tr("No voices match this view. Clear a filter to return to the 128-slot "
                      "voicegroup."),
                   results);
    m_emptyState->setAlignment(Qt::AlignCenter);
    m_emptyState->setWordWrap(true);
    auto emptyStatePalette = m_emptyState->palette();
    emptyStatePalette.setColor(QPalette::WindowText,
                               themes::color(themes::Role::song_view_secondary_text));
    m_emptyState->setPalette(emptyStatePalette);
    m_emptyState->setVisible(false);
    resultsLayout->addWidget(m_emptyState, 1);
    auto *dialogButtons =
        new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, results);
    m_okButton = dialogButtons->button(QDialogButtonBox::Ok);
    connect(dialogButtons, &QDialogButtonBox::accepted, this, &QDialog::accept);
    connect(dialogButtons, &QDialogButtonBox::rejected, this, &QDialog::reject);
    resultsLayout->addWidget(dialogButtons);
    m_dialogLayout->addWidget(m_facetRail);
    m_dialogLayout->addWidget(results, 1);
    setMinimumWidth(geometry.minimumWidth);
    resize(geometry.width, geometry.height);

    connect(m_familyButtons, &QButtonGroup::idClicked, this, [this](int id) {
        m_family = id == 0
                       ? std::nullopt
                       : std::optional<VoiceFamily>(kFamilies[static_cast<std::size_t>(id - 1)]);
        refreshVisibility();
    });
    connect(m_usedOnlyCheck, &QCheckBox::toggled, this, [this](bool checked) {
        m_usedOnly = checked;
        refreshVisibility();
    });
    connect(m_namedOnlyCheck, &QCheckBox::toggled, this, [this](bool checked) {
        m_namedOnly = checked;
        refreshVisibility();
    });
    connect(clearFilters, &QPushButton::clicked, this, &VoicePickerDialog::clearFilters);
    {
        // No construction path may project a voice into the live edit session.
        // Keep every initial current-row mutation in this scope; the observer
        // is deliberately connected last below.
        const QSignalBlocker constructionSelectionBlocker(m_list);
        m_list->setCurrentRow(std::clamp(initialVoice, 0, VOICEGROUP_SIZE - 1));
        m_list->scrollToItem(m_list->currentItem(), QAbstractItemView::PositionAtCenter);
        refreshVisibility();
    }
    m_list->setFocus();
    connect(m_list, &QListWidget::itemPressed, this, [this](QListWidgetItem *item) {
        releaseVoice();
        if (item) {
            m_sounding = m_list->row(item);
            m_audition(m_sounding, kVoiceAuditionVel);
        }
    });
    connect(m_list, &QListWidget::itemDoubleClicked, this, [this] { accept(); });
    m_list->viewport()->installEventFilter(this);
    installEventFilter(this); // hide, deactivate, and close also end audition
    // This is the last current-row setup: opening the dialog must not select
    // a voice, while every later filter-driven replacement must project it.
    connect(m_list, &QListWidget::currentRowChanged, this, [this](int row) {
        if (row >= 0 && row < VOICEGROUP_SIZE && m_onRowChange)
            m_onRowChange(row);
    });
}

VoicePickerDialog::~VoicePickerDialog()
{
    releaseVoice();
}

int VoicePickerDialog::selectedVoice() const
{
    // -1 when the view has no visible selection; callers gate commits on it.
    const int row = m_list->currentRow();
    return row >= 0 && row < VOICEGROUP_SIZE ? row : -1;
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
    // releaseVoice() no-ops while nothing sounds, so fire it on every event
    // that can end the press-and-hold: a release anywhere (the mouse grab
    // returns releases to the viewport; the dialog self-filter covers the
    // rest) and the deactivate/hide/close paths that would otherwise drone
    // until destruction.
    if (event->type() == QEvent::MouseButtonRelease || event->type() == QEvent::WindowDeactivate ||
        event->type() == QEvent::Hide || event->type() == QEvent::Close)
        releaseVoice();
    return QDialog::eventFilter(watched, event);
}

void VoicePickerDialog::accept()
{
    // Ok is inert on a zero-match view: the button box, Enter, and the
    // double-click path all land here, and none may close the dialog as
    // Accepted without a visible selection.
    if (selectedVoice() < 0)
        return;
    releaseVoice();
    m_onRowChange = nullptr; // the live projection ends with the modal run
    QDialog::accept();
}

void VoicePickerDialog::reject()
{
    releaseVoice();
    m_onRowChange = nullptr; // the live projection ends with the modal run
    QDialog::reject();
}

void VoicePickerDialog::refreshVisibility()
{
    const auto visible = visibleVoiceRows(m_families, m_displayNames, m_usedSlots, m_family,
                                          m_usedOnly, m_namedOnly, m_list->currentRow());
    for (int voice = 0; voice < VOICEGROUP_SIZE; ++voice)
        m_list->item(voice)->setHidden(!visible.rows[static_cast<std::size_t>(voice)]);
    m_matchingCount->setText(tr("%1 matching voices").arg(visible.matchingCount));
    const bool hasVisibleRows = visible.nextRow >= 0;
    m_okButton->setEnabled(hasVisibleRows);
    m_emptyState->setVisible(!hasVisibleRows);
    m_list->setVisible(hasVisibleRows);
    if (!hasVisibleRows) {
        m_list->setCurrentItem(nullptr);
        return;
    }
    if (m_list->currentRow() != visible.nextRow)
        m_list->setCurrentRow(visible.nextRow);
}

void VoicePickerDialog::clearFilters()
{
    m_family.reset();
    m_usedOnly = false;
    m_namedOnly = false;
    const QSignalBlocker familyButtonsBlocker(m_familyButtons);
    m_familyButtons->button(0)->setChecked(true);
    const QSignalBlocker usedOnlyBlocker(m_usedOnlyCheck);
    const QSignalBlocker namedOnlyBlocker(m_namedOnlyCheck);
    m_usedOnlyCheck->setChecked(false);
    m_namedOnlyCheck->setChecked(false);
    refreshVisibility();
}

void VoicePickerDialog::releaseVoice()
{
    if (m_sounding < 0)
        return;
    m_audition(m_sounding, 0);
    m_sounding = -1;
}

} // namespace songview
