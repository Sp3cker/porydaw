// Frozen-appearance baselines for the Sample Editor's full visual state
// matrix — the "no loss of visual specificity" contract for the QWidget→QML
// port. Every scenario shows the real SampleEditorDialog in the canonical
// check environment and compares the render against frozen geometry + PNG
// baselines (PORYDAW_RECORD_VISUAL_BASELINES=1 records for review).
//
// Port contract: baseline ids "sample-editor/*" and their region names are
// semantic, never QWidget-derived. A future QML host check must reproduce
// the same ids with identical logical-pixel bounds and pixels (grab the
// QQuickWindow the way visual/quick.cpp does). A state that exists only in
// the QWidget version — loop chrome appearing/disappearing, the seam
// badge's green/amber/red bands, the Advanced disclosure, the pitch-adopt
// button, the read-only edit-target name row, the disabled audition strip —
// is a porting regression these ids exist to catch.
//
// Deliberately unpinned: hover/drag cursors and tooltips are transient
// surfaces a grab cannot freeze; tooltip *text* belongs in the behavior
// suite, not a raster. Nothing here exec()s a modal loop or touches real
// audio output (the audition scenario uses the null backend).

#include "checks/visual/visualbaseline.h"

#include <QApplication>
#include <QByteArray>
#include <QCheckBox>
#include <QComboBox>
#include <QDialogButtonBox>
#include <QFormLayout>
#include <QLabel>
#include <QLineEdit>
#include <QListView>
#include <QPushButton>
#include <QScrollArea>
#include <QScrollBar>
#include <QSet>
#include <QSpinBox>
#include <QSplitter>
#include <QToolButton>
#include <QtTest>

#include "audio/audioengine.h"
#include "audio/sampleimport.h"
#include "checks/samplecheck/samplecheck.h"
#include "checks/support/eventsynth.h"
#include "ui/sampleeditordialog.h"
#include "ui/theme/themeresolver.h"
#include "ui/theme/themeruntime.h"
#include "ui/waveformview.h"

namespace {

// Forces the production null audio backend for the duration of an audition
// scenario so engine-enabled controls render their enabled state without a
// real device.
class ScopedNullAudioBackend final
{
  public:
    ScopedNullAudioBackend()
        : m_wasSet(qEnvironmentVariableIsSet("PORYDAW_AUDIO_BACKEND"))
        , m_previous(qgetenv("PORYDAW_AUDIO_BACKEND"))
    {
        qputenv("PORYDAW_AUDIO_BACKEND", "null");
    }

    ~ScopedNullAudioBackend()
    {
        if (m_wasSet)
            qputenv("PORYDAW_AUDIO_BACKEND", m_previous);
        else
            qunsetenv("PORYDAW_AUDIO_BACKEND");
    }

