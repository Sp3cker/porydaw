#pragma once

#include <QFont>
#include <QFontMetrics>
#include <QPoint>
#include <QPointF>
#include <QRect>
#include <QString>
#include <QWidget>
#include <optional>

#include "ui/layout.h"

class QContextMenuEvent;
class QEvent;
class QKeyEvent;
class QLineEdit;
class QMouseEvent;
class QPaintEvent;
class QResizeEvent;
class QPoint;
class QToolButton;
class SongView;

namespace songview {

class TrackHeaderPanel;

class TrackHeaderRow : public QWidget
{
  private:
    enum class SelectionState {
        None,
        InScope,
        Primary,
    };

    struct Geometry {
        int trackHeaderButtonExtent;
        int trackHeaderRowHeight;
        int trackHeaderButtonColumnWidth;
        int trackHeaderVoiceLineLeft;
        int trackHeaderVoiceLineTop;
        int trackHeaderVoiceLineRight;
        int trackHeaderVoiceLineHeight;
        int trackHeaderTextLeft;
        int trackHeaderRenameEditorLeft;
        int trackHeaderRenameEditorTop;
        int trackHeaderRenameEditorRight;
        int trackHeaderRenameEditorHeight;

        static Geometry resolve();
    };

    void refreshGeometry();
    void rebuildFontCache();

  public:
    TrackHeaderRow(SongView *sv, int track, QWidget *parent);
    // Sole row-height formula; the panel's activity overlay consumes it too.
    static int resolvedHeight();
    int track() const;
    bool exceedsProjectTrackBudget() const;
    void syncVoice();
    void updateToolTip();
    void beginRename();
    void commitOpenRename();

  protected:
    void paintEvent(QPaintEvent *) override;
    QRect voiceLineRect() const;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void mouseDoubleClickEvent(QMouseEvent *event) override;
    void contextMenuEvent(QContextMenuEvent *event) override;
    bool eventFilter(QObject *watched, QEvent *event) override;
    bool event(QEvent *event) override;
    void resizeEvent(QResizeEvent *) override;

  private:
    friend class TrackHeaderPanel;
    void cancelRename();
    QString fallbackTrackName() const;
    void resyncSong();
    SelectionState selectionState() const;
    QRect editorRect() const;
    QRect textColumnRect() const;
    void finishRename(bool commit, bool restoreFocus);
    void updateVisibleTitleCenteringCache(const QString &visibleTitle);

    QFont m_normalTitleFont;
    QFont m_boldTitleFont;
    QFont m_subtitleFont;
    QFontMetrics m_normalTitleMetrics{QFont{}};
    QFontMetrics m_boldTitleMetrics{QFont{}};
    QFontMetrics m_subtitleMetrics{QFont{}};
    std::optional<layout::TwoLineTextLayout> m_textLayout;
    QString m_centeredTitle;
    QPointF m_selectedTitleOffset;
    SongView *m_sv;
    int m_track;
    Geometry m_geometry;
    QToolButton *m_mute;
    QToolButton *m_solo;
    QLineEdit *m_editor = nullptr;
    bool m_finishing = false;
    // Program painted on the voice line, for syncVoice's changed check
    // (-2 = never painted; distinct from -1, "no voice set").
    int m_shownProgram = -2;
    std::optional<SelectionState> m_paintedSelection;
    QPoint m_pressPos;
    bool m_dragArmed = false;
    bool m_dragging = false;
    bool m_voiceClickArmed = false;
};

} // namespace songview
