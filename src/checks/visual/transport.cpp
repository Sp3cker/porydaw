// Freeze the QWidget reference before replacing its renderer. Baseline IDs and
// semantic regions describe the visible surface, not the future QML hierarchy.
// Run at the application's one base font. Freeze the whole strip, including
// spacing, separators and overflow chrome, as well as individual controls and
// the transient pointer and open-popup states a real interaction produces.
#include "checks/visual/transportregions.h"
#include "checks/visual/visualfixture.h"

#include "ui/theme/themeresolver.h"
#include "ui/theme/themeruntime.h"
#include "ui/transportbar.h"

#include <QAbstractAnimation>
#include <QAbstractItemView>
#include <QAction>
#include <QApplication>
#include <QComboBox>
#include <QCoreApplication>
#include <QDial>
#include <QDir>
#include <QEnterEvent>
#include <QLineEdit>
#include <QMainWindow>
#include <QMap>
#include <QPropertyAnimation>
#include <QSettings>
#include <QSpinBox>
#include <QStyle>
#include <QStyleOptionComboBox>
#include <QTemporaryDir>
#include <QToolButton>
#include <QWindow>
#include <QtTest>

namespace {

using Regions = QList<checks::visual::Region>;
using PlaybackState = TransportBar::PlaybackState;

// Each frozen row names its production theme; the same name reaches the
// baseline ID, so a QML adapter can pair appearances with themes by name.
struct ThemeVariant {
    const char *id;
    themes::Theme (*theme)();
};

const ThemeVariant kThemeVariants[] = {
    {"vanilla", &themes::vanilla},
    {"darkneutralhigh", &themes::darkNeutralHigh},
    {"immaterial", &themes::immaterial},
};

void applyTransportTheme(const QString &name)
{
    for (const ThemeVariant &variant : kThemeVariants) {
        if (name == QLatin1String(variant.id)) {
            themes::apply(*qApp, variant.theme());
            return;
        }
    }
    QFAIL(qPrintable(QStringLiteral("unknown transport theme '%1'").arg(name)));
}

void configureLoaded(TransportBar &bar, PlaybackState state)
{
    bar.setSessionAvailable(true);
    bar.setPlaybackState(state);
    bar.setFollowPlayhead(true);
    bar.loopAction()->setChecked(true);
    bar.resonanceAction()->setChecked(false);
    bar.setTimeText(QStringLiteral("1:23.4 / 4:56.7"));
    bar.setMasterVolume(96, true);
    bar.setOutputVolume(80);
    bar.setScaleState(0, porydaw_scale::ScaleId::major, true, false);
}

// Where the style animates layout changes, the main-window layout moves a
// widget through a QPropertyAnimation parented to that widget and deletes it
// once it stops. Waiting for that animation to disappear is the layout's own
// completion condition, so a capture never lands mid-move.
bool layoutSettled(const QWidget &widget)
{
    for (QPropertyAnimation *animation : widget.findChildren<QPropertyAnimation *>()) {
        if (animation->state() == QAbstractAnimation::Running)
            return false;
    }
    return true;
}

// The pointer half of a settled row. The shared showSettled parks focus; every
// transport row then parks the pointer on the host's own centre, below the bar,
// in the repo input fixtures' enter-then-move order, which needs no native
// cursor movement or OS focus. No row can then inherit hover left on a control
// by the previous row's pointer.
void parkPointer(QWidget &host)
{
    QWindow *const window = host.windowHandle();
    QVERIFY2(window, "the shown host must own a window");
    const QPoint point = host.rect().center();
    QEnterEvent enter(point, point, window->mapToGlobal(point));
    QCoreApplication::sendEvent(window, &enter);
    QTest::mouseMove(window, point);
}

// The strip's controls plus the whole surface: the region set every frozen bar
// capture carries, so no control is compared without the chrome around it.
Regions stripRegions(TransportBar &bar)
{
    Regions regions = checks::visual::transportRegions(bar);
    regions.append({QStringLiteral("transport.surface"), bar.rect()});
    return regions;
}

QMap<QString, QRect> boundsByName(TransportBar &bar)
{
    QMap<QString, QRect> result;
    for (const checks::visual::Region &region : checks::visual::transportRegions(bar))
        result.insert(region.name, region.bounds);
    return result;
}

// Every snapshot has to keep the contract the regions promise: named,
// non-degenerate rectangles that render inside the bar. How many controls the
// strip carries is production's decision, not a fact this test freezes.
void verifyRegions(const TransportBar &bar, const QMap<QString, QRect> &regions)
{
    QVERIFY2(!regions.isEmpty(), "the strip must expose named controls");
    for (auto it = regions.cbegin(); it != regions.cend(); ++it) {
        QVERIFY2(it.value().isValid(),
                 qPrintable(QStringLiteral("%1 must render a real rectangle").arg(it.key())));
        QVERIFY2(bar.rect().contains(it.value()),
                 qPrintable(QStringLiteral("%1 must render inside the bar").arg(it.key())));
    }
}

} // namespace

