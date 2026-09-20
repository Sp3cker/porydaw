// Freeze the QWidget reference before replacing its renderer. Baseline IDs and
// semantic regions describe the visible surface, not the future QML hierarchy.
// Run at the application's one base font. Freeze the whole strip, including
// spacing, separators and overflow chrome, as well as individual controls and
// the transient pointer and open-popup states a real interaction produces.
#include "checks/visual/visualbaseline.h"

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
#include <QFocusEvent>
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

Regions transportRegions(TransportBar &bar)
{
    Regions regions;
    const auto append = [&](const char *name, QWidget *widget) {
        // Missing controls are errors, not an excuse to silently lose coverage.
        if (!widget) {
            regions.append({QString::fromLatin1(name), {}});
            return;
        }
        if (widget->isVisibleTo(&bar)) {
            const QRect bounds(widget->mapTo(&bar, QPoint()), widget->size());
            regions.append({QString::fromLatin1(name), bounds.intersected(bar.rect())});
        }
    };
    append("transport.go-to-start", bar.widgetForAction(bar.goToStartAction()));
    append("transport.play", bar.widgetForAction(bar.playAction()));
    append("transport.pause", bar.widgetForAction(bar.pauseAction()));
    append("transport.stop", bar.widgetForAction(bar.stopAction()));
    append("transport.loop", bar.widgetForAction(bar.loopAction()));
    append("transport.follow-playhead", bar.widgetForAction(bar.followPlayheadAction()));
    append("transport.resonance", bar.widgetForAction(bar.resonanceAction()));
    const struct {
        const char *name;
        const char *objectName;
    } controls[] = {
        {"transport.time", "transportTimeLabel"},
        {"transport.scale-root", "transportScaleRoot"},
        {"transport.scale-type", "transportScaleType"},
        {"transport.scale-highlight", "transportScaleHighlight"},
        {"transport.scale-fold", "transportScaleFold"},
        {"transport.master-volume-caption", "transportMasterVolumeCaption"},
        {"transport.master-volume", "transportMasterVolume"},
        {"transport.output-volume-caption", "transportOutputVolumeCaption"},
        {"transport.output-volume", "transportOutputVolume"},
    };
    for (const auto &control : controls)
        append(control.name, bar.findChild<QWidget *>(QString::fromLatin1(control.objectName)));
    return regions;
}

// Drops focus from `root` or any of its descendants: showing a host hands
// focus to an auto-focused control, so that control's caret must never reach
// a grab.
void releaseFocus(QWidget &root)
{
    QWidget *const focused = QApplication::focusWidget();
    if (focused && (focused == &root || root.isAncestorOf(focused)))
        focused->clearFocus();
    QApplication::processEvents();
}

void showSettled(QWidget &widget)
{
    const QSize requested = widget.size();
    widget.show();
    QApplication::processEvents();
    widget.resize(requested);
    QApplication::processEvents();
    // Enter the window at the host's empty centre, below the bar, then move
    // there — the repo input fixtures' enter-then-move order, which needs no
    // native cursor movement or OS focus. No row can then inherit hover left
    // on a control by the previous row's pointer.
    QWindow *const window = widget.windowHandle();
    QVERIFY2(window, "the shown host must own a window");
    const QPoint point = widget.rect().center();
    QEnterEvent enter(point, point, window->mapToGlobal(point));
    QCoreApplication::sendEvent(window, &enter);
    QTest::mouseMove(window, point);
    releaseFocus(widget);
}

void configureLoaded(TransportBar &bar, TransportBar::PlaybackState state)
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

