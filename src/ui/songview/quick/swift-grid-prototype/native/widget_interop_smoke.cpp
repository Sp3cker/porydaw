// Scenario automation for the widget interop lane.
//
// Everything here drives the prototype as a user would: real pointer clicks at
// window-local logical pixels, real key events, and clicks on the widgets the
// wizard and the menu really render. The smoke only observes product state,
// with one startup precondition: activation is requested once before the
// baseline keyboard input, because an automated launch may not foreground the
// window. No activation or focus is ever requested after a dismissal, and no
// QML or Swift API a user could not reach is called, so a scenario passing
// means the lane works without verification-only repair. After every close it
// waits for the real window activation and then repeats the input the widget
// had blocked.
//
// Environment: PORYDAW_SWIFT_WIDGET_SMOKE=1 runs the automation and exits after
// the exact "SWIFT_GRID_WIDGET_SMOKE PASS" marker; PORYDAW_SWIFT_WIDGET_PREVIEW=1
// runs the same automation and leaves the application open with the outcome
// history visible in the window.

#include "new_song_wizard_smoke.h"
#include "widget_interop.h"
#include "widget_window_fixtures.h"

#include <QAbstractButton>
#include <QAction>
#include <QApplication>
#include <QComboBox>
#include <QDialog>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLineEdit>
#include <QMenu>
#include <QMessageBox>
#include <QPointer>
#include <QProgressDialog>
#include <QQuickItem>
#include <QQuickWindow>
#include <QScreen>
#include <QSet>
#include <QTest>
#include <QTimer>
#include <QVector>
#include <QWindow>

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <string>

// Internal to this library pair (see widget_interop.cpp): the host's readiness
// and the adopted window, observed instead of re-derived from Qt state.
extern "C" int sgw_widgetInteropHostReady(void);
extern "C" void *sgw_widgetInteropHostWindow(void);
extern "C" void *sgw_widgetInteropActiveWidget(void);

#if defined(Q_OS_MACOS)
extern "C" bool sgw_nativeFilePanelVisible(void);
#endif

namespace {

using namespace std::chrono_literals;

constexpr int kWaitMs = 5000;

// ---- Harness ----------------------------------------------------------------

struct SmokeFailure {
    std::string message;
};

[[noreturn]] void fail(const QString &reason)
{
    throw SmokeFailure{reason.toStdString()};
}

void require(bool condition, const QString &reason)
{
    if (!condition)
        fail(reason);
}

void evidence(const QString &text)
{
    std::printf("SWIFT_GRID_WIDGET_SMOKE evidence: %s\n", qPrintable(text));
    std::fflush(stdout);
}

void pass(const QString &scenario)
{
    std::printf("SWIFT_GRID_WIDGET_SMOKE %s PASS\n", qPrintable(scenario));
    std::fflush(stdout);
}

bool boundedMode()
{
    return qEnvironmentVariable("PORYDAW_SWIFT_WIDGET_SMOKE") == QStringLiteral("1");
}

bool previewMode()
{
    return qEnvironmentVariable("PORYDAW_SWIFT_WIDGET_PREVIEW") == QStringLiteral("1");
}

// Bounded mode exits on failure; preview keeps the application open so the
// failure stays visible in the window and on the log.
void reportFailure(const SmokeFailure &failure)
{
    std::fprintf(stderr, "SWIFT_GRID_WIDGET_SMOKE FAIL: %s\n", failure.message.c_str());
    std::fflush(stderr);
    if (boundedMode())
        std::exit(EXIT_FAILURE);
}

// ---- QML surface ------------------------------------------------------------

QQuickItem *namedItem(QQuickItem *parent, const QString &name)
{
    if (parent->objectName() == name)
        return parent;
    for (QQuickItem *child : parent->childItems()) {
        if (QQuickItem *found = namedItem(child, name))
            return found;
    }
    return nullptr;
}

void collectNamed(QQuickItem *parent, const QString &prefix, QVector<QQuickItem *> &found)
{
    if (parent->objectName().startsWith(prefix))
        found.append(parent);
    for (QQuickItem *child : parent->childItems())
        collectNamed(child, prefix, found);
}

// Every tab page exists at once, so the visible match is the page that owns the
// geometry the gestures below map through.
QQuickItem *visibleItem(QQuickWindow *window, const QString &name)
{
    QVector<QQuickItem *> matches;
    collectNamed(window->contentItem(), name, matches);
    for (QQuickItem *match : matches) {
        if (match->isVisible())
            return match;
    }
    return nullptr;
}

struct Surface {
    QPointer<QQuickWindow> window;
    QPointer<QQuickItem> wizardButton;
    QPointer<QQuickItem> menuButton;
    QPointer<QQuickItem> fixtureChooser;
    QPointer<QQuickItem> openButton;
    QPointer<QQuickItem> tabStrip;
    QPointer<QObject> interop;
    QPointer<QObject> songTabs;
    QPointer<QObject> audio;
    QPointer<QObject> model;
    QPointer<QQuickItem> gridViewport;
    QPointer<QQuickItem> gridSurface;

