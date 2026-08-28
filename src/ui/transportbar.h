#pragma once

#include <QString>
#include <QToolBar>

#include "porydaw_scale.h"

class QAction;
class QComboBox;
class QDial;
class QEvent;
class QLabel;
class QToolButton;
class QSpinBox;

class TransportBar final : public QToolBar
{
    Q_OBJECT

  public:
    enum class PlaybackState { Unavailable, Stopped, Paused, Playing };

    explicit TransportBar(QWidget *parent = nullptr);

    QAction *playPauseAction() const { return m_playPauseAction; }
    QAction *followPlayheadAction() const { return m_followPlayheadAction; }
    QAction *resonanceAction() const { return m_resonanceAction; }
    bool followPlayhead() const;

    void setPlaybackState(PlaybackState state);
    void setSessionAvailable(bool available);
    void setFollowPlayhead(bool enabled);
    void setTimeText(const QString &text);
    void setMasterVolume(int value, bool enabled);
    void setOutputVolume(int value);
    void setScaleState(int root, porydaw_scale::ScaleId scale, bool highlight, bool fold);

  signals:
    void goToStartRequested();
    void playRequested();
    void playPauseRequested();
    void pauseRequested();
    void stopRequested();
    void loopEnabledChanged(bool enabled);
    void followPlayheadChanged(bool enabled);
    void resonanceSuppressionChanged(bool enabled);
    void masterVolumeChanged(int value);
    void outputVolumeChanged(int value);
    void scaleRootChanged(int root);
    void scaleIdChanged(porydaw_scale::ScaleId scale);
    void scaleHighlightChanged(bool enabled);
    void scaleFoldChanged(bool enabled);

  protected:
    void changeEvent(QEvent *event) override;
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    void refreshIcons();

    QAction *m_goToStartAction = nullptr;
    QAction *m_playAction = nullptr;
    QAction *m_playPauseAction = nullptr;
    QAction *m_pauseAction = nullptr;
    QAction *m_stopAction = nullptr;
    QAction *m_loopAction = nullptr;
    QAction *m_followPlayheadAction = nullptr;
    QAction *m_resonanceAction = nullptr;
    QLabel *m_timeLabel = nullptr;
    QComboBox *m_rootCombo = nullptr;
    QComboBox *m_scaleCombo = nullptr;
    QToolButton *m_highlightButton = nullptr;
    QToolButton *m_foldButton = nullptr;
    QLabel *m_masterVolCaption = nullptr;
    QSpinBox *m_masterVolSpin = nullptr;
    QLabel *m_outputVolumeCaption = nullptr;
    QDial *m_outputVolumeDial = nullptr;
    QString m_lastTimeText;
};