// Each frozen row names its production theme; the same name reaches the
// baseline ID, so a QML adapter can pair appearances with themes by name.
void applyTransportTheme(const QString &name)
{
    if (name == QStringLiteral("darkneutralhigh"))
        themes::apply(*qApp, themes::darkNeutralHigh());
    else if (name == QStringLiteral("immaterial"))
        themes::apply(*qApp, themes::immaterial());
    else
        themes::apply(*qApp, themes::vanilla());
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

QMap<QString, QRect> boundsByName(TransportBar &bar)
{
    QMap<QString, QRect> result;
    for (const auto &region : transportRegions(bar))
        result.insert(region.name, region.bounds);
    return result;
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

void VisualTransportTest::appearance_data()
{
    QTest::addColumn<QString>("theme");
    QTest::addColumn<QString>("state");
    for (const char *theme : {"vanilla", "darkneutralhigh", "immaterial"}) {
        for (const char *state :
             {"unavailable", "stopped", "paused", "playing", "toggles-off", "toggles-on-long-text",
              "widest-scale-name", "volume-min", "volume-max", "narrow", "intermediate"}) {
            const QByteArray name = QByteArray(theme) + "/" + state;
            QTest::newRow(name.constData())
                << QString::fromLatin1(theme) << QString::fromLatin1(state);
        }
    }
}

void VisualTransportTest::appearance()
{
    QFETCH(QString, theme);
    QFETCH(QString, state);
    applyTransportTheme(theme);
    // Production parents the bar to the workspace window and addToolBar()s it;
    // a standalone toolbar would freeze borders and overflow the real chrome
    // never has.
    QMainWindow host;
    TransportBar bar(&host);
    host.addToolBar(&bar);
    configureLoaded(bar, TransportBar::PlaybackState::Stopped);
    if (state == QStringLiteral("unavailable")) {
        bar.setSessionAvailable(false);
        bar.setPlaybackState(TransportBar::PlaybackState::Unavailable);
        bar.setMasterVolume(127, false);
        bar.setTimeText(QStringLiteral("0:00.0 / 0:00.0"));
    } else if (state == QStringLiteral("playing")) {
        bar.setPlaybackState(TransportBar::PlaybackState::Playing);
    } else if (state == QStringLiteral("paused")) {
        bar.setPlaybackState(TransportBar::PlaybackState::Paused);
    } else if (state == QStringLiteral("toggles-off")) {
        bar.loopAction()->setChecked(false);
        bar.setFollowPlayhead(false);
        bar.resonanceAction()->setChecked(false);
        bar.setScaleState(0, porydaw_scale::ScaleId::major, false, false);
    } else if (state == QStringLiteral("toggles-on-long-text")) {
        bar.loopAction()->setChecked(true);
        bar.setFollowPlayhead(true);
        bar.resonanceAction()->setChecked(true);
        bar.setScaleState(10, porydaw_scale::ScaleId::whole_half_diminished, true, true);
        bar.setTimeText(QStringLiteral("99:59.9 / 99:59.9"));
    } else if (state == QStringLiteral("widest-scale-name")) {
        // The widest production scale name has to fit the scale combo's
        // current text without clipping; the combo keeps its dressed-up
        // highlight and fold state so the frozen row carries that chrome too.
        bar.setScaleState(10, porydaw_scale::ScaleId::altered, true, true);
    } else if (state == QStringLiteral("volume-min")) {
        bar.setMasterVolume(0, true);
        bar.setOutputVolume(0);
    } else if (state == QStringLiteral("volume-max")) {
        bar.setMasterVolume(127, true);
        bar.setOutputVolume(100);
    }
    // The two narrow widths stress the strip's own limits: 640 gives up the
    // whole tail from the scale control on, 900 gives up less of it. Which
    // controls are given up, in what order, the disabled Fold and Volume
    // caption next to the still enabled follow and resonance in `unavailable`,
    // and the spacing between all of them are the current reference behaviour
    // of the strip, not a licence to redesign it.
    int hostWidth = 1100;
    if (state == QStringLiteral("narrow"))
        hostWidth = 640;
    else if (state == QStringLiteral("intermediate"))
        hostWidth = 900;
    host.resize(hostWidth, 240);
    showSettled(host);
    auto regions = transportRegions(bar);
    regions.append({QStringLiteral("transport.surface"), bar.rect()});
    if (state == QStringLiteral("narrow") || state == QStringLiteral("intermediate")) {
        auto *overflow = bar.findChild<QToolButton *>(QStringLiteral("qt_toolbar_ext_button"));
        QVERIFY(overflow);
        QVERIFY2(overflow->isVisible(),
                 "a width that gives up controls must expose the overflow affordance");
        regions.append({QStringLiteral("transport.overflow"),
                        QRect(overflow->mapTo(&bar, QPoint()), overflow->size())});
    }
    QString error;
    const QString id = QStringLiteral("transportbar/%1/%2").arg(theme, state);
    QVERIFY2(checks::visual::compareWidget(id, bar, regions, &error), qPrintable(error));
}

void VisualTransportTest::interactionAppearance_data()
{
    QTest::addColumn<QString>("theme");
    QTest::addColumn<QString>("state");
    for (const char *theme : {"vanilla", "darkneutralhigh", "immaterial"}) {
        for (const char *state :
             {"hover-play", "pressed-play", "hover-loop", "hover-resonance", "hover-scale-type",
              "hover-scale-arrow", "pressed-fold", "pressed-output", "focused-volume", "root-popup",
              "scale-popup", "overflow-expanded"}) {
            const QByteArray name = QByteArray(theme) + "/" + state;
            QTest::newRow(name.constData())
                << QString::fromLatin1(theme) << QString::fromLatin1(state);
        }
    }
}

void VisualTransportTest::interactionAppearance()
{
    QFETCH(QString, theme);
    QFETCH(QString, state);
    applyTransportTheme(theme);
    QMainWindow host;
    TransportBar bar(&host);
    host.addToolBar(&bar);
    configureLoaded(bar, TransportBar::PlaybackState::Stopped);
    // The overflow row needs the width where the strip gives controls up; the
    // rest of the interaction rows freeze the fully revealed strip.
    host.resize(state == QStringLiteral("overflow-expanded") ? 640 : 1100, 240);
    showSettled(host);

    QString error;
    const QString id = QStringLiteral("transportbar/%1/%2").arg(theme, state);

    // An open popup lives in its own transient window, so the popup surface
    // itself is the capture; the bar's own grab never contains it.
    if (state.endsWith(QStringLiteral("-popup"))) {
        auto *combo = bar.findChild<QComboBox *>(state == QStringLiteral("root-popup")
                                                     ? QStringLiteral("transportScaleRoot")
                                                     : QStringLiteral("transportScaleType"));
        QVERIFY2(combo, "the production scale combo must exist");
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
        const QRect row = combo->view()->visualRect(combo->view()->currentIndex());
        const QRect rowBounds(combo->view()->viewport()->mapTo(popup, row.topLeft()), row.size());
        const QRect rowRegion = rowBounds.intersected(popup->rect());
        QVERIFY2(!rowRegion.isEmpty(), "the open popup must render its current row");
        const QList<checks::visual::Region> regions{
            {QStringLiteral("transport.popup"), popup->rect()},
            {QStringLiteral("transport.popup.current-row"), rowRegion}};
        // The open combo repaints its own raster into its open state while the
        // popup lives, so the bar is frozen alongside the popup under this
        // row's anchor ID; both captures happen before anything closes.
        auto anchorRegions = transportRegions(bar);
        anchorRegions.append({QStringLiteral("transport.surface"), bar.rect()});
        QString anchorError;
        const bool matched = checks::visual::compareWidget(id, *popup, regions, &error);
        const bool anchorMatched = checks::visual::compareWidget(id + QStringLiteral("-anchor"),
                                                                 bar, anchorRegions, &anchorError);
        combo->hidePopup();
        QApplication::processEvents();
        QVERIFY2(matched, qPrintable(error));
        QVERIFY2(anchorMatched, qPrintable(anchorError));
        return;
    }

    // The output dial repaints its custom face while held down; only a real
    // press sets that state, and no button state covers it.
    if (state == QStringLiteral("pressed-output")) {
        auto *dial = bar.findChild<QDial *>(QStringLiteral("transportOutputVolume"));
        QVERIFY2(dial, "the production output dial must exist");
        const QPoint center = dial->rect().center();
        QTest::mousePress(dial, Qt::LeftButton, Qt::NoModifier, center);
        QVERIFY2(dial->isSliderDown(), "a real press must hold the dial down");
        auto regions = transportRegions(bar);
        regions.append({QStringLiteral("transport.surface"), bar.rect()});
        const bool matched = checks::visual::compareWidget(id, bar, regions, &error);
        QTest::mouseRelease(dial, Qt::LeftButton, Qt::NoModifier, center);
        QVERIFY2(matched, qPrintable(error));
        return;
    }

    // The master volume field is frozen with its text selected: a selection
    // keeps the caret out of the raster on this platform (the Fusion/macOS
    // answer to SH_BlinkCursorWhenTextSelected is false and the line edit only
    // shows a caret once focus arrives with no selection), so the row is
    // pixel-stable instead of catching a blink. Focus is delivered as a normal
    // window focus event rather than native activation, and the assertion
    // checks the focus widget itself, which is what decides the rendering.
    if (state == QStringLiteral("focused-volume")) {
        auto *spin = bar.findChild<QSpinBox *>(QStringLiteral("transportMasterVolume"));
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
        auto regions = transportRegions(bar);
        regions.append({QStringLiteral("transport.surface"), bar.rect()});
        const bool matched = checks::visual::compareWidget(id, bar, regions, &error);
        QVERIFY2(matched, qPrintable(error));
        return;
    }

    // A strip hosted in a QMainWindow has no overflow menu to open - Qt builds
    // the extension QMenu only for a floating toolbar, or for a window that
    // cannot fit the expanded strip - so the expansion itself is the real
    // overflow reference here: a click grows the strip in place and reveals
    // the controls it had given up.
    if (state == QStringLiteral("overflow-expanded")) {
        auto *extension = bar.findChild<QToolButton *>(QStringLiteral("qt_toolbar_ext_button"));
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
        auto regions = transportRegions(bar);
        regions.append({QStringLiteral("transport.surface"), bar.rect()});
        regions.append({QStringLiteral("transport.overflow"),
                        QRect(extension->mapTo(&bar, QPoint()), extension->size())});
        const bool matched = checks::visual::compareWidget(id, bar, regions, &error);
        // Collapsing has to restore the narrow reference, so the row freezes
        // the expansion without leaving the strip stuck in it.
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

    QWidget *target = nullptr;
    bool held = false;
    // A row that freezes a style sub-control aims the pointer inside its
    // widget; every other row hovers the widget's own centre.
    QPoint hoverPoint;
    bool hoverPointSet = false;
    if (state == QStringLiteral("hover-play") || state == QStringLiteral("pressed-play")) {
        target = bar.widgetForAction(bar.playAction());
        held = state == QStringLiteral("pressed-play");
    } else if (state == QStringLiteral("hover-loop")) {
        target = bar.widgetForAction(bar.loopAction());
    } else if (state == QStringLiteral("hover-resonance")) {
        target = bar.widgetForAction(bar.resonanceAction());
    } else if (state == QStringLiteral("hover-scale-type")) {
        // The body of a themed scale combo paints no hover feedback of its
        // own, so this row freezes the body under the pointer exactly as it
        // rests; the dropdown lane beside it is the part that answers hover,
        // which the arrow row below freezes.
        target = bar.findChild<QComboBox *>(QStringLiteral("transportScaleType"));
    } else if (state == QStringLiteral("hover-scale-arrow")) {
        auto *scaleType = bar.findChild<QComboBox *>(QStringLiteral("transportScaleType"));
        QVERIFY2(scaleType, "the production scale type combo must exist");
        QVERIFY2(scaleType->isEnabled() && scaleType->isVisibleTo(&bar),
                 "a loaded bar must keep the scale type combo live, not parked in the overflow");
        // The dropdown arrow is a style sub-control instead of a child widget,
        // so its rect is the style's own answer for this combo - never a
        // guessed offset inside the body.
        QStyleOptionComboBox option;
        option.initFrom(scaleType);
        option.subControls = QStyle::SC_All;
        option.editable = scaleType->isEditable();
        option.frame = scaleType->hasFrame();
        option.currentText = scaleType->currentText();
        const QStyle *const style = scaleType->style();
        const QRect arrow = style->subControlRect(QStyle::CC_ComboBox, &option,
                                                  QStyle::SC_ComboBoxArrow, scaleType);
        QVERIFY2(scaleType->rect().contains(arrow.center()),
                 "the dropdown arrow must resolve to a rect inside the combo");
        hoverPoint = arrow.center();
        hoverPointSet = true;
        // The lane is the whole difference this row freezes, so the same hit
        // test the combo itself runs to pick its hovered sub-control has to
        // resolve the arrow before anything is captured.
        QCOMPARE(style->hitTestComplexControl(QStyle::CC_ComboBox, &option, hoverPoint, scaleType),
                 QStyle::SC_ComboBoxArrow);
        target = scaleType;
    } else if (state == QStringLiteral("pressed-fold")) {
        target = bar.findChild<QToolButton *>(QStringLiteral("transportScaleFold"));
        held = true;
    }
    QVERIFY2(target && target->isEnabled() && target->isVisibleTo(&bar),
             qPrintable(QStringLiteral("%1 must resolve a live production control").arg(state)));
    // The resting strip keeps loop checked and resonance unchecked, so the two
    // toggle rows freeze both backgrounds under the pointer; the toolbar's
    // checked state is what wins over hover while the toggle stays on.
    if (state == QStringLiteral("hover-loop"))
        QVERIFY2(bar.loopAction()->isChecked(), "the resting strip keeps loop on");
    if (state == QStringLiteral("hover-resonance"))
        QVERIFY2(!bar.resonanceAction()->isChecked(), "the resting strip keeps resonance off");
    // Appearance checks do not need native OS focus: the repo input fixtures
    // enter the window and then move inside it, which is enough to place real
    // hover on the target without moving the desktop cursor.
    QVERIFY2(QTest::qWaitForWindowExposed(&host, 2000),
             "the host window must be exposed before pointer input");
    releaseFocus(host);
    const QPoint center = hoverPointSet ? hoverPoint : target->rect().center();
    QWindow *const window = host.windowHandle();
    QVERIFY2(window, "the shown host must own a window");
    const QPoint point = window->mapFromGlobal(target->mapToGlobal(center));
    QEnterEvent enter(point, point, window->mapToGlobal(point));
    QCoreApplication::sendEvent(window, &enter);
    QTest::mouseMove(window, point);
    QTRY_VERIFY2_WITH_TIMEOUT(target->underMouse(),
                              "the pointer must rest on the requested transport control", 2000);
    if (held) {
        QTest::mousePress(target, Qt::LeftButton, Qt::NoModifier, center);
        auto *button = qobject_cast<QAbstractButton *>(target);
        QVERIFY2(button && button->isDown(), "a real press must hold the tool button down");
    }
    auto regions = transportRegions(bar);
    regions.append({QStringLiteral("transport.surface"), bar.rect()});
    const bool matched = checks::visual::compareWidget(id, bar, regions, &error);
    if (held)
        QTest::mouseRelease(target, Qt::LeftButton, Qt::NoModifier, center);
    QVERIFY2(matched, qPrintable(error));
}

void VisualTransportTest::geometrySurvivesStateAndWidthChanges()
{
    QMainWindow host;
    TransportBar bar(&host);
    host.addToolBar(&bar);
    configureLoaded(bar, TransportBar::PlaybackState::Stopped);
    // All controls fit at this width under the production base font; width is
    // an input, never an expected size derived from the implementation being
    // protected.
    host.resize(1400, 240);
    showSettled(host);
    const auto original = boundsByName(bar);
    QCOMPARE(original.size(), 16);
    for (const auto &bounds : original) {
        QVERIFY(bounds.isValid());
        QVERIFY(bar.rect().contains(bounds));
    }
    for (auto state :
         {TransportBar::PlaybackState::Playing, TransportBar::PlaybackState::Paused,
          TransportBar::PlaybackState::Unavailable, TransportBar::PlaybackState::Stopped}) {
        bar.setPlaybackState(state);
        bar.setSessionAvailable(state != TransportBar::PlaybackState::Unavailable);
        bar.setMasterVolume(0, state != TransportBar::PlaybackState::Unavailable);
        bar.setOutputVolume(0);
        bar.setTimeText(QStringLiteral("99:59.9 / 99:59.9"));
        bar.setScaleState(10, porydaw_scale::ScaleId::whole_half_diminished, false, true);
        QApplication::processEvents();
        QCOMPARE(boundsByName(bar), original);
    }
    host.resize(1600, 240);
    QApplication::processEvents();
    const auto expanded = boundsByName(bar);
    QCOMPARE(expanded.keys(), original.keys());
    for (auto it = original.cbegin(); it != original.cend(); ++it) {
        const bool volume = it.key().startsWith(QStringLiteral("transport.master-volume")) ||
                            it.key().startsWith(QStringLiteral("transport.output-volume"));
        QCOMPARE(expanded.value(it.key()), it.value().translated(volume ? 200 : 0, 0));
    }
    host.resize(640, 240);
    QApplication::processEvents();
    host.resize(1400, 240);
    QApplication::processEvents();
    QCOMPARE(boundsByName(bar), original);
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
