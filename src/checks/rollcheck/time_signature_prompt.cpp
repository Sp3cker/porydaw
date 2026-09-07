// Time-signature editing through the live ruler and application-modal Quick
// prompt. These checks deliberately drive the Quick window rather than the
// bridge invokables so focus, keyboard input, button routing, and guarded
// document commits remain observable.

#include "checks/rollcheck/tst_pianoroll.h"

#include "checks/quickmodalguard.h"
#include "checks/support/asyncwait.h"
#include "checks/support/editorrig.h"
#include "checks/support/songfixture.h"
#include "core/miditimeline.h"
#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/timeaxis.h"

#include <QAction>
#include <QApplication>
#include <QByteArray>
#include <QCoreApplication>
#include <QKeySequence>
#include <QMenu>
#include <QPoint>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSize>
#include <QString>
#include <QTimer>
#include <QtGlobal>
#include <QtTest>

#include <algorithm>
#include <cstdint>
#include <memory>
#include <vector>

namespace {

constexpr double kSampleRate = 48000.0;

struct TimeSignatureFixture final {
    std::unique_ptr<checks::LoadedSong> song;
    std::unique_ptr<checks::EditorRig> rig;
    QPointer<songview::TimelineInputItem> rulerInput;
    uint64_t signatureTick = 0;

    static std::unique_ptr<TimeSignatureFixture> create(const QString &projectRoot,
                                                        const QString &songLabel, QString &error)
    {
        auto fixture = std::make_unique<TimeSignatureFixture>();
        fixture->song = checks::LoadedSong::load(projectRoot, songLabel, error);
        if (!fixture->song)
            return nullptr;

        SongDocument &document = fixture->song->document();
        const uint64_t ticksPerBeat = document.ticksPerClock();
        if (ticksPerBeat == 0) {
            error = QStringLiteral("the loaded song has no tick resolution");
            return nullptr;
        }
        fixture->signatureTick = ticksPerBeat * 4;
        document.setTimeSig(fixture->signatureTick, 3, 2);

        checks::EditorRigConfig config;
        config.viewSize = QSize(1280, 800);
        config.timeZoom = 96.0;
        config.show = true;
        fixture->rig = checks::EditorRig::create(document, config, error);
        if (!fixture->rig)
            return nullptr;

        QQuickItem *const root = fixture->rig->quickRoot();
        fixture->rulerInput = root ? root->findChild<songview::TimelineInputItem *>(
                                         QLatin1String("timelineRulerInput"))
                                   : nullptr;
        if (!fixture->rulerInput) {
            error = QStringLiteral("the editor rig has no ruler Quick input");
            return nullptr;
        }
        return fixture;
    }

    SongDocument &document() const noexcept { return song->document(); }
    SongView &view() const noexcept { return rig->view(); }