class VisualTransportTest final : public QObject
{
    Q_OBJECT

  private slots:
    void initTestCase();
    void cleanup();
    void appearance_data();
    void appearance();
    void interactionAppearance_data();
    void interactionAppearance();
    void geometrySurvivesStateAndWidthChanges();

  private:
    QTemporaryDir m_settingsDirectory;
};

void VisualTransportTest::initTestCase()
{
    QVERIFY2(m_settingsDirectory.isValid(), "could not create isolated QSettings directory");
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_settingsDirectory.path());
    QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, m_settingsDirectory.path());
}

void VisualTransportTest::cleanup()
{
    themes::apply(*qApp, themes::vanilla());
}

namespace {

// One frozen appearance row: the resting strip `configureLoaded` leaves
// (`configure` null) plus whatever the named state changes, frozen at
// `hostWidth`. The two narrow widths stress the strip's own limits: 640 gives
// up the whole tail from the scale control on, 900 gives up less of it, and
// both expose the overflow affordance the strip answers with. Which controls
// are given up, in what order, the disabled Fold and Volume caption next to the
// still enabled follow and resonance in `unavailable`, and the spacing between
// all of them are the current reference behaviour of the strip, not a licence
// to redesign it.
struct AppearanceRow {
    const char *state;
    void (*configure)(TransportBar &) = nullptr;
    int hostWidth = 1100;
    bool givesControlsUp = false;
};

const AppearanceRow kAppearanceRows[] = {
    {.state = "unavailable",
     .configure =
         [](TransportBar &bar) {
             bar.setSessionAvailable(false);
             bar.setPlaybackState(PlaybackState::Unavailable);
             bar.setMasterVolume(127, false);
             bar.setTimeText(QStringLiteral("0:00.0 / 0:00.0"));
         }},
    {.state = "stopped"},
    {.state = "paused",
     .configure = [](TransportBar &bar) { bar.setPlaybackState(PlaybackState::Paused); }},
    {.state = "playing",
     .configure = [](TransportBar &bar) { bar.setPlaybackState(PlaybackState::Playing); }},
    {.state = "toggles-off",
     .configure =
         [](TransportBar &bar) {
             bar.loopAction()->setChecked(false);
             bar.setFollowPlayhead(false);
             bar.resonanceAction()->setChecked(false);
             bar.setScaleState(0, porydaw_scale::ScaleId::major, false, false);
         }},
    {.state = "toggles-on-long-text",
     .configure =
         [](TransportBar &bar) {
             bar.loopAction()->setChecked(true);
             bar.setFollowPlayhead(true);
             bar.resonanceAction()->setChecked(true);
             bar.setScaleState(10, porydaw_scale::ScaleId::whole_half_diminished, true, true);
             bar.setTimeText(QStringLiteral("99:59.9 / 99:59.9"));
         }},
    // The widest production scale name has to fit the scale combo's current text
    // without clipping; the combo keeps its dressed-up highlight and fold state
    // so the frozen row carries that chrome too.
    {.state = "widest-scale-name",
     .configure =
         [](TransportBar &bar) {
             bar.setScaleState(10, porydaw_scale::ScaleId::altered, true, true);
         }},
    {.state = "volume-min",
     .configure =
         [](TransportBar &bar) {
             bar.setMasterVolume(0, true);
             bar.setOutputVolume(0);
         }},
    {.state = "volume-max",
     .configure =
         [](TransportBar &bar) {
             bar.setMasterVolume(127, true);
             bar.setOutputVolume(100);
         }},
    {.state = "narrow", .hostWidth = 640, .givesControlsUp = true},
    {.state = "intermediate", .hostWidth = 900, .givesControlsUp = true},
};

} // namespace

