#pragma once

#include <QString>
#include <array>
#include <memory>

#include <QObject>
#include <QPoint>
#include <QPointF>
#include <QPointer>
#include <Qt>

#include "project/voicegroupsource.h"

class QQuickItem;
class QQuickWindow;
class QPointingDevice;
class SongTab;
class SongView;

class ScrollbarTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(ScrollbarTest)

  public:
    ScrollbarTest(const QString &projectRoot, const QString &songLabel);
    ~ScrollbarTest() override;

  protected:
    SongView &view();
    QQuickWindow &window();
    QQuickItem &bar(Qt::Orientation orientation);
    QQuickItem &thumb(Qt::Orientation orientation);
    void press(QPointF windowPosition);
    void move(QPointF windowPosition);
    void release();
    QPointF beginDrag(Qt::Orientation orientation);
    void wheel(Qt::Orientation orientation, QPoint pixel, QPoint angle, bool inverted = false,
               bool touchpad = false);
    void endWheel(Qt::Orientation orientation, bool touchpad = false);
    bool withinTrack(Qt::Orientation orientation);

  private slots:
    void init();
    void cleanup();

    void automationLabelActivatesAfterResize();
    void signedRangeDragRebasesAndTracksModel();

    void trackPaging_data();
    void trackPaging();
    void wheelScrolling_data();
    void wheelScrolling();
    void keyboardNavigation_data();
    void keyboardNavigation();

    void layoutFollowsCanonicalBands();
    void scrollbarHostContainsBothTracks();
    void dragClampsAndReverses_data();
    void dragClampsAndReverses();
    void dragRebasesAfterZoom();
    void dragRebasesAfterResize();
    void foldingDisablesAndRestoresRollDrag();
    void drawerResizeFollowsRollBand();
    void eventListHidesOnlyRollScrollbar();
    void externalCameraMovesReleasedThumb_data();
    void externalCameraMovesReleasedThumb();

  private:
    struct WheelSession final {
        QPointF position;
        bool active = false;
        bool touchpad = false;
    };

    static constexpr int orientationIndex(Qt::Orientation orientation)
    {
        return orientation == Qt::Horizontal ? 0 : 1;
    }

    QString m_projectRoot;
    QString m_songLabel;

    // The tab borrows this value-owned bank, so it must outlive m_tab.
    // Declaration order makes the tab die first during cleanup.
    LoadedVoiceGroup m_bank = {};
    std::unique_ptr<SongTab> m_tab;
    QPointer<QQuickWindow> m_window;
    QPointer<QQuickItem> m_root;
    QPointer<QQuickItem> m_horizontalBar;
    QPointer<QQuickItem> m_horizontalThumb;
    QPointer<QQuickItem> m_verticalBar;
    QPointer<QQuickItem> m_verticalThumb;
    std::unique_ptr<QPointingDevice> m_touchpad;
    Qt::MouseButton m_heldButton = Qt::NoButton;
    QPointF m_lastWindowPosition;
    std::array<WheelSession, 2> m_wheelSessions;
};
