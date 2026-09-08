// Time-signature editing through the live ruler and its in-canvas Quick
// prompt. These checks deliberately drive the existing Quick window rather
// than bridge invokables so focus, keyboard input, button routing, and guarded
// document commits remain observable.

#include "checks/rollcheck/tst_pianoroll.h"

#include "checks/quickpopupguard.h"
#include "checks/rollcheck/rollcheck.h"
#include "checks/support/asyncwait.h"
#include "core/miditimeline.h"
#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timeaxis.h"
#include "ui/songview/timeruler.h"

#include <QByteArray>
#include <QCoreApplication>

#include <QPoint>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QString>
#include <QtGlobal>
#include <QtTest>

#include <algorithm>
#include <cstdint>
#include <memory>
#include <vector>

namespace {

constexpr double kSampleRate = 48000.0;

struct TimeSignatureFixture final {
    checks::rollcheck::PianoRollFixture *outer = nullptr;
    QPointer<songview::TimelineInputItem> rulerInput;
    uint64_t signatureTick = 0;

    static std::unique_ptr<TimeSignatureFixture>
    create(checks::rollcheck::PianoRollFixture &existing, QString &error)
    {
        auto fixture = std::make_unique<TimeSignatureFixture>();
        fixture->outer = &existing;

        SongDocument &document = fixture->outer->document();
        const uint64_t ticksPerBeat = document.ticksPerClock();
        if (ticksPerBeat == 0) {
            error = QStringLiteral("the loaded song has no tick resolution");
            return nullptr;
        }
        fixture->signatureTick = ticksPerBeat * 4;
        document.setTimeSig(fixture->signatureTick, 3, 2);
        QCoreApplication::processEvents();

        SongView &view = fixture->outer->view();
        auto *quick =
            view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
        QQuickItem *const root = quick ? quick->rootObject() : nullptr;
        fixture->rulerInput = root ? root->findChild<songview::TimelineInputItem *>(
                                         QLatin1String("timelineRulerInput"))
                                   : nullptr;
        if (!fixture->rulerInput) {
            error = QStringLiteral("the song view has no ruler Quick input");
            return nullptr;
        }
        // Local Quick focus is sufficient: pointer and key input route through
        // the scene once the ruler input owns active focus. Never depend on
        // OS-global host or window activation here; late in a full rollcheck
        // run the host can no longer become globally active.
        QQuickWindow *const window = fixture->rulerInput->window();
        if (!window) {
            error = QStringLiteral("the song view has no ruler Quick window");
            return nullptr;
        }
        if (!QTest::qWaitFor([window] { return window->isVisible() && window->isExposed(); })) {
            error = QStringLiteral("the song view Quick window never exposed");
            return nullptr;
        }
        // Re-force while waiting: the first show in a process can still settle
        // window activation or initial scene focus after this call, which
        // clears the forced item. This stays strictly local: no host or window
        // activation, just the ruler input owning scene focus.
        bool focused = false;
        for (int attempt = 0; attempt < 100 && !focused; ++attempt) {
            fixture->rulerInput->forceActiveFocus(Qt::OtherFocusReason);
            focused =
                QTest::qWaitFor([&fixture] { return fixture->rulerInput->hasActiveFocus(); }, 50);
        }
        if (!focused) {
            error = QStringLiteral("the ruler Quick input never took local focus");
            return nullptr;
        }
        return fixture;
    }

    SongDocument &document() const noexcept { return outer->document(); }
    SongView &view() const noexcept { return outer->view(); }