    QPoint rulerPoint(uint64_t tick) const
    {
        const qreal x = view().camera().displayX(double(tick), 0.0, rulerInput->devicePixelRatio());
        return QPoint(qRound(x), (std::max)(1, qRound(rulerInput->height()) / 4));
    }
};

struct TimeSignaturePromptSession {
    QQuickWindow *window = nullptr;
    QString diagnostic = QStringLiteral("the time-signature prompt did not open");
};

QPoint windowPoint(const songview::TimelineInputItem &item, QPoint local)
{
    return item.mapToScene(local).toPoint();
}

TimeSignaturePromptSession openedPrompt(SongView &view)
{
    TimeSignaturePromptSession session;
    songview::QuickModalHost *const host = quick_modal::modalHost(view);
    if (!host || !host->isOpen() || !host->modalWindow()) {
        session.diagnostic = QStringLiteral("the ruler action did not open a modal prompt");
        return session;
    }
    session.window = host->modalWindow();
    if (!QTest::qWaitForWindowExposed(session.window)) {
        session.diagnostic =
            QStringLiteral("the time-signature prompt window did not become exposed");
        return session;
    }
    if (checks::async_wait::waitUntil([] { return true; },
                                      [&session] {
                                          return quick_modal::inputHasActiveFocus(
                                              *session.window,
                                              QLatin1String("timeSignatureNumerator"));
                                      },
                                      5000, 10) != checks::async_wait::Result::Ready) {
        session.diagnostic = QStringLiteral("the time-signature numerator did not take focus");
        return session;
    }
    session.diagnostic.clear();
    return session;
}

TimeSignaturePromptSession openFromChip(TimeSignatureFixture &fixture)
{
    TimeSignaturePromptSession session;
    QQuickWindow *const window = fixture.rulerInput->window();
    const QPoint local = fixture.rulerPoint(fixture.signatureTick);
    if (!window || !fixture.rulerInput->bounds().contains(local)) {
        session.diagnostic =
            QStringLiteral("the seeded signature chip is outside the live ruler input");
        return session;
    }

    const QPoint point = windowPoint(*fixture.rulerInput, local);
    QTest::mousePress(window, Qt::LeftButton, Qt::NoModifier, point);
    QTest::mouseRelease(window, Qt::LeftButton, Qt::NoModifier, point);
    QTest::mouseDClick(window, Qt::LeftButton, Qt::NoModifier, point);
    QCoreApplication::processEvents();
    return openedPrompt(fixture.view());
}

struct RulerMenuSelection {
    bool foundAction = false;
    bool closedMenu = false;
};

TimeSignaturePromptSession openFromRulerMenu(TimeSignatureFixture &fixture, bool onChip,
                                             RulerMenuSelection &selection)
{
    TimeSignaturePromptSession session;
    QQuickWindow *const window = fixture.rulerInput->window();
    const uint64_t targetTick =
        onChip ? fixture.signatureTick : fixture.signatureTick + fixture.document().ticksPerClock();
    const QPoint local = fixture.rulerPoint(targetTick);
    if (!window || !fixture.rulerInput->bounds().contains(local)) {
        session.diagnostic =
            QStringLiteral("the requested ruler menu point is outside the live input");
        return session;
    }

    QTimer::singleShot(10, [&selection] {
        auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
        if (!menu)
            menu = qobject_cast<QMenu *>(QApplication::activeModalWidget());
        if (!menu)
            return;

        QAction *action = nullptr;
        for (QAction *const candidate : menu->actions()) {
            if (candidate->objectName() == QLatin1String("timeSignatureEditAction")) {
                action = candidate;
                break;
            }
        }
        if (!action)
            return;
        selection.foundAction = true;
        QTest::mouseClick(menu, Qt::LeftButton, Qt::NoModifier,
                          menu->actionGeometry(action).center());
        selection.closedMenu = !menu->isVisible();
    });

    const QPoint point = windowPoint(*fixture.rulerInput, local);
    QTest::mousePress(window, Qt::RightButton, Qt::NoModifier, point);
    QTest::mouseRelease(window, Qt::RightButton, Qt::NoModifier, point);
    QCoreApplication::processEvents();
    return openedPrompt(fixture.view());
}

bool chooseDenominator(QQuickWindow &window, int denominatorPow2)
{
    switch (denominatorPow2) {
    case 0:
        return quick_modal::clickPromptButton(window, QLatin1String("timeSignatureDenominator0"));
    case 1:
        return quick_modal::clickPromptButton(window, QLatin1String("timeSignatureDenominator1"));
    case 2:
        return quick_modal::clickPromptButton(window, QLatin1String("timeSignatureDenominator2"));
    case 3:
        return quick_modal::clickPromptButton(window, QLatin1String("timeSignatureDenominator3"));
    case 4:
        return quick_modal::clickPromptButton(window, QLatin1String("timeSignatureDenominator4"));
    case 5:
        return quick_modal::clickPromptButton(window, QLatin1String("timeSignatureDenominator5"));
    default:
        return false;
    }
}

} // namespace