    QString status() const { return interop->property("statusText").toString(); }

    QString history() const { return interop->property("historyText").toString(); }

    int historyLines() const { return history().split(QLatin1Char('\n')).size(); }

    int selectedTab() const { return songTabs->property("selectedId").toInt(); }

    bool playing() const { return audio->property("playing").toBool(); }

    QJsonArray notes() const
    {
        require(model, "the selected tab publishes no grid model");
        const QJsonDocument document =
            QJsonDocument::fromJson(model->property("noteSummary").toString().toUtf8());
        require(document.isArray(), "the grid model's noteSummary is not a JSON array");
        return document.array();
    }

    double modelNumber(const char *property) const
    {
        require(model, "the selected tab publishes no grid model");
        return model->property(property).toDouble();
    }

    // The per-tab grid model, audio session, and grid items follow the selected
    // tab; nothing else in the lane does, so they are re-resolved whenever the
    // tab may have changed.
    void refresh()
    {
        model = window->property("gridModel").value<QObject *>();
        audio = window->property("audio").value<QObject *>();
        gridViewport = visibleItem(window, QStringLiteral("pianoGridViewport"));
        gridSurface = visibleItem(window, QStringLiteral("pianoGridSurface"));
        require(model && audio && gridViewport && gridSurface,
                "the selected tab publishes no grid model, audio session, and visible grid");
    }
};

// The Quick window active and holding keyboard focus. Checked, never repaired:
// the only activation request is the one-time startup precondition documented
// in runAutomation.
bool quickWindowActive(const Surface &surface)
{
    return surface.window && surface.window->isActive() &&
           QGuiApplication::focusWindow() == surface.window.data();
}

void clickItem(const Surface &surface, QQuickItem *item, const QString &what)
{
    require(item && item->isVisible() && item->isEnabled(),
            QStringLiteral("%1 is not an enabled, visible control").arg(what));
    const QPointF center = item->mapToScene(QPointF(item->width() / 2, item->height() / 2));
    require(surface.window->contentItem()->boundingRect().contains(center),
            QStringLiteral("%1 is outside the Quick window").arg(what));
    QTest::mouseClick(surface.window, Qt::LeftButton, Qt::NoModifier, center.toPoint());
    QTest::qWait(20ms);
}

void awaitStatus(const Surface &surface, const QString &expected, const QString &reason)
{
    const auto matches = [&surface, &expected] { return surface.status() == expected; };
    if (QTest::qWaitFor(matches, 5s))
        return;
    evidence(QStringLiteral("status expected='%1' actual='%2'").arg(expected, surface.status()));
    fail(reason);
}

// The tab the scenarios drive: a tab other than the selected one, so clicking
// it is visible in the controller's selected id.
QQuickItem *otherTab(const Surface &surface)
{
    QVector<QQuickItem *> tabs;
    collectNamed(surface.tabStrip, QStringLiteral("songTabSelect_"), tabs);
    require(tabs.size() >= 2, "the prototype did not open at least two song tabs");
    const QString selectedTab = QStringLiteral("songTabSelect_%1").arg(surface.selectedTab());
    for (QQuickItem *tab : tabs) {
        if (tab->objectName() != selectedTab && tab->isVisible())
            return tab;
    }
    fail("no unselected, visible tab to click");
}

// ---- Draw gesture -----------------------------------------------------------

struct DrawTarget {
    QPoint press;
    QPoint release;
    int pitch = -1;
    int tick = -1;
};

// Scrolls the production viewport so a content point is on screen, using the
// same content properties the flickable exposes, then maps through the unmoved
// surface.
QPointF windowPoint(const Surface &surface, const QPointF &content)
{
    const QPointF scene = surface.gridSurface->mapToScene(content);
    require(scene.x() >= 0 && scene.x() < surface.window->width() && scene.y() >= 0 &&
                scene.y() < surface.window->height(),
            QStringLiteral("gesture target (%1,%2) is outside the native window")
                .arg(scene.x())
                .arg(scene.y()));
    return scene;
}

void reveal(const Surface &surface, const QPointF &content)
{
    QQuickItem *viewport = surface.gridViewport;
    const double maxX =
        qMax(0.0, viewport->property("contentWidth").toDouble() - viewport->width());
    const double maxY =
        qMax(0.0, viewport->property("contentHeight").toDouble() - viewport->height());
    require(
        viewport->setProperty("contentX", qBound(0.0, content.x() - viewport->width() / 2, maxX)) &&
            viewport->setProperty("contentY",
                                  qBound(0.0, content.y() - viewport->height() / 2, maxY)),
        "the grid viewport refused a content scroll");
    QTest::qWait(20ms);
}

// A draw gesture on empty ground: an unused pitch row, at a tick away from the
// transport playhead. A pass that commits on the row it used simply moves the
// next pass to the next free row, so repeated passes stay independent.
DrawTarget drawTarget(const Surface &surface)
{
    QSet<int> usedPitches;
    for (const QJsonValue value : surface.notes())
        usedPitches.insert(value.toObject().value("pitch").toInt());
    int pitch = -1;
    for (int candidate = 96; candidate >= 0; --candidate) {
        if (!usedPitches.contains(candidate)) {
            pitch = candidate;
            break;
        }
    }
    require(pitch >= 0, "the fixture occupies every pitch row; no empty row to draw on");

    const int tick = 192;
    const double beatWidth = surface.modelNumber("beatWidth");
    const double ticksPerBeat = qMax(1.0, surface.modelNumber("ticksPerBeat"));
    const QPointF start(surface.modelNumber("leadPadWidth") + tick * beatWidth / ticksPerBeat,
                        (127 - pitch + 0.5) * surface.modelNumber("rowHeight"));
    // Leftward drag, well past the production minimum draw distance and one
    // snap step wide at any zoom.
    const QPointF end = start - QPointF(qMax(beatWidth * 0.5, 24.0), 0.0);

    DrawTarget target;
    target.pitch = pitch;
    target.tick = tick;
    reveal(surface, (start + end) / 2.0);
    target.press = windowPoint(surface, start).toPoint();
    target.release = windowPoint(surface, end).toPoint();
    return target;
}

void dragDraw(const Surface &surface, const DrawTarget &target)
{
    QTest::mousePress(surface.window, Qt::LeftButton, Qt::NoModifier, target.press);
    QTest::mouseMove(surface.window, target.release);
    QTest::mouseRelease(surface.window, Qt::LeftButton, Qt::NoModifier, target.release);
}

QJsonObject noteCommittedBy(const QJsonArray &before, const QJsonArray &after)
{
    QSet<int> known;
    for (const QJsonValue value : before)
        known.insert(value.toObject().value("id").toInt());
    for (const QJsonValue value : after) {
        const QJsonObject note = value.toObject();
        if (!known.contains(note.value("id").toInt()))
            return note;
    }
    return {};
}

// ---- Widget observation -----------------------------------------------------

QMenu *awaitMenu()
{
    QMenu *menu = nullptr;
    const auto appeared = [&menu] {
        menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
        return menu != nullptr && menu->isVisible();
    };
    require(QTest::qWaitFor(appeared, 5s), "the widget toolbar did not pop up a native menu");
    require(QTest::qWaitForWindowExposed(menu->windowHandle(), kWaitMs),
            "the popup menu never became visible on screen");
    return menu;
}

// The lane's menu: no QWidget parent, transient for the Quick window, and the
// single action it renders.
QAction *expectProductionMenu(const Surface &surface, QMenu *menu)
{
    require(!menu->parentWidget(), "the menu must pop up with no QWidget parent");
    require(menu->windowHandle()->transientParent() == surface.window.data(),
            "the menu's platform window is not transient for the Quick window");
    const QList<QAction *> actions = menu->actions();
    require(actions.size() == 1 && actions.first()->text() == QStringLiteral("Inspect Current Tab"),
            "the popup does not render the lane's single menu action");
    return actions.first();
}

// ---- Scenario steps ---------------------------------------------------------

// A dismissal owes exactly real activation, then the three input paths it had
// blocked. Activation is only observed here — unlike the one-time startup
// precondition in runAutomation, nothing is requested. The keyboard check runs
// before any click, so a later click cannot stand in for a broken immediate
// keyboard return, and nothing reads an item. The Space press is addressed at
// the Quick window because it has just been required to be the focused window,
// so that target is the one real routing would pick.
void proveResumedInput(Surface &surface, QQuickItem *tab)
{
    require(QTest::qWaitFor([&surface] { return quickWindowActive(surface); }, kWaitMs),
            "the Quick window did not become the active, focused window after the widget closed");

    const bool playingBefore = surface.playing();
    QTest::keyClick(surface.window, Qt::Key_Space);
    require(QTest::qWaitFor(
                [&surface, playingBefore] { return surface.playing() != playingBefore; }, 3s),
            "the Space shortcut did not reach the transport after the widget closed");
    QTest::keyClick(surface.window, Qt::Key_Space);
    require(QTest::qWaitFor(
                [&surface, playingBefore] { return surface.playing() == playingBefore; }, 3s),
            "the Space shortcut did not toggle the transport back");

    const int tabBefore = surface.selectedTab();
    clickItem(surface, tab, QStringLiteral("the host tab strip"));
    require(
        QTest::qWaitFor([&surface, tabBefore] { return surface.selectedTab() != tabBefore; }, 3s),
        "the same tab click that was blocked while modal did not select the tab");
    surface.refresh();

    const QJsonArray before = surface.notes();
    const DrawTarget target = drawTarget(surface);
    dragDraw(surface, target);
    const bool committed = QTest::qWaitFor(
        [&surface, &before] { return surface.notes().size() == before.size() + 1; }, 3s);
    if (!committed) {
        evidence(
            QStringLiteral("draw notes before=%1 after=%2 tick=%3 press=(%4,%5) release=(%6,%7)")
                .arg(before.size())
                .arg(surface.notes().size())
                .arg(target.tick)
                .arg(target.press.x())
                .arg(target.press.y())
                .arg(target.release.x())
                .arg(target.release.y()));
        fail("the same draw gesture that was blocked while modal did not commit a note");
    }
    const QJsonObject drawn = noteCommittedBy(before, surface.notes());
    require(drawn.value("pitch").toInt(-1) == target.pitch,
            "the draw gesture did not commit the note on the row it was drawn on");
    const bool focused = QGuiApplication::focusWindow() == surface.window.data();
    evidence(QStringLiteral("resumed windowActive=%1 focusedWindow=%2 tab=%3 notes=%4 "
                            "drawnPitch=%5")
                 .arg(surface.window->isActive() ? QStringLiteral("yes") : QStringLiteral("no"))
                 .arg(focused ? QStringLiteral("quick") : QStringLiteral("other"))
                 .arg(surface.selectedTab())
                 .arg(before.size() + 1)
                 .arg(target.pitch));
}

// ---- Scenarios --------------------------------------------------------------

// One menu pass: trigger the single action, or leave through Escape.
QPointer<QMenu> menuScenario(Surface &surface, bool escape, const QPointer<QMenu> &previous)
{
    require(previous.isNull(), "the previous menu was still alive when the scenario reopened it");
    // Resolved per scenario: the previous pass selected the tab it drove.
    QQuickItem *tab = otherTab(surface);
    clickItem(surface, surface.menuButton, QStringLiteral("the widget menu button"));
    QMenu *menu = awaitMenu();
    QAction *action = expectProductionMenu(surface, menu);
    // Guarded before the dismissal: the popup deletes itself on close, so a
    // QPointer built from the raw pointer afterwards would read a deleted
    // object.
    const QPointer<QMenu> closed = menu;

    if (escape) {
        // The dismissal key goes to the popup's own window: that is the window
        // a user's Escape reaches while the menu is up.
        QTest::keyClick(menu->windowHandle(), Qt::Key_Escape);
        awaitStatus(surface, QStringLiteral("Menu dismissed"),
                    "Escape did not report 'Menu dismissed'");
    } else {
        const QRect actionRect = menu->actionGeometry(action);
        require(actionRect.isValid(), "the popup did not lay out its action");
        // Real pointer input on the popup's own window, at the point the action
        // is really rendered at.
        const QPoint local =
            menu->windowHandle()->mapFromGlobal(menu->mapToGlobal(actionRect.center()));
        QTest::mouseClick(menu->windowHandle(), Qt::LeftButton, Qt::NoModifier, local);
        awaitStatus(surface, QStringLiteral("Menu action: Inspect Current Tab"),
                    "the menu action did not report its own label");
    }

    require(QTest::qWaitFor([] { return QApplication::activePopupWidget() == nullptr; }, kWaitMs),
            "the popup menu stayed active after its outcome");
    require(QTest::qWaitFor([&closed] { return closed.isNull(); }, kWaitMs),
            "the closed menu was not deleted (stale pointer left behind)");
    proveResumedInput(surface, tab);
    evidence(
        QStringLiteral("menu %1 deleted=true status='%2' historyLines=%3")
            .arg(escape ? QStringLiteral("escape") : QStringLiteral("action"), surface.status())
            .arg(surface.historyLines()));
    pass(escape ? QStringLiteral("menu-escape-dismissal-and-resumed-input")
                : QStringLiteral("menu-action-detail-reopen-and-resumed-input"));
    // `closed` already tracks the widget; see wizardScenario.
    return closed;
}

// ---- ABI-level anchor scenario ---------------------------------------------

struct SmokeOutcome {
    int kind = 0;
    QString detail;
    int deliveries = 0;
};

void recordOutcome(int kind, const char *detail, void *context)
{
    auto *outcome = static_cast<SmokeOutcome *>(context);
    ++outcome->deliveries;
    outcome->kind = kind;
    outcome->detail = QString::fromUtf8(detail);
}

// The ABI popup's observable placement contract, in two passes. Interior: the
// visible menu must contain the logical global point the window-local anchor
// maps to, and on a scaled screen must not contain the point a device-pixel-
// ratio-scaled mapping would have produced. Off-screen: only the boundary
// promise holds — the popup lands fully inside the screen's available geometry —
// because the native platform may adjust the requested top-left, so its exact
// value is not a behavioral contract.
void anchorScenario(Surface &surface)
{
    QScreen *screen = surface.window->screen();
    require(screen, "the Quick window has no screen to clamp against");
    const QRect available = screen->availableGeometry();
    const qreal dpr = surface.window->devicePixelRatio();

    // Interior pass: the Quick window's own center, so no screen edge can move
    // the popup.
    const QPoint interiorLocal(surface.window->width() / 2, surface.window->height() / 2);
    const QPoint interiorGlobal = surface.window->mapToGlobal(interiorLocal);
    // What a DPR-scaled local-to-global mapping would have produced instead.
    const QPoint scaledHypothesis(
        surface.window->position() +
        QPoint(qRound(interiorLocal.x() * dpr), qRound(interiorLocal.y() * dpr)));
    const int separation = (interiorGlobal - scaledHypothesis).manhattanLength();
    require(dpr <= 1.0 || separation >= 16,
            QStringLiteral("the interior anchor cannot discriminate a DPR-scaled mapping "
                           "(points %1 px apart)")
                .arg(separation));

    SmokeOutcome interiorOutcome;
    require(sgw_openWidgetMenu(interiorLocal.x(), interiorLocal.y(), recordOutcome,
                               &interiorOutcome) != 0,
            "the ABI refused an interior menu anchor");
    QMenu *interiorMenu = awaitMenu();
    expectProductionMenu(surface, interiorMenu);
    // Guarded before the dismissal key: the popup deletes itself on close, so a
    // QPointer built from the raw pointer afterwards would read a deleted
    // object.
    const QPointer<QMenu> interiorClosed = interiorMenu;
    const QRect interiorFrame = interiorMenu->geometry();
    require(interiorFrame.contains(interiorGlobal),
            QStringLiteral("the visible menu does not contain the logical global anchor "
                           "global=(%1,%2) frame=(%3,%4 %5x%6)")
                .arg(interiorGlobal.x())
                .arg(interiorGlobal.y())
                .arg(interiorFrame.x())
                .arg(interiorFrame.y())
                .arg(interiorFrame.width())
                .arg(interiorFrame.height()));
    if (dpr > 1.0) {
        require(!interiorFrame.contains(scaledHypothesis),
                "the visible menu contains the DPR-scaled anchor point, so the mapping scaled "
                "window-local logical pixels");
    }
    evidence(QStringLiteral("menu-anchor-interior local=(%1,%2) global=(%3,%4) "
                            "scaledHypothesis=(%5,%6) dpr=%7 frame=(%8,%9 %10x%11)")
                 .arg(interiorLocal.x())
                 .arg(interiorLocal.y())
                 .arg(interiorGlobal.x())
                 .arg(interiorGlobal.y())
                 .arg(scaledHypothesis.x())
                 .arg(scaledHypothesis.y())
                 .arg(dpr)
                 .arg(interiorFrame.x())
                 .arg(interiorFrame.y())
                 .arg(interiorFrame.width())
                 .arg(interiorFrame.height()));
    QTest::keyClick(interiorMenu->windowHandle(), Qt::Key_Escape);
    require(
        QTest::qWaitFor([&interiorOutcome] { return interiorOutcome.deliveries == 1; }, kWaitMs) &&
            interiorOutcome.kind == 4,
        "the interior ABI menu did not report exactly one dismissal");
    require(interiorOutcome.detail.isEmpty(), "a dismissal must not carry an action detail");
    require(QTest::qWaitFor([&interiorClosed] { return interiorClosed.isNull(); }, kWaitMs),
            "the interior ABI menu was not deleted (stale pointer left behind)");
    pass(QStringLiteral("menu-anchor-interior-logical-point"));

    // Off-screen pass: the same ABI, anchored far outside the screen.
    const QPoint extremeGlobal(available.right() + 512, available.bottom() + 512);
    const QPoint local = surface.window->mapFromGlobal(extremeGlobal);
    require(!available.contains(surface.window->mapToGlobal(local)),
            "the scenario point does not round-trip to an off-screen global point");

    SmokeOutcome outcome;
    require(sgw_openWidgetMenu(local.x(), local.y(), recordOutcome, &outcome) != 0,
            "the ABI refused an off-window menu anchor");
    QMenu *menu = awaitMenu();
    expectProductionMenu(surface, menu);
    // Guarded before its dismissal key for the same reason as the interior pass.
    const QPointer<QMenu> closed = menu;

    const QRect frame = menu->geometry();
    require(available.contains(frame),
            "the clamped popup is not fully inside the screen's available geometry");
    evidence(QStringLiteral("menu-anchor-edge requestedLocal=(%1,%2) requestedGlobal=(%3,%4) "
                            "frame=(%5,%6 %7x%8) screen=(%9,%10 %11x%12) dpr=%13")
                 .arg(local.x())
                 .arg(local.y())
                 .arg(surface.window->mapToGlobal(local).x())
                 .arg(surface.window->mapToGlobal(local).y())
                 .arg(frame.x())
                 .arg(frame.y())
                 .arg(frame.width())
                 .arg(frame.height())
                 .arg(available.x())
                 .arg(available.y())
                 .arg(available.width())
                 .arg(available.height())
                 .arg(dpr));

    QTest::keyClick(menu->windowHandle(), Qt::Key_Escape);
    require(QTest::qWaitFor([&outcome] { return outcome.deliveries == 1; }, kWaitMs) &&
                outcome.kind == 4,
            "the ABI-level menu did not report exactly one dismissal");
    require(outcome.detail.isEmpty(), "a dismissal must not carry an action detail");
    require(QTest::qWaitFor([&closed] { return closed.isNull(); }, kWaitMs),
            "the ABI-dismissed menu was not deleted (stale pointer left behind)");
    // An ABI-level dismissal is a real close too: activation and input resume,
    // observed only — never requested.
    proveResumedInput(surface, otherTab(surface));
    pass(QStringLiteral("menu-anchor-clamped-inside-available-screen"));
}

struct FixtureSpec {
    int kind;
    bool isNativeFileDialog;
};

static const FixtureSpec kFixtures[] = {
    {SgwWindowSettings, false},   {SgwWindowSampleEditor, false},  {SgwWindowSf2Picker, false},
    {SgwWindowImportMidi, false}, {SgwWindowNewVoicegroup, false}, {SgwWindowExportWav, false},
    {SgwWindowProgress, false},   {SgwWindowOpenFile, true},       {SgwWindowSaveFile, true},
    {SgwWindowDirectory, true},   {SgwWindowConfirmation, false},  {SgwWindowError, false},
    {SgwWindowAbout, false},
};

QString fixtureScenario(Surface &surface, const FixtureSpec &spec)
{
    require(surface.openButton && surface.openButton->isEnabled(),
            QStringLiteral("open button was not enabled before launching fixture kind %1")
                .arg(spec.kind));
    require(!surface.interop->property("busy").toBool(),
            "interop controller was busy before launch");

    // 1. Select fixture in QML chooser
    require(surface.fixtureChooser->setProperty("currentIndex", spec.kind - 1),
            QStringLiteral("could not set chooser index for fixture kind %1").arg(spec.kind));
    QTest::qWait(20ms);

    // 2. Click Open button through the actual QML control
    clickItem(surface, surface.openButton,
              QStringLiteral("the Open button for fixture kind %1").arg(spec.kind));

    // 3. Await visible dialog via explicit observable bridge identity
    QDialog *dialog = nullptr;
    const auto appeared = [&dialog] {
        dialog = static_cast<QDialog *>(sgw_widgetInteropActiveWidget());
        return dialog != nullptr && dialog->isVisible() && dialog->windowHandle() != nullptr;
    };
    require(QTest::qWaitFor(appeared, kWaitMs),
            QStringLiteral("fixture kind %1 did not open an active visible dialog").arg(spec.kind));

    // 4. Verify parenting and modality
    require(!dialog->parentWidget(),
            QStringLiteral("fixture kind %1 must open with no QWidget parent").arg(spec.kind));
    require(dialog->windowHandle() != nullptr,
            QStringLiteral("fixture kind %1 has no platform window").arg(spec.kind));

    const QWindow *transient = dialog->windowHandle();
    while (transient && transient != surface.window.data())
        transient = transient->transientParent();
    require(transient == surface.window.data(),
            QStringLiteral("fixture kind %1 platform window is not transient for the Quick window")
                .arg(spec.kind));

    require(dialog->windowModality() == Qt::WindowModal ||
                dialog->windowModality() == Qt::ApplicationModal,
            QStringLiteral("fixture kind %1 is not modal").arg(spec.kind));

    // Read actual title from the dialog — smoke MUST NOT pin wording or title text
    const QString actualTitle = dialog->windowTitle();

    // 5. Observe exposure
    if (spec.isNativeFileDialog) {
#if defined(Q_OS_MACOS)
        require(QTest::qWaitFor(sgw_nativeFilePanelVisible, kWaitMs),
                QStringLiteral(
                    "native macOS file panel for kind %1 never became visible in NSApp.windows")
                    .arg(spec.kind));
        evidence(
            QStringLiteral("fixture kind %1 native file panel observed visible via NSApp.windows")
                .arg(spec.kind));
#else
        require(
            QTest::qWaitForWindowExposed(dialog->windowHandle(), kWaitMs),
            QStringLiteral("fixture kind %1 platform window never became exposed").arg(spec.kind));
#endif
    } else {
        require(
            QTest::qWaitForWindowExposed(dialog->windowHandle(), kWaitMs),
            QStringLiteral("fixture kind %1 platform window never became exposed").arg(spec.kind));
    }

    // Acknowledge the error, cancel the confirmation, and close About through
    // their actual buttons. Other windows exercise keyboard dismissal.
    const bool expectsAccept = spec.kind == SgwWindowError;

    const QPointer<QDialog> closed = dialog;
    const QString expectedOutcome =
        expectsAccept ? (actualTitle.isEmpty() ? QStringLiteral("Accepted")
                                               : QStringLiteral("Accepted: %1").arg(actualTitle))
                      : (actualTitle.isEmpty() ? QStringLiteral("Cancelled")
                                               : QStringLiteral("Cancelled: %1").arg(actualTitle));

    if (auto *box = qobject_cast<QMessageBox *>(dialog)) {
        const auto button = spec.kind == SgwWindowConfirmation ? QMessageBox::Cancel
                            : spec.kind == SgwWindowError      ? QMessageBox::Ok
                                                               : QMessageBox::Close;
        QAbstractButton *target = box->button(button);
        require(target && target->isVisible() && target->isEnabled(),
                QStringLiteral("fixture kind %1 has no usable dismissal button").arg(spec.kind));
        QTest::mouseClick(target, Qt::LeftButton);
    } else {
        QTest::keyClick(dialog->windowHandle(), Qt::Key_Escape);
    }

    const auto dismissed = [&closed] { return closed.isNull() || !closed->isVisible(); };
    require(QTest::qWaitFor(dismissed, kWaitMs),
            QStringLiteral("fixture kind %1 did not dismiss after user input").arg(spec.kind));

    // 7. Verify outcome reported to controller and history
    awaitStatus(surface, expectedOutcome,
                QStringLiteral("fixture kind %1 did not report outcome '%2'")
                    .arg(spec.kind)
                    .arg(expectedOutcome));

    require(QTest::qWaitFor([&closed] { return closed.isNull(); }, kWaitMs),
            QStringLiteral("closed fixture kind %1 was not deleted (stale pointer left behind)")
                .arg(spec.kind));

    // 8. Validate NO lingering modal blocks launching next surface
    require(QTest::qWaitFor([] { return QApplication::activeModalWidget() == nullptr; }, kWaitMs),
            QStringLiteral("lingering active modal widget after fixture kind %1 closed")
                .arg(spec.kind));
    require(QTest::qWaitFor([] { return QGuiApplication::modalWindow() == nullptr; }, kWaitMs),
            QStringLiteral("lingering modal platform window after fixture kind %1 closed")
                .arg(spec.kind));
    require(!surface.interop->property("busy").toBool(),
            QStringLiteral("controller remained busy after fixture kind %1 closed").arg(spec.kind));
    require(QTest::qWaitFor([&surface] { return surface.openButton->isEnabled(); }, kWaitMs),
            QStringLiteral("open button was not re-enabled after fixture kind %1 closed")
                .arg(spec.kind));

    // 9. Verify window activation returned to Quick window
    require(QTest::qWaitFor([&surface] { return quickWindowActive(surface); }, kWaitMs),
            QStringLiteral("Quick window did not regain activation after fixture kind %1 closed")
                .arg(spec.kind));

    evidence(QStringLiteral(
                 "fixture kind %1 verified and dismissed cleanly; actualTitle='%2' status='%3'")
                 .arg(spec.kind)
                 .arg(actualTitle, surface.status()));
    pass(QStringLiteral("fixture-%1-clean-dismissal").arg(spec.kind));
    return expectedOutcome;
}

// ---- Automation -------------------------------------------------------------

void runAutomation()
{
    Surface surface;
    surface.window = static_cast<QQuickWindow *>(sgw_widgetInteropHostWindow());
    require(qobject_cast<QApplication *>(QCoreApplication::instance()),
            "the host must run under a QApplication, not a bare QGuiApplication");
    require(sgw_widgetInteropHostReady() == 1 && surface.window && surface.window->isExposed(),
            "the host never logged readiness for an exposed Quick window");
    surface.wizardButton =
        namedItem(surface.window->contentItem(), QStringLiteral("widgetInteropWizardButton"));
    surface.menuButton =
        namedItem(surface.window->contentItem(), QStringLiteral("widgetInteropMenuButton"));
    surface.fixtureChooser =
        namedItem(surface.window->contentItem(), QStringLiteral("widgetInteropFixtureChooser"));
    surface.openButton =
        namedItem(surface.window->contentItem(), QStringLiteral("widgetInteropOpenButton"));
    surface.tabStrip = namedItem(surface.window->contentItem(), QStringLiteral("songTabStrip"));
    surface.interop = surface.window->property("widgetInterop").value<QObject *>();
    surface.songTabs = surface.window->property("songTabs").value<QObject *>();
    require(surface.interop && surface.songTabs && surface.tabStrip && surface.wizardButton &&
                surface.menuButton && surface.fixtureChooser && surface.openButton,
            "the QML widget interop contract (controls, chooser, tabs) is incomplete");
    surface.refresh();
    require(surface.status().isEmpty() && surface.history().isEmpty(),
            "the outcome history must start empty");
    // The one-time startup precondition: an automated launch can hand the app a
    // window that was never foregrounded, so the smoke requests activation
    // exactly once, before the first keyboard input. Every later check observes
    // activation only (see proveResumedInput); nothing installs, remembers, or
    // forces focus on an item.
    surface.window->requestActivate();
    require(QTest::qWaitForWindowActive(surface.window, kWaitMs),
            "the Quick window never became active for the smoke");
    require(quickWindowActive(surface),
            "the Quick window is not the active, focused window for the smoke startup");
    QTest::keyClick(surface.window, Qt::Key_Tab);
    require(
        QTest::qWaitFor([&surface] { return surface.window->activeFocusItem() != nullptr; }, 3s),
        "Tab did not move keyboard focus onto any control");
    evidence(QStringLiteral("focus after Tab: '%1'")
                 .arg(surface.window->activeFocusItem()->objectName()));
    evidence(QStringLiteral("host ready window=%1x%2 exposed=true dpr=%3 tab=%4 notes=%5")
                 .arg(surface.window->width())
                 .arg(surface.window->height())
                 .arg(surface.window->devicePixelRatio())
                 .arg(surface.selectedTab())
                 .arg(surface.notes().size()));
    pass(QStringLiteral("host-ready-qapplication-and-qml-surface"));

    QObject *newSongWizard = surface.window->property("newSongWizard").value<QObject *>();
    QObject *newSongResult = surface.window->property("newSongResult").value<QObject *>();
    require(newSongWizard && newSongResult,
            "the root window does not publish newSongWizard and newSongResult");
    try {
        runNewSongWizardSmoke(surface.window.data(), surface.wizardButton.data(), newSongWizard,
                              newSongResult);
    } catch (const std::exception &e) {
        require(false, QString::fromUtf8(e.what()));
    }
    QPointer<QMenu> menu = menuScenario(surface, false, {});
    menu = menuScenario(surface, true, menu);
    anchorScenario(surface);

    // The QML contract's history: one line per completed outcome, in order, and
    // the last outcome on show in the window.
    QStringList expected = {
        QStringLiteral("Menu action: Inspect Current Tab"),
        QStringLiteral("Menu dismissed"),
    };
    for (const auto &spec : kFixtures) {
        expected.append(fixtureScenario(surface, spec));
    }
    const QStringList history = surface.history().split(QLatin1Char('\n'));
    require(history == expected, QStringLiteral("the outcome history does not record every outcome "
                                                "in order (%1 actual vs %2 expected lines)")
                                     .arg(history.size())
                                     .arg(expected.size()));
    require(surface.status() == expected.last(), "the status text does not match the last outcome");
    require(surface.history() == expected.join(QLatin1Char('\n')),
            "the history text does not match the published history");
    evidence(
        QStringLiteral("historyLines=%1 status='%2'").arg(history.size()).arg(surface.status()));

    std::puts("SWIFT_GRID_WIDGET_SMOKE PASS");
    std::fflush(stdout);
    if (!previewMode())
        std::exit(EXIT_SUCCESS);
    evidence(QStringLiteral("preview mode: application left open"));
}

// Waits for the host installer's exposed surface, then drives the automation.
// Reached from sgw_installWidgetInteropSmokeImpl at
// ApplicationWindow.Component.onCompleted, after QApplication construction.
void pumpUntilReady()
{
    auto *app = QCoreApplication::instance();
    require(app, "the smoke installer ran without a QApplication");
    auto *poll = new QTimer(app);
    const auto checkReady = [poll] {
        try {
            if (sgw_widgetInteropHostReady() != 1)
                return;
            auto *window = static_cast<QQuickWindow *>(sgw_widgetInteropHostWindow());
            if (!window || !window->isExposed())
                return;
            if (!namedItem(window->contentItem(), QStringLiteral("widgetInteropWizardButton")) ||
                !namedItem(window->contentItem(), QStringLiteral("widgetInteropMenuButton")) ||
                !namedItem(window->contentItem(), QStringLiteral("widgetInteropFixtureChooser")) ||
                !namedItem(window->contentItem(), QStringLiteral("widgetInteropOpenButton")) ||
                !window->property("newSongWizard").value<QObject *>() ||
                !window->property("newSongResult").value<QObject *>() ||
                !window->property("gridModel").value<QObject *>())
                poll->stop();
            poll->deleteLater();
            runAutomation();
        } catch (const SmokeFailure &failure) {
            reportFailure(failure);
        }
    };
    QObject::connect(poll, &QTimer::timeout, app, checkReady);
    poll->start(25ms);
    QTimer::singleShot(30s, app, [] {
        reportFailure(
            SmokeFailure{"30-second wall timeout waiting for the widget interop surface"});
    });
}

} // namespace

// Called by sgw_installWidgetInteropSmoke (widget_interop.cpp) from the QML
// bootstrap at ApplicationWindow.Component.onCompleted, after the host installer
// has run and QApplication is fully constructed. The environment gate lives
// here so the host translation unit carries no verification-only code.
void sgw_installWidgetInteropSmokeImpl()
{
    if (!boundedMode() && !previewMode())
        return;
    try {
        pumpUntilReady();
    } catch (const SmokeFailure &failure) {
        reportFailure(failure);
    }
}