    QPoint rulerPoint(uint64_t tick) const
    {
        const qreal x = view().camera().displayX(double(tick), 0.0, rulerInput->devicePixelRatio());
        return QPoint(qRound(x), (std::max)(1, qRound(rulerInput->height()) / 4));
    }
};

struct TimeSignaturePromptSession {
    QQuickWindow *window = nullptr;
    songview::QuickPopupSession *popup = nullptr;
    QString diagnostic = QStringLiteral("the time-signature prompt did not open");
};

QPoint windowPoint(const songview::TimelineInputItem &item, QPoint local)
{
    return item.mapToScene(local).toPoint();
}

TimeSignaturePromptSession openedPrompt(SongView &view)
{
    TimeSignaturePromptSession session;
    const QPointer<songview::QuickPopupSession> live(quick_popup::popupSession(view));
    // The prompt may replace a just-closed shared menu, so wait for the
    // canvas session to publish before demanding form readiness.
    if (!QTest::qWaitFor([&live] { return live && live->isOpen() && live->window(); })) {
        session.diagnostic = QStringLiteral("the ruler action did not open a canvas prompt");
        return session;
    }
    session.popup = live;
    session.window = live->window();
    if (checks::async_wait::waitUntil(
            [] { return true; },
            [&session] {
                if (!quick_popup::inputHasActiveFocus(*session.window,
                                                      QLatin1String("timeSignatureNumerator")))
                    return false;
                QQuickItem *const numerator = quick_popup::promptItem(
                    *session.popup, QLatin1String("timeSignatureNumerator"));
                if (!numerator)
                    return false;
                const QString text = numerator->property("text").toString();
                return !text.isEmpty() && numerator->property("selectedText").toString() == text;
            },
            5000, 10) != checks::async_wait::Result::Ready) {
        if (!quick_popup::inputHasActiveFocus(*session.window,
                                              QLatin1String("timeSignatureNumerator"))) {
            session.diagnostic = QStringLiteral("the time-signature numerator did not take focus");
        } else {
            session.diagnostic =
                QStringLiteral("the time-signature numerator did not select its initial text");
        }
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
    // Deliver the complete physical double-click sequence. Production releases
    // the ruler's pointer grab before publishing the form, so this final
    // release stays with the opening gesture rather than cancelling it.
    QTest::mousePress(window, Qt::LeftButton, Qt::NoModifier, point);
    QTest::mouseRelease(window, Qt::LeftButton, Qt::NoModifier, point);
    QTest::mouseDClick(window, Qt::LeftButton, Qt::NoModifier, point);
    QTest::mouseRelease(window, Qt::LeftButton, Qt::NoModifier, point);
    QCoreApplication::processEvents();
    return openedPrompt(fixture.view());
}

// Right-clicks the live ruler and activates the shared menu's time-signature
// row for real: the press opens the typed ruler menu, the click lands on the
// rendered EditTimeSig row, and the readiness wait covers the prompt that is
// published only after the menu session closed.
TimeSignaturePromptSession openFromRulerMenu(TimeSignatureFixture &fixture, bool onChip)
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

    const QPoint point = windowPoint(*fixture.rulerInput, local);
    QTest::mousePress(window, Qt::RightButton, Qt::NoModifier, point);
    QTest::mouseRelease(window, Qt::RightButton, Qt::NoModifier, point);
    const QPointer<songview::QuickPopupSession> live(quick_popup::popupSession(fixture.view()));
    if (!QTest::qWaitFor([&live] {
            return live && live->isOpen() && quick_popup::menuPanel(*live) &&
                   quick_popup::menuModel(*quick_popup::menuPanel(*live)) != nullptr;
        })) {
        session.diagnostic = QStringLiteral("the ruler right-click did not open the shared menu");
        return session;
    }
    songview::QuickMenuModel *const model = quick_popup::menuModel(*quick_popup::menuPanel(*live));
    const int editRow = model->rowForId(int(songview::RulerMenuAction::EditTimeSig));
    if (editRow < 0) {
        session.diagnostic = QStringLiteral("the shared ruler menu has no time-signature row");
        return session;
    }
    if (!quick_popup::clickMenuRow(*live, editRow)) {
        session.diagnostic = QStringLiteral("the time-signature menu row did not render a target");
        return session;
    }
    return openedPrompt(fixture.view());
}

bool chooseDenominator(songview::QuickPopupSession &popup, int denominatorPow2)
{
    switch (denominatorPow2) {
    case 0:
        return quick_popup::clickPromptButton(popup, QLatin1String("timeSignatureDenominator0"));
    case 1:
        return quick_popup::clickPromptButton(popup, QLatin1String("timeSignatureDenominator1"));
    case 2:
        return quick_popup::clickPromptButton(popup, QLatin1String("timeSignatureDenominator2"));
    case 3:
        return quick_popup::clickPromptButton(popup, QLatin1String("timeSignatureDenominator3"));
    case 4:
        return quick_popup::clickPromptButton(popup, QLatin1String("timeSignatureDenominator4"));
    case 5:
        return quick_popup::clickPromptButton(popup, QLatin1String("timeSignatureDenominator5"));
    }
    return false;
}

QQuickItem *draftNumerator(songview::QuickPopupSession &popup, const QString &text)
{
    QQuickItem *const numerator =
        quick_popup::promptItem(popup, QLatin1String("timeSignatureNumerator"));
    if (numerator)
        numerator->setProperty("text", text);
    return numerator;
}

} // namespace

