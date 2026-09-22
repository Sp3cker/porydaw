#include "app/RewriteWindow.h"

#include "app/native_host.h"
#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/theme/color_math.h"
#include "ui/theme/themecontroller.h"
#include "ui/theme/themeruntime.h"

#include <QAction>
#include <QApplication>
#include <QByteArray>
#include <QClipboard>
#include <QCloseEvent>
#include <QColor>
#include <QCursor>
#include <QEvent>
#include <QFileDialog>
#include <QInputDialog>
#include <QKeyEvent>
#include <QLabel>
#include <QMenu>
#include <QMenuBar>
#include <QMessageBox>
#include <QMetaMethod>
#include <QMetaObject>
#include <QMetaProperty>
#include <QMimeData>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlError>
#include <QQuickItem>
#include <QQuickView>
#include <QSettings>
#include <QStatusBar>
#include <QStringList>
#include <QThread>
#include <QUrl>

#include <iterator>
#include <limits>

namespace {

constexpr auto kClipMimeType = "application/x-porydaw-clip";
constexpr int kSelectionFillAlpha = 30;

QString hexColor(const QColor &color)
{
    return color.name(color.alpha() == 255 ? QColor::HexRgb : QColor::HexArgb);
}

QColor withRelativeAlpha(themes::Role role, int alpha)
{
    auto color = themes::color(role);
    color.setAlpha((color.alpha() * alpha + 127) / 255);
    return color;
}

QColor mixToward(const QColor &from, const QColor &to, double amount)
{
    const themes::Oklab a = themes::oklabFromColor(from);
    const themes::Oklab b = themes::oklabFromColor(to);
    return themes::colorFromOklab({a.lightness + (b.lightness - a.lightness) * amount,
                                   a.a + (b.a - a.a) * amount, a.b + (b.b - a.b) * amount});
}

QLabel *makePlaceholder(const QString &text, QWidget *parent)
{
    auto *label = new QLabel(text, parent);
    label->setAlignment(Qt::AlignCenter);
    label->setMargin(layout::space(layout::Space::Two));
    return label;
}

bool quickFocusOwnsLocalKeys(QQuickView *view)
{
    QQuickItem *const focus = view ? view->activeFocusItem() : nullptr;
    if (!focus || focus == view->contentItem() || focus == view->rootObject())
        return false;
    for (QQuickItem *item = focus; item; item = item->parentItem()) {
        if (item->objectName() == QLatin1String("swiftRollInput"))
            return false;
    }
    return focus->property("activeFocusOnTab").toBool() || focus->property("modal").toBool() ||
           focus->metaObject()->indexOfProperty("text") >= 0;
}
} // namespace

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
        m_placeholder = makePlaceholder(
            tr("The application session could not start.\n%1").arg(component.errorString()), this);
        setCentralWidget(m_placeholder);
        return;
    }
    QQmlEngine::setObjectOwnership(m_session, QQmlEngine::CppOwnership);
    m_session->setParent(this);
    applyGridPalette();

    if (!connectPropertyNotify("projectOpen", "updateWindowActions()"))
        qWarning("host-contract: projectOpen notify missing");
    if (!connectPropertyNotify("saveInProgress", "handleSaveStateChanged()"))
        qWarning("host-contract: saveInProgress notify missing");
    if (!connectPropertyNotify("songOpen", "handleSongOpenChanged()"))
        qWarning("host-contract: songOpen notify missing");
    if (!connectPropertyNotify("canUndo", "updateWindowActions()"))
        qWarning("host-contract: canUndo notify missing");
    if (!connectPropertyNotify("canRedo", "updateWindowActions()"))
        qWarning("host-contract: canRedo notify missing");
    if (!connectSessionSignal("aboutToReleaseGrid()", "detachGridScene()"))
        qWarning("host-contract: aboutToReleaseGrid missing");
    if (!connectSessionSignal("openFailed(QString)", "handleOpenFailed(QString)"))
        qWarning("host-contract: openFailed missing");
    if (!connectSessionSignal("operationFailed(QString)", "handleOperationFailed(QString)"))
        qWarning("host-contract: operationFailed missing");
    if (!connectSessionSignal("gridContextMenuRequested(double,double)",
                              "showGridContextMenu(double,double)"))
        qWarning("host-contract: gridContextMenuRequested missing");
    if (!connectSessionSignal("gridCommandAvailabilityChanged()", "updateGridActions()"))
        qWarning("host-contract: gridCommandAvailabilityChanged missing");
    if (!connectSessionSignal("allTabsClosed()", "handleAllTabsClosed()"))
        qWarning("host-contract: allTabsClosed missing");
    if (!connectSessionSignal("closeCancelled()", "handleCloseCancelled()"))
        qWarning("host-contract: closeCancelled missing");
    auto *fileMenu = menuBar()->addMenu(tr("&File"));
    m_openProjectAction =
        fileMenu->addAction(tr("Open Project…"), this, &RewriteWindow::chooseProject);
    keymap::Registry::instance().attach(QStringLiteral("file.open_project"), m_openProjectAction);
    m_openSongAction = fileMenu->addAction(tr("Open Song…"), this, &RewriteWindow::chooseSong);
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
    editMenu->addSeparator();
    addGridActions(*editMenu);

    auto *transportMenu = menuBar()->addMenu(tr("&Transport"));
    m_playPauseAction = transportMenu->addAction(tr("Play/Pause"), this, &RewriteWindow::playPause);
    keymap::Registry::instance().attach(QStringLiteral("transport.play_pause"), m_playPauseAction);
    m_stopAction = transportMenu->addAction(tr("Stop"), this, &RewriteWindow::stop);
    keymap::Registry::instance().attach(QStringLiteral("transport.stop"), m_stopAction);

    m_gridContextMenu = new QMenu(this);
    for (const GridAction &item : m_gridActions) {
        switch (item.command) {
        case 0:  // copy
        case 1:  // cut
        case 2:  // duplicate
        case 3:  // paste
        case 5:  // delete
        case 28: // split
        case 29: // join
            m_gridContextMenu->addAction(item.action);
            break;
        default:
            break;
        }
    }

    m_placeholder =
        makePlaceholder(tr("Open a project and song to play with the Swift core."), this);
    setCentralWidget(m_placeholder);
    statusBar()->showMessage(tr("Ready"));
    resize(layout::fontPx(72), layout::fontPx(48));
    setWindowTitle(tr("Porydaw"));
    updateWindowActions();
}