  private:
    bool m_wasSet;
    QByteArray m_previous;
};

// Rendered bounds of a child widget in root image coordinates: the widget's
// visibleRegion (already clipped by scroll areas and ancestor masks) mapped
// to root space. Empty when the widget is scrolled entirely out of view.
checks::visual::Region childRegion(const QString &name, QWidget &root, const QWidget &child)
{
    const QPoint offset = child.mapTo(&root, QPoint(0, 0));
    return {name, child.visibleRegion().boundingRect().translated(offset)};
}

// Appends the region of a named descendant; false when the widget is absent
// so the caller can QVERIFY with a useful message. A widget that exists but
// is scrolled out of its viewport contributes no region — it renders no
// pixels in the grab.
bool appendNamedRegion(QList<checks::visual::Region> &regions, const QString &name, QWidget &root,
                       const QString &objectName)
{
    const QWidget *child = root.findChild<QWidget *>(objectName);
    if (!child)
        return false;
    const checks::visual::Region region = childRegion(name, root, *child);
    if (!region.bounds.isEmpty())
        regions.append(region);
    return true;
}

// Appends a structural child's rendered region; false when the widget is
// absent or renders nothing — required chrome must fail setup, not skip.
bool appendRequiredRegion(QList<checks::visual::Region> &regions, const QString &name,
                          QWidget &root, const QWidget *child)
{
    if (!child)
        return false;
    const checks::visual::Region region = childRegion(name, root, *child);
    if (region.bounds.isEmpty())
        return false;
    regions.append(region);
    return true;
}

// Park focus on stable non-input chrome so no blinking caret lands in the
// grab. QWidget::clearFocus() only drops focus when the widget itself holds
// it — a focused descendant keeps its caret, so focus is moved to a button
// instead.
void parkFocus(QWidget &widget)
{
    QWidget *anchor = nullptr;
    if (auto *buttons = widget.findChild<QDialogButtonBox *>())
        anchor = buttons->button(QDialogButtonBox::Cancel);
    if (!anchor)
        anchor = widget.findChild<QPushButton *>();
    if (anchor && anchor->isVisible() && anchor->focusPolicy() != Qt::NoFocus)
        anchor->setFocus(Qt::OtherFocusReason);
    else if (QWidget *focused = QApplication::focusWidget())
        if (focused == &widget || widget.isAncestorOf(focused))
            focused->clearFocus();
    QApplication::processEvents();
}

// Show a top-level dialog non-modally, let layout/focus settle, then park
// focus before the grab.
void showSettled(QWidget &widget)
{
    widget.show();
    QApplication::processEvents();
    parkFocus(widget);
}

// Compare the shown widget against its frozen baseline: automatic named
// descendant regions plus the caller's semantic subregions. Semantic names
// win on collision so a scenario can re-pin a named widget under a stable
// identifier.
void compareShown(const QString &id, QWidget &widget, const QList<checks::visual::Region> &extra)
{
    QSet<QString> semanticNames;
    for (const checks::visual::Region &region : extra)
        semanticNames.insert(region.name);
    QList<checks::visual::Region> regions;
    for (const checks::visual::Region &region : checks::visual::widgetRegions(widget))
        if (!semanticNames.contains(region.name))
            regions.append(region);
    regions.append(extra);
    QString error;
    QVERIFY2(checks::visual::compareWidget(id, widget, regions, &error), qPrintable(error));
}

// Finds the field widget a QFormLayout places beside the row whose label
// reads `labelText` (mnemonic '&' stripped). Null when no row matches or the
// field is a layout rather than a widget.
QWidget *formField(QWidget &container, const QString &labelText)
{
    const QString wanted = QString(labelText).remove(QLatin1Char('&'));
    for (QFormLayout *form : container.findChildren<QFormLayout *>()) {
        for (int row = 0; row < form->rowCount(); ++row) {
            QLayoutItem *labelItem = form->itemAt(row, QFormLayout::LabelRole);
            auto *label = labelItem ? qobject_cast<QLabel *>(labelItem->widget()) : nullptr;
            if (!label || label->text().remove(QLatin1Char('&')) != wanted)
                continue;
            QLayoutItem *fieldItem = form->itemAt(row, QFormLayout::FieldRole);
            return fieldItem ? fieldItem->widget() : nullptr;
        }
    }
    return nullptr;
}

// Appends the rendered region of a form field identified by its row label.
// False only when the row or its field is absent; a field scrolled out of
// the viewport contributes no region (it renders no pixels in the grab).
bool appendFieldRegion(QList<checks::visual::Region> &regions, const QString &name, QWidget &root,
                       QWidget &container, const QString &labelText)
{
    QWidget *field = formField(container, labelText);
    if (!field)
        return false;
    const checks::visual::Region region = childRegion(name, root, *field);
    if (!region.bounds.isEmpty())
        regions.append(region);
    return true;
}

// Pins the caption QLabel of the QFormLayout row whose text reads
// `labelText`. Row captions are unnamed, so the automatic named-descendant
// enumeration never sees them; a port that drops or rewords a caption would
// otherwise pass. False only when no row matches; a caption scrolled out of
// view contributes no region.
bool appendRowLabelRegion(QList<checks::visual::Region> &regions, const QString &name,
                          QWidget &root, QWidget &container, const QString &labelText)
{
    const QString wanted = QString(labelText).remove(QLatin1Char('&'));
    for (QFormLayout *form : container.findChildren<QFormLayout *>())
        for (int row = 0; row < form->rowCount(); ++row) {
            QLayoutItem *labelItem = form->itemAt(row, QFormLayout::LabelRole);
            auto *label = labelItem ? qobject_cast<QLabel *>(labelItem->widget()) : nullptr;
            if (!label || label->text().remove(QLatin1Char('&')) != wanted)
                continue;
            const checks::visual::Region region = childRegion(name, root, *label);
            if (!region.bounds.isEmpty())
                regions.append(region);
            return true;
        }
    return false;
}

// Pins every painted QLabel in `container` whose text matches — standalone
// labels ("to", "Key:") are likewise unnamed. When several match, names get
// a 1-based ".N" suffix in document order. Returns the match count; labels
// scrolled or hidden out of view contribute nothing.
int appendLabelRegions(QList<checks::visual::Region> &regions, const QString &baseName,
                       QWidget &root, QWidget &container, const QString &text)
{
    QList<const QLabel *> matches;
    for (const QLabel *label : container.findChildren<QLabel *>())
        if (label->text() == text)
            matches.append(label);
    int painted = 0;
    for (int i = 0; i < matches.size(); ++i) {
        const QString name =
            matches.size() == 1 ? baseName : QStringLiteral("%1.%2").arg(baseName).arg(i + 1);
        const checks::visual::Region region = childRegion(name, root, *matches.at(i));
        if (!region.bounds.isEmpty()) {
            regions.append(region);
            ++painted;
        }
    }
    return painted;
}

// Semantic regions for an open QComboBox popup: the view plus one region per
// item row, clipped to the painted viewport, so row count, order, and the
// highlighted row are all frozen. The popup is a separate window — it must
// be grabbed directly; the dialog grab never sees it.
QList<checks::visual::Region> comboPopupRegions(QWidget &popup)
{
    auto regions = checks::visual::widgetRegions(popup);
    auto *view = popup.findChild<QListView *>();
    if (!view)
        return regions;
    const QRect popupBounds(QPoint(0, 0), popup.size());
    const QRect viewport =
        QRect(view->viewport()->mapTo(&popup, QPoint(0, 0)), view->viewport()->size()) &
        popupBounds;
    regions.append({QStringLiteral("popup.view"), viewport});
    for (int row = 0; row < view->model()->rowCount(); ++row) {
        const QRect rect = view->visualRect(view->model()->index(row, 0));
        if (!rect.isValid())
            continue;
        const QRect mapped =
            rect.translated(view->viewport()->mapTo(&popup, QPoint(0, 0))) & viewport;
        if (!mapped.isEmpty())
            regions.append({QStringLiteral("popup.row.%1").arg(row), mapped});
    }
    return regions;
}

// Semantic subregions inside the sample editor: the waveform surface, its
// painted handle glyphs, the seam inset, the splitter, and the named control
// rows. Geometry mirrors WaveformView::paintEvent: each handle is a 7x8 grip
// (top edge for crop, bottom edge for loop) plus a 1px full-height marker
// line, and the seam overlay is the fixed 228x56 inset at the top-right.
// This is the legacy pin set shared by the dialog-vanilla/dialog-dark
// baselines recorded before the state matrix existed — do not widen it, or
// those fixtures' region sets stop matching.
bool sampleEditorRegions(SampleEditorDialog &dialog, QList<checks::visual::Region> &regions)
{
    WaveformView *wave = dialog.waveform();
    if (!wave)
        return false;
    if (!appendRequiredRegion(regions, QStringLiteral("waveform"), dialog, wave))
        return false;
    const QRect waveBounds = childRegion(QStringLiteral("waveform"), dialog, *wave).bounds;
    const auto handle = [&dialog, wave, waveBounds](const QString &name, WaveformView::Handle h) {
        const int hx = wave->mapTo(&dialog, wave->handlePoint(h)).x();
        const int waveTop = waveBounds.top();
        const int waveH = wave->height();
        const bool loop = h == WaveformView::LoopStartHandle || h == WaveformView::LoopEndHandle;
        const bool leftGrip =
            h == WaveformView::CropStartHandle || h == WaveformView::LoopStartHandle;
        const int gy = loop ? waveTop + waveH - 8 : waveTop;
        const QRect grip(leftGrip ? hx : hx - 6, gy, 7, 8);
        const QRect marker(hx, waveTop, 1, waveH);
        return checks::visual::Region{name, (grip | marker) & waveBounds};
    };
    // Handles scrolled offscreen by zoom/pan contribute no region — a marker
    // outside the viewport renders nothing, and an empty bound would fail
    // the degenerate-region check.
    for (const auto &entry : {std::pair{"waveform.crop-start", WaveformView::CropStartHandle},
                              {"waveform.crop-end", WaveformView::CropEndHandle},
                              {"waveform.loop-start", WaveformView::LoopStartHandle},
                              {"waveform.loop-end", WaveformView::LoopEndHandle}}) {
        const checks::visual::Region region =
            handle(QString::fromLatin1(entry.first), entry.second);
        if (!region.bounds.isEmpty())
            regions.append(region);
    }
    regions.append({QStringLiteral("waveform.seam"),
                    QRect(waveBounds.topLeft() + QPoint(wave->width() - 236, 6), QSize(228, 56)) &
                        waveBounds});

    if (!appendRequiredRegion(regions, QStringLiteral("splitter"), dialog,
                              dialog.findChild<QSplitter *>(QStringLiteral("sampleSplit"))) ||
        !appendRequiredRegion(regions, QStringLiteral("button-box"), dialog,
                              dialog.findChild<QDialogButtonBox *>()))
        return false;
    for (const char *name : {"sampleNameEdit", "sampleLoopOn", "sampleLoopBody", "sampleSeamBadge",
                             "sampleBaseKey", "sampleAuditionPlay", "sampleRateCombo",
                             "sampleFineTune", "sampleNormalizeMode", "sampleAddButton"})
        if (!appendNamedRegion(regions, QString::fromLatin1(name), dialog,
                               QString::fromLatin1(name)))
            return false;
    return true;
}

// The full pin set for the state-matrix scenarios: the legacy regions plus
// the unnamed text chrome (form-row captions, separator labels) and the
// Advanced section's rows when expanded. Conditional chrome contributes
// only while painted, so each state's region set itself records which
// chrome exists — a port that renders the loop frame for a one-shot fails
// on the region set before pixels are compared.
bool sampleEditorFullRegions(SampleEditorDialog &dialog, QList<checks::visual::Region> &regions)
{
    if (!sampleEditorRegions(dialog, regions))
        return false;
    const auto pin = [](const char *name, auto &&fn) {
        const bool ok = fn();
        if (!ok)
            qWarning("sample-editor regions: pin '%s' failed", name);
        return ok;
    };
    bool ok = pin("row-label.name",
                  [&] {
                      return appendRowLabelRegion(regions, QStringLiteral("row-label.name"), dialog,
                                                  dialog, QStringLiteral("Name:"));
                  }) &&
              pin("row-label.source",
                  [&] {
                      return appendRowLabelRegion(regions, QStringLiteral("row-label.source"),
                                                  dialog, dialog, QStringLiteral("Source:"));
                  }) &&
              pin("row-field.source",
                  [&] {
                      return appendFieldRegion(regions, QStringLiteral("row-field.source"), dialog,
                                               dialog, QStringLiteral("Source:"));
                  }) &&
              pin("row-label.base-key",
                  [&] {
                      return appendRowLabelRegion(regions, QStringLiteral("row-label.base-key"),
                                                  dialog, dialog, QStringLiteral("Base key:"));
                  }) &&
              pin("row-label.rate", [&] {
                  return appendRowLabelRegion(regions, QStringLiteral("row-label.rate"), dialog,
                                              dialog, QStringLiteral("Target rate (Hz):"));
              });
    appendLabelRegions(regions, QStringLiteral("audition.key-label"), dialog, dialog,
                       QStringLiteral("Key:"));
    // The splitter handle is unnamed chrome: pin its band explicitly so its
    // thickness and position are frozen bounds, not just incidental pixels
    // inside the splitter region.
    if (auto *split = dialog.findChild<QSplitter *>(QStringLiteral("sampleSplit")))
        ok = pin("splitter.handle",
                 [&] {
                     return appendRequiredRegion(regions, QStringLiteral("splitter.handle"), dialog,
                                                 split->handle(1));
                 }) &&
             ok;
    if (QWidget *loopBody = dialog.findChild<QWidget *>(QStringLiteral("sampleLoopBody"))) {
        appendLabelRegions(regions, QStringLiteral("loop.range-label"), dialog, *loopBody,
                           QStringLiteral("Loop range (samples):"));
        appendLabelRegions(regions, QStringLiteral("loop.range-to"), dialog, *loopBody,
                           QStringLiteral("to"));
    }
    if (QWidget *advanced = dialog.findChild<QWidget *>(QStringLiteral("sampleAdvancedBody"));
        advanced && advanced->isVisible()) {
        ok =
            pin("advanced.format-label",
                [&] {
                    return appendRowLabelRegion(regions, QStringLiteral("advanced.format-label"),
                                                dialog, *advanced, QStringLiteral("Format:"));
                }) &&
            pin("advanced.format",
                [&] {
                    return appendFieldRegion(regions, QStringLiteral("advanced.format"), dialog,
                                             *advanced, QStringLiteral("Format:"));
                }) &&
            pin("advanced.crop-label",
                [&] {
                    return appendRowLabelRegion(regions, QStringLiteral("advanced.crop-label"),
                                                dialog, *advanced,
                                                QStringLiteral("Crop (samples):"));
                }) &&
            pin("advanced.tune-label",
                [&] {
                    return appendRowLabelRegion(regions, QStringLiteral("advanced.tune-label"),
                                                dialog, *advanced, QStringLiteral("Fine tune:"));
                }) &&
            pin("advanced.normalize-label",
                [&] {
                    return appendRowLabelRegion(regions, QStringLiteral("advanced.normalize-label"),
                                                dialog, *advanced, QStringLiteral("Normalize:"));
                }) &&
            ok;
        appendLabelRegions(regions, QStringLiteral("advanced.crop-to"), dialog, *advanced,
                           QStringLiteral("to"));
    }
    return ok;
}

ImportedSample importFixture(const QByteArray &wav, const QString &path)
{
    ImportedSample sample;
    QString error;
    if (!importAudioBytes(wav, path, &sample, &error))
        qFatal("sample editor visual fixture failed to import: %s", qPrintable(error));
    return sample;
}

} // namespace

class VisualSampleEditorTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(VisualSampleEditorTest)

  public:
    VisualSampleEditorTest() = default;

  private slots:
    void cleanup();

    void dialogVanilla();
    void dialogDark();
    void oneShotVanilla();
    void oneShotDark();
    void seamWarning();
    void seamFair();
    void seamClean();
    void seamCleanDark();
    void crossfadeOn();
    void crossfadeOnDark();
    void pitchHint();
    void advancedVanilla();
    void advancedDark();
    void advancedCropped();
    void suggestStatus();
    void nameInvalid();
    void editTarget();
    void auditionStrip();
    void scrolled();
    void splitterMin();
    void ratePopup();
    void normalizePopup();
    void normalizeOneshot();
    void customRate();
    void zoomPan();
    void midDrag();
    void playhead();
    void handleHover();
    void loopOutOfCrop();
    void focusedControl();
    void controlHover();
    void keepSource();
    void emptyCrop();

  private:
    QApplication *app() const;
};

QApplication *VisualSampleEditorTest::app() const
{
    return qobject_cast<QApplication *>(QCoreApplication::instance());
}

void VisualSampleEditorTest::cleanup()
{
    // Every scenario returns the app to the committed vanilla baseline so
    // theme state never leaks between tests.
    if (app())
        themes::apply(*app(), themes::vanilla());
}

