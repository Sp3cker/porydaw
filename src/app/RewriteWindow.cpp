#include "app/RewriteWindow.h"

#include "app/native_host.h"
#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/theme/themecontroller.h"

#include <QAction>
#include <QApplication>
#include <QCloseEvent>
#include <QFileDialog>
#include <QInputDialog>
#include <QLabel>
#include <QMenu>
#include <QMenuBar>
#include <QMessageBox>
#include <QMetaObject>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QSettings>
#include <QStatusBar>
#include <QStringList>
#include <QUrl>

#include <utility>

RewriteWindow::RewriteWindow(QWidget *parent)
    : QMainWindow(parent)
    , m_settings(std::make_unique<QSettings>())
    , m_themeController(std::make_unique<themes::ThemeController>(*qApp, *m_settings))
{
    pd_app_register_types();
    m_engine = std::make_unique<QQmlEngine>();
    m_themeController->restore();

    QQmlComponent component(m_engine.get());
    component.setData("import PorydawApp\nApplicationSession {}\n", QUrl());
    m_session = component.create();
    if (!m_session) {
        const QString detail = component.errorString();
        auto *label =
            new QLabel(tr("The application session could not start.\n%1").arg(detail), this);
        label->setAlignment(Qt::AlignCenter);
        setCentralWidget(label);
        return;
    }
    QQmlEngine::setObjectOwnership(m_session, QQmlEngine::CppOwnership);
    m_session->setParent(this);
    connect(m_session, SIGNAL(saveInProgressChanged()), this, SLOT(handleSaveStateChanged()));

    auto *fileMenu = menuBar()->addMenu(tr("&File"));
    m_openProjectAction =
        fileMenu->addAction(tr("Open Project…"), this, &RewriteWindow::chooseProject);
    keymap::Registry::instance().attach(QStringLiteral("file.open_project"), m_openProjectAction);
    m_openSongAction = fileMenu->addAction(tr("Open Song…"), this, &RewriteWindow::chooseSong);
    keymap::Registry::instance().attach(QStringLiteral("songs.find"), m_openSongAction);
    fileMenu->addSeparator();
    m_saveAction = fileMenu->addAction(tr("Save"), this, &RewriteWindow::save);
    keymap::Registry::instance().attach(QStringLiteral("file.save_song"), m_saveAction);
    auto *quitAction = fileMenu->addAction(tr("Quit"), qApp, &QApplication::closeAllWindows);
    keymap::Registry::instance().attach(QStringLiteral("file.quit"), quitAction);

    auto *editMenu = menuBar()->addMenu(tr("&Edit"));
    m_undoAction = editMenu->addAction(tr("Undo"), this, &RewriteWindow::undo);
    keymap::Registry::instance().attach(QStringLiteral("edit.undo"), m_undoAction);
    m_redoAction = editMenu->addAction(tr("Redo"), this, &RewriteWindow::redo);
    keymap::Registry::instance().attach(QStringLiteral("edit.redo"), m_redoAction);

    auto *transportMenu = menuBar()->addMenu(tr("&Transport"));
    m_playPauseAction = transportMenu->addAction(tr("Play/Pause"), this, &RewriteWindow::playPause);
    keymap::Registry::instance().attach(QStringLiteral("transport.play_pause"), m_playPauseAction);
    m_stopAction = transportMenu->addAction(tr("Stop"), this, &RewriteWindow::stop);
    keymap::Registry::instance().attach(QStringLiteral("transport.stop"), m_stopAction);

    auto *message = new QLabel(tr("Open a project and song to play with the Swift core."), this);
    message->setAlignment(Qt::AlignCenter);
    message->setMargin(layout::space(layout::Space::Two));
    setCentralWidget(message);
    statusBar()->showMessage(tr("Ready"));
    resize(layout::fontPx(72), layout::fontPx(48));
    setWindowTitle(tr("Porydaw"));
}

RewriteWindow::~RewriteWindow()
{
    delete m_session;
    m_session = nullptr;
}

void RewriteWindow::openStartup(const QString &projectPath, const QString &songLabel)
{
    if (!m_session || projectPath.isEmpty())
        return;
    if (songLabel.isEmpty()) {
        invokeOpenProject(projectPath, false);
        return;
    }
    QMetaObject::invokeMethod(m_session, "openProjectAndSong", Q_ARG(QString, projectPath),
                              Q_ARG(QString, songLabel));
}

void RewriteWindow::chooseProject()
{
    const QString path = QFileDialog::getExistingDirectory(this, tr("Open Project"));
    if (path.isEmpty())
        return;
    runAfterDirtyGate(tr("Open Project"),
                      [this, path](bool discard) { invokeOpenProject(path, discard); });
}

