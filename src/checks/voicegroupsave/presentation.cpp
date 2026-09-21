#include "checks/voicegroupsave/tst_voicegroupsave.h"

#include <QComboBox>
#include <QCoreApplication>
#include <QDialog>
#include <QDialogButtonBox>
#include <QDir>
#include <QFile>
#include <QFormLayout>
#include <QHeaderView>
#include <QImage>
#include <QLabel>
#include <QLineEdit>
#include <QPointer>
#include <QPushButton>
#include <QQuickItem>
#include <QTimer>
#include <QToolButton>
#include <QTreeWidget>
#include <QtTest>

#include <algorithm>
#include <array>

#include "checks/support/eventsynth.h"
#include "checks/support/songfixture.h"
#include "checks/support/voicegroupbrowserdriver.h"
#include "core/songdocument.h"
#include "mainwindow.h"
#include "ui/layout.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/trackheadermodel.h"
#include "ui/voicegroupbrowser.h"
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

void VoicegroupSaveTest::typeColumnMapsEveryFamily()
{
    auto *browser = m_window->findChild<VoicegroupBrowser *>();
    QVERIFY(browser);
    auto *tree = browser->findChild<QTreeWidget *>();
    QVERIFY(tree);
    QVERIFY(tree->columnWidth(1) >= tree->header()->sectionSizeHint(1));
    QVERIFY(tree->columnWidth(1) >=
            tree->iconSize().width() + 2 * layout::space(layout::Space::Two));
    // The Type column is icon-only: every family publishes its name through
    // the column-1 tooltip and accessible text, and its glyph through the
    // icon. fixture_rich covers the plain families plus keysplit, drumkit,
    // and a read-only cry line; the alt chips live in fixture_alt.
    const LoadedBankView *const home = m_browser->selectedBankView();
    QVERIFY(home);
    const struct {
        int slot;
        const char *type;
    } expected[] = {{0, "Sample"},
                    {1, "Sample"},
                    {2, "Sample (fixed pitch)"},
                    {3, "Sample (reverse)"},
                    {4, "Square 1"},
                    {5, "Square 2"},
                    {6, "Wave"},
                    {7, "Noise"},
                    {8, "Keysplit"},
                    {9, "Keysplit"},
                    {10, "Drumkit"},
                    {11, "Drumkit"},
                    {12, "Sample"}}; // cry renders as a sample
    for (const auto &row : expected) {
        QCOMPARE(m_browser->slotRowType(row.slot), QLatin1String(row.type));
        QCOMPARE(m_browser->slotRowAccessibleType(row.slot), QLatin1String(row.type));
        QVERIFY2(m_browser->hasTypeIcon(row.slot),
                 qPrintable(QStringLiteral("slot %1 lost its type icon").arg(row.slot)));
        const QStringList text = m_browser->slotRowText(row.slot);
        QCOMPARE(text.size(), 3);
        QVERIFY2(
            text.at(1).isEmpty(),
            qPrintable(QStringLiteral("slot %1 leaked text into the icon column").arg(row.slot)));
    }
    const int blank = firstBlankSlot();
    QVERIFY2(blank >= 0, "fixture must provide a blank slot for the no-type contract");
    QVERIFY(!m_browser->hasTypeIcon(blank));
    QVERIFY(m_browser->slotRowType(blank).isEmpty());
    QVERIFY(m_browser->slotRowAccessibleType(blank).isEmpty());

    // Distinct families carry distinct glyphs; cry shares the plain sample
    // waveform, and the reverse sample is the same waveform rotated 180°.
    const std::array<int, 8> glyphSlots = {0, 3, 4, 5, 6, 7, 8, 10};
    for (size_t i = 0; i < glyphSlots.size(); ++i) {
        const QImage a = m_browser->slotTypeIcon(glyphSlots.at(i));
        QVERIFY(!a.isNull());
        for (size_t j = i + 1; j < glyphSlots.size(); ++j)
            QVERIFY2(a != m_browser->slotTypeIcon(glyphSlots.at(j)),
                     qPrintable(QStringLiteral("slots %1 and %2 share a type glyph")
                                    .arg(glyphSlots.at(i))
                                    .arg(glyphSlots.at(j))));
    }
    QCOMPARE(m_browser->slotTypeIcon(12), m_browser->slotTypeIcon(0));

    // A synth voice is memory-only until save: mint the definition the way
    // synthDefinitionsStayMemoryOnlyUntilSave does, then adopt the type.
    const QString synthPath =
        m_project->root() + QStringLiteral("/sound/direct_sound_synth_data.inc");
    const QString macroDir = m_project->root() + QStringLiteral("/asm/macros");
    QVERIFY(QDir().mkpath(macroDir));
    {
        QFile macros(macroDir + QStringLiteral("/vgtypecheck_synth.inc"));
        QVERIFY(macros.open(QIODevice::WriteOnly));
        QCOMPARE(macros.write("\t.macro set_synth_pulse base_duty=0x80, duty_step=0x00, "
                              "mod_depth=0x00, duty_phase=0x00\n\t.endm\n") > 0,
                 true);
    }
    {
        QFile data(synthPath);
        QVERIFY(data.open(QIODevice::WriteOnly | QIODevice::Append));
        QCOMPARE(data.write("\n\t.align 2\nVgTypeCheckPulse::\n\tset_synth_pulse\n") > 0, true);
    }
    QVERIFY2(refreshCatalog(), "synth catalog refresh did not settle");
    QVERIFY2(settle([this] {
                 return m_window->m_workspace->projectState().catalog.synths.find(
                            QStringLiteral("VgTypeCheckPulse")) != nullptr;
             }),
             "synth definition did not reach the published catalog");
    const int synthSlot = firstSynthableSlot();
    QVERIFY2(synthSlot >= 0, "fixture must provide a non-synth DirectSound voice");
    const QString originalSymbol =
        m_browser->selectedBankView()->slotViews.at(synthSlot).voice->symbol;
    m_browser->selectSlot(synthSlot);
    QVERIFY(m_browser->hasSynthEditorControls());
    QVERIFY(m_browser->activateSynthType());
    QVERIFY2(settle([this, synthSlot, &originalSymbol] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return bank && bank->slotViews.at(synthSlot).voice &&
                        bank->slotViews.at(synthSlot).voice->symbol != originalSymbol;
             }),
             "synth type did not create a memory-only tone");
    QVERIFY(m_browser->activateSynthWave(0));
    QVERIFY2(settle([this, synthSlot] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return bank && bank->slotViews.at(synthSlot).voice &&
                        m_browser->slotRowType(synthSlot) == QStringLiteral("Synth (Golden Sun)");
             }),
             "synth adoption did not publish the Synth (Golden Sun) type");
    QCOMPARE(m_browser->slotRowAccessibleType(synthSlot), QStringLiteral("Synth (Golden Sun)"));
    QVERIFY(m_browser->hasTypeIcon(synthSlot));
    QCOMPARE(m_browser->slotTypeIcon(synthSlot), m_browser->slotTypeIcon(0));

    // The alt-chip families live in fixture_alt: same family names, grey-chip
    // glyphs that must differ from the plain chip of the same family.
    QString altArg;
    for (const QString &arg : m_window->m_workspace->projectState().catalog.groupArgs) {
        if (arg == m_homeArg)
            continue;
        const VoicegroupId previous = *m_tab->voicegroupId();
        SongCfg cfg = m_document->cfg();
        cfg.voicegroupArg = arg;
        m_document->setCfg(cfg);
        if (!settle([this, &previous] {
                return m_tab->voicegroupId() && *m_tab->voicegroupId() != previous;
            }))
            continue;
        if (m_tab->voicegroupId()->sourceRelativePath().endsWith(
                QStringLiteral("fixture_alt.inc"))) {
            altArg = arg;
            break;
        }
    }
    QVERIFY2(!altArg.isEmpty(),
             "catalog must offer the fixture_alt voicegroup for alt-chip coverage");
    QVERIFY2(settle([this] {
                 const LoadedBankView *const bank = m_browser->selectedBankView();
                 return bank && bank->slotViews.at(2).voice &&
                        bank->slotViews.at(2).voice->macro == VgMacro::Square1Alt;
             }),
             "fixture_alt bank view did not publish its alt voices");
    const struct {
        int slot;
        const char *type;
        int plainSlot;
    } altExpected[] = {{2, "Square 1 (Alt)", 4},
                       {3, "Square 2 (Alt)", 5},
                       {4, "Wave (Alt)", 6},
                       {5, "Noise (Alt)", 7}};
    for (const auto &row : altExpected) {
        QCOMPARE(m_browser->slotRowType(row.slot), QLatin1String(row.type));
        QCOMPARE(m_browser->slotRowAccessibleType(row.slot), QLatin1String(row.type));
        QVERIFY2(m_browser->hasTypeIcon(row.slot),
                 qPrintable(QStringLiteral("alt slot %1 lost its type icon").arg(row.slot)));
        QVERIFY2(m_browser->slotTypeIcon(row.slot) != m_browser->slotTypeIcon(row.plainSlot),
                 qPrintable(QStringLiteral("slot %1 lost its alt chip").arg(row.slot)));
    }
    const int altBlank = firstBlankSlot();
    QVERIFY2(altBlank >= 0, "fixture_alt must provide a blank slot");
    QVERIFY(!m_browser->hasTypeIcon(altBlank));
    QVERIFY(m_browser->slotRowType(altBlank).isEmpty());
    QVERIFY(m_browser->slotRowAccessibleType(altBlank).isEmpty());
}