void VisualTransportTest::appearance_data()
{
    // Both columns come from the table `appearance()` dispatches on, so a
    // scenario can never exist in one place and not the other.
    QTest::addColumn<QString>("theme");
    QTest::addColumn<int>("row");
    for (const ThemeVariant &variant : kThemeVariants) {
        int row = 0;
        for (const AppearanceRow &entry : kAppearanceRows) {
            const QString theme = QString::fromLatin1(variant.id);
            const QString tag = QStringLiteral("%1/%2").arg(theme, QLatin1String(entry.state));
            QTest::newRow(qPrintable(tag)) << theme << row;
            ++row;
        }
    }
}

void VisualTransportTest::appearance()
{
    QFETCH(QString, theme);
    QFETCH(int, row);
    const AppearanceRow &entry = kAppearanceRows[row];
    applyTransportTheme(theme);
    // Production parents the bar to the workspace window and addToolBar()s it;
    // a standalone toolbar would freeze borders and overflow the real chrome
    // never has.
    QMainWindow host;
    TransportBar bar(&host);
    host.addToolBar(&bar);
    configureLoaded(bar, PlaybackState::Stopped);
    if (entry.configure)
        entry.configure(bar);
    host.resize(entry.hostWidth, 240);
    checks::visual::showSettled(host);
    parkPointer(host);
    auto regions = stripRegions(bar);
    if (entry.givesControlsUp) {
        auto *overflow = bar.findChild<QToolButton *>(QStringLiteral("qt_toolbar_ext_button"));
        QVERIFY(overflow);
        QVERIFY2(overflow->isVisible(),
                 "a width that gives up controls must expose the overflow affordance");
        regions.append({QStringLiteral("transport.overflow"),
                        QRect(overflow->mapTo(&bar, QPoint()), overflow->size())});
    }
    QString error;
    const QString id = QStringLiteral("transportbar/%1/%2").arg(theme, QLatin1String(entry.state));
    QVERIFY2(checks::visual::compareWidget(id, bar, regions, &error), qPrintable(error));
}

