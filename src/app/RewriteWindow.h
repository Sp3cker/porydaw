#pragma once

#include <QMainWindow>

#include <functional>
#include <memory>

class QAction;
class QCloseEvent;
class QObject;
class QQmlEngine;
class QSettings;

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

  protected:
    void closeEvent(QCloseEvent *event) override;

  private slots:
    void chooseProject();
    void chooseSong();
    void save();
    void undo();
    void redo();
    void playPause();
    void stop();
    void handleSaveStateChanged();

  private:
    enum class DirtyDecision { Save, Discard, Cancel };

    DirtyDecision askDirtyDecision(const QString &title);
    bool documentDirty() const;
    bool saveInProgress() const;
    QString saveError() const;
    void invokeOpenProject(const QString &path, bool discardChanges);
    void invokeOpenSong(const QString &label, bool discardChanges);
    void runAfterDirtyGate(QString title, std::function<void(bool)> operation);
    void requestSaveThen(std::function<void()> completion);
    void invokeNoArgs(const char *method);

    std::unique_ptr<QQmlEngine> m_engine;
    QObject *m_session = nullptr;
    std::unique_ptr<QSettings> m_settings;
    std::unique_ptr<themes::ThemeController> m_themeController;
    QAction *m_openProjectAction = nullptr;
    QAction *m_openSongAction = nullptr;
    QAction *m_saveAction = nullptr;
    QAction *m_undoAction = nullptr;
    QAction *m_redoAction = nullptr;
    QAction *m_playPauseAction = nullptr;
    QAction *m_stopAction = nullptr;
    std::function<void()> m_afterSave;
};
