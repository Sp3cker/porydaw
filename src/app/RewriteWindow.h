#pragma once

#include <QMainWindow>
#include <QPointer>
#include <QString>

#include <functional>
#include <memory>

#include <vector>
class QAction;
class QCloseEvent;
class QEvent;
class QKeyEvent;
class QObject;
class QQmlEngine;
class QMenu;
class QQuickView;
class QSettings;
class QWidget;

namespace themes {
class ThemeController;
}

class RewriteWindow final : public QMainWindow
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(RewriteWindow)

  public:
    explicit RewriteWindow(QWidget *parent = nullptr);
    ~RewriteWindow() override;

    bool isReady() const { return m_session != nullptr; }
    void openStartup(const QString &projectPath, const QString &songLabel);
    QObject *sessionObject() const { return m_session; }
    QQuickView *gridView() const;

  protected:
    void closeEvent(QCloseEvent *event) override;
    bool eventFilter(QObject *watched, QEvent *event) override;

  private slots:
    void chooseProject();
    void chooseSong();
    void save();
    void undo();
    void redo();
    void playPause();
    void stop();
    void handleSaveStateChanged();
    void handleSongOpenChanged();
    void detachGridScene();
    void showGridContextMenu(double x, double y);
    void updateWindowActions();
    void updateGridActions();
    void handleOpenFailed(const QString &message);
    void handleOperationFailed(const QString &message);

  private:
    enum class DirtyDecision { Save, Discard, Cancel };
    struct GridAction {
        QString keymap;
        int command = -1;
        QAction *action = nullptr;
    };

    DirtyDecision askDirtyDecision(const QString &title);
    bool documentDirty() const;
    bool saveInProgress() const;
    QString saveError() const;
    void invokeOpenProject(const QString &path, bool discardChanges);
    void invokeOpenSong(const QString &label, bool discardChanges);
    void runAfterDirtyGate(QString title, std::function<void(bool)> operation);
    void requestSaveThen(std::function<void()> completion);
    void invokeNoArgs(const char *method);
    void attachGridScene();
    void applyGridPalette();
    void addGridActions(QMenu &menu);
    bool routeGridKey(QKeyEvent *event);
    bool handleGridEscape();
    void invokeGridCommand(int command);
    bool connectPropertyNotify(const char *property, const char *slot);
    bool connectSessionSignal(const char *signal, const char *slot);
    void deliverInputCancel(int reason);

    std::unique_ptr<QQmlEngine> m_engine;
    QObject *m_session = nullptr;
    QPointer<QQuickView> m_quickView;
    QPointer<QWidget> m_sceneContainer;
    QPointer<QWidget> m_placeholder;
    std::unique_ptr<QSettings> m_settings;
    std::unique_ptr<themes::ThemeController> m_themeController;
    QAction *m_openProjectAction = nullptr;
    QAction *m_openSongAction = nullptr;
    QAction *m_saveAction = nullptr;
    QAction *m_undoAction = nullptr;
    QAction *m_redoAction = nullptr;
    QAction *m_playPauseAction = nullptr;
    QAction *m_stopAction = nullptr;
    std::vector<GridAction> m_gridActions;
    QMenu *m_gridContextMenu = nullptr;
    std::function<void()> m_afterSave;
    bool m_isClosing = false;
};