namespace {

// The live controls the interaction rows freeze: a toolbar action owns its own
// button, every other control is a named child of the strip. A row resolves its
// control once, so a row that cannot find one fails under the row's own state
// name.
QWidget *playButton(TransportBar &bar)
{
    return bar.widgetForAction(bar.playAction());
}

QWidget *loopToggle(TransportBar &bar)
{
    return bar.widgetForAction(bar.loopAction());
}

QWidget *resonanceToggle(TransportBar &bar)
{
    return bar.widgetForAction(bar.resonanceAction());
}

QWidget *scaleRootCombo(TransportBar &bar)
{
    return bar.findChild<QComboBox *>(QStringLiteral("transportScaleRoot"));
}

QWidget *scaleTypeCombo(TransportBar &bar)
{
    return bar.findChild<QComboBox *>(QStringLiteral("transportScaleType"));
}

QWidget *scaleFoldButton(TransportBar &bar)
{
    return bar.findChild<QToolButton *>(QStringLiteral("transportScaleFold"));
}

QWidget *masterVolumeField(TransportBar &bar)
{
    return bar.findChild<QSpinBox *>(QStringLiteral("transportMasterVolume"));
}

QWidget *outputVolumeDial(TransportBar &bar)
{
    return bar.findChild<QDial *>(QStringLiteral("transportOutputVolume"));
}

QWidget *overflowAffordance(TransportBar &bar)
{
    return bar.findChild<QToolButton *>(QStringLiteral("qt_toolbar_ext_button"));
}

// What a row does with its control once the host is shown. Every kind but the
// pointer one owns its capture and returns.
enum class InteractionKind {
    Pointer,          // rest the pointer on the control, freeze the strip under it
    Popup,            // open the scale combo's own popup window, freeze both
    HeldDial,         // hold the output dial's custom face down
    FocusedField,     // carry the frozen text selection a focused field shows
    OverflowExpanded, // grow the strip in place and reveal what it gave up
};

// What a pointer row pins about the resting strip's toggle polarity: nothing, or
// that toggle resting on/off. The resting strip keeps loop checked and
// resonance unchecked, and the toolbar's checked state is what wins over hover
// while a toggle stays on, so those two rows freeze both backgrounds under the
// pointer.
enum class TogglePin { None, On, Off };

// The pointer rest a pointer row freezes: where the pointer sits in the control,
// and why the row's own lane did not resolve (empty when it did). Carrying the
// reason lets the row's lane stay one resolver while the failure still names the
// row it belongs to.
struct PointerRest {
    QPoint point;
    QString problem;
};

// One frozen interaction row: the live production control it freezes, where the
// pointer rests inside that control (`lane` null: the control's own centre), the
// resting polarity it pins, whether it holds the control down, and the width the
// strip is frozen at.
struct InteractionRow {
    const char *state;
    InteractionKind kind = InteractionKind::Pointer;
    QWidget *(*control)(TransportBar &) = nullptr;
    PointerRest (*lane)(const QWidget &control) = nullptr;
    TogglePin togglePin = TogglePin::None;
    bool held = false;
    int hostWidth = 1100;
};

// The dropdown arrow is a style sub-control instead of a child widget, so its
// rect is the style's own answer for this combo - never a guessed offset inside
// the body - and that lane is the whole difference the arrow row freezes.
PointerRest scaleArrowLane(const QWidget &control)
{
    const auto *const combo = qobject_cast<const QComboBox *>(&control);
    if (!combo)
        return {{}, QStringLiteral("the scale combo must exist to resolve its dropdown lane")};
    QStyleOptionComboBox option;
    option.initFrom(combo);
    option.subControls = QStyle::SC_All;
    option.editable = combo->isEditable();
    option.frame = combo->hasFrame();
    option.currentText = combo->currentText();
    const QStyle *const style = combo->style();
    const QRect arrow =
        style->subControlRect(QStyle::CC_ComboBox, &option, QStyle::SC_ComboBoxArrow, combo);
    if (!combo->rect().contains(arrow.center()))
        return {{}, QStringLiteral("the dropdown arrow must resolve to a rect inside the combo")};
    // The combo runs this same hit test to pick its hovered sub-control, so the
    // lane has to resolve the arrow before anything is captured.
    if (style->hitTestComplexControl(QStyle::CC_ComboBox, &option, arrow.center(), combo) !=
        QStyle::SC_ComboBoxArrow)
        return {{}, QStringLiteral("the dropdown arrow must be the lane the combo hit-tests")};
    return {arrow.center(), {}};
}

const InteractionRow kInteractionRows[] = {
    {.state = "hover-play", .control = playButton},
    {.state = "pressed-play", .control = playButton, .held = true},
    {.state = "hover-loop", .control = loopToggle, .togglePin = TogglePin::On},
    {.state = "hover-resonance", .control = resonanceToggle, .togglePin = TogglePin::Off},
    // The body of a themed scale combo paints no hover feedback of its own, so
    // the body row freezes it under the pointer exactly as it rests; the
    // dropdown lane beside it is the part that answers hover, which the arrow
    // row freezes.
    {.state = "hover-scale-type", .control = scaleTypeCombo},
    {.state = "hover-scale-arrow", .control = scaleTypeCombo, .lane = scaleArrowLane},
    {.state = "pressed-fold", .control = scaleFoldButton, .held = true},
    {.state = "pressed-output", .kind = InteractionKind::HeldDial, .control = outputVolumeDial},
    {.state = "focused-volume",
     .kind = InteractionKind::FocusedField,
     .control = masterVolumeField},
    {.state = "root-popup", .kind = InteractionKind::Popup, .control = scaleRootCombo},
    {.state = "scale-popup", .kind = InteractionKind::Popup, .control = scaleTypeCombo},
    {.state = "overflow-expanded",
     .kind = InteractionKind::OverflowExpanded,
     .control = overflowAffordance,
     .hostWidth = 640},
};

} // namespace

