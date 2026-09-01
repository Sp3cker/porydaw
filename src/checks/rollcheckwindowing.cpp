#include <QCoreApplication>
#include <QDialog>
#include <QDialogButtonBox>
#include <QElapsedTimer>
#include <QLineEdit>
#include <QListWidget>
#include <QPushButton>
#include <QThread>
#include <QTimer>
#include <QWidget>
#include <QWindow>

#include "checks/support/eventsynth.h"
#include "checks/support/songfixture.h"
#include "core/miditimeline.h"
#include "core/songdocument.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/songview.h"

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
    const MidiTimeline *timeline = &rig->timeline();
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

    const int track = view.selectionModel().primaryTrack();
    auto *row = view.findChild<QWidget *>(QStringLiteral("trackHeaderRow%1").arg(track));
    if (!row) {
        fail("track header row for the selected track was not found");
    } else {
        const int undoCommands = document.undoStack()->count();
        const QPoint voicePosition(row->width() / 2, 30);
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
            if (searchField && voiceList && dialogButtons && voiceList->count() == 128) {
                searchField->setText(QStringLiteral("127  "));
                searchFilteredList =
                    voiceList->item(0)->isHidden() && !voiceList->item(127)->isHidden();
                searchField->clear();
                searchFilteredList &= !voiceList->item(0)->isHidden();
                voiceList->setCurrentRow(127);
                searchField->setText(QStringLiteral("1"));
                searchFilteredList &= voiceList->currentRow() == 1 &&
                                      !voiceList->item(1)->isHidden() &&
                                      !voiceList->item(127)->isHidden() &&
                                      dialogButtons->button(QDialogButtonBox::Ok)->isEnabled();
                searchField->clear();
                searchFilteredList &= voiceList->currentRow() == 0;
            }
            dialog->reject();
        });
        dialogPoll.start();
        checks::events::sendMouse(*row, QEvent::MouseButtonDblClick, QPointF(voicePosition),
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*row, QEvent::MouseButtonRelease, QPointF(voicePosition),
                                  Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
        processWindowEvents();
        dialogPoll.stop();

        if (!pickerSeen)
            fail("voice-line double-click did not open the voice picker");
        if (!searchFilteredList)
            fail("voice picker search did not select and restore its first match");
        const auto *renameEditor = view.findChild<QLineEdit *>(QStringLiteral("trackRenameEditor"));
        if (renameEditor && !renameEditor->isHidden())
            fail("voice-line double-click opened the rename editor");
        if (document.undoStack()->count() != undoCommands)
            fail("voice picker navigation changed the undo stack");
    }

    view.close();
    processWindowEvents();
    if (failures == 0)
        std::fprintf(stderr, "rollwindowingcheck: PASS\n");
    return failures == 0 ? 0 : 1;
}