RewriteWindow::~RewriteWindow()
{
    m_isClosing = true;
    if (m_session)
        QMetaObject::invokeMethod(m_session, "hostClosing");
    detachGridScene();
    delete m_session;
    m_session = nullptr;
}

QQuickView *RewriteWindow::gridView() const
{
    return m_quickView;
}

void RewriteWindow::openStartup(const QString &projectPath, const QString &songLabel)
{
    if (!m_session || projectPath.isEmpty())
        return;
    if (songLabel.isEmpty()) {
        invokeOpenProject(projectPath);
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
    invokeOpenProject(path);
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
    invokeOpenSong(label);
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

void RewriteWindow::changeEvent(QEvent *event)
{
    QMainWindow::changeEvent(event);
    // ThemeController has no signal of its own; themes::apply() restyles the
    // application, so the palette event is the theme-change notification the
    // window sees (the pattern the previous shell used).
    switch (event->type()) {
    case QEvent::ApplicationPaletteChange:
    case QEvent::StyleChange:
    case QEvent::ThemeChange:
        applyGridPalette();
        break;
    default:
        break;
    }
}

void RewriteWindow::closeEvent(QCloseEvent *event)
{
    if (openTabCount() > 0) {
        // Tab semantics own the dirty gate: the session walks its tabs and
        // answers with allTabsClosed() or closeCancelled(). Ignore first so a
        // synchronous answer cannot accept this event, and ignore any further
        // close request while the walk is in flight.
        //
        // requestCloseAll() must complete asynchronously with respect to this
        // event: a synchronous allTabsClosed -> close() from inside closeEvent
        // would recurse into this function before it returned.
        event->ignore();
        if (m_closeAllPending)
            return;
        m_closeAllPending = true;
        QMetaObject::invokeMethod(m_session, "requestCloseAll");
        return;
    }
    m_isClosing = true;
    if (m_session)
        QMetaObject::invokeMethod(m_session, "hostClosing");
    detachGridScene();
    event->accept();
}

bool RewriteWindow::eventFilter(QObject *watched, QEvent *event)
{
    if (watched == m_quickView || watched == m_sceneContainer) {
        switch (event->type()) {
        case QEvent::KeyPress: {
            auto *const key = static_cast<QKeyEvent *>(event);
            if (!quickFocusOwnsLocalKeys(m_quickView)) {
                if (key->key() == Qt::Key_Escape && !key->isAutoRepeat() && handleGridEscape()) {
                    key->accept();
                    return true;
                }
                if (routeGridKey(key)) {
                    key->accept();
                    return true;
                }
            }
            break;
        }
        case QEvent::FocusOut:
            deliverInputCancel(0);
            break;
        case QEvent::UngrabMouse:
            deliverInputCancel(1);
            break;
        case QEvent::Hide:
            deliverInputCancel(2);
            break;
        case QEvent::WindowDeactivate:
            deliverInputCancel(3);
            break;
        default:
            break;
        }
    }
    return QMainWindow::eventFilter(watched, event);
}

int RewriteWindow::openTabCount() const
{
    // A session that never started has no strip: the placeholder path already
    // reported why, so this is not a contract break.
    if (!m_session)
        return 0;
    QObject *const tabs = m_session->property("songTabs").value<QObject *>();
    if (!tabs) {
        qWarning("host-contract: songTabs missing");
        return 0;
    }
    const QVariant count = tabs->property("tabCount");
    if (!count.isValid()) {
        qWarning("host-contract: songTabs.tabCount missing");
        return 0;
    }
    return count.toInt();
}

bool RewriteWindow::saveInProgress() const
{
    return m_session && m_session->property("saveInProgress").toBool();
}

QString RewriteWindow::saveError() const
{
    return m_session ? m_session->property("lastSaveError").toString() : QString();
}

void RewriteWindow::invokeOpenProject(const QString &path)
{
    QMetaObject::invokeMethod(m_session, "openProject", Q_ARG(QString, path));
}

void RewriteWindow::invokeOpenSong(const QString &label)
{
    QMetaObject::invokeMethod(m_session, "openSong", Q_ARG(QString, label));
}

void RewriteWindow::handleSaveStateChanged()
{
    updateWindowActions();
    if (saveInProgress() || saveError().isEmpty())
        return;
    QMessageBox::critical(this, tr("Save Failed"), saveError());
}

void RewriteWindow::handleSongOpenChanged()
{
    if (m_session && m_session->property("songOpen").toBool())
        attachGridScene();
    updateWindowActions();
    updateGridActions();
}

void RewriteWindow::handleOpenFailed(const QString &message)
{
    if (message.isEmpty())
        return;
    statusBar()->showMessage(message);
    QMessageBox::critical(this, tr("Open Failed"), message);
}

void RewriteWindow::handleOperationFailed(const QString &message)
{
    if (message.isEmpty())
        return;
    statusBar()->showMessage(message);
    QMessageBox::critical(this, tr("Operation Failed"), message);
}

void RewriteWindow::handleAllTabsClosed()
{
    // The session emits this only for the walk this window requested: a walk it
    // started for a project open continues that switch instead (see
    // ApplicationSession.closeAllResolved). Re-enters closeEvent with no tabs
    // left, which takes the accept path.
    m_closeAllPending = false;
    close();
}

void RewriteWindow::handleCloseCancelled()
{
    m_closeAllPending = false;
}

void RewriteWindow::attachGridScene()
{
    if (m_isClosing || m_quickView || !m_session || !m_session->property("songOpen").toBool())
        return;

    auto *view = new QQuickView(m_engine.get(), nullptr);
    view->setResizeMode(QQuickView::SizeRootObjectToView);
    view->setColor(themes::color(themes::Role::song_view_piano_roll_background));
    view->rootContext()->setContextProperty(QStringLiteral("appSession"), m_session);
    view->installEventFilter(this);
    view->setSource(QUrl(QStringLiteral("qrc:/porydaw/swiftroll/SwiftRollOverlay.qml")));
    if (view->status() == QQuickView::Error || !view->rootObject()) {
        const QStringList errors = [view] {
            QStringList result;
            for (const QQmlError &error : view->errors())
                result.append(error.toString());
            return result;
        }();
        view->removeEventFilter(this);
        delete view;
        m_placeholder = makePlaceholder(
            tr("The piano grid could not start.\n%1").arg(errors.join(u'\n')), this);
        setCentralWidget(m_placeholder);
        return;
    }

    m_quickView = view;
    m_sceneContainer = QWidget::createWindowContainer(view, this);
    m_sceneContainer->installEventFilter(this);
    setCentralWidget(m_sceneContainer);
    statusBar()->showMessage(tr("Song open"));
}

void RewriteWindow::detachGridScene()
{
    if (m_quickView)
        m_quickView->removeEventFilter(this);
    if (m_sceneContainer) {
        m_sceneContainer->removeEventFilter(this);
        QWidget *container = takeCentralWidget();
        m_sceneContainer = nullptr;
        m_quickView = nullptr;
        delete container;
    }
    if (!centralWidget() && m_session && !m_isClosing) {
        m_placeholder =
            makePlaceholder(tr("Open a project and song to play with the Swift core."), this);
        setCentralWidget(m_placeholder);
    }
    if (m_session)
        QMetaObject::invokeMethod(m_session, "acknowledgeGridDetached");
}

void RewriteWindow::applyGridPalette()
{
    // Session creation has not finished (or failed): nothing to push to yet.
    if (!m_session)
        return;
    // Task 2 contract: one session-owned GridPalette, and every tab's
    // PianoGrid.palette IS this object (not a copy), so the theme push happens
    // once here — at session creation, before any grid exists, and again on
    // every theme change — instead of once per mounted grid.
    QObject *const palette = m_session->property("palette").value<QObject *>();
    if (!palette) {
        qWarning("host-contract: session palette missing");
        return;
    }

    static constexpr struct {
        const char *name;
        themes::Role role;
    } colors[] = {
        {"windowBackground", themes::Role::window_background},
        {"rollBackground", themes::Role::song_view_piano_roll_background},
        {"accidentalLane", themes::Role::song_view_piano_roll_accidental_lane},
        {"chromeBackground", themes::Role::song_view_timeline_chrome_background},
        {"separator", themes::Role::song_view_separator},
        {"outline", themes::Role::palette_outline},
        {"keyboardNatural", themes::Role::song_view_piano_keyboard_natural_key},
        {"keyboardBlack", themes::Role::song_view_piano_keyboard_black_key},
        {"keyboardSeparator", themes::Role::song_view_piano_keyboard_separator},
        {"keyboardLabel", themes::Role::song_view_piano_keyboard_label},
        {"keyboardActiveKey", themes::Role::song_view_piano_keyboard_active_key},
        {"gridLine", themes::Role::song_view_grid},
        {"gridLineBar", themes::Role::song_view_grid},
        {"noteVelocityZero", themes::Role::song_view_note_velocity_zero},
        {"implicitSignature", themes::Role::song_view_note_velocity_zero},
        {"selectionRing", themes::Role::item_selected_background},
        {"selectionEdge", themes::Role::song_view_selection_edge},
        {"primaryText", themes::Role::song_view_primary_text},
        {"windowText", themes::Role::window_text},
        {"secondaryText", themes::Role::song_view_secondary_text},
        {"editCursor", themes::Role::song_view_edit_cursor},
        {"playhead", themes::Role::song_view_playhead},
    };
    for (const auto &entry : colors)
        palette->setProperty(entry.name, hexColor(themes::color(entry.role)));

    auto selectionFill = themes::color(themes::Role::song_view_selection_fill);
    selectionFill.setAlpha(kSelectionFillAlpha);
    palette->setProperty("selectionFill", hexColor(selectionFill));

    palette->setProperty("gridLineSub1",
                         hexColor(withRelativeAlpha(themes::Role::song_view_grid, 125)));
    palette->setProperty("gridLineSub2",
                         hexColor(withRelativeAlpha(themes::Role::song_view_grid, 100)));
    palette->setProperty("gridLineSub3",
                         hexColor(withRelativeAlpha(themes::Role::song_view_grid, 75)));
    palette->setProperty("gridLineBeat",
                         hexColor(withRelativeAlpha(themes::Role::song_view_grid, 160)));
    palette->setProperty("gridLineBeatFine",
                         hexColor(withRelativeAlpha(themes::Role::song_view_grid, 200)));
    palette->setProperty("rowLine", hexColor(withRelativeAlpha(themes::Role::song_view_grid, 50)));
    palette->setProperty(
        "preRollMask",
        hexColor(mixToward(themes::color(themes::Role::song_view_piano_roll_background),
                           themes::color(themes::Role::song_view_grid), 0.15)));
    palette->setProperty(
        "rulerPreRollMask",
        hexColor(mixToward(themes::color(themes::Role::song_view_timeline_chrome_background),
                           themes::color(themes::Role::song_view_grid), 0.15)));
    auto hover = themes::color(themes::Role::song_view_piano_keyboard_active_key);
    hover.setAlpha(80);
    palette->setProperty("keyboardHover", hexColor(hover));

    // The palette's NOTIFY signals refresh QML bindings (EditorSurface fills,
    // the strip), but the roll bakes palette colours into the GridScene rect
    // models that TimelineQuickItem renders, and a palette write alone does not
    // mark those static inputs dirty. Re-bake the presented grid so a theme
    // change repaints it; hidden tabs' grids re-bake on their next rebuild.
    // `gridPresenter()` requires an open song, so gate on `songOpen` — it is
    // false at session creation and in the empty-strip state, where nothing is
    // presented to re-bake.
    if (!m_session->property("songOpen").toBool())
        return;
    QObject *grid = nullptr;
    if (!QMetaObject::invokeMethod(m_session, "gridPresenter", Q_RETURN_ARG(QObject *, grid)) ||
        !grid)
        return;
    QMetaObject::invokeMethod(grid, "reloadVisuals");
}

void RewriteWindow::addGridActions(QMenu &menu)
{
    struct Definition {
        const char *label;
        const char *keymap;
        int command;
    };
    static constexpr Definition definitions[] = {
        {"Copy Notes", "roll.copy", 0},
        {"Cut Notes", "roll.cut", 1},
        {"Duplicate Notes", "roll.duplicate_time", 2},
        {"Paste Notes", "roll.paste", 3},
        {"Select All Notes", "roll.select_all", 4},
        {"Delete Notes", "roll.delete", 5},
        {"Transpose Up", "roll.transpose_up", 7},
        {"Transpose Down", "roll.transpose_down", 8},
        {"Transpose Up an Octave", "roll.transpose_up_octave", 9},
        {"Transpose Down an Octave", "roll.transpose_down_octave", 10},
        {"Nudge Left", "roll.nudge_left", 11},
        {"Nudge Right", "roll.nudge_right", 12},
        {"Mute Track", "roll.mute_tracks", 13},
        {"Solo Track", "roll.solo_tracks", 14},
        {"Pencil Mode", "automation.pencil_mode", 25},
        {"Split Notes", "roll.split", 28},
        {"Join Notes", "roll.join", 29},
        {"Lengthen Notes", "roll.lengthen_note", 30},
        {"Shorten Notes", "roll.shorten_note", 31},
        {"Narrow Grid", "roll.grid_narrow", 32},
        {"Widen Grid", "roll.grid_widen", 33},
        {"Triplet Grid", "roll.grid_triplet", 34},
    };
    m_gridActions = std::vector<GridAction>(std::size(definitions));
    for (size_t index = 0; index < std::size(definitions); ++index) {
        const Definition &definition = definitions[index];
        QAction *action = menu.addAction(tr(definition.label));
        connect(action, &QAction::triggered, this,
                [this, command = definition.command] { invokeGridCommand(command); });
        keymap::Registry::instance().attach(QString::fromLatin1(definition.keymap), action);
        m_gridActions[index].keymap = QString::fromLatin1(definition.keymap);
        m_gridActions[index].command = definition.command;
        m_gridActions[index].action = action;
    }
}

bool RewriteWindow::routeGridKey(QKeyEvent *event)
{
    for (const GridAction &item : m_gridActions) {
        if (!item.action || item.action->shortcutContext() != Qt::WidgetShortcut ||
            !keymap::Registry::instance().matches(event->key(), event->modifiers(), item.keymap)) {
            continue;
        }
        int decision = 0;
        const bool routed =
            m_session &&
            QMetaObject::invokeMethod(m_session, "routeGridKey", Q_RETURN_ARG(int, decision),
                                      Q_ARG(int, item.command), Q_ARG(bool, event->isAutoRepeat()));
        if (!routed || decision == 0)
            return false;
        if (decision == 2)
            invokeGridCommand(item.command);
        return true;
    }
    return false;
}

bool RewriteWindow::handleGridEscape()
{
    bool handled = false;
    if (m_session) {
        QMetaObject::invokeMethod(m_session, "handleGridEscape", Q_RETURN_ARG(bool, handled));
    }
    return handled;
}

void RewriteWindow::invokeGridCommand(int command)
{
    if (m_session)
        QMetaObject::invokeMethod(m_session, "performGridCommand", Q_ARG(int, command));
    updateWindowActions();
}

void RewriteWindow::updateWindowActions()
{
    const bool songOpen = m_session && m_session->property("songOpen").toBool();
    const bool saving = saveInProgress();
    if (m_openSongAction)
        m_openSongAction->setEnabled(m_session && m_session->property("projectOpen").toBool());
    if (m_saveAction)
        m_saveAction->setEnabled(songOpen && !saving);
    if (m_playPauseAction)
        m_playPauseAction->setEnabled(songOpen);
    if (m_stopAction)
        m_stopAction->setEnabled(songOpen);
    if (m_undoAction)
        m_undoAction->setEnabled(songOpen && m_session && m_session->property("canUndo").toBool());
    if (m_redoAction)
        m_redoAction->setEnabled(songOpen && m_session && m_session->property("canRedo").toBool());

    // Grid actions follow `gridCommandAvailabilityChanged` and `songOpen`
    // only: a mid-gesture command query can report a transient unavailable
    // state (the press holds the selection), and no availability emission
    // follows the release because the settled set matches the last publish.
}

void RewriteWindow::updateGridActions()
{
    const bool songOpen = m_session && m_session->property("songOpen").toBool();
    for (const GridAction &item : m_gridActions) {
        bool available = false;
        if (songOpen) {
            QMetaObject::invokeMethod(m_session, "gridCommandAvailable",
                                      Q_RETURN_ARG(bool, available), Q_ARG(int, item.command));
        }
        item.action->setEnabled(available);
    }
}

void RewriteWindow::showGridContextMenu(double, double)
{
    updateGridActions();
    if (m_gridContextMenu)
        m_gridContextMenu->popup(QCursor::pos());
}

bool RewriteWindow::connectPropertyNotify(const char *property, const char *slot)
{
    if (!m_session)
        return false;
    const int propertyIndex = m_session->metaObject()->indexOfProperty(property);
    const QByteArray normalizedSlot = QMetaObject::normalizedSignature(slot);
    const int slotIndex = metaObject()->indexOfSlot(normalizedSlot.constData());
    if (propertyIndex < 0 || slotIndex < 0)
        return false;
    const QMetaProperty metaProperty = m_session->metaObject()->property(propertyIndex);
    if (!metaProperty.hasNotifySignal())
        return false;
    return QObject::connect(m_session, metaProperty.notifySignal(), this,
                            metaObject()->method(slotIndex));
}

bool RewriteWindow::connectSessionSignal(const char *signal, const char *slot)
{
    if (!m_session)
        return false;
    const QByteArray normalizedSignal = QMetaObject::normalizedSignature(signal);
    const QByteArray normalizedSlot = QMetaObject::normalizedSignature(slot);
    const int signalIndex = m_session->metaObject()->indexOfSignal(normalizedSignal.constData());
    const int slotIndex = metaObject()->indexOfSlot(normalizedSlot.constData());
    if (signalIndex < 0 || slotIndex < 0)
        return false;
    return QObject::connect(m_session, m_session->metaObject()->method(signalIndex), this,
                            metaObject()->method(slotIndex));
}

void RewriteWindow::deliverInputCancel(int reason)
{
    if (m_session)
        QMetaObject::invokeMethod(m_session, "cancelGridInput", Q_ARG(int, reason));
}

void RewriteWindow::invokeNoArgs(const char *method)
{
    if (m_session)
        QMetaObject::invokeMethod(m_session, method);
}

extern "C" bool pd_clipboard_write(const uint8_t *bytes, size_t count)
{
    if (!qApp || QThread::currentThread() != qApp->thread() || (bytes == nullptr && count != 0) ||
        count > size_t((std::numeric_limits<qsizetype>::max)())) {
        return false;
    }
    auto *mime = new QMimeData;
    const QByteArray payload =
        count == 0 ? QByteArray{}
                   : QByteArray(reinterpret_cast<const char *>(bytes), qsizetype(count));
    mime->setData(kClipMimeType, payload);
    QApplication::clipboard()->setMimeData(mime);
    return true;
}

extern "C" bool pd_clipboard_read(void *context, PdConsumeBytesCallback consume)
{
    if (!qApp || QThread::currentThread() != qApp->thread() || consume == nullptr)
        return false;
    const QMimeData *mime = QApplication::clipboard()->mimeData();
    if (!mime || !mime->hasFormat(kClipMimeType))
        return false;
    const QByteArray payload = mime->data(kClipMimeType);
    consume(context, reinterpret_cast<const uint8_t *>(payload.constData()),
            size_t(payload.size()));
    return true;
}