void VisualTransportTest::interactionAppearance_data()
{
    // Same table `interactionAppearance()` dispatches on: one row per scenario,
    // the pointer rows and the flows that own their capture alike.
    QTest::addColumn<QString>("theme");
    QTest::addColumn<int>("row");
    for (const ThemeVariant &variant : kThemeVariants) {
        int row = 0;
        for (const InteractionRow &entry : kInteractionRows) {
            const QString theme = QString::fromLatin1(variant.id);
            const QString tag = QStringLiteral("%1/%2").arg(theme, QLatin1String(entry.state));
            QTest::newRow(qPrintable(tag)) << theme << row;
            ++row;
        }
    }
}

void VisualTransportTest::interactionAppearance()
{
    QFETCH(QString, theme);
    QFETCH(int, row);
    const InteractionRow &entry = kInteractionRows[row];
    const QString state = QString::fromLatin1(entry.state);
    applyTransportTheme(theme);
    QMainWindow host;
    TransportBar bar(&host);
    host.addToolBar(&bar);
    configureLoaded(bar, PlaybackState::Stopped);
    // The overflow row needs the width where the strip gives controls up; the
    // rest of the interaction rows freeze the fully revealed strip.
    host.resize(entry.hostWidth, 240);
    checks::visual::showSettled(host);
    parkPointer(host);

    QString error;
    const QString id = QStringLiteral("transportbar/%1/%2").arg(theme, state);
    QWidget *const control = entry.control(bar);
    QVERIFY2(control,
             qPrintable(QStringLiteral("%1 must resolve a live production control").arg(state)));

    switch (entry.kind) {
    case InteractionKind::Popup: {
        // An open popup lives in its own transient window, so the popup surface
        // itself is the capture; the bar's own grab never contains it.
        auto *const combo = qobject_cast<QComboBox *>(control);
        QVERIFY2(combo, "the popup rows freeze the scale combo");
        QVERIFY2(combo->isEnabled() && combo->isVisibleTo(&bar),
                 "a loaded bar must keep the scale combo live, not parked in the overflow");
        combo->showPopup();
        QWidget *popup = combo->view()->window();
        QVERIFY2(popup && popup != combo->window(),
                 "the scale combo must open a Qt-rendered popup window");
        QTRY_VERIFY_WITH_TIMEOUT(popup->isVisible(), 5000);
        // Opening moves focus into the popup view, so the raster would
        // otherwise depend on whether this process owns the active window.
        // The sample-picker popup baseline drops that transience the same way.
        if (QWidget *focused = QApplication::focusWidget())
            focused->clearFocus();
        QApplication::processEvents();
        QVERIFY2(popup->isVisible(), "the open popup must survive its focus being dropped");
        const QRect rowRect = combo->view()->visualRect(combo->view()->currentIndex());
        const QRect rowBounds(combo->view()->viewport()->mapTo(popup, rowRect.topLeft()),
                              rowRect.size());
        const QRect rowRegion = rowBounds.intersected(popup->rect());
        QVERIFY2(!rowRegion.isEmpty(), "the open popup must render its current row");
        const QList<checks::visual::Region> regions{
            {QStringLiteral("transport.popup"), popup->rect()},
            {QStringLiteral("transport.popup.current-row"), rowRegion}};
        // The open combo repaints its own raster into its open state while the
        // popup lives, so the bar is frozen alongside the popup under this
        // row's anchor ID; both captures happen before anything closes — the
        // quick suite's popup rows freeze the form alone by contrast.
        QString anchorError;
        const bool matched = checks::visual::compareWidget(id, *popup, regions, &error);
        const bool anchorMatched = checks::visual::compareWidget(
            id + QStringLiteral("-anchor"), bar, stripRegions(bar), &anchorError);
        combo->hidePopup();
        QApplication::processEvents();
        QVERIFY2(matched, qPrintable(error));
        QVERIFY2(anchorMatched, qPrintable(anchorError));
        return;
    }
    case InteractionKind::HeldDial: {
        // The output dial repaints its custom face while held down; only a real
        // press sets that state, and no button state covers it.
        auto *const dial = qobject_cast<QDial *>(control);
        QVERIFY2(dial, "the held-dial row freezes the output volume dial");
        const QPoint center = dial->rect().center();
        QTest::mousePress(dial, Qt::LeftButton, Qt::NoModifier, center);
        QVERIFY2(dial->isSliderDown(), "a real press must hold the dial down");
        const bool matched = checks::visual::compareWidget(id, bar, stripRegions(bar), &error);
        QTest::mouseRelease(dial, Qt::LeftButton, Qt::NoModifier, center);
        QVERIFY2(matched, qPrintable(error));
        return;
    }
    case InteractionKind::FocusedField: {
        // The master volume field is frozen with its text selected: a selection
        // keeps the caret out of the raster on this platform (the Fusion/macOS
        // answer to SH_BlinkCursorWhenTextSelected is false and the line edit
        // only shows a caret once focus arrives with no selection), so the row
        // is pixel-stable instead of catching a blink. Focus is delivered as a
        // normal window focus event rather than native activation, and the
        // assertion checks the focus widget itself, which is what decides the
        // rendering.
        auto *const spin = qobject_cast<QSpinBox *>(control);
        QVERIFY2(spin && spin->isEnabled() && spin->isVisibleTo(&bar),
                 "a loaded bar must keep the master volume field live");
        // The offscreen platform never grants real activation
        // (activateWindow() is a no-op there), so the toolkit-level active
        // window is set directly — the same path a native focus change takes.
        QT_WARNING_PUSH
        QT_WARNING_DISABLE_DEPRECATED
        QApplication::setActiveWindow(&host);
        QT_WARNING_POP
        QApplication::processEvents();
        // The selection has to exist before focus lands, or the field would
        // show a caret with nothing selected.
        spin->selectAll();
        spin->setFocus(Qt::MouseFocusReason);
        QApplication::processEvents();
        QWidget *const focused = QApplication::focusWidget();
        QVERIFY2(focused && (focused == spin || spin->isAncestorOf(focused)),
                 "the master volume field must hold the focus");
        // QAbstractSpinBox keeps its editor protected; the field's only
        // QLineEdit descendant is that editor.
        auto *field = spin->findChild<QLineEdit *>();
        QVERIFY2(field && field->hasSelectedText(),
                 "the volume field must show a selection, never a caret mid-blink");
        QCOMPARE(field->selectedText(), field->text());
        const bool matched = checks::visual::compareWidget(id, bar, stripRegions(bar), &error);
        QVERIFY2(matched, qPrintable(error));
        return;
    }
    case InteractionKind::OverflowExpanded: {
        // A strip hosted in a QMainWindow has no overflow menu to open - Qt
        // builds the extension QMenu only for a floating toolbar, or for a
        // window that cannot fit the expanded strip - so the expansion itself is
        // the real overflow reference here: a click grows the strip in place and
        // reveals the controls it had given up.
        auto *const extension = qobject_cast<QToolButton *>(control);
        QVERIFY2(extension && extension->isVisible() && extension->isEnabled(),
                 "a width that gives controls up must offer a live overflow affordance");
        auto *scaleType = bar.findChild<QComboBox *>(QStringLiteral("transportScaleType"));
        auto *masterVolume = bar.findChild<QSpinBox *>(QStringLiteral("transportMasterVolume"));
        auto *outputVolume = bar.findChild<QDial *>(QStringLiteral("transportOutputVolume"));
        QVERIFY2(scaleType && masterVolume && outputVolume,
                 "the controls the strip gives up must exist to be revealed again");
        QVERIFY2(!scaleType->isVisibleTo(&bar) && !masterVolume->isVisibleTo(&bar) &&
                     !outputVolume->isVisibleTo(&bar),
                 "the narrow strip must actually give these controls up before expanding");
        const int collapsedHeight = bar.height();
        const auto collapsedBounds = boundsByName(bar);
        QWindow *const window = host.windowHandle();
        QVERIFY2(window, "the shown host must own a window");
        const QPoint point =
            window->mapFromGlobal(extension->mapToGlobal(extension->rect().center()));
        QEnterEvent enter(point, point, window->mapToGlobal(point));
        QCoreApplication::sendEvent(window, &enter);
        QTest::mouseMove(window, point);
        QTRY_VERIFY2_WITH_TIMEOUT(extension->underMouse(),
                                  "the pointer must rest on the overflow affordance", 2000);
        QTest::mouseClick(extension, Qt::LeftButton, Qt::NoModifier, extension->rect().center());
        QTRY_VERIFY2_WITH_TIMEOUT(
            layoutSettled(bar) && bar.height() > collapsedHeight && scaleType->isVisibleTo(&bar) &&
                masterVolume->isVisibleTo(&bar) && outputVolume->isVisibleTo(&bar),
            "the strip must expand in place and reveal what it gave up", 2000);
        auto regions = stripRegions(bar);
        regions.append({QStringLiteral("transport.overflow"),
                        QRect(extension->mapTo(&bar, QPoint()), extension->size())});
        const bool matched = checks::visual::compareWidget(id, bar, regions, &error);
        // Collapsing has to restore the narrow reference, so the row freezes the
        // expansion without leaving the strip stuck in it.
        QTest::mouseClick(extension, Qt::LeftButton, Qt::NoModifier, extension->rect().center());
        QTRY_VERIFY2_WITH_TIMEOUT(layoutSettled(bar) && bar.height() == collapsedHeight &&
                                      !scaleType->isVisibleTo(&bar) &&
                                      !masterVolume->isVisibleTo(&bar) &&
                                      !outputVolume->isVisibleTo(&bar),
                                  "the strip must collapse back to its narrow reference", 2000);
        // Same names and same bounds, not just the same height: the collapsed
        // reference has to come back exactly, region by region.
        QTRY_COMPARE_WITH_TIMEOUT(boundsByName(bar), collapsedBounds, 2000);
        QVERIFY2(matched, qPrintable(error));
        return;
    }
    case InteractionKind::Pointer:
        break;
    }

    // The shared pointer flow: dress the control's own rest state, then freeze
    // the strip under the pointer. A toggle row pins the polarity its capture
    // shows, because the toolbar's checked state is what wins over hover while
    // the toggle stays on.
    QVERIFY2(
        control->isEnabled() && control->isVisibleTo(&bar),
        qPrintable(
            QStringLiteral("%1 must freeze a live control, not one the strip gave up").arg(state)));
    if (entry.togglePin != TogglePin::None) {
        auto *const button = qobject_cast<QToolButton *>(control);
        QAction *const action = button ? button->defaultAction() : nullptr;
        const bool wanted = entry.togglePin == TogglePin::On;
        QVERIFY2(
            action && action->isChecked() == wanted,
            qPrintable(QStringLiteral("%1 freezes the resting strip, where that toggle "
                                      "rests %2")
                           .arg(state, wanted ? QStringLiteral("on") : QStringLiteral("off"))));
    }
    const PointerRest rest =
        entry.lane ? entry.lane(*control) : PointerRest{control->rect().center(), {}};
    QVERIFY2(rest.problem.isEmpty(), qPrintable(QStringLiteral("%1: %2").arg(state, rest.problem)));
    // Appearance checks do not need native OS focus: the repo input fixtures
    // enter the window and then move inside it, which is enough to place real
    // hover on the control without moving the desktop cursor.
    QVERIFY2(QTest::qWaitForWindowExposed(&host, 2000),
             "the host window must be exposed before pointer input");
    checks::visual::parkFocus(host);
    QWindow *const window = host.windowHandle();
    QVERIFY2(window, "the shown host must own a window");
    const QPoint point = window->mapFromGlobal(control->mapToGlobal(rest.point));
    QEnterEvent enter(point, point, window->mapToGlobal(point));
    QCoreApplication::sendEvent(window, &enter);
    QTest::mouseMove(window, point);
    QTRY_VERIFY2_WITH_TIMEOUT(control->underMouse(),
                              "the pointer must rest on the requested transport control", 2000);
    if (entry.held) {
        QTest::mousePress(control, Qt::LeftButton, Qt::NoModifier, rest.point);
        auto *button = qobject_cast<QAbstractButton *>(control);
        QVERIFY2(button && button->isDown(), "a real press must hold the tool button down");
    }
    const bool matched = checks::visual::compareWidget(id, bar, stripRegions(bar), &error);
    if (entry.held)
        QTest::mouseRelease(control, Qt::LeftButton, Qt::NoModifier, rest.point);
    QVERIFY2(matched, qPrintable(error));
}