void PianoRollTest::timeSignaturePromptAcceptUndoGrid()
{
    QString error;
    std::unique_ptr<TimeSignatureFixture> fixture =
        TimeSignatureFixture::create(m_project->root(), m_songLabel, error);
    QVERIFY2(fixture, qPrintable(error));
    SongDocument &document = fixture->document();
    const quick_modal::PromptGuard guard(fixture->view());
    const QByteArray before = document.smf().write();
    const int undo = document.undoStack()->index();
    const int undoCount = document.undoStack()->count();
    const uint64_t revision = document.revision();

    const TimeSignaturePromptSession opened = openFromChip(*fixture);
    QVERIFY2(opened.window, qUtf8Printable(opened.diagnostic));
    QQuickItem *const numerator =
        quick_modal::promptItem(*opened.window, QLatin1String("timeSignatureNumerator"));
    QVERIFY2(numerator, "the time-signature prompt has no numerator input");

    QTest::keySequence(opened.window, QKeySequence(Qt::Key_7));
    QCoreApplication::processEvents();
    QCOMPARE(numerator->property("text").toString(), QStringLiteral("7"));
    QVERIFY2(chooseDenominator(*opened.window, 3), "the time-signature prompt has no 8 button");
    // The denominator now owns focus; Enter must commit the displayed 7/8,
    // not merely re-select the focused denominator.
    QTest::keyClick(opened.window, Qt::Key_Return);
    QCoreApplication::processEvents();

    songview::QuickModalHost *const host = quick_modal::modalHost(fixture->view());
    QVERIFY2(host && !host->isOpen(), "Return did not close the time-signature prompt");
    const std::vector<DocTimeSig> signatures = document.timeSigs();
    const auto signature =
        std::find_if(signatures.cbegin(), signatures.cend(), [&fixture](const DocTimeSig &value) {
            return value.tick == fixture->signatureTick;
        });
    QVERIFY2(signature != signatures.cend() && signature->numerator == 7 &&
                 signature->denomPow2 == 3 && document.revision() == revision + 1 &&
                 document.undoStack()->index() == undo + 1 &&
                 document.undoStack()->count() == undoCount + 1,
             "Return did not commit 7/8 as one undoable time-signature edit");

    const std::unique_ptr<MidiTimeline> rebuilt = document.buildTimeline(kSampleRate);
    QVERIFY2(rebuilt, "the accepted time signature could not rebuild a timeline");
    songview::TimeAxis axis;
    axis.bind(rebuilt.get());
    const songview::TimeAxis::GridSegment grid = axis.segmentAt(fixture->signatureTick);
    QVERIFY2(grid.start == fixture->signatureTick && grid.beatsPerBar == 7 &&
                 grid.beatTicks == rebuilt->ticksPerBeat / 2,
             "the accepted 7/8 signature did not produce its denominator-scaled grid segment");

    QTRY_VERIFY2(fixture->rulerInput->hasActiveFocus(),
                 "Return did not return focus to the ruler input");
    document.undoStack()->undo();
    QCOMPARE(document.smf().write(), before);

    // Reopening and accepting the displayed 3/4 makes no document edit.
    const TimeSignaturePromptSession unchanged = openFromChip(*fixture);
    QVERIFY2(unchanged.window, qUtf8Printable(unchanged.diagnostic));
    const QByteArray beforeUnchanged = document.smf().write();
    const int unchangedUndo = document.undoStack()->index();
    const int unchangedUndoCount = document.undoStack()->count();
    const uint64_t unchangedRevision = document.revision();
    QVERIFY2(
        quick_modal::clickPromptButton(*unchanged.window, QLatin1String("timeSignatureAccept")),
        "the reopened time-signature prompt has no Accept button");
    QCoreApplication::processEvents();
    QVERIFY2(host && !host->isOpen() && document.smf().write() == beforeUnchanged &&
                 document.undoStack()->index() == unchangedUndo &&
                 document.undoStack()->count() == unchangedUndoCount &&
                 document.revision() == unchangedRevision,
             "accepting an unchanged time signature added an undoable document edit");
}