void RewriteWindow::chooseSong()
{
    if (!m_session)
        return;
    int count = 0;
    QMetaObject::invokeMethod(m_session, "songCount", Q_RETURN_ARG(int, count));
    QStringList labels;
    labels.reserve(count);
    for (int index = 0; index < count; ++index) {
        QString label;
        QMetaObject::invokeMethod(m_session, "songLabel", Q_RETURN_ARG(QString, label),
                                  Q_ARG(int, index));
        if (!label.isEmpty())
            labels.append(label);
    }
    if (labels.isEmpty()) {
        QMessageBox::information(this, tr("Open Song"), tr("The project has no playable songs."));
        return;
    }
    bool accepted = false;
    const QString label =
        QInputDialog::getItem(this, tr("Open Song"), tr("Song:"), labels, 0, false, &accepted);
    if (!accepted)
        return;
    runAfterDirtyGate(tr("Open Song"),
                      [this, label](bool discard) { invokeOpenSong(label, discard); });
}

void RewriteWindow::save()
{
    invokeNoArgs("requestSave");
}

void RewriteWindow::undo()
{
    invokeNoArgs("requestUndo");
}

void RewriteWindow::redo()
{
    invokeNoArgs("requestRedo");
}

void RewriteWindow::playPause()
{
    invokeNoArgs("playPause");
}

void RewriteWindow::stop()
{
    invokeNoArgs("stop");
}

void RewriteWindow::closeEvent(QCloseEvent *event)
{
    if (!documentDirty()) {
        event->accept();
        return;
    }
    switch (askDirtyDecision(tr("Close Porydaw"))) {
    case DirtyDecision::Discard:
        event->accept();
        return;
    case DirtyDecision::Cancel:
        event->ignore();
        return;
    case DirtyDecision::Save:
        event->ignore();
        requestSaveThen([this] { close(); });
        return;
    }
}

RewriteWindow::DirtyDecision RewriteWindow::askDirtyDecision(const QString &title)
{
    QMessageBox box(QMessageBox::Warning, title, tr("The current song has unsaved changes."),
                    QMessageBox::Save | QMessageBox::Discard | QMessageBox::Cancel, this);
    box.setDefaultButton(QMessageBox::Save);
    const auto result = QMessageBox::StandardButton(box.exec());
    if (result == QMessageBox::Save)
        return DirtyDecision::Save;
    if (result == QMessageBox::Discard)
        return DirtyDecision::Discard;
    return DirtyDecision::Cancel;
}

bool RewriteWindow::documentDirty() const
{
    bool dirty = false;
    if (m_session)
        QMetaObject::invokeMethod(m_session, "isDocumentDirty", Q_RETURN_ARG(bool, dirty));
    return dirty;
}

bool RewriteWindow::saveInProgress() const
{
    return m_session && m_session->property("saveInProgress").toBool();
}

QString RewriteWindow::saveError() const
{
    return m_session ? m_session->property("lastSaveError").toString() : QString();
}

void RewriteWindow::invokeOpenProject(const QString &path, bool discardChanges)
{
    QMetaObject::invokeMethod(m_session, "openProject", Q_ARG(QString, path),
                              Q_ARG(bool, discardChanges));
}

void RewriteWindow::invokeOpenSong(const QString &label, bool discardChanges)
{
    QMetaObject::invokeMethod(m_session, "openSong", Q_ARG(QString, label),
                              Q_ARG(bool, discardChanges));
}

void RewriteWindow::runAfterDirtyGate(QString title, std::function<void(bool)> operation)
{
    if (!documentDirty()) {
        operation(false);
        return;
    }
    switch (askDirtyDecision(title)) {
    case DirtyDecision::Discard:
        operation(true);
        break;
    case DirtyDecision::Cancel:
        break;
    case DirtyDecision::Save:
        requestSaveThen([operation = std::move(operation)] { operation(false); });
        break;
    }
}

void RewriteWindow::requestSaveThen(std::function<void()> completion)
{
    if (saveInProgress())
        return;
    m_afterSave = std::move(completion);
    invokeNoArgs("requestSave");
}

void RewriteWindow::handleSaveStateChanged()
{
    if (saveInProgress())
        return;
    if (!saveError().isEmpty()) {
        m_afterSave = {};
        QMessageBox::critical(this, tr("Save Failed"), saveError());
        return;
    }
    if (documentDirty())
        return;
    auto completion = std::move(m_afterSave);
    m_afterSave = {};
    if (completion)
        completion();
}

void RewriteWindow::invokeNoArgs(const char *method)
{
    if (m_session)
        QMetaObject::invokeMethod(m_session, method);
}