void PianoRollTest::timeSignaturePromptAcceptUndoGrid()
{
    QString error;
    std::unique_ptr<TimeSignatureFixture> fixture = TimeSignatureFixture::create(*m_fixture, error);
    QVERIFY2(fixture, qPrintable(error));
    SongDocument &document = fixture->document();
    const quick_popup::PromptGuard guard(fixture->view());
    const QByteArray before = document.smf().write();
    const int undo = document.undoStack()->index();
    const int undoCount = document.undoStack()->count();
    const uint64_t revision = document.revision();

    const TimeSignaturePromptSession opened = openFromChip(*fixture);
    QVERIFY2(opened.window && opened.popup, qUtf8Printable(opened.diagnostic));
    QQuickItem *const numerator = draftNumerator(*opened.popup, QStringLiteral("7"));
    QVERIFY2(numerator, "the time-signature prompt has no numerator input");
    QTRY_COMPARE(numerator->property("text").toString(), QStringLiteral("7"));
    QVERIFY2(chooseDenominator(*opened.popup, 3), "the time-signature prompt has no 8 button");
    // The denominator now owns focus; Enter must commit the displayed 7/8,
    // not merely re-select the focused denominator.
    QTest::keyClick(opened.window, Qt::Key_Return);
    QCoreApplication::processEvents();

    songview::QuickPopupSession *const popup = quick_popup::popupSession(fixture->view());
    QVERIFY2(popup && !popup->isOpen(), "Return did not close the time-signature prompt");
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
    QVERIFY2(unchanged.window && unchanged.popup, qUtf8Printable(unchanged.diagnostic));
    const QByteArray beforeUnchanged = document.smf().write();
    const int unchangedUndo = document.undoStack()->index();
    const int unchangedUndoCount = document.undoStack()->count();
    const uint64_t unchangedRevision = document.revision();
    QVERIFY2(quick_popup::clickPromptButton(*unchanged.popup, QLatin1String("timeSignatureAccept")),
             "the reopened time-signature prompt has no Accept button");
    QCoreApplication::processEvents();
    QVERIFY2(popup && !popup->isOpen() && document.smf().write() == beforeUnchanged &&
                 document.undoStack()->index() == unchangedUndo &&
                 document.undoStack()->count() == unchangedUndoCount &&
                 document.revision() == unchangedRevision,
             "accepting an unchanged time signature added an undoable document edit");
}

