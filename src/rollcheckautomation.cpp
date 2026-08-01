#include "ui/automationpage.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <cstdio>
#include <memory>
#include <vector>

#include <QAction>
#include <QDialog>
#include <QListWidget>
#include <QCoreApplication>
#include <QApplication>
#include <QImage>
#include <QColor>
#include <QPainter>
#include <QMouseEvent>
#include <QKeyEvent>
#include <QMenu>
#include <QWheelEvent>
#include <QStringList>
#include <QTimer>

#include "core/songdocument.h"
#include "project/decompproject.h"
#include "ui/automationarea.h"
#include "ui/editordrawer.h"
#include "ui/songview.h"
#include "ui/layout.h"
#include "ui/theme/themeruntime.h"

namespace {


void sendWheel(QWidget *widget, const QPoint &position, int vertical,
               Qt::KeyboardModifiers modifiers = Qt::NoModifier)
{
    QWheelEvent event(QPointF(position), QPointF(widget->mapToGlobal(position)), QPoint(),
                      QPoint(0, vertical), Qt::NoButton, modifiers, Qt::NoScrollPhase, false);
    QCoreApplication::sendEvent(widget, &event);
}

void sendMouse(QWidget *widget, QEvent::Type type, const QPoint &position, Qt::MouseButton button,
               Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers = Qt::NoModifier)
{
    QMouseEvent event(type, QPointF(position), QPointF(widget->mapToGlobal(position)), button, buttons,
                      modifiers);
    QCoreApplication::sendEvent(widget, &event);
}

uint64_t drawerContextTick(double tick)
{
    return static_cast<uint64_t>(std::floor(std::max(0.0, tick) + 0.5));
}

bool rowExists(const std::vector<AutomationRow> &rows, const EditorAutomationRowId &id)
{
    return std::any_of(rows.cbegin(), rows.cend(), [&id](const AutomationRow &row) {
        return row.id == id;
    });
}
int automationRowsHeight(const AutomationPage &page)
{
    const auto &state = page.automationViewState();
    const int shared = state.laneHeight > 0 ? state.laneHeight : layout::editorGeometry().automationRowDefaultHeight;
    int height = 0;
    for (const auto &row : page.area()->rows()) {
        const auto it = state.laneHeights.find(row.id);
        height += std::clamp(it == state.laneHeights.cend() ? shared : it->second,
                             layout::editorGeometry().automationRowMinimumHeight,
                             layout::editorGeometry().automationRowMaximumHeight);
    }
    return height;
}
int automationRowTop(const AutomationPage &page, const EditorAutomationRowId &id)
{
    const auto &state = page.automationViewState();
    const int shared = state.laneHeight > 0 ? state.laneHeight : layout::editorGeometry().automationRowDefaultHeight;
    int top = 0;
    for (const auto &row : page.area()->rows()) {
        if (row.id == id)
            return top;
        const auto it = state.laneHeights.find(row.id);
        top += std::clamp(it == state.laneHeights.cend() ? shared : it->second,
                          layout::editorGeometry().automationRowMinimumHeight,
                          layout::editorGeometry().automationRowMaximumHeight);
    }
    return -1;
}
bool regionHasColor(const QImage &image, const QRect &logicalBounds, const QColor &color)
{
    const qreal dpr = image.devicePixelRatio();
    const QRect pixelBounds(qFloor(logicalBounds.x() * dpr), qFloor(logicalBounds.y() * dpr),
                            qCeil(logicalBounds.width() * dpr),
                            qCeil(logicalBounds.height() * dpr));
    const QRect bounds = pixelBounds.intersected(image.rect());
    for (int y = bounds.top(); y <= bounds.bottom(); ++y)
        for (int x = bounds.left(); x <= bounds.right(); ++x)
            if (image.pixelColor(x, y) == color)
                return true;
    return false;
}
bool regionsDiffer(const QImage &first, const QImage &second, const QRect &logicalBounds)
{
    if (first.size() != second.size() || first.devicePixelRatio() != second.devicePixelRatio())
        return true;
    const qreal dpr = first.devicePixelRatio();
    const QRect pixelBounds(qFloor(logicalBounds.x() * dpr), qFloor(logicalBounds.y() * dpr),
                            qCeil(logicalBounds.width() * dpr),
                            qCeil(logicalBounds.height() * dpr));
    const QRect bounds = pixelBounds.intersected(first.rect());
    for (int y = bounds.top(); y <= bounds.bottom(); ++y)
        for (int x = bounds.left(); x <= bounds.right(); ++x)
            if (first.pixel(x, y) != second.pixel(x, y))
                return true;
    return false;
}
bool hasVerticalStroke(const QImage &image, qreal logicalX, const QRect &logicalBounds)
{
    const qreal dpr = image.devicePixelRatio();
    const int center = qRound(logicalX * dpr);
    const int firstY = std::max(0, qCeil((logicalBounds.top() + 2) * dpr));
    const int lastY = std::min(image.height() - 1, qFloor((logicalBounds.bottom() - 2) * dpr));
    if (firstY > lastY)
        return false;
    for (int x = center - 2; x <= center + 2; ++x) {
        if (x < 3 || x + 3 >= image.width())
            continue;
        int changedPixels = 0;
        for (int y = firstY; y <= lastY; ++y)
            if (image.pixel(x, y) != image.pixel(x - 3, y)
                && image.pixel(x, y) != image.pixel(x + 3, y))
                ++changedPixels;
        if (changedPixels * 2 >= lastY - firstY + 1)
            return true;
    }
    return false;
}
} // namespace