void VisualSampleEditorTest::dialogVanilla()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample prepared =
        importFixture(samplecheck::preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    auto *loopOn = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
    QVERIFY(loopOn);
    loopOn->setChecked(true); // deterministic loop chrome + seam badge
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/dialog-vanilla"), dialog, regions);
}

void VisualSampleEditorTest::dialogDark()
{
    themes::apply(*app(), themes::darkNeutralHigh());
    ImportedSample prepared =
        importFixture(samplecheck::preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    auto *loopOn = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
    QVERIFY(loopOn);
    loopOn->setChecked(true);
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/dialog-darkneutralhigh"), dialog, regions);
}

void VisualSampleEditorTest::oneShotVanilla()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample prepared =
        importFixture(samplecheck::preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    auto *loopOn = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
    auto *loopBody = dialog.findChild<QWidget *>(QStringLiteral("sampleLoopBody"));
    auto *badge = dialog.findChild<QLabel *>(QStringLiteral("sampleSeamBadge"));
    QVERIFY(loopOn && loopBody && badge);
    loopOn->setChecked(false); // one-shot: the loop frame disappears entirely
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    QVERIFY2(!loopBody->isVisible() && !badge->isVisible(),
             "one-shot hides the loop chrome and seam badge");
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/oneshot-vanilla"), dialog, regions);
}

void VisualSampleEditorTest::oneShotDark()
{
    themes::apply(*app(), themes::darkNeutralHigh());
    ImportedSample prepared =
        importFixture(samplecheck::preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    auto *loopOn = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
    QVERIFY(loopOn);
    loopOn->setChecked(false);
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/oneshot-darkneutralhigh"), dialog, regions);
}

void VisualSampleEditorTest::seamWarning()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample hiRes =
        importFixture(samplecheck::hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"));
    SampleEditorDialog dialog(hiRes, [](const QString &, QString *) { return true; });
    auto *loopStart = dialog.findChild<QSpinBox *>(QStringLiteral("sampleLoopStart"));
    auto *loopEnd = dialog.findChild<QSpinBox *>(QStringLiteral("sampleLoopEnd"));
    auto *badge = dialog.findChild<QLabel *>(QStringLiteral("sampleSeamBadge"));
    QVERIFY(loopStart && loopEnd && badge);
    // A deliberately misaligned loop: deterministic non-clean seam metrics,
    // so the badge shows its amber or red band instead of green.
    loopStart->setValue(2000);
    loopEnd->setValue(2137);
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    QVERIFY2(badge->isVisible() && badge->text() != QStringLiteral("seam: clean"),
             "misaligned loop exposes a non-clean seam badge");
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/seam-warning-vanilla"), dialog, regions);
}

void VisualSampleEditorTest::seamFair()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample hiRes =
        importFixture(samplecheck::hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"));
    SampleEditorDialog dialog(hiRes, [](const QString &, QString *) { return true; });
    auto *loopStart = dialog.findChild<QSpinBox *>(QStringLiteral("sampleLoopStart"));
    auto *loopEnd = dialog.findChild<QSpinBox *>(QStringLiteral("sampleLoopEnd"));
    auto *badge = dialog.findChild<QLabel *>(QStringLiteral("sampleSeamBadge"));
    QVERIFY(loopStart && loopEnd && badge);
    // The badge is a three-band control (green clean / amber fair / red
    // click); this offset pair lands in the amber band (amp 3, deriv 3 LSB),
    // pinned by text so the band is identifiable, not just "not green".
    loopStart->setValue(1914);
    loopEnd->setValue(2310);
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    QCOMPARE(badge->text(), QStringLiteral("seam: fair"));
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/seam-fair-vanilla"), dialog, regions);
}

void VisualSampleEditorTest::pitchHint()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample hiRes =
        importFixture(samplecheck::hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"));
    SampleEditorDialog dialog(hiRes, [](const QString &, QString *) { return true; });
    auto *pitchApply = dialog.findChild<QPushButton *>(QStringLiteral("samplePitchApply"));
    QVERIFY(pitchApply);
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    // The fixture's smpl metadata disagrees with the detected pitch, so the
    // quiet-agreement chrome shows its one-click adopt button.
    QVERIFY2(pitchApply->isVisible(), "metadata/detection mismatch exposes the adopt button");
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/pitch-hint-vanilla"), dialog, regions);
}

void VisualSampleEditorTest::advancedVanilla()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample prepared =
        importFixture(samplecheck::preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    auto *loopOn = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
    auto *toggle = dialog.findChild<QToolButton *>(QStringLiteral("sampleAdvancedToggle"));
    auto *body = dialog.findChild<QWidget *>(QStringLiteral("sampleAdvancedBody"));
    QVERIFY(loopOn && toggle && body);
    loopOn->setChecked(true);
    toggle->setChecked(true); // disclosure open: expert rows + tech readout
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    QVERIFY2(body->isVisible(), "expanded disclosure shows the expert rows");
    // The expanded body overflows the control column: scroll to the bottom
    // so the expert rows actually paint before their regions are pinned.
    auto *scroll = dialog.findChild<QScrollArea *>(QStringLiteral("sampleScroll"));
    QVERIFY(scroll);
    scroll->verticalScrollBar()->setValue(scroll->verticalScrollBar()->maximum());
    QApplication::processEvents();
    parkFocus(dialog);
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/advanced-vanilla"), dialog, regions);
}

void VisualSampleEditorTest::advancedDark()
{
    themes::apply(*app(), themes::darkNeutralHigh());
    ImportedSample prepared =
        importFixture(samplecheck::preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    auto *loopOn = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
    auto *toggle = dialog.findChild<QToolButton *>(QStringLiteral("sampleAdvancedToggle"));
    QVERIFY(loopOn && toggle);
    loopOn->setChecked(true);
    toggle->setChecked(true);
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    auto *scroll = dialog.findChild<QScrollArea *>(QStringLiteral("sampleScroll"));
    QVERIFY(scroll);
    scroll->verticalScrollBar()->setValue(scroll->verticalScrollBar()->maximum());
    QApplication::processEvents();
    parkFocus(dialog);
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/advanced-darkneutralhigh"), dialog, regions);
}

void VisualSampleEditorTest::nameInvalid()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample prepared =
        importFixture(samplecheck::preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *error) {
        *error = QStringLiteral("a sample with this name is already registered");
        return false;
    });
    auto *addButton = dialog.findChild<QPushButton *>(QStringLiteral("sampleAddButton"));
    auto *status = dialog.findChild<QLabel *>(QStringLiteral("sampleNameStatus"));
    QVERIFY(addButton && status);
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    QVERIFY2(!addButton->isEnabled() && !status->text().isEmpty(),
             "rejected name disables the commit and shows the refusal");
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/name-invalid-vanilla"), dialog, regions);
}

void VisualSampleEditorTest::editTarget()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample prepared =
        importFixture(samplecheck::preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    auto *nameEdit = dialog.findChild<QLineEdit *>(QStringLiteral("sampleNameEdit"));
    auto *addButton = dialog.findChild<QPushButton *>(QStringLiteral("sampleAddButton"));
    QVERIFY(nameEdit && addButton);
    dialog.setEditTarget(QStringLiteral("prepared_tone"));
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    QVERIFY2(nameEdit->isReadOnly() && addButton->text() == QStringLiteral("Save Sample"),
             "edit-target mode fixes the name and renames the commit");
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/edit-target-vanilla"), dialog, regions);
}

void VisualSampleEditorTest::auditionStrip()
{
    themes::apply(*app(), themes::vanilla());
    ScopedNullAudioBackend nullBackend;
    AudioEngine engine;
    QString audioError;
    QVERIFY2(engine.init(&audioError), qPrintable(audioError));
    const AuditionSlots::Adsr destAdsr;
    ImportedSample prepared =
        importFixture(samplecheck::preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"));
    SampleEditorDialog dialog(
        prepared, [](const QString &, QString *) { return true; }, &engine, &destAdsr);
    auto *play = dialog.findChild<QPushButton *>(QStringLiteral("sampleAuditionPlay"));
    auto *key = dialog.findChild<QSpinBox *>(QStringLiteral("sampleAuditionKey"));
    auto *destAdsrBox = dialog.findChild<QCheckBox *>(QStringLiteral("sampleDestAdsr"));
    QVERIFY(play && key && destAdsrBox);
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    QVERIFY2(play->isEnabled() && key->isEnabled() && destAdsrBox->isVisible(),
             "a live engine enables the audition strip and shows the ADSR option");
    QCOMPARE(play->text(), QStringLiteral("Play"));
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/audition-vanilla"), dialog, regions);
}

void VisualSampleEditorTest::seamClean()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample hiRes =
        importFixture(samplecheck::hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"));
    SampleEditorDialog dialog(hiRes, [](const QString &, QString *) { return true; });
    auto *loopOn = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
    auto *loopStart = dialog.findChild<QSpinBox *>(QStringLiteral("sampleLoopStart"));
    auto *loopEnd = dialog.findChild<QSpinBox *>(QStringLiteral("sampleLoopEnd"));
    auto *badge = dialog.findChild<QLabel *>(QStringLiteral("sampleSeamBadge"));
    auto *status = dialog.findChild<QLabel *>(QStringLiteral("sampleSuggestStatus"));
    QVERIFY(loopOn && loopStart && loopEnd && badge && status);
    // Re-enabling on a zeroed loop seeds the analyzer's best candidate —
    // deterministic clean seam on this fixture (editor.cpp asserts the
    // same metrics) — plus the "loop 1 of N" suggest status.
    loopOn->setChecked(false);
    loopEnd->setValue(0);
    loopStart->setValue(0);
    loopOn->setChecked(true);
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    QVERIFY2(badge->isVisible() && badge->text() == QStringLiteral("seam: clean"),
             "auto-populated loop exposes the green seam badge");
    QVERIFY2(status->text().startsWith(QStringLiteral("loop ")),
             "suggest status names the applied candidate");
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/seam-clean-vanilla"), dialog, regions);
}

void VisualSampleEditorTest::seamCleanDark()
{
    themes::apply(*app(), themes::darkNeutralHigh());
    ImportedSample hiRes =
        importFixture(samplecheck::hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"));
    SampleEditorDialog dialog(hiRes, [](const QString &, QString *) { return true; });
    auto *loopOn = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
    auto *loopStart = dialog.findChild<QSpinBox *>(QStringLiteral("sampleLoopStart"));
    auto *loopEnd = dialog.findChild<QSpinBox *>(QStringLiteral("sampleLoopEnd"));
    QVERIFY(loopOn && loopStart && loopEnd);
    loopOn->setChecked(false);
    loopEnd->setValue(0);
    loopStart->setValue(0);
    loopOn->setChecked(true);
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/seam-clean-darkneutralhigh"), dialog, regions);
}

void VisualSampleEditorTest::crossfadeOn()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample hiRes =
        importFixture(samplecheck::hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"));
    SampleEditorDialog dialog(hiRes, [](const QString &, QString *) { return true; });
    auto *loopStart = dialog.findChild<QSpinBox *>(QStringLiteral("sampleLoopStart"));
    auto *loopEnd = dialog.findChild<QSpinBox *>(QStringLiteral("sampleLoopEnd"));
    auto *crossfade = dialog.findChild<QCheckBox *>(QStringLiteral("sampleCrossfade"));
    QVERIFY(loopStart && loopEnd && crossfade);
    // Misaligned loop + crossfade bake: the seam inset traces visibly
    // reshape (editor.cpp asserts the windows differ).
    loopStart->setValue(2000);
    loopEnd->setValue(2137);
    crossfade->setChecked(true);
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    QVERIFY2(crossfade->isChecked() && dialog.document()->params().crossfadeOn,
             "crossfade bake is on");
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/crossfade-vanilla"), dialog, regions);
}

void VisualSampleEditorTest::crossfadeOnDark()
{
    themes::apply(*app(), themes::darkNeutralHigh());
    ImportedSample hiRes =
        importFixture(samplecheck::hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"));
    SampleEditorDialog dialog(hiRes, [](const QString &, QString *) { return true; });
    auto *loopStart = dialog.findChild<QSpinBox *>(QStringLiteral("sampleLoopStart"));
    auto *loopEnd = dialog.findChild<QSpinBox *>(QStringLiteral("sampleLoopEnd"));
    auto *crossfade = dialog.findChild<QCheckBox *>(QStringLiteral("sampleCrossfade"));
    QVERIFY(loopStart && loopEnd && crossfade);
    loopStart->setValue(2000);
    loopEnd->setValue(2137);
    crossfade->setChecked(true);
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/crossfade-darkneutralhigh"), dialog, regions);
}
void VisualSampleEditorTest::scrolled()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample prepared =
        importFixture(samplecheck::preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    auto *loopOn = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
    auto *scroll = dialog.findChild<QScrollArea *>(QStringLiteral("sampleScroll"));
    QVERIFY(loopOn && scroll);
    loopOn->setChecked(true);
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    // Squeeze-then-scroll: a short window keeps the sections at their layout
    // minimums and scrolls the control column instead of squashing them.
    dialog.setFixedSize(900, 280);
    QApplication::processEvents();
    parkFocus(dialog);
    QVERIFY2(scroll->verticalScrollBar()->maximum() > 0, "short window scrolls the control column");
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    // Under the pinned Fusion style the bar is classically painted, not a
    // transient macOS overlay — pin its band explicitly.
    QScrollBar *bar = scroll->verticalScrollBar();
    QVERIFY2(bar->isVisibleTo(&dialog), "the squeezed column must show its scrollbar");
    regions.append({QStringLiteral("scrolled.scrollbar"),
                    QRect(bar->mapTo(&dialog, QPoint(0, 0)), bar->size())});
    compareShown(QStringLiteral("sample-editor/scrolled-vanilla"), dialog, regions);
}

void VisualSampleEditorTest::advancedCropped()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample prepared =
        importFixture(samplecheck::preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    auto *loopOn = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
    auto *toggle = dialog.findChild<QToolButton *>(QStringLiteral("sampleAdvancedToggle"));
    auto *cropEnd = dialog.findChild<QSpinBox *>(QStringLiteral("sampleCropEnd"));
    QVERIFY(loopOn && toggle && cropEnd);
    loopOn->setChecked(true);
    toggle->setChecked(true);
    // A non-zero crop exercises the dimmed outside-crop overlay on the
    // waveform — never drawn in the default full-range state.
    cropEnd->setValue(32);
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    auto *scroll = dialog.findChild<QScrollArea *>(QStringLiteral("sampleScroll"));
    QVERIFY(scroll);
    scroll->verticalScrollBar()->setValue(scroll->verticalScrollBar()->maximum());
    QApplication::processEvents();
    parkFocus(dialog);
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/advanced-cropped-vanilla"), dialog, regions);
}

void VisualSampleEditorTest::suggestStatus()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample hiRes =
        importFixture(samplecheck::hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"));
    SampleEditorDialog dialog(hiRes, [](const QString &, QString *) { return true; });
    auto *loopOn = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
    auto *loopStart = dialog.findChild<QSpinBox *>(QStringLiteral("sampleLoopStart"));
    auto *loopEnd = dialog.findChild<QSpinBox *>(QStringLiteral("sampleLoopEnd"));
    auto *tryLoop = dialog.findChild<QPushButton *>(QStringLiteral("sampleTryLoop"));
    auto *status = dialog.findChild<QLabel *>(QStringLiteral("sampleSuggestStatus"));
    QVERIFY(loopOn && loopStart && loopEnd && tryLoop && status);
    loopOn->setChecked(false);
    loopEnd->setValue(0);
    loopStart->setValue(0);
    loopOn->setChecked(true);
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    QVERIFY2(status->text().startsWith(QStringLiteral("loop ")),
             "suggest status names the applied candidate");
    // Cycle to the next candidate so the "loop 2 of N" text is pinned too.
    tryLoop->click();
    QApplication::processEvents();
    parkFocus(dialog);
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/suggest-status-vanilla"), dialog, regions);
}

void VisualSampleEditorTest::splitterMin()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample prepared =
        importFixture(samplecheck::preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    auto *loopOn = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
    auto *split = dialog.findChild<QSplitter *>(QStringLiteral("sampleSplit"));
    WaveformView *wave = dialog.waveform();
    QVERIFY(loopOn && split && wave);
    loopOn->setChecked(true);
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    // Waveform squeezed to its minimum height; the control column stretches.
    split->setSizes({wave->minimumSizeHint().height(), 10000});
    QApplication::processEvents();
    parkFocus(dialog);
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/splitter-min-vanilla"), dialog, regions);
}

void VisualSampleEditorTest::ratePopup()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample prepared =
        importFixture(samplecheck::preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    auto *rateCombo = dialog.findChild<QComboBox *>(QStringLiteral("sampleRateCombo"));
    QVERIFY(rateCombo);
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    rateCombo->showPopup();
    QWidget *popup = rateCombo->view()->window();
    QVERIFY(popup);
    QTRY_VERIFY_WITH_TIMEOUT(popup->isVisible(), 5000);
    QApplication::processEvents();
    if (QWidget *focused = QApplication::focusWidget())
        focused->clearFocus();
    QApplication::processEvents();
    QString error;
    QVERIFY2(checks::visual::compareWidget(QStringLiteral("sample-editor/rate-popup-vanilla"),
                                           *popup, comboPopupRegions(*popup), &error),
             qPrintable(error));
    popup->hide();
    QApplication::processEvents();
}

void VisualSampleEditorTest::normalizePopup()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample prepared =
        importFixture(samplecheck::preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    auto *toggle = dialog.findChild<QToolButton *>(QStringLiteral("sampleAdvancedToggle"));
    auto *normalize = dialog.findChild<QComboBox *>(QStringLiteral("sampleNormalizeMode"));
    QVERIFY(toggle && normalize);
    toggle->setChecked(true);
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    auto *scroll = dialog.findChild<QScrollArea *>(QStringLiteral("sampleScroll"));
    QVERIFY(scroll);
    scroll->verticalScrollBar()->setValue(scroll->verticalScrollBar()->maximum());
    QApplication::processEvents();
    normalize->showPopup();
    QWidget *popup = normalize->view()->window();
    QVERIFY(popup);
    QTRY_VERIFY_WITH_TIMEOUT(popup->isVisible(), 5000);
    QApplication::processEvents();
    if (QWidget *focused = QApplication::focusWidget())
        focused->clearFocus();
    QApplication::processEvents();
    QString error;
    QVERIFY2(checks::visual::compareWidget(QStringLiteral("sample-editor/normalize-popup-vanilla"),
                                           *popup, comboPopupRegions(*popup), &error),
             qPrintable(error));
    popup->hide();
    QApplication::processEvents();
}

void VisualSampleEditorTest::normalizeOneshot()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample prepared =
        importFixture(samplecheck::preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    auto *loopOn = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
    auto *toggle = dialog.findChild<QToolButton *>(QStringLiteral("sampleAdvancedToggle"));
    auto *normalize = dialog.findChild<QComboBox *>(QStringLiteral("sampleNormalizeMode"));
    auto *gain = dialog.findChild<QLabel *>(QStringLiteral("sampleGainReadout"));
    QVERIFY(loopOn && toggle && normalize && gain);
    loopOn->setChecked(true);
    toggle->setChecked(true);
    // One-shot normalize applies a real gain: the readout changes and the
    // waveform trace rescales.
    normalize->setCurrentIndex(2);
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    auto *scroll = dialog.findChild<QScrollArea *>(QStringLiteral("sampleScroll"));
    QVERIFY(scroll);
    scroll->verticalScrollBar()->setValue(scroll->verticalScrollBar()->maximum());
    QApplication::processEvents();
    parkFocus(dialog);
    QVERIFY2(gain->text() != QStringLiteral("gain 0.0 dB"), "normalize applies a gain");
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/normalize-oneshot-vanilla"), dialog, regions);
}

void VisualSampleEditorTest::customRate()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample prepared =
        importFixture(samplecheck::preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    auto *loopOn = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
    auto *rateCombo = dialog.findChild<QComboBox *>(QStringLiteral("sampleRateCombo"));
    QVERIFY(loopOn && rateCombo && rateCombo->lineEdit());
    loopOn->setChecked(true);
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    // A typed rate commits on editingFinished (preset pick, Enter, focus-out).
    // QTest key events don't move real focus, and Return would also reach the
    // dialog's default button and accept it — deliver the focus-out commit
    // directly.
    QLineEdit *rateEdit = rateCombo->lineEdit();
    rateEdit->selectAll();
    QTest::keyClicks(rateEdit, QStringLiteral("8000"));
    QFocusEvent focusOut(QEvent::FocusOut, Qt::OtherFocusReason);
    QApplication::sendEvent(rateEdit, &focusOut);
    QApplication::processEvents();
    parkFocus(dialog);
    QCOMPARE(dialog.document()->params().targetRate, 8000.0);
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/custom-rate-vanilla"), dialog, regions);
}

void VisualSampleEditorTest::zoomPan()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample hiRes =
        importFixture(samplecheck::hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"));
    SampleEditorDialog dialog(hiRes, [](const QString &, QString *) { return true; });
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    WaveformView *wave = dialog.waveform();
    QVERIFY(wave);
    // Zoom in with the wheel, then pan left: the view leaves fit-to-width.
    const QPointF center(wave->width() / 2.0, wave->height() / 2.0);
    checks::events::sendWheel(*wave, center, QPoint(0, 0), QPoint(0, 240), Qt::NoButton,
                              Qt::NoModifier, Qt::NoScrollPhase, false);
    QApplication::processEvents();
    checks::events::sendMouse(*wave, QEvent::MouseButtonPress, center, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*wave, QEvent::MouseMove, center + QPointF(-60, 0), Qt::NoButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*wave, QEvent::MouseButtonRelease, center + QPointF(-60, 0),
                              Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    QApplication::processEvents();
    parkFocus(dialog);
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/zoom-pan-vanilla"), dialog, regions);
}

void VisualSampleEditorTest::midDrag()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample hiRes =
        importFixture(samplecheck::hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"));
    SampleEditorDialog dialog(hiRes, [](const QString &, QString *) { return true; });
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    WaveformView *wave = dialog.waveform();
    QVERIFY(wave);
    // Press on the loop-start handle and drag without releasing: the marker
    // draws with the 2px emphasis pen and the render updates live.
    const QPoint from = wave->handlePoint(WaveformView::LoopStartHandle);
    const QPoint to(wave->xForSample(3000), from.y());
    checks::events::sendMouse(*wave, QEvent::MouseButtonPress, QPointF(from), Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*wave, QEvent::MouseMove, QPointF((from + to) / 2), Qt::NoButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*wave, QEvent::MouseMove, QPointF(to), Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    QApplication::processEvents();
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/mid-drag-vanilla"), dialog, regions);
    // Release so the gesture does not leak into the next scenario.
    checks::events::sendMouse(*wave, QEvent::MouseButtonRelease, QPointF(to), Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
}

void VisualSampleEditorTest::playhead()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample prepared =
        importFixture(samplecheck::preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    auto *loopOn = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
    QVERIFY(loopOn);
    loopOn->setChecked(true);
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    // The deterministic substitute for the audition playhead: setPlayhead is
    // public, so pin the 1px line without running the 33 ms timer.
    dialog.waveform()->setPlayhead(10);
    QApplication::processEvents();
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/playhead-vanilla"), dialog, regions);
}

void VisualSampleEditorTest::handleHover()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample prepared =
        importFixture(samplecheck::preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    auto *loopOn = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
    QVERIFY(loopOn);
    loopOn->setChecked(true);
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    WaveformView *wave = dialog.waveform();
    QVERIFY(wave);
    // Hover-only move onto a loop handle: WaveformView paints the hovered
    // handle with the 2px emphasis pen — the only cue a handle is grabbable.
    // A port that renders hover identically to idle loses that cue silently.
    const QPoint handle = wave->handlePoint(WaveformView::LoopStartHandle);
    checks::events::sendMouse(*wave, QEvent::MouseMove, QPointF(handle), Qt::NoButton, Qt::NoButton,
                              Qt::NoModifier);
    QApplication::processEvents();
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/handle-hover-vanilla"), dialog, regions);
}

void VisualSampleEditorTest::loopOutOfCrop()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample prepared =
        importFixture(samplecheck::preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    auto *loopOn = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
    auto *advanced = dialog.findChild<QToolButton *>(QStringLiteral("sampleAdvancedToggle"));
    QVERIFY(loopOn && advanced);
    loopOn->setChecked(true);
    advanced->setChecked(true);
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    auto *cropStart = dialog.findChild<QSpinBox *>(QStringLiteral("sampleCropStart"));
    auto *loopStart = dialog.findChild<QSpinBox *>(QStringLiteral("sampleLoopStart"));
    auto *badge = dialog.findChild<QLabel *>(QStringLiteral("sampleSeamBadge"));
    auto *summary = dialog.findChild<QLabel *>(QStringLiteral("sampleOutputSummary"));
    QVERIFY(cropStart && loopStart && badge && summary);
    // Loop markers outside the crop: the pipeline drops the loop and warns,
    // but the loop frame stays visible and editable — the one state where
    // the surface promises an action the render does not deliver.
    cropStart->setValue(loopStart->value() + 100);
    QApplication::processEvents();
    QVERIFY2(!dialog.document()->processed().looped,
             "loop markers outside the crop must disable the render's loop");
    QVERIFY2(summary->text().contains(QStringLiteral("loop disabled")),
             "the summary must carry the loop-disabled warning");
    QVERIFY2(!badge->isVisibleTo(&dialog), "no seam badge without a rendered loop");
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/loop-out-of-crop-vanilla"), dialog, regions);
}

void VisualSampleEditorTest::focusedControl()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample prepared =
        importFixture(samplecheck::preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    // Every other baseline parks focus on Cancel; this one freezes the focus
    // indicator on a non-text control (a text field's caret blinks and would
    // make the grab nondeterministic). The offscreen platform never grants
    // real activation (activateWindow() is a no-op there), so the
    // toolkit-level active window is set directly.
    auto *loopOn = dialog.findChild<QCheckBox *>(QStringLiteral("sampleLoopOn"));
    QVERIFY(loopOn);
    QT_WARNING_PUSH
    QT_WARNING_DISABLE_DEPRECATED
    QApplication::setActiveWindow(&dialog);
    QT_WARNING_POP
    QApplication::processEvents();
    loopOn->setFocus(Qt::MouseFocusReason);
    QApplication::processEvents();
    QVERIFY2(QApplication::focusWidget() == loopOn,
             "the loop checkbox must hold the focus for the focus-ring pin");
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/focused-control-vanilla"), dialog, regions);
}

void VisualSampleEditorTest::controlHover()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample prepared =
        importFixture(samplecheck::preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    // One representative control-hover row: enough to catch a port that drops
    // hover feedback wholesale, without baseline-bloating every control.
    auto *add = dialog.findChild<QPushButton *>(QStringLiteral("sampleAddButton"));
    QVERIFY(add);
    QVERIFY2(QTest::qWaitForWindowExposed(&dialog, 2000),
             "the dialog must be exposed before pointer input");
    QWindow *window = dialog.windowHandle();
    QVERIFY(window);
    const QPoint point = window->mapFromGlobal(add->mapToGlobal(add->rect().center()));
    QEnterEvent enter(point, point, window->mapToGlobal(point));
    QCoreApplication::sendEvent(window, &enter);
    QTest::mouseMove(window, point);
    QTRY_VERIFY2_WITH_TIMEOUT(add->underMouse(), "the pointer must rest on the Add button", 2000);
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/control-hover-vanilla"), dialog, regions);
}

void VisualSampleEditorTest::keepSource()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample prepared =
        importFixture(samplecheck::preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    auto *rateCombo = dialog.findChild<QComboBox *>(QStringLiteral("sampleRateCombo"));
    QVERIFY(rateCombo);
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    // The identity-rate preset: no resample, the agbp word passes through,
    // and the summary/tech-detail numbers take the other branch.
    rateCombo->setCurrentIndex(0);
    QApplication::processEvents();
    QCOMPARE(dialog.document()->params().targetRate, dialog.document()->source().sampleRate);
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/keep-source-vanilla"), dialog, regions);
}

void VisualSampleEditorTest::emptyCrop()
{
    themes::apply(*app(), themes::vanilla());
    ImportedSample prepared =
        importFixture(samplecheck::preparedSampleWav(), QStringLiteral("fix/prepared_tone.wav"));
    SampleEditorDialog dialog(prepared, [](const QString &, QString *) { return true; });
    auto *advanced = dialog.findChild<QToolButton *>(QStringLiteral("sampleAdvancedToggle"));
    QVERIFY(advanced);
    advanced->setChecked(true);
    dialog.setFixedSize(900, 640);
    showSettled(dialog);
    auto *cropStart = dialog.findChild<QSpinBox *>(QStringLiteral("sampleCropStart"));
    auto *cropEnd = dialog.findChild<QSpinBox *>(QStringLiteral("sampleCropEnd"));
    // The degenerate render the UI can reach: the pipeline clamps cropEnd to
    // >= cropStart, so the minimal crop is a single sample — dimmed waveform,
    // no seam inset, "17 bytes ROM".
    const int frames = int(dialog.document()->source().frameCount());
    cropStart->setValue(frames - 1);
    cropEnd->setValue(frames);
    QApplication::processEvents();
    QCOMPARE(dialog.document()->processed().size, quint32(1));
    QList<checks::visual::Region> regions;
    QVERIFY2(sampleEditorFullRegions(dialog, regions), "sample editor widgets not found");
    compareShown(QStringLiteral("sample-editor/empty-crop-vanilla"), dialog, regions);
}

int runVisualSampleEditorCheck(QApplication &application, const QStringList &qtArguments)
{
    checks::visual::prepare(application); // canonical style, font, theme, app init
    VisualSampleEditorTest test;
    QStringList arguments{QStringLiteral("visual-sampleeditor")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "sampleeditor.moc"