void PianoRollTest::timeSignaturePromptCancelStale()
{
    QString error;
    std::unique_ptr<TimeSignatureFixture> fixture =
        TimeSignatureFixture::create(m_project->root(), m_songLabel, error);
    QVERIFY2(fixture, qPrintable(error));
    SongDocument &document = fixture->document();
    const quick_modal::PromptGuard guard(fixture->view());
    const QByteArray before = document.smf().write();
    const int undo = document.undoStack()->index();
    const int undoCount = document.undoStack()->count();
    const uint64_t revision = document.revision();

    const TimeSignaturePromptSession cancelled = openFromChip(*fixture);
    QVERIFY2(cancelled.window, qUtf8Printable(cancelled.diagnostic));
    QTest::keySequence(cancelled.window, QKeySequence(Qt::Key_7));
    QVERIFY2(
        quick_modal::clickPromptButton(*cancelled.window, QLatin1String("timeSignatureCancel")),
        "the time-signature prompt has no Cancel button");
    QCoreApplication::processEvents();
    songview::QuickModalHost *const host = quick_modal::modalHost(fixture->view());
    QVERIFY2(host && !host->isOpen() && document.smf().write() == before &&
                 document.undoStack()->index() == undo &&
                 document.undoStack()->count() == undoCount && document.revision() == revision,
             "Cancel wrote the draft time signature to the song");
    QTRY_VERIFY2(fixture->rulerInput->hasActiveFocus(),
                 "Cancel did not return focus to the ruler input");

    // An invalid numerator must leave the modal open and the song untouched.
    const TimeSignaturePromptSession invalid = openFromChip(*fixture);
    QVERIFY2(invalid.window, qUtf8Printable(invalid.diagnostic));
    QTest::keySequence(invalid.window, QKeySequence(Qt::Key_9, Qt::Key_9, Qt::Key_9));
    QTest::keyClick(invalid.window, Qt::Key_Return);
    QCoreApplication::processEvents();
    QVERIFY2(host && host->isOpen() && document.smf().write() == before &&
                 document.undoStack()->index() == undo &&
                 document.undoStack()->count() == undoCount && document.revision() == revision,
             "an invalid numerator was accepted or wrote to the song");
    QTest::keyClick(invalid.window, Qt::Key_Escape);
    QCoreApplication::processEvents();
    QVERIFY2(host && !host->isOpen(), "Escape did not close the invalid-number prompt");

    const TimeSignaturePromptSession stale = openFromChip(*fixture);
    QVERIFY2(stale.window, qUtf8Printable(stale.diagnostic));
    // A document revision change owns cancellation; it must not leave an
    // actionable stale draft or append another document command.
    document.setTimeSig(fixture->signatureTick + document.ticksPerClock(), 5, 2);
    const QByteArray afterInterveningEdit = document.smf().write();
    const int staleUndo = document.undoStack()->index();
    const int staleUndoCount = document.undoStack()->count();
    const uint64_t staleRevision = document.revision();
    QCoreApplication::processEvents();
    QVERIFY2(host && !host->isOpen() && document.smf().write() == afterInterveningEdit &&
                 document.undoStack()->index() == staleUndo &&
                 document.undoStack()->count() == staleUndoCount &&
                 document.revision() == staleRevision,
             "a document revision change left a stale prompt or wrote an extra edit");
    QTRY_VERIFY2(fixture->rulerInput->hasActiveFocus(),
                 "stale cancellation did not return focus to the ruler input");
}

void PianoRollTest::timeSignaturePromptMenuEntries_data()
{
    QTest::addColumn<bool>("onChip");
    QTest::newRow("Edit time signature") << true;
    QTest::newRow("Set time signature") << false;
}

void PianoRollTest::timeSignaturePromptMenuEntries()
{
    QFETCH(bool, onChip);
    QString error;
    std::unique_ptr<TimeSignatureFixture> fixture =
        TimeSignatureFixture::create(m_project->root(), m_songLabel, error);
    QVERIFY2(fixture, qPrintable(error));
    const quick_modal::PromptGuard guard(fixture->view());
    RulerMenuSelection selection;
    const TimeSignaturePromptSession opened = openFromRulerMenu(*fixture, onChip, selection);
    QVERIFY2(selection.foundAction,
             "the ruler menu did not expose its semantic time-signature action identity");
    QVERIFY2(selection.closedMenu,
             "the ruler menu still owned input when the time-signature prompt opened");
    QVERIFY2(opened.window, qUtf8Printable(opened.diagnostic));
    QVERIFY2(quick_modal::promptItem(*opened.window, QLatin1String("timeSignaturePrompt")),
             "the ruler menu action did not open the time-signature prompt surface");

    QTest::keyClick(opened.window, Qt::Key_Escape);
    QCoreApplication::processEvents();
    songview::QuickModalHost *const host = quick_modal::modalHost(fixture->view());
    QVERIFY2(host && !host->isOpen(), "Escape did not close the ruler-menu time-signature prompt");
}
