#pragma once

#include <QMargins>
#include <QWidget>

#include <optional>

#include "ui/theme/theme_roles.h"

/// Layout-inert text display for chrome that updates at playback cadence
/// (transport clock, polyphony counts). Changing QLabel text calls
/// updateGeometry(), whose propagation re-activates ancestor layouts up to
/// QMainWindowLayout — at 10 Hz that repainted the full status bar and dock
/// gaps every tick. FastLabel paints its text directly and calls only update();
/// unchanged text is an early-out. Its size hint is fixed at construction from
/// the widest expected text, so ancestor layouts stay stable across updates.
class FastLabel final : public QWidget
{
    Q_OBJECT

  public:
    FastLabel(const QString &widestText, Qt::Alignment alignment, const QMargins &margins,
              themes::Role textRole, QWidget *parent);

    void setText(const QString &text);
    void clear() { setText(QString()); }
    QString text() const { return m_text; }
    /// Paints the shared field background under the text (e.g. the polyphony
    /// value wells); unset leaves the parent surface visible.
    void setFieldBackground(themes::Role role)
    {
        if (m_background == role)
            return;
        m_background = role;
        update();
    }

    QSize sizeHint() const override;
    /// Mirrors sizeHint so layouts cannot compress the label below its widest
    /// expected text under a crowded toolbar or status bar.
    QSize minimumSizeHint() const override;

  protected:
    void changeEvent(QEvent *event) override;
    void paintEvent(QPaintEvent *event) override;

  private:
    QString m_text;
    const Qt::Alignment m_alignment;
    const QMargins m_margins;
    const themes::Role m_textRole;
    std::optional<themes::Role> m_background;
    QSize m_hint;
};