int runAutomationCheck(const QString &scratchProject, const QString &songLabel,
                       const QString &screenshotPath)
{
    DecompProject project;
    QString error;
    if (!project.open(scratchProject, &error)) {
        std::fprintf(stderr, "automation-check: %s\n", qUtf8Printable(error));
        return 1;
    }
    const SongInfo *song = nullptr;
    for (const auto &candidate : project.songs()) {
        if (candidate.label == songLabel) {
            song = &candidate;
            break;
        }
    }
    if (!song) {
        std::fprintf(stderr, "automation-check: no playable song %s\n", qUtf8Printable(songLabel));
        return 1;
    }
    SongDocument document;
    if (!document.load(*song, &error)) {
        std::fprintf(stderr, "automation-check: %s\n", qUtf8Printable(error));
        return 1;
    }
    const QByteArray baseline = document.smf().write();
    if (document.engineTrackCount() == 0) {
        std::fprintf(stderr, "automation-check: %s has no engine tracks\n", qUtf8Printable(songLabel));
        return 1;
    }
    document.addLanePoint(0, 7, 24, 32);
    document.addLanePoint(0, 21, 48, 96);
    document.addLanePoint(0, LANE_CC_BEND, 72, 8191);
    document.addLanePoint(0, DOC_CC_VOICE, 24, 3);
    auto timeline = document.buildTimeline(48000.0);
    LoadedVoiceGroup voicegroup{};
    voicegroup.voices[3].type = VOICE_NOISE;
    std::strncpy(voicegroup.voiceNames[3], "automation-voice",
                 sizeof(voicegroup.voiceNames[3]) - 1);
    SongView view;
    view.resize(960, 720);
    view.setDocument(&document);
    view.setSong(timeline.get(), &voicegroup);
    EditorViewState state;
    const EditorAutomationRowId volume{EditorAutomationRowKind::ControlChange, 0, 7};
    const EditorAutomationRowId pan{EditorAutomationRowKind::ControlChange, 0, 10};
    const EditorAutomationRowId lfo{EditorAutomationRowKind::ControlChange, 0, 21};
    const EditorAutomationRowId voiceRow{EditorAutomationRowKind::Voice, 0, DOC_CC_VOICE};
    state.hideLane(volume);
    state.emptyLanes.insert(pan);
    state.laneHeights[lfo] = layout::editorGeometry().automationRowDefaultHeight + 5;
    state.laneRanges[lfo] = 91;
    view.applyEditorViewState(state);
    view.setDrawerPage(EditorDrawerPage::Automations);
    view.setDrawerVisible(true);
    view.setDrawerHeight(360);
    view.show();
    QCoreApplication::processEvents();
    auto *drawer = view.editorDrawer();
    auto *pagePtr = drawer ? drawer->automationPage() : nullptr;
    if (!pagePtr) {
        std::fprintf(stderr, "automation-check: concrete SongView did not expose AutomationPage\n");
        return 1;
    }
    auto &page = *pagePtr;
    page.resize(960, 360);
    page.songChanged();
    EditorPageLiveState live;
    live.documentRevision = document.revision();
    live.timeZoom = 96.0;
    view.setEditorTimeZoom(live.timeZoom);
    live.editCursorTick = 24;
    page.refreshLiveState(live);
    page.show();
    QCoreApplication::processEvents();

    int failures = 0;
    const auto check = [&](bool condition, const QString &message) {
        if (!condition) {
            std::fprintf(stderr, "automation-check: FAIL %s: %s\n", qUtf8Printable(songLabel),
                         qUtf8Printable(message));
            ++failures;
        }
    };
    const auto &rows = page.area()->rows();
    check(!rows.empty() && rows.front().id.kind == EditorAutomationRowKind::Tempo,
          QStringLiteral("tempo is not the first automation row"));
    check(rows.size() > 1 && rows[1].id.kind == EditorAutomationRowKind::Voice,
          QStringLiteral("document-backed voice row is missing"));
    check(!rowExists(rows, volume), QStringLiteral("hidden lane remained visible"));
    check(rowExists(rows, pan), QStringLiteral("empty primary-track lane is missing"));
    check(rowExists(rows, lfo), QStringLiteral("visible controller lane is missing"));
    check(page.automationViewState().laneRanges.at(lfo) == 91,
          QStringLiteral("typed non-menu lane range was not retained"));
    const auto bend = EditorAutomationRowId{EditorAutomationRowKind::ControlChange, 0, LANE_CC_BEND};
    check(!rows.empty() && rows.back().id == bend,
          QStringLiteral("bend pseudo-controller is not ordered last"));
    const auto heightFor = [&](const EditorAutomationRowId &id) {
        const auto it = state.laneHeights.find(id);
        const int shared =
            state.laneHeight > 0 ? state.laneHeight : layout::editorGeometry().automationRowDefaultHeight;
        return std::clamp(it == state.laneHeights.cend() ? shared : it->second,
                          layout::editorGeometry().automationRowMinimumHeight,
                          layout::editorGeometry().automationRowMaximumHeight);
    };
    const int voiceTop = automationRowTop(page, voiceRow);
    const int voiceHeight = heightFor(voiceRow);
    const int lfoTop = automationRowTop(page, lfo);
    const int lfoHeight = heightFor(lfo);
    const QImage namedVoiceImage = page.area()->grab().toImage();
    const QRect lfoCaptionBounds(
        layout::space(layout::Space::One), lfoTop + lfoHeight / 2,
        layout::editorGeometry().plotOrigin - 2 * layout::space(layout::Space::One), lfoHeight / 2);
    const QRect voiceCaptionBounds(
        layout::space(layout::Space::One), voiceTop + voiceHeight / 2,
        layout::editorGeometry().plotOrigin - 2 * layout::space(layout::Space::One), voiceHeight / 2);
    const QColor secondaryText = themes::color(themes::Role::song_view_secondary_text);
    check(lfoTop >= 0 && regionHasColor(namedVoiceImage, lfoCaptionBounds, secondaryText),
          QStringLiteral("automation row header did not render its points sub-label"));
    check(voiceTop >= 0 && regionHasColor(namedVoiceImage, voiceCaptionBounds, secondaryText),
          QStringLiteral("voice row header did not render its change sub-label"));
    const int voicePointX =
        qRound(layout::editorGeometry().plotOrigin + 24.0 * live.timeZoom / timeline->ticksPerBeat);
    const QRect voicePointLabelBounds(voicePointX, voiceTop,
                                      std::max(0, std::min(160, page.area()->width() - voicePointX)),
                                      voiceHeight);
    voicegroup.voiceNames[3][0] = '\0';
    page.area()->invalidateContent();
    const QImage fallbackVoiceImage = page.area()->grab().toImage();
    check(voiceTop >= 0
              && regionsDiffer(namedVoiceImage, fallbackVoiceImage, voicePointLabelBounds),
          QStringLiteral("voice point label did not resolve the voicegroup name"));
    std::strncpy(voicegroup.voiceNames[3], "automation-voice",
                 sizeof(voicegroup.voiceNames[3]) - 1);
    QTimer::singleShot(0, [] {
        if (auto *dialog = qobject_cast<QDialog *>(QApplication::activeModalWidget())) {
            if (auto *list = dialog->findChild<QListWidget *>())
                list->setCurrentRow(4);
            dialog->accept();
        }
    });
    sendMouse(page.area(), QEvent::MouseButtonPress,
              QPoint(voicePointX, voiceTop + voiceHeight / 2), Qt::LeftButton, Qt::LeftButton);
    QCoreApplication::processEvents();
    DocLanePoint updatedVoice;
    check(document.findLanePoint(0, DOC_CC_VOICE, 24, &updatedVoice)
              && updatedVoice.value == 4,
          QStringLiteral("voice automation did not use the concrete SongView voice picker"));
    bool leftGutterMenuOpened = false;
    QTimer::singleShot(0, [&] {
        if (auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget())) {
            leftGutterMenuOpened = true;
            menu->close();
        }
    });
    sendMouse(page.area(), QEvent::MouseButtonPress,
              QPoint(layout::space(layout::Space::One), lfoTop + lfoHeight / 2),
              Qt::LeftButton, Qt::LeftButton);
    sendMouse(page.area(), QEvent::MouseButtonRelease,
              QPoint(layout::space(layout::Space::One), lfoTop + lfoHeight / 2),
              Qt::LeftButton, Qt::NoButton);
    QCoreApplication::processEvents();
    check(!leftGutterMenuOpened,
          QStringLiteral("left click in a control-row gutter opened its menu"));
    QStringList addLaneActions;
    QTimer::singleShot(0, [&] {
        auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
        if (!menu)
            return;
        for (QAction *action : menu->actions())
            addLaneActions.push_back(action->text());
        menu->close();
    });
    sendMouse(page.area(), QEvent::MouseButtonPress,
              QPoint(layout::space(layout::Space::One), automationRowsHeight(page) + 1),
              Qt::RightButton, Qt::RightButton);
    check(addLaneActions.contains(QStringLiteral("Show: Volume (VOL) (hidden)")),
          QStringLiteral("right-click add-lane menu lost hidden-lane label or order"));

    page.area()->invalidateContent();
    page.area()->grab();
    const EditorPageGridState meterGrid = view.gridState(48, false);
    const EditorPageGridState voiceGrid = view.gridState(12, true);
    check(meterGrid.gridTicks > 0 && meterGrid.snapTicks > 0,
          QStringLiteral("automation grid did not resolve through its SongView owner"));
    check(voiceGrid.snapTicks > 0,
          QStringLiteral("voice row did not resolve its owner snap-grid subdivision"));
    const int gridCellWidth = layout::editorGeometry().automationGridMinimumCellWidth;
    const double ticksPerBeat = double(std::max(1u, timeline->ticksPerBeat));
    const auto snapStopX = [&] {
        return layout::editorGeometry().plotOrigin + 12.0 * live.timeZoom / ticksPerBeat;
    };
    const QRect voicePlotBounds(layout::editorGeometry().plotOrigin, voiceTop,
                                page.area()->width() - layout::editorGeometry().plotOrigin, voiceHeight);
    live.timeZoom = double(gridCellWidth) * ticksPerBeat / 12.0;
    view.setEditorTimeZoom(live.timeZoom);
    page.refreshLiveState(live);
    const QImage thresholdGrid = page.area()->grab().toImage();
    check(hasVerticalStroke(thresholdGrid, snapStopX(), voicePlotBounds),
          QStringLiteral("voice row did not draw its snap stop at the visibility threshold"));
    live.timeZoom = double(std::max(1, gridCellWidth - 1)) * ticksPerBeat / 12.0;
    view.setEditorTimeZoom(live.timeZoom);
    page.refreshLiveState(live);
    const QImage belowThresholdGrid = page.area()->grab().toImage();
    check(!hasVerticalStroke(belowThresholdGrid, snapStopX(), voicePlotBounds),
          QStringLiteral("voice row drew its snap stop below the visibility threshold"));
    QImage gridImage(page.area()->size(), QImage::Format_ARGB32);
    QPainter gridPainter(&gridImage);
    check(view.paintGrid(gridPainter, page.area()->rect(), layout::editorGeometry().plotOrigin),
          QStringLiteral("automation page did not delegate grid painting to its SongView owner"));
    live.timeZoom = 96.0;
    view.setEditorTimeZoom(live.timeZoom);
    page.refreshLiveState(live);
    const QPoint indicatorPoint(layout::editorGeometry().plotOrigin + 180,
                                layout::editorGeometry().automationRowDefaultHeight / 2);
    const QImage beforeIndicator = page.area()->grab().toImage();
    sendMouse(page.area(), QEvent::MouseButtonPress, indicatorPoint, Qt::LeftButton, Qt::LeftButton);
    const QImage activeIndicator = page.area()->grab().toImage();
    const QRect indicatorBounds(indicatorPoint.x() - layout::space(layout::Space::One), 0,
                                std::min(200, page.area()->width() - indicatorPoint.x()
                                                  + layout::space(layout::Space::One)),
                                layout::editorGeometry().automationRowDefaultHeight);
    check(regionsDiffer(beforeIndicator, activeIndicator, indicatorBounds),
          QStringLiteral("automation draw did not render its live value indicator"));
    page.cancelInteraction();

    page.refreshLiveState(live);
    check(rowExists(page.area()->rows(), lfo),
          QStringLiteral("SongView selected-track refresh did not retain primary lanes"));
    const int initialHeight = page.automationViewState().laneHeight;
    sendWheel(page.area(), QPoint(layout::editorGeometry().plotOrigin + 20,
                                  layout::editorGeometry().automationRowDefaultHeight / 2),
              120, Qt::ControlModifier);
    check(page.automationViewState().laneHeight > initialHeight,
          QStringLiteral("Ctrl-wheel did not publish typed row-height state"));

    const int sharedHeight = page.automationViewState().laneHeight;
    const QPoint selectionStart(layout::editorGeometry().plotOrigin + 24, sharedHeight / 2);
    const QPoint selectionEnd(layout::editorGeometry().plotOrigin + 216, sharedHeight / 2);
    const QPoint selectionContractedEnd((selectionStart.x() + selectionEnd.x()) / 2,
                                        selectionEnd.y());
    const QImage selectionBaseline = page.area()->grab().toImage();
    sendMouse(page.area(), QEvent::MouseButtonPress, selectionStart, Qt::RightButton,
              Qt::RightButton);
    sendMouse(page.area(), QEvent::MouseMove, selectionEnd, Qt::NoButton, Qt::RightButton);
    QApplication::processEvents();
    const QImage expandedSelection = page.area()->grab().toImage();
    const QRect selectionInterior(
        selectionStart.x() + layout::space(layout::Space::One),
        layout::space(layout::Space::One),
        selectionEnd.x() - selectionStart.x() - 2 * layout::space(layout::Space::One),
        sharedHeight - 2 * layout::space(layout::Space::One));
    check(regionsDiffer(selectionBaseline, expandedSelection, selectionInterior),
          QStringLiteral("automation drag-select did not paint its selection reticle"));
    const QPoint transparencyProbe = selectionInterior.center();
    const auto colorAt = [&transparencyProbe](const QImage &image) {
        const qreal dpr = image.devicePixelRatio();
        return image.pixelColor(qFloor(transparencyProbe.x() * dpr),
                                qFloor(transparencyProbe.y() * dpr));
    };
    check(colorAt(expandedSelection) != colorAt(selectionBaseline)
              && colorAt(expandedSelection)
                     != themes::color(themes::Role::song_view_selection_edge),
          QStringLiteral("automation drag-select did not use the translucent note selector"));
    sendMouse(page.area(), QEvent::MouseMove, selectionContractedEnd, Qt::NoButton,
              Qt::RightButton);
    QApplication::processEvents();
    const QRect abandonedSelection(
        selectionContractedEnd.x() + layout::space(layout::Space::One),
        layout::space(layout::Space::One),
        selectionEnd.x() - selectionContractedEnd.x() - layout::space(layout::Space::One),
        sharedHeight - 2 * layout::space(layout::Space::One));
    check(!regionsDiffer(selectionBaseline, page.area()->grab().toImage(), abandonedSelection),
          QStringLiteral("contracting automation drag-select left stale pixels"));
    sendMouse(page.area(), QEvent::MouseButtonRelease, selectionContractedEnd, Qt::RightButton,
              Qt::NoButton);
    const auto &timeSelection = view.timeSelection();
    check(timeSelection.active() && timeSelection.scope == SongView::TimeSelection::Lanes
              && timeSelection.lanes.size() == 1,
          QStringLiteral("right drag did not commit a half-open automation selection"));
    QStringList selectionActions;
    QTimer::singleShot(0, [&] {
        auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
        if (!menu)
            return;
        for (QAction *action : menu->actions())
            selectionActions.push_back(action->text());
        menu->close();
    });
    const QPoint selectionInside(layout::editorGeometry().plotOrigin + 100, sharedHeight / 2);
    sendMouse(page.area(), QEvent::MouseButtonPress, selectionInside, Qt::RightButton, Qt::RightButton);
    sendMouse(page.area(), QEvent::MouseButtonRelease, selectionInside, Qt::RightButton, Qt::NoButton);
    check(selectionActions.contains(QStringLiteral("Clear time selection")),
          QStringLiteral("right click inside a time selection did not open its menu"));
    QKeyEvent escapeSelection(QEvent::KeyPress, Qt::Key_Escape, Qt::NoModifier);
    QCoreApplication::sendEvent(page.area(), &escapeSelection);

    const QPoint voiceHover(layout::editorGeometry().plotOrigin + 96, sharedHeight + sharedHeight / 2);
    sendMouse(page.area(), QEvent::MouseMove, voiceHover, Qt::NoButton, Qt::NoButton);
    page.area()->grab();
    const double hoverTick
        = double(voiceHover.x() - layout::editorGeometry().plotOrigin) * timeline->ticksPerBeat / live.timeZoom;
    check(view.voiceContext(drawerContextTick(hoverTick)).voice == &voicegroup.voices[3],
          QStringLiteral("voice hover did not consume its row and tick through SongView"));
    QEvent leave(QEvent::Leave);
    QCoreApplication::sendEvent(page.area(), &leave);

    const auto checkCancelledGesture = [&](auto cancel, const QString &route) {
        const uint64_t revision = document.revision();
        const int undoIndex = document.undoStack()->index();
        const QPoint start(layout::editorGeometry().plotOrigin + 24, layout::editorGeometry().automationRowDefaultHeight / 2);
        sendMouse(page.area(), QEvent::MouseButtonPress, start, Qt::LeftButton, Qt::LeftButton);
        sendMouse(page.area(), QEvent::MouseMove, start + QPoint(80, 12), Qt::NoButton,
                  Qt::LeftButton);
        cancel();
        sendMouse(page.area(), QEvent::MouseButtonRelease, start + QPoint(80, 12),
                  Qt::LeftButton, Qt::NoButton);
        check(document.revision() == revision && document.undoStack()->index() == undoIndex,
              QStringLiteral("%1 cancellation changed the document").arg(route));
    };
    checkCancelledGesture([&] { page.cancelInteraction(); }, QStringLiteral("explicit"));
    checkCancelledGesture([&] { page.documentChanged(); }, QStringLiteral("document mutation"));
    checkCancelledGesture(
        [&] {
            QEvent event(QEvent::UngrabMouse);
            QCoreApplication::sendEvent(page.area(), &event);
        },
        QStringLiteral("mouse-grab loss"));
    checkCancelledGesture(
        [&] {
            QEvent event(QEvent::WindowDeactivate);
            QCoreApplication::sendEvent(page.area(), &event);
        },
        QStringLiteral("window loss"));
    checkCancelledGesture(
        [&] {
            QKeyEvent event(QEvent::KeyPress, Qt::Key_Escape, Qt::NoModifier);
            QCoreApplication::sendEvent(page.area(), &event);
        },
        QStringLiteral("Escape"));
    checkCancelledGesture(
        [&] {
            page.hide();
            page.show();
            QCoreApplication::processEvents();
        },
        QStringLiteral("page hide"));

    for (const double playhead : {-3.0, 10.49, 10.5, 10.51}) {
        live.playback = {playhead, true};
        page.refreshLiveState(live);
        page.area()->grab();
        check(view.voiceContext(drawerContextTick(playhead)).voice == &voicegroup.voices[3],
              QStringLiteral("playing voice context did not use the SongView owner at %1")
                  .arg(playhead));
    }
    live.playback.playing = false;
    live.editCursorTick = 73;
    page.refreshLiveState(live);
    page.area()->grab();
    check(view.voiceContext(73).voice == &voicegroup.voices[3],
          QStringLiteral("stopped voice context did not use the edit cursor"));

    view.setDocument(&document);
    while (document.undoStack()->index() > 0)
        document.undoStack()->undo();
    check(document.smf().write() == baseline,
          QStringLiteral("automation check did not restore its scratch document"));
    document.undoStack()->clear();
    check(page.automationViewState().laneRanges.at(lfo) == 91 &&
              page.automationViewState().isLaneHidden(volume),
          QStringLiteral("document refresh did not retain surviving typed row state"));
    if (!screenshotPath.isEmpty()) {
        page.grab().toImage().save(screenshotPath);
        std::printf("automation-check: wrote %s\n", qUtf8Printable(screenshotPath));
    }
    page.hide();
    if (failures == 0)
        std::printf("automation-check: PASS %s\n", qUtf8Printable(songLabel));
    return failures == 0 ? 0 : 1;
}
