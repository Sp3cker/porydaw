#include <QCoreApplication>
#include <QDialog>
#include <QDialogButtonBox>
#include <QElapsedTimer>
#include <QLineEdit>
#include <QListWidget>
#include <QMouseEvent>
#include <QPushButton>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRegion>
#include <QThread>
#include <QTimer>
#include <QWindow>

#include <optional>

#include "checks/support/eventsynth.h"
#include "checks/support/songfixture.h"
#include "core/songdocument.h"
#include "ui/playheadoverlay.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/trackheadermodel.h"

namespace {

// Window visibility and modal transitions need every queued event processed.
void processWindowEvents()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

bool waitForNativeWindowExposure(QWidget &widget)
{
    QElapsedTimer elapsed;
    elapsed.start();
    do {
        processWindowEvents();
        auto *window = widget.windowHandle();
        if (widget.isVisible() && window && window->isExposed())
            return true;
        QThread::msleep(10);
    } while (elapsed.elapsed() < 1000);
    return false;
}

} // namespace

int runRollWindowingCheck(const QString &projectRoot, const QString &songLabel)
{
    QString error;
    auto loadedSong = checks::LoadedSong::load(projectRoot, songLabel, error);
    if (!loadedSong) {
        std::fprintf(stderr, "rollwindowingcheck: %s\n", qUtf8Printable(error));
        return 1;
    }
    auto rig = checks::SongViewRig::create(std::move(loadedSong), 48000.0, error);
    if (!rig) {
        std::fprintf(stderr, "rollwindowingcheck: %s\n", qUtf8Printable(error));
        return 1;
    }
    SongDocument &document = rig->document();
    SongView &view = rig->view();
    view.resize(1280, 800);
    view.show();
    processWindowEvents();

    int failures = 0;
    const auto fail = [&](const char *message) {
        std::fprintf(stderr, "rollwindowingcheck: FAIL %s: %s\n", qUtf8Printable(songLabel),
                     message);
        ++failures;
    };

    if (!waitForNativeWindowExposure(view))
        fail("SongView did not create an exposed native window");

    auto *quick = view.findChild<songview::TimelineQuickView *>(
        QStringLiteral("timelineQuickCanvas"), Qt::FindDirectChildrenOnly);
    auto *overlay =
        view.findChild<songview::PlayheadOverlay *>(QString{}, Qt::FindDirectChildrenOnly);
    if (!quick || !overlay) {
        fail("SongView did not create direct Quick and native playhead children");
    } else if (QWidget *const fallback = overlay->fallbackWidget()) {
        if (fallback->parentWidget() != &view || fallback->geometry() != view.rect())
            fail("playhead fallback widget was reparented away from the SongView");
        const QList<QWidget *> widgetStacking =
            view.findChildren<QWidget *>(QString{}, Qt::FindDirectChildrenOnly);
        if (widgetStacking.indexOf(fallback) <= widgetStacking.indexOf(quick))
            fail("playhead fallback widget is stacked below the retained Quick host");
    } else if (quick->playheadVisible()) {
        fail("default windowing published a Quick playhead without a native fallback widget");
    }

    if (!quick) {
        fail("SongView did not create the Quick host needed for TrackHeaders routing");
    } else {
        QQuickItem *const quickRoot = quick->rootObject();
        auto *headers = view.findChild<songview::TrackHeaderModel *>(
            QStringLiteral("trackHeaderModel"), Qt::FindDirectChildrenOnly);
        auto *headerBand =
            quickRoot
                ? quickRoot->findChild<QQuickItem *>(QStringLiteral("timelineQuickTrackHeaders"))
                : nullptr;
        auto *headerInput = quickRoot ? quickRoot->findChild<songview::TimelineInputItem *>(
                                            QStringLiteral("timelineTrackHeadersInput"))
                                      : nullptr;
        QObject *const headerRows =
            quickRoot ? quickRoot->findChild<QObject *>(QStringLiteral("timelineTrackHeaderRows"))
                      : nullptr;
        QQuickWindow *const quickWindow = quick->quickWindow();
        const std::optional<songview::TimelineBandGeometry> &headerGeometry =
            view.timelineBandLayout().geometry(songview::TimelineBand::TrackHeaders);
        const bool headerSurfacePresent =
            quickRoot && headers && headerBand && headerInput && headerRows && quickWindow &&
            headerGeometry && headerBand->isVisible() && headerInput->isVisible() &&
            headerInput->interaction() == headers &&
            QRectF(headerBand->mapToItem(quickRoot, QPointF()), headerBand->size()) ==
                QRectF(headerGeometry->rect.translated(-quick->geometry().topLeft())) &&
            headerInput->width() + headers->scrollbarWidth() == headerGeometry->rect.width() &&
            headerInput->height() == headerGeometry->rect.height() &&
            headerRows->property("count").toInt() == headers->rowCount() &&
            quickWindow->mask().isEmpty();
        if (!headerSurfacePresent) {
            fail("TrackHeaders did not expose model-backed Quick geometry in the unmasked window");
        } else {
            const int selectedTrack = view.selectionModel().primaryTrack();
            int previousTrack = -1;
            int selectedRow = -1;
            int alternateRow = -1;
            int addRows = 0;
            bool rowsOrdered = headers->rowCount() > 0;
            for (int row = 0; row < headers->rowCount(); ++row) {
                const QModelIndex index = headers->index(row, 0);
                const bool isAdd =
                    headers->data(index, songview::TrackHeaderModel::IsAddTrackRole).toBool();
                if (isAdd) {
                    ++addRows;
                    rowsOrdered &= row == headers->rowCount() - 1;
                    continue;
                }
                const int modelTrack =
                    headers->data(index, songview::TrackHeaderModel::TrackRole).toInt();
                rowsOrdered &= addRows == 0 && modelTrack > previousTrack;
                previousTrack = modelTrack;
                if (modelTrack == selectedTrack)
                    selectedRow = row;
                else if (alternateRow < 0)
                    alternateRow = row;
            }
            const int expectedAddRows = document.canAddTrack() ? 1 : 0;
            rowsOrdered &= addRows == expectedAddRows && selectedRow >= 0;
            if (!rowsOrdered)
                fail("TrackHeaderModel used tracks were not strictly ordered with the document's "
                     "expected trailing add row");

            const int targetRow = alternateRow >= 0 ? alternateRow : selectedRow;
            const QModelIndex targetIndex =
                targetRow >= 0 ? headers->index(targetRow, 0) : QModelIndex{};
            const int targetTrack =
                targetIndex.isValid()
                    ? headers->data(targetIndex, songview::TrackHeaderModel::TrackRole).toInt()
                    : -1;
            if (targetTrack < 0) {
                fail("TrackHeaderModel did not expose a selectable track row");
            } else {
                headers->setScrollY(qreal(targetRow * headers->rowHeight()));
                processWindowEvents();
                const QRectF titleRect =
                    headers->data(targetIndex, songview::TrackHeaderModel::TitleRectRole).toRectF();
                const QPointF bodyPosition =
                    titleRect.center() +
                    QPointF(0.0, targetRow * headers->rowHeight() - headers->scrollY());
                const QPointF voicePosition =
                    headers->voiceLineRect().center() +
                    QPointF(0.0, targetRow * headers->rowHeight() - headers->scrollY());
                const auto sendHeaderMouse = [&](QEvent::Type type, const QPointF &position,
                                                 Qt::MouseButton button, Qt::MouseButtons buttons) {
                    const QPointF windowPosition = headerInput->mapToScene(position);
                    QMouseEvent event(type, windowPosition,
                                      QPointF(quickWindow->mapToGlobal(windowPosition.toPoint())),
                                      button, buttons, Qt::NoModifier);
                    QCoreApplication::sendEvent(quickWindow, &event);
                };
                if (titleRect.isEmpty() || !headerInput->bounds().contains(bodyPosition) ||
                    !headerInput->bounds().contains(voicePosition)) {
                    fail("TrackHeaderModel did not publish clickable Quick title and voice "
                         "geometry");
                } else {
                    const int undoCommands = document.undoStack()->count();
                    sendHeaderMouse(QEvent::MouseButtonPress, bodyPosition, Qt::LeftButton,
                                    Qt::LeftButton);
                    const bool headerGrabbed = quickWindow->mouseGrabberItem() == headerInput;
                    sendHeaderMouse(QEvent::MouseButtonRelease, bodyPosition, Qt::LeftButton,
                                    Qt::NoButton);
                    processWindowEvents();
                    if (!headerGrabbed || view.selectionModel().primaryTrack() != targetTrack)
                        fail("real QuickWindow header input did not select the clicked track");

                    QTimer dialogPoll;
                    dialogPoll.setInterval(0);
                    bool pickerSeen = false;
                    bool searchFilteredList = false;
                    QObject::connect(&dialogPoll, &QTimer::timeout, [&] {
                        auto *dialog = view.findChild<QDialog *>();
                        if (!dialog)
                            return;
                        pickerSeen = true;
                        auto *searchField = dialog->findChild<QLineEdit *>();
                        auto *voiceList = dialog->findChild<QListWidget *>();
                        auto *dialogButtons = dialog->findChild<QDialogButtonBox *>();
                        if (searchField && voiceList && dialogButtons &&
                            voiceList->count() == 128) {
                            searchField->setText(QStringLiteral("127  "));
                            searchFilteredList =
                                voiceList->item(0)->isHidden() && !voiceList->item(127)->isHidden();
                            searchField->clear();
                            searchFilteredList &= !voiceList->item(0)->isHidden();
                            voiceList->setCurrentRow(127);
                            searchField->setText(QStringLiteral("1"));
                            searchFilteredList &=
                                voiceList->currentRow() == 1 && !voiceList->item(1)->isHidden() &&
                                !voiceList->item(127)->isHidden() &&
                                dialogButtons->button(QDialogButtonBox::Ok)->isEnabled();
                            searchField->clear();
                            searchFilteredList &= voiceList->currentRow() == 0;
                        }
                        dialog->reject();
                    });
                    dialogPoll.start();
                    checks::events::sendMouse(*headerInput, QEvent::MouseButtonDblClick,
                                              voicePosition, Qt::LeftButton, Qt::LeftButton,
                                              Qt::NoModifier);
                    checks::events::sendMouse(*headerInput, QEvent::MouseButtonRelease,
                                              voicePosition, Qt::LeftButton, Qt::NoButton,
                                              Qt::NoModifier);
                    processWindowEvents();
                    dialogPoll.stop();

                    if (!pickerSeen)
                        fail("Quick voice-line double-click did not open the voice picker");
                    if (!searchFilteredList)
                        fail("voice picker search did not select and restore its first match");
                    const auto *renameEditor = quickRoot->findChild<QQuickItem *>(
                        QStringLiteral("timelineTrackHeaderRename"));
                    if (renameEditor && renameEditor->isVisible())
                        fail("Quick voice-line double-click opened the rename editor");
                    if (document.undoStack()->count() != undoCommands)
                        fail("voice picker navigation changed the undo stack");
                }
            }
        }
    }

    view.close();
    processWindowEvents();
    if (failures == 0)
        std::fprintf(stderr, "rollwindowingcheck: PASS\n");
    return failures == 0 ? 0 : 1;
}