void PianoRollTest::timeSignaturePromptCancelStale()
{
    QString error;
    std::unique_ptr<TimeSignatureFixture> fixture = TimeSignatureFixture::create(*m_fixture, error);
    QVERIFY2(fixture, qPrintable(error));
    SongDocument &document = fixture->document();
    const quick_popup::PromptGuard guard(fixture->view());
    const QByteArray before = document.smf().write();
    const int undo = document.undoStack()->index();
    const int undoCount = document.undoStack()->count();
    const uint64_t revision = document.revision();

    const TimeSignaturePromptSession cancelled = openFromChip(*fixture);
    QVERIFY2(cancelled.window && cancelled.popup, qUtf8Printable(cancelled.diagnostic));
    QQuickItem *const cancelledNumerator = draftNumerator(*cancelled.popup, QStringLiteral("7"));
    QVERIFY2(cancelledNumerator, "the time-signature prompt has no numerator input");
    QTRY_COMPARE(cancelledNumerator->property("text").toString(), QStringLiteral("7"));
    QVERIFY2(quick_popup::clickPromptButton(*cancelled.popup, QLatin1String("timeSignatureCancel")),
             "the time-signature prompt has no Cancel button");
    QCoreApplication::processEvents();
    songview::QuickPopupSession *const popup = quick_popup::popupSession(fixture->view());
    QVERIFY2(popup && !popup->isOpen() && document.smf().write() == before &&
                 document.undoStack()->index() == undo &&
                 document.undoStack()->count() == undoCount && document.revision() == revision,
             "Cancel wrote the draft time signature to the song");
    QTRY_VERIFY2(fixture->rulerInput->hasActiveFocus(),
                 "Cancel did not return focus to the ruler input");

    // An invalid numerator must leave the prompt open and the song untouched.
    const TimeSignaturePromptSession invalid = openFromChip(*fixture);
    QVERIFY2(invalid.window && invalid.popup, qUtf8Printable(invalid.diagnostic));
    QQuickItem *const invalidNumerator = draftNumerator(*invalid.popup, QStringLiteral("999"));
    QVERIFY2(invalidNumerator, "the time-signature prompt has no numerator input");
    QTRY_COMPARE(invalidNumerator->property("text").toString(), QStringLiteral("999"));
    QTest::keyClick(invalid.window, Qt::Key_Return);
    QCoreApplication::processEvents();
    QVERIFY2(popup && popup->isOpen() && document.smf().write() == before &&
                 document.undoStack()->index() == undo &&
                 document.undoStack()->count() == undoCount && document.revision() == revision,
             "an invalid numerator was accepted or wrote to the song");
    QTest::keyClick(invalid.window, Qt::Key_Escape);
    QCoreApplication::processEvents();
    QVERIFY2(popup && !popup->isOpen(), "Escape did not close the invalid-number prompt");

    const TimeSignaturePromptSession stale = openFromChip(*fixture);
    QVERIFY2(stale.window && stale.popup, qUtf8Printable(stale.diagnostic));
    // A document revision change owns stale-session retirement; it must not
    // leave an actionable draft or append another document command.
    document.setTimeSig(fixture->signatureTick + document.ticksPerClock(), 5, 2);
    const QByteArray afterInterveningEdit = document.smf().write();
    const int staleUndo = document.undoStack()->index();
    const int staleUndoCount = document.undoStack()->count();
    const uint64_t staleRevision = document.revision();
    QCoreApplication::processEvents();
    QVERIFY2(popup && !popup->isOpen() && document.smf().write() == afterInterveningEdit &&
                 document.undoStack()->index() == staleUndo &&
                 document.undoStack()->count() == staleUndoCount &&
                 document.revision() == staleRevision,
             "a document revision change left a stale prompt or wrote an extra edit");
}

void PianoRollTest::timeSignaturePromptMenuEntries_data()
{
    QTest::addColumn<bool>("onChip");
    QTest::newRow("on the signature chip") << true;
    QTest::newRow("off the signature chip") << false;
}

void PianoRollTest::timeSignaturePromptMenuEntries()
{
    QFETCH(bool, onChip);
    QString error;
    std::unique_ptr<TimeSignatureFixture> fixture = TimeSignatureFixture::create(*m_fixture, error);
    QVERIFY2(fixture, qPrintable(error));
    const quick_popup::PromptGuard guard(fixture->view());
    const TimeSignaturePromptSession opened = openFromRulerMenu(*fixture, onChip);
    QVERIFY2(opened.window && opened.popup, qUtf8Printable(opened.diagnostic));
    songview::QuickPopupSession *const popup = quick_popup::popupSession(fixture->view());
    QVERIFY2(popup && popup->isOpen() && !quick_popup::menuPanel(*popup),
             "the shared ruler menu still owned the session when the time-signature prompt opened");
    QVERIFY2(quick_popup::promptItem(*opened.popup, QLatin1String("timeSignaturePrompt")),
             "the ruler menu action did not open the time-signature prompt surface");

    QTest::keyClick(opened.window, Qt::Key_Escape);
    QCoreApplication::processEvents();
    QVERIFY2(popup && !popup->isOpen(),
             "Escape did not close the ruler-menu time-signature prompt");
    QTRY_VERIFY2(fixture->rulerInput->hasActiveFocus(),
                 "closing the ruler-menu prompt did not return focus to the ruler input");
}
