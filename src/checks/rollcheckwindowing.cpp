#include <QApplication>
#include <QColor>
#include <QCoreApplication>
#include <QDialog>
#include <QDialogButtonBox>
#include <QElapsedTimer>
#include <QImage>
#include <QLineEdit>
#include <QListWidget>
#include <QMouseEvent>
#include <QPixmap>
#include <QPoint>
#include <QPushButton>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRect>
#include <QRegion>
#include <QScrollBar>
#include <QThread>
#include <QTimer>
#include <QWindow>

#include <array>
#include <cmath>
#include <cstdio>
#include <optional>

#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"
#include "core/songdocument.h"
#include "ui/playheadoverlay.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
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

class PaintEventCounter final : public QObject
{
  public:
    int count = 0;

  protected:
    bool eventFilter(QObject *, QEvent *event) override
    {
        if (event->type() == QEvent::Paint)
            ++count;
        return false;
    }
};

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

    auto *quick = view.quickView();
    QQuickItem *const quickRoot = quick ? quick->rootObject() : nullptr;
    auto *overlay =
        view.findChild<songview::PlayheadOverlay *>(QString{}, Qt::FindDirectChildrenOnly);
    if (!quick || !overlay) {
        fail("SongView did not create direct Quick and playhead surfaces");
#ifdef __APPLE__
    } else if (quick->playheadVisible()) {
        fail("default windowing published a Quick playhead on the macOS native path");
#endif
    }

    if (!quick) {
        fail("SongView did not create the Quick host needed for TrackHeaders routing");
    } else {
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

    QScrollBar *hbar = nullptr;
    for (auto *bar : view.findChildren<QScrollBar *>(QString{}, Qt::FindDirectChildrenOnly)) {
        if (bar->orientation() == Qt::Horizontal) {
            hbar = bar;
            break;
        }
    }
    if (!hbar || hbar->size().isEmpty()) {
        fail("SongView did not expose a sized horizontal scrollbar");
    } else {
        QScrollBar reference(Qt::Horizontal, &view);
        const auto matchesReference = [&] {
            reference.setGeometry(hbar->geometry());
            reference.setRange(hbar->minimum(), hbar->maximum());
            reference.setPageStep(hbar->pageStep());
            reference.setSingleStep(hbar->singleStep());
            reference.setInvertedAppearance(hbar->invertedAppearance());
            reference.setInvertedControls(hbar->invertedControls());
            reference.setLayoutDirection(hbar->layoutDirection());
            reference.setPalette(hbar->palette());
            reference.setEnabled(hbar->isEnabled());
            reference.setValue(hbar->value());
            reference.ensurePolished();
            const QImage actualRaw = hbar->grab().toImage();
            const QImage expectedRaw = reference.grab().toImage();
            const QImage actual = actualRaw.convertToFormat(QImage::Format_ARGB32);
            const QImage expected = expectedRaw.convertToFormat(QImage::Format_ARGB32);
            return !actual.isNull() && actual == expected;
        };

        const bool initiallyEnabled = hbar->isEnabled();
        hbar->setEnabled(true);
        if (!matchesReference())
            fail("horizontal scrollbar pixels differed from QScrollBar while enabled");
        hbar->setEnabled(false);
        if (!matchesReference())
            fail("horizontal scrollbar pixels differed from QScrollBar while disabled");
        hbar->setEnabled(true);

        auto *application = qobject_cast<QApplication *>(QCoreApplication::instance());
        if (!application) {
            fail("horizontal scrollbar check did not have a QApplication");
        } else {
            application->setStyleSheet(application->styleSheet());
            processWindowEvents();
            if (!matchesReference())
                fail("horizontal scrollbar pixels changed after stylesheet repolish");

            PaintEventCounter ancestorPaints;
            view.installEventFilter(&ancestorPaints);
            const int originalValue = hbar->value();
            const int movedValue =
                originalValue < hbar->maximum() ? originalValue + 1 : originalValue - 1;
            if (movedValue >= hbar->minimum() && movedValue <= hbar->maximum()) {
                hbar->setValue(movedValue);
                processWindowEvents();
                if (ancestorPaints.count != 0)
                    fail("horizontal scrollbar value change repainted its SongView parent");
                hbar->setValue(originalValue);
                processWindowEvents();
            }
            view.removeEventFilter(&ancestorPaints);
        }
        hbar->setEnabled(initiallyEnabled);
    }

    if (!quick || !quickRoot) {
        fail("SongView did not expose the Quick root for geometry chunk regression coverage");
    } else {
        const std::optional<songview::TimelineBandGeometry> &rollGeometry =
            view.timelineBandLayout().geometry(songview::TimelineBand::Roll);
        const QRectF rootBand =
            rollGeometry ? QRectF(rollGeometry->rect.translated(-quick->geometry().topLeft()))
                               .intersected(QRectF(QPointF{}, quickRoot->size()))
                         : QRectF{};
        if (rootBand.width() < 160.0 || rootBand.height() < 120.0) {
            fail("Quick roll band was too small for geometry chunk regression coverage");
        } else {
            auto *geometryItem = new songview::TimelineQuickItem(quickRoot);
            auto *geometryScene = new songview::TimelineQuickScene(geometryItem);
            geometryItem->setWidth(quickRoot->width());
            geometryItem->setHeight(quickRoot->height());
            geometryItem->setZ(10000.0);
            geometryItem->setSceneLayer(songview::TimelineQuickLayer::PianoDrawPreviewFill);
            geometryItem->setScene(geometryScene);

            const songview::TimelineQuickLayer layer =
                songview::TimelineQuickLayer::PianoDrawPreviewFill;
            const QRectF clip = rootBand;
            const qreal x = rootBand.left() + 24.0;
            const qreal y = rootBand.top() + 24.0;
            const QRectF filler{x + 120.0, y + 88.0, 1.0, 1.0};
            const QRectF oldSolid{x, y, 20.0, 20.0};
            const QRectF oldGradientBase{x + 32.0, y, 48.0, 20.0};
            const QRectF oldGradient = oldGradientBase;
            const std::array<QPointF, 3> oldTriangle = {
                QPointF{x + 96.0, y + 20.0},
                QPointF{x + 116.0, y + 20.0},
                QPointF{x + 106.0, y},
            };
            const QRectF shrinkMarker{x, y + 36.0, 20.0, 20.0};
            const QRectF newSolid{x, y + 64.0, 20.0, 20.0};
            const QRectF newGradientBase{x + 32.0, y + 64.0, 48.0, 20.0};
            const QRectF newGradient = newGradientBase;
            const std::array<QPointF, 3> newTriangle = {
                QPointF{x + 96.0, y + 84.0},
                QPointF{x + 116.0, y + 84.0},
                QPointF{x + 106.0, y + 64.0},
            };
            const QColor fillerColor{8, 12, 16};
            const QColor oldSolidColor{208, 24, 112};
            const QColor oldBaseColor{20, 52, 192};
            const QColor oldLeft{232, 20, 88, 128};
            const QColor oldRight{24, 232, 72, 128};
            const QColor oldTriangleColor{232, 176, 24};
            const QColor shrinkColor{16, 200, 72};
            const QColor newSolidColor{40, 168, 232};
            const QColor newBaseColor{168, 44, 24};
            const QColor newLeft{32, 224, 224, 128};
            const QColor newRight{240, 48, 224, 128};
            const QColor newTriangleColor{128, 48, 232};

            const auto addRectLoad = [&] {
                for (int index = 0; index < 256; ++index)
                    songview::timeline_quick::addRect(*geometryScene, layer, filler, fillerColor,
                                                      clip);
            };
            const auto addTriangleLoad = [&](const std::array<QPointF, 3> &special,
                                             const QColor &specialColor) {
                songview::timeline_quick::addClippedTriangle(
                    *geometryScene, layer, special[0], special[1], special[2], specialColor, clip);
                for (int index = 1; index < 506; ++index) {
                    songview::timeline_quick::addClippedTriangle(
                        *geometryScene, layer, filler.topLeft(), filler.bottomRight(),
                        filler.bottomLeft(), fillerColor, clip);
                }
            };
            const auto capture = [&](const char *phase) {
                geometryItem->update();
                checks::support::pumpQuick();
                QString captureError;
                const QImage frame =
                    checks::support::captureQuickBand(view, rollGeometry->rect, &captureError);
                if (frame.isNull()) {
                    std::fprintf(stderr, "rollwindowingcheck: FAIL %s: %s capture failed: %s\n",
                                 qUtf8Printable(songLabel), phase, qUtf8Printable(captureError));
                    ++failures;
                }
                return frame;
            };
            const auto sample = [&](const QImage &frame, const QPointF &rootPoint) {
                const QPointF bandPoint = rootPoint - rootBand.topLeft();
                const QRect deviceRect = checks::support::devicePixelRect(
                    frame, QRect{qFloor(bandPoint.x()), qFloor(bandPoint.y()), 1, 1});
                return deviceRect.isEmpty() ? QColor{} : frame.pixelColor(deviceRect.center());
            };
            const auto isNear = [](const QColor &actual, const QColor &expected,
                                   int tolerance = 14) {
                return std::abs(actual.alpha() - expected.alpha()) <= tolerance &&
                       std::abs(actual.red() - expected.red()) <= tolerance &&
                       std::abs(actual.green() - expected.green()) <= tolerance &&
                       std::abs(actual.blue() - expected.blue()) <= tolerance;
            };
            const auto center = [](const QRectF &rect) { return rect.center(); };
            const auto triangleCenter = [](const std::array<QPointF, 3> &triangle) {
                return (triangle[0] + triangle[1] + triangle[2]) / 3.0;
            };
            const auto midpointOver = [](const QColor &background, const QColor &left,
                                         const QColor &right) {
                const int alpha = (left.alpha() + right.alpha()) / 2;
                const auto blend = [alpha](int backgroundChannel, int leftChannel,
                                           int rightChannel) {
                    const int source = (leftChannel + rightChannel) / 2;
                    return (source * alpha + backgroundChannel * (255 - alpha) + 127) / 255;
                };
                return QColor{blend(background.red(), left.red(), right.red()),
                              blend(background.green(), left.green(), right.green()),
                              blend(background.blue(), left.blue(), right.blue()), 255};
            };

            const QImage baseline = capture("baseline");
            const auto unchangedFromBaseline = [&](const QImage &frame, const QPointF &point) {
                return !frame.isNull() && !baseline.isNull() &&
                       isNear(sample(frame, point), sample(baseline, point));
            };

            songview::timeline_quick::resetLayer(*geometryScene, layer);
            addRectLoad();
            songview::timeline_quick::addRect(*geometryScene, layer, shrinkMarker, shrinkColor,
                                              clip);
            songview::timeline_quick::addRect(*geometryScene, layer, oldSolid, oldSolidColor, clip);
            songview::timeline_quick::addRect(*geometryScene, layer, oldGradientBase, oldBaseColor,
                                              clip);
            songview::timeline_quick::addHorizontalGradient(*geometryScene, layer, oldGradient,
                                                            oldLeft, oldRight, clip);
            addTriangleLoad(oldTriangle, oldTriangleColor);
            const QImage populated = capture("populated");
            if (!populated.isNull() &&
                (!isNear(sample(populated, center(oldSolid)), oldSolidColor) ||
                 !isNear(sample(populated, triangleCenter(oldTriangle)), oldTriangleColor))) {
                fail("Quick geometry chunk setup did not render its solid rect and triangle");
            }

            songview::timeline_quick::resetLayer(*geometryScene, layer);
            addRectLoad();
            songview::timeline_quick::addRect(*geometryScene, layer, shrinkMarker, shrinkColor,
                                              clip);
            const QImage shrunken = capture("shrunken");
            if (!shrunken.isNull() &&
                (!isNear(sample(shrunken, center(shrinkMarker)), shrinkColor) ||
                 !unchangedFromBaseline(shrunken, center(oldSolid)) ||
                 !unchangedFromBaseline(shrunken, center(oldGradient)) ||
                 !unchangedFromBaseline(shrunken, triangleCenter(oldTriangle)))) {
                fail("Quick geometry chunk shrink retained stale rect or triangle pixels");
            }

            songview::timeline_quick::resetLayer(*geometryScene, layer);
            const QImage cleared = capture("cleared");
            if (!cleared.isNull() &&
                (!unchangedFromBaseline(cleared, center(shrinkMarker)) ||
                 !unchangedFromBaseline(cleared, center(oldSolid)) ||
                 !unchangedFromBaseline(cleared, triangleCenter(oldTriangle)))) {
                fail("Quick geometry chunk clear retained visible pixels");
            }

            songview::timeline_quick::resetLayer(*geometryScene, layer);
            addRectLoad();
            songview::timeline_quick::addClippedTriangle(*geometryScene, layer, newTriangle[0],
                                                         newTriangle[1], newTriangle[2],
                                                         newTriangleColor, clip);
            const QImage partialReactivation = capture("partial-reactivation");
            const QPointF shrinkTail =
                shrinkMarker.topLeft() +
                QPointF{shrinkMarker.width() * 0.75, shrinkMarker.height() * 0.75};
            if (!partialReactivation.isNull() &&
                (!isNear(sample(partialReactivation, triangleCenter(newTriangle)),
                         newTriangleColor) ||
                 !unchangedFromBaseline(partialReactivation, shrinkTail))) {
                fail("Quick geometry chunk partial reactivation retained a blocked chunk tail");
            }

            songview::timeline_quick::resetLayer(*geometryScene, layer);
            addRectLoad();
            songview::timeline_quick::addRect(*geometryScene, layer, shrinkMarker, newSolidColor,
                                              clip);
            songview::timeline_quick::addRect(*geometryScene, layer, newSolid, newSolidColor, clip);
            songview::timeline_quick::addRect(*geometryScene, layer, newGradientBase, newBaseColor,
                                              clip);
            songview::timeline_quick::addHorizontalGradient(*geometryScene, layer, newGradient,
                                                            newLeft, newRight, clip);
            addTriangleLoad(newTriangle, newTriangleColor);
            const QImage reactivated = capture("reactivated");
            if (!reactivated.isNull() &&
                (!isNear(sample(reactivated, center(newSolid)), newSolidColor) ||
                 !isNear(sample(reactivated, triangleCenter(newTriangle)), newTriangleColor) ||
                 !isNear(sample(reactivated, center(newGradient)),
                         midpointOver(newBaseColor, newLeft, newRight)) ||
                 !unchangedFromBaseline(reactivated, center(oldSolid)) ||
                 !unchangedFromBaseline(reactivated, center(oldGradient)) ||
                 !unchangedFromBaseline(reactivated, triangleCenter(oldTriangle)))) {
                fail("Quick geometry chunk reactivation rendered stale or incorrectly blended "
                     "pixels");
            }

            geometryItem->setScene(nullptr);
            geometryItem->deleteLater();
            checks::support::pumpQuick();
        }
    }

    view.close();
    processWindowEvents();
    if (failures == 0)
        std::fprintf(stderr, "rollwindowingcheck: PASS\n");
    return failures == 0 ? 0 : 1;
}
