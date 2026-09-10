#include "ui/fastlabel.h"

#include <QPainter>

#include "ui/theme/themeruntime.h"
#include "ui/typography.h"

FastLabel::FastLabel(const QString &widestText, Qt::Alignment alignment, const QMargins &margins,
                     themes::Role textRole, QWidget *parent)
    : QWidget(parent)
    , m_alignment(alignment)
    , m_margins(margins)
    , m_textRole(textRole)
{
    const QFontMetrics metrics(typography::bodyMono(font()));
    m_hint = QSize(metrics.horizontalAdvance(widestText) + margins.left() + margins.right(),
                   metrics.height() + margins.top() + margins.bottom());
    // Hard-clamp the reserved strip: min = max = hint, so the surrounding
    // layout reserves exactly the widest text and can neither compress nor
    // stretch the label (QToolBar would otherwise grow it into spare space).
    setFixedWidth(m_hint.width());
}

void FastLabel::setText(const QString &text)
{
    if (m_text == text)
        return;
    m_text = text;
    update();
}

QSize FastLabel::minimumSizeHint() const
{
    return m_hint;
}

void FastLabel::changeEvent(QEvent *event)
{
    QWidget::changeEvent(event);
    switch (event->type()) {
    case QEvent::ApplicationPaletteChange:
    case QEvent::PaletteChange:
    case QEvent::StyleChange:
    case QEvent::ThemeChange:
        // Role colors are resolved at paint time rather than stored in the
        // widget palette, so static text must repaint when appearance changes.
        update();
        break;
    default:
        break;
    }
}

QSize FastLabel::sizeHint() const
{
    return m_hint;
}

void FastLabel::paintEvent(QPaintEvent * /*event*/)
{
    QPainter painter(this);
    painter.setFont(typography::bodyMono(font()));
    if (m_background)
        painter.fillRect(rect(), themes::color(*m_background));
    painter.setPen(themes::color(m_textRole));
    painter.drawText(rect().marginsRemoved(m_margins), m_alignment, m_text);
}