void VoicegroupSaveTest::treePressHoldAuditions()
{
    auto *browser = m_window->findChild<VoicegroupBrowser *>();
    QVERIFY(browser);
    auto *tree = browser->findChild<QTreeWidget *>();
    QVERIFY(tree);
    m_window->show();
    m_window->activateWindow();
    QCoreApplication::processEvents();

    QTreeWidgetItem *const first = tree->topLevelItem(m_dsSlot);
    QVERIFY(first);
    const QPoint firstPos = tree->visualItemRect(first).center();
    QVERIFY2(!firstPos.isNull(), "first slot row has no visible rect");

    QSignalSpy spy(browser, &VoicegroupBrowser::auditionVoice);
    QTest::mousePress(tree->viewport(), Qt::LeftButton, Qt::NoModifier, firstPos);
    QCOMPARE(spy.size(), 1);
    QCOMPARE(spy.at(0).at(0).toInt(), m_dsSlot);
    QCOMPARE(spy.at(0).at(1).toInt(), 60);
    QCOMPARE(spy.at(0).at(2).toInt(), 112);

    // Pressing a second row while the first is held releases it first, then
    // starts the new voice — the note never overlaps.
    const int other = m_dsSlot == 0 ? 1 : 0;
    QTreeWidgetItem *const second = tree->topLevelItem(other);
    QVERIFY(second);
    const QPoint secondPos = tree->visualItemRect(second).center();
    QVERIFY2(!secondPos.isNull(), "second slot row has no visible rect");
    QTest::mousePress(tree->viewport(), Qt::LeftButton, Qt::NoModifier, secondPos);
    QCOMPARE(spy.size(), 3);
    QCOMPARE(spy.at(1).at(0).toInt(), m_dsSlot);
    QCOMPARE(spy.at(1).at(2).toInt(), 0);
    QCOMPARE(spy.at(2).at(0).toInt(), other);
    QCOMPARE(spy.at(2).at(2).toInt(), 112);

    QTest::mouseRelease(tree->viewport(), Qt::LeftButton, Qt::NoModifier, secondPos);
    QCOMPARE(spy.size(), 4);
    QCOMPARE(spy.at(3).at(0).toInt(), other);
    QCOMPARE(spy.at(3).at(2).toInt(), 0);
}

