#include "checks/voicegroupsave/tst_voicegroupsave.h"

#include <QComboBox>
#include <QCoreApplication>
#include <QDialog>
#include <QDialogButtonBox>
#include <QFile>
#include <QFormLayout>
#include <QLabel>
#include <QLineEdit>
#include <QPointer>
#include <QPushButton>
#include <QQuickItem>
#include <QTimer>
#include <QtTest>

#include <algorithm>

#include "checks/support/eventsynth.h"
#include "checks/support/songfixture.h"
#include "checks/support/voicegroupbrowserdriver.h"
#include "core/songdocument.h"
#include "mainwindow.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/trackheadermodel.h"
#include "ui/workspaceui.h"

namespace checks {
namespace {

int rowForTrack(const songview::TrackHeaderModel &model, int track)
{
    for (int row = 0; row < model.rowCount(); ++row) {
        if (model.data(model.index(row, 0), songview::TrackHeaderModel::TrackRole).toInt() == track)
            return row;
    }
    return -1;
}

QPointF trackHeaderPoint(songview::TrackHeaderModel &model, songview::TimelineInputItem &input,
                         int row)
{
    const qreal centered = row * model.rowHeight() - (input.height() - model.rowHeight()) / 2.0;
    model.setScrollY(std::clamp(centered, qreal(0.0), model.maximumScrollY()));
    return QPointF(model.activityWidth() / 2.0,
                   row * model.rowHeight() - model.scrollY() + model.rowHeight() / 2.0);
}

} // namespace

void VoicegroupSaveTest::revealsTrackProgramsAndUsedMarks()
{
    SongView &view = m_tab->view();
    QVERIFY(!m_browser->slotRowText(0).isEmpty());
    const QSet<int> used = view.usedVoices();
    QVERIFY(!used.isEmpty());
    int unused = -1;
    for (int slot = 0; slot < VOICEGROUP_SIZE && unused < 0; ++slot) {
        if (!used.contains(slot))
            unused = slot;
    }
    QVERIFY(std::all_of(used.cbegin(), used.cend(),
                        [this](int slot) { return m_browser->slotIsMarkedUsed(slot); }));
    QVERIFY(unused < 0 || !m_browser->slotIsMarkedUsed(unused));

    m_browser->hideDock();
    const int program = view.currentProgram(m_track);
    QVERIFY(program >= 0);
    view.revealTrackVoice(m_track);
    QVERIFY(!m_browser->dockIsHidden());
    QCOMPARE(m_browser->currentSlot(), program);
    QVERIFY2(unused >= 0, "fixture must provide an unused program for the mark transition");
    view.revealVoice(unused);
    QCOMPARE(m_browser->currentSlot(), unused);
    m_document->addLanePoint(m_track, DOC_CC_VOICE, 480, unused);
    QVERIFY(m_browser->slotIsMarkedUsed(unused));
    requestUndo();
    QVERIFY2(settle([this, unused] { return !m_browser->slotIsMarkedUsed(unused); }),
             "voice-lane undo did not clear the used mark");
}

void VoicegroupSaveTest::quickHeaderPressSurvivesVoicegroupRebuild()
{
    const QString other = otherVoicegroupArg();
    QVERIFY2(m_window->m_workspace->projectState().catalog.groupArgs.size() >= 2 &&
                 !other.isEmpty(),
             "required staged voicegroups missing: >=2 groupArgs via sound/voice_groups.inc and "
             "sound/voicegroups/fixture_alt.inc");
    m_window->show();
    m_window->activateWindow();
    QCoreApplication::processEvents();
    SongView &view = m_tab->view();
    QComboBox *const selector = m_browser->voicegroupSelector();
    auto *const quick =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    auto *const headers =
        view.findChild<songview::TrackHeaderModel *>(QStringLiteral("trackHeaderModel"));
    QQuickItem *const root = quick ? quick->rootObject() : nullptr;
    auto *const input = root ? root->findChild<songview::TimelineInputItem *>(
                                   QStringLiteral("timelineTrackHeadersInput"))
                             : nullptr;
    int otherTrack = -1;
    const MidiTimeline *const timeline = view.timeline();
    for (int track = 0; timeline && track < 16 && otherTrack < 0; ++track) {
        if (track != view.selectionModel().primaryTrack() && timeline->tracks[track].used)
            otherTrack = track;
    }
    QVERIFY(selector && selector->lineEdit());
    QVERIFY(quick && headers && input);
    QVERIFY(input->width() > 0.0 && input->height() > 0.0 && input->interaction() == headers);
    QVERIFY(otherTrack >= 0);
    const int otherRow = rowForTrack(*headers, otherTrack);
    QVERIFY(otherRow >= 0);
    QLineEdit *const edit = selector->lineEdit();
    edit->setFocus();
    QCoreApplication::processEvents();
    QVERIFY(edit->hasFocus());
    edit->setText(other);
    edit->setModified(true);
    const QPointF point = trackHeaderPoint(*headers, *input, otherRow);
    QVERIFY(input->bounds().contains(point));
    QPointer<songview::TrackHeaderModel> retainedModel(headers);
    QPointer<songview::TimelineInputItem> retainedInput(input);
    QPointer<songview::TimelineQuickView> retainedQuick(quick);
    events::sendMouse(*input, QEvent::MouseButtonPress, point, Qt::LeftButton, Qt::LeftButton,
                      Qt::NoModifier);
    QVERIFY(!retainedInput.isNull());
    QVERIFY(!retainedModel.isNull());
    QCOMPARE(view.selectionModel().primaryTrack(), otherTrack);
    QCOMPARE(m_document->cfg().voicegroupArg, other);
    events::sendMouse(*retainedInput, QEvent::MouseButtonRelease, point, Qt::LeftButton,
                      Qt::NoButton, Qt::NoModifier);
    QVERIFY2(settle([this, &other] {
                 return m_document->cfg().voicegroupArg == other && m_tab->voicegroupId() &&
                        *m_tab->voicegroupId() != *m_homeId;
             }),
             "mid-press -G commit did not complete voicegroup binding");
    QVERIFY(!retainedQuick.isNull());
    QVERIFY(!retainedModel.isNull());
    QQuickItem *const rebuiltRoot = retainedQuick->rootObject();
    auto *const rebuiltInput = rebuiltRoot ? rebuiltRoot->findChild<songview::TimelineInputItem *>(
                                                 QStringLiteral("timelineTrackHeadersInput"))
                                           : nullptr;
    const int rebuiltRow = rowForTrack(*retainedModel, m_track);
    QVERIFY(rebuiltInput && rebuiltInput->interaction() == retainedModel);
    QVERIFY(rebuiltInput->width() > 0.0 && rebuiltInput->height() > 0.0 && rebuiltRow >= 0);
    const QPointF next = trackHeaderPoint(*retainedModel, *rebuiltInput, rebuiltRow);
    QVERIFY(rebuiltInput->bounds().contains(next));
    events::sendMouse(*rebuiltInput, QEvent::MouseButtonPress, next, Qt::LeftButton, Qt::LeftButton,
                      Qt::NoModifier);
    events::sendMouse(*rebuiltInput, QEvent::MouseButtonRelease, next, Qt::LeftButton, Qt::NoButton,
                      Qt::NoModifier);
    QCOMPARE(view.selectionModel().primaryTrack(), m_track);

    requestUndo();
    QVERIFY2(waitForVoicegroup(m_homeArg, *m_homeId),
             "mid-press -G undo did not restore home binding");
}

void VoicegroupSaveTest::newVoicegroupCreatesAndAssignsUndoably()
{
    const QString name = QStringLiteral("vgsavecheck_created");
    bool intercepted = false;
    QString interceptionError;
    QTimer::singleShot(0, m_window.get(), [this, &intercepted, &interceptionError, name] {
        const QList<QDialog *> dialogs = m_window->findChildren<QDialog *>();
        QList<QDialog *> visible;
        for (QDialog *const dialog : dialogs) {
            if (dialog->isVisible())
                visible.append(dialog);
        }
        if (visible.size() != 1) {
            interceptionError = QStringLiteral("expected exactly one New Voicegroup dialog");
            for (QDialog *const dialog : visible)
                dialog->reject();
            return;
        }
        QDialog *const dialog = visible.constFirst();
        auto *const form = dialog->findChild<QFormLayout *>();
        auto *const edit = dialog->findChild<QLineEdit *>();
        auto *const source = dialog->findChild<QComboBox *>();
        auto *const buttons = dialog->findChild<QDialogButtonBox *>();
        QPushButton *const accept = buttons ? buttons->button(QDialogButtonBox::Ok) : nullptr;
        QPushButton *const cancel = buttons ? buttons->button(QDialogButtonBox::Cancel) : nullptr;
        if (!form || !edit || !source || !buttons || !accept || !cancel) {
            interceptionError =
                QStringLiteral("New Voicegroup dialog lacks its structural form controls");
            dialog->reject();
            return;
        }
        auto *const sourceLabel = qobject_cast<QLabel *>(form->labelForField(source));
        int nameRow = -1;
        int sourceRow = -1;
        int buttonsRow = -1;
        QFormLayout::ItemRole nameRole = QFormLayout::LabelRole;
        QFormLayout::ItemRole sourceRole = QFormLayout::LabelRole;
        QFormLayout::ItemRole buttonsRole = QFormLayout::LabelRole;
        form->getWidgetPosition(edit, &nameRow, &nameRole);
        form->getWidgetPosition(source, &sourceRow, &sourceRole);
        form->getWidgetPosition(buttons, &buttonsRow, &buttonsRole);
        if (!sourceLabel || !sourceLabel->isVisible() || nameRow < 0 || sourceRow < 0 ||
            buttonsRow < 0 || nameRole != QFormLayout::FieldRole ||
            sourceRole != QFormLayout::FieldRole || buttonsRole != QFormLayout::SpanningRole ||
            !(nameRow < sourceRow && sourceRow < buttonsRow) || !edit->isVisible() ||
            !source->isVisible() || !buttons->isVisible() || !accept->isVisible() ||
            !cancel->isVisible()) {
            interceptionError =
                QStringLiteral("New Voicegroup dialog form is not structurally usable");
            dialog->reject();
            return;
        }
        const QString sourceArg = source->itemData(0).toString();
        if (sourceArg.isEmpty()) {
            interceptionError = QStringLiteral("New Voicegroup dialog has no copy source");
            dialog->reject();
            return;
        }
        source->setCurrentIndex(0);
        edit->setText(name);
        if (!edit->hasAcceptableInput()) {
            interceptionError = QStringLiteral("New Voicegroup dialog rejects valid fixture name");
            dialog->reject();
            return;
        }
        intercepted = true;
        accept->click();
    });
    m_window->m_workspace->runCreateVoicegroupFlow();
    QVERIFY2(interceptionError.isEmpty(), qPrintable(interceptionError));
    QVERIFY(intercepted);
    const QString createdArg = QStringLiteral("_") + name;
    const QString createdPath =
        m_project->root() + QStringLiteral("/sound/voicegroups/") + name + QStringLiteral(".inc");
    QVERIFY2(settle([this, &createdArg, &createdPath, &name] {
                 return m_document->cfg().voicegroupArg == createdArg &&
                        QFile::exists(createdPath) && m_tab->voicegroupId() &&
                        m_tab->voicegroupId()->sourceRelativePath().endsWith(
                            name + QStringLiteral(".inc"));
             }),
             "New Voicegroup did not create and bind the source");
    QVERIFY(m_document->isDirty());
    requestUndo();
    QVERIFY2(waitForVoicegroup(m_homeArg, *m_homeId),
             "New Voicegroup undo did not restore home binding");
    QVERIFY2(settle([this] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return bank && bank->loadName == m_loadName;
             }),
             "New Voicegroup undo did not restore the original loaded bank");
}

} // namespace checks