void VisualTransportTest::geometrySurvivesStateAndWidthChanges()
{
    QMainWindow host;
    TransportBar bar(&host);
    host.addToolBar(&bar);
    configureLoaded(bar, PlaybackState::Stopped);
    // All controls fit at this width under the production base font; width is an
    // input, never an expected size derived from the implementation being
    // protected.
    const int wideWidth = 1400;
    const int widerWidth = 1600;
    const int narrowWidth = 640;
    host.resize(wideWidth, 240);
    checks::visual::showSettled(host);
    parkPointer(host);
    const auto original = boundsByName(bar);
    verifyRegions(bar, original);
    // A playback state change must not move the strip: the same controls keep
    // the same bounds through the production setters.
    for (auto state : {PlaybackState::Playing, PlaybackState::Paused, PlaybackState::Unavailable,
                       PlaybackState::Stopped}) {
        bar.setPlaybackState(state);
        bar.setSessionAvailable(state != PlaybackState::Unavailable);
        bar.setMasterVolume(0, state != PlaybackState::Unavailable);
        bar.setOutputVolume(0);
        bar.setTimeText(QStringLiteral("99:59.9 / 99:59.9"));
        bar.setScaleState(10, porydaw_scale::ScaleId::whole_half_diminished, false, true);
        // The change has to reach the layout before it is measured, so the
        // layout request it filed is delivered first; the style then animates
        // layout moves through a property animation, so the measurement also
        // waits for that layout's own completion condition instead of trusting
        // one event pump.
        QCoreApplication::sendPostedEvents(nullptr, QEvent::LayoutRequest);
        QTRY_VERIFY_WITH_TIMEOUT(layoutSettled(bar), 2000);
        QCOMPARE(boundsByName(bar), original);
    }
    // Widening the host may only move the strip's tail: every control keeps its
    // row, its size and its anchoring to one of the window's edges, and what
    // rides the right edge gains exactly the width the window gained.
    host.resize(widerWidth, 240);
    QTRY_VERIFY2_WITH_TIMEOUT(layoutSettled(bar) && boundsByName(bar) != original,
                              "the wider host must move the strip's right-anchored controls", 2000);
    const auto expanded = boundsByName(bar);
    verifyRegions(bar, expanded);
    QCOMPARE(expanded.keys(), original.keys());
    const int gained = widerWidth - wideWidth;
    for (auto it = original.cbegin(); it != original.cend(); ++it) {
        const QRect was = it.value();
        const QRect now = expanded.value(it.key());
        QCOMPARE(now.top(), was.top());
        QCOMPARE(now.size(), was.size());
        QVERIFY2(now.left() == was.left() || now.left() == was.left() + gained,
                 qPrintable(QStringLiteral("%1 must stay anchored to a strip edge, not slide %2px")
                                .arg(it.key())
                                .arg(now.left() - was.left())));
    }
    // The narrow width has to re-lay the strip out, or the restore below would
    // prove nothing; coming back then has to restore the wide reference exactly,
    // region by region, not merely a similarly sized strip.
    host.resize(narrowWidth, 240);
    QTRY_VERIFY2_WITH_TIMEOUT(layoutSettled(bar) && boundsByName(bar) != original,
                              "the narrow width must re-lay the strip out", 2000);
    verifyRegions(bar, boundsByName(bar));
    host.resize(wideWidth, 240);
    QTRY_COMPARE_WITH_TIMEOUT(boundsByName(bar), original, 2000);
}

int runVisualTransportCheck(QApplication &application, const QStringList &qtArguments)
{
    // This dedicated check process uses one application font. Give its theme
    // assets private scratch storage, independent of other visual-check runs.
    // Keep failure artifacts outside the automatically removed scratch tree.
    if (qEnvironmentVariableIsEmpty("PORYDAW_VISUAL_ARTIFACT_DIR"))
        qputenv("PORYDAW_VISUAL_ARTIFACT_DIR",
                QDir::temp().absoluteFilePath(QStringLiteral("porydaw-visual-artifacts")).toUtf8());
    QTemporaryDir temporaryDirectory;
    if (!temporaryDirectory.isValid())
        qFatal("visual-transport: could not create private temporary directory");
    const auto temporaryPath = temporaryDirectory.path().toUtf8();
    qputenv("TMPDIR", temporaryPath);
    qputenv("TEMP", temporaryPath);
    qputenv("TMP", temporaryPath);
    checks::visual::prepare(application);
    VisualTransportTest test;
    QStringList arguments{QStringLiteral("visual-transport")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "transport.moc"