void VoicegroupSaveTest::sampleButtonsEmitRequests()
{
    auto *browser = m_window->findChild<VoicegroupBrowser *>();
    QVERIFY(browser);
    m_window->show();
    m_window->activateWindow();
    QCoreApplication::processEvents();
    m_browser->selectSlot(m_dsSlot);
    QVERIFY2(m_browser->hasSamplePickerEditor(),
             "DirectSound slot did not surface the sample picker editor");

    auto *const newButton = browser->findChild<QToolButton *>(QStringLiteral("vgNewSampleButton"));
    auto *const editButton =
        browser->findChild<QToolButton *>(QStringLiteral("vgEditSampleButton"));
    QVERIFY(newButton && editButton);
    QVERIFY2(newButton->isVisible() && editButton->isVisible(),
             "sample action buttons are not visible for the DirectSound slot");

    QSignalSpy newSpy(browser, &VoicegroupBrowser::newSampleRequested);
    QSignalSpy editSpy(browser, &VoicegroupBrowser::editSampleRequested);
    QTest::mouseClick(newButton, Qt::LeftButton);
    QCOMPARE(newSpy.size(), 1);
    QCOMPARE(newSpy.at(0).at(0).toInt(), m_dsSlot);
    QTest::mouseClick(editButton, Qt::LeftButton);
    QCOMPARE(editSpy.size(), 1);
    QCOMPARE(editSpy.at(0).at(0).toInt(), m_dsSlot);
}

void VoicegroupSaveTest::selectorChangeRequestsArg()
{
    const QString other = otherVoicegroupArg();
    QVERIFY2(m_window->m_workspace->projectState().catalog.groupArgs.size() >= 2 &&
                 !other.isEmpty(),
             "required staged voicegroups missing: >=2 groupArgs via sound/voice_groups.inc and "
             "sound/voicegroups/fixture_alt.inc");
    auto *browser = m_window->findChild<VoicegroupBrowser *>();
    QVERIFY(browser);
    QComboBox *const selector = m_browser->voicegroupSelector();
    QVERIFY(selector);

    QSignalSpy spy(browser, &VoicegroupBrowser::voicegroupChangeRequested);
    selector->setCurrentText(SongRegistry::voicegroupDisplayName(other));
    QVERIFY(QMetaObject::invokeMethod(selector, "activated", Qt::DirectConnection,
                                      Q_ARG(int, selector->currentIndex())));
    QCOMPARE(spy.size(), 1);
    QCOMPARE(spy.at(0).at(0).toString(), other);
    QVERIFY2(settle([this, &other] {
                 return m_document->cfg().voicegroupArg == other && m_tab->voicegroupId() &&
                        *m_tab->voicegroupId() != *m_homeId;
             }),
             "selector request did not rebind the voicegroup");
    requestUndo();
    QVERIFY2(waitForVoicegroup(m_homeArg, *m_homeId), "selector undo did not restore home binding");
}

} // namespace checks
