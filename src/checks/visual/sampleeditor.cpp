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
#include "checks/visual/visualfixture.h"

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

#include <memory>
#include <utility>

namespace {

// Forces the production null audio backend for the duration of an audition
// scenario so engine-enabled controls render their enabled state without a
// real device.
//
// shared-harness candidate: any suite that renders engine-gated chrome wants
// this scope guard.
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

// A named production control, typed at the call site: QObject::findChild with
// the QStringLiteral boilerplate folded away. Null when absent, so scenarios
// QVERIFY the controls they dereference.
template <typename T>
T *child(QWidget &root, const char *objectName)
{
    return root.findChild<T *>(QString::fromLatin1(objectName));
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
            const checks::visual::Region region = checks::visual::childRegion(name, root, *label);
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
        const checks::visual::Region region =
            checks::visual::childRegion(name, root, *matches.at(i));
        if (!region.bounds.isEmpty()) {
            regions.append(region);
            ++painted;
        }
    }
    return painted;
}

// Geometry these regions mirror in WaveformView::paintEvent
// (src/ui/waveformview.cpp) — the exact lines are cited so a change there is
// traceable to the baselines it invalidates:
//   :340  const int gy = loop ? h - 8 : 0;
//   :341  p.fillRect(QRect(leftGrip ? hx : hx - 6, gy, 7, 8), c);
//   :354  p.setPen(QPen(QColor(0xE8, 0x50, 0x50), 1));   (marker, full height)
//   :365  const QRect inset(r.width() - 236, 6, 228, 56);
namespace wavegeom {

// Handle grips: 7x8, bottom-anchored for the loop handles (:340), drawn 6px
// left of the marker line for right-hand grips (:341).
constexpr int kGripWidth = 7;
constexpr int kGripHeight = 8;
constexpr int kGripLeftOffset = 6;
// Every handle also paints a 1px full-height marker line (:354).
constexpr int kMarkerWidth = 1;
// The seam overlay inset at the top-right of the waveform (:365).
constexpr int kSeamInsetWidth = 228;
constexpr int kSeamInsetHeight = 56;
constexpr int kSeamInsetFromRight = 236;
constexpr int kSeamInsetTop = 6;

} // namespace wavegeom

// Semantic subregions inside the sample editor: the waveform surface, its
// painted handle glyphs, the seam inset, the splitter, and the named control
// rows. This is the legacy pin set shared by the dialog-vanilla/dialog-dark
// baselines recorded before the state matrix existed — do not widen it, or
// those fixtures' region sets stop matching.
bool sampleEditorRegions(SampleEditorDialog &dialog, QList<checks::visual::Region> &regions)
{
    WaveformView *wave = dialog.waveform();
    if (!wave)
        return false;
    if (!checks::visual::appendRequiredRegion(regions, QStringLiteral("waveform"), dialog, wave))
        return false;
    const QRect waveBounds =
        checks::visual::childRegion(QStringLiteral("waveform"), dialog, *wave).bounds;
    const auto handle = [&dialog, wave, waveBounds](const QString &name, WaveformView::Handle h) {
        const int hx = wave->mapTo(&dialog, wave->handlePoint(h)).x();
        const int waveTop = waveBounds.top();
        const int waveH = wave->height();
        const bool loop = h == WaveformView::LoopStartHandle || h == WaveformView::LoopEndHandle;
        const bool leftGrip =
            h == WaveformView::CropStartHandle || h == WaveformView::LoopStartHandle;
        const int gy = loop ? waveTop + waveH - wavegeom::kGripHeight : waveTop;
        const QRect grip(leftGrip ? hx : hx - wavegeom::kGripLeftOffset, gy, wavegeom::kGripWidth,
                         wavegeom::kGripHeight);
        const QRect marker(hx, waveTop, wavegeom::kMarkerWidth, waveH);
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
    // The seam overlay inset (waveformview.cpp:365) in root coordinates,
    // clipped to the wave's painted bounds.
    const QPoint seamOrigin =
        waveBounds.topLeft() +
        QPoint(wave->width() - wavegeom::kSeamInsetFromRight, wavegeom::kSeamInsetTop);
    const QRect seamInset(seamOrigin, QSize(wavegeom::kSeamInsetWidth, wavegeom::kSeamInsetHeight));
    regions.append({QStringLiteral("waveform.seam"), seamInset & waveBounds});

    const auto required = [&regions, &dialog](const char *name, QWidget *child) {
        if (checks::visual::appendRequiredRegion(regions, QString::fromLatin1(name), dialog, child))
            return true;
        qWarning("sample-editor regions: required pin '%s' failed", name);
        return false;
    };
    if (!required("splitter", dialog.findChild<QSplitter *>(QStringLiteral("sampleSplit"))) ||
        !required("button-box", dialog.findChild<QDialogButtonBox *>()))
        return false;
    for (const char *name : {"sampleNameEdit", "sampleLoopOn", "sampleLoopBody", "sampleSeamBadge",
                             "sampleBaseKey", "sampleAuditionPlay", "sampleRateCombo",
                             "sampleFineTune", "sampleNormalizeMode", "sampleAddButton"})
        if (!checks::visual::appendNamedRegion(regions, QString::fromLatin1(name), dialog,
                                               QString::fromLatin1(name))) {
            qWarning("sample-editor regions: named pin '%s' failed", name);
            return false;
        }
    return true;
}

// One pin in the state-matrix region set: a form-row caption, a form-row
// field, or an unnamed standalone label matched by exact text.
struct RegionPin {
    enum Kind { RowLabel, RowField, Label };

    const char *name;
    const char *text;
    Kind kind;
};

// Applies one pin, naming it in the warning when a caption or field is
// missing — those are required chrome, while standalone labels are matched by
// text and contribute only what paints.
bool appendPin(QList<checks::visual::Region> &regions, QWidget &root, QWidget &container,
               const RegionPin &pin)
{
    const QString name = QString::fromLatin1(pin.name);
    const QString text = QString::fromLatin1(pin.text);
    bool resolved = true;
    switch (pin.kind) {
    case RegionPin::RowLabel:
        resolved = appendRowLabelRegion(regions, name, root, container, text);
        break;
    case RegionPin::RowField:
        resolved = checks::visual::appendFieldRegion(regions, name, root, container, text);
        break;
    case RegionPin::Label:
        appendLabelRegions(regions, name, root, container, text);
        break;
    }
    if (!resolved)
        qWarning("sample-editor regions: pin '%s' failed", pin.name);
    return resolved;
}

// The full pin set for the state-matrix scenarios: the legacy regions plus
// the unnamed text chrome (form-row captions, separator labels) and the
// Advanced section's rows when expanded. Conditional chrome contributes
// only while painted, so each state's region set itself records which
// chrome exists — a port that renders the loop frame for a one-shot fails
// on the region set before pixels are compared. The tables below are the
// contract: a dropped row breaks the pin named in the warning.
bool sampleEditorFullRegions(SampleEditorDialog &dialog, QList<checks::visual::Region> &regions)
{
    if (!sampleEditorRegions(dialog, regions))
        return false;
    static constexpr RegionPin kDialogPins[] = {
        {"row-label.name", "Name:", RegionPin::RowLabel},
        {"row-label.source", "Source:", RegionPin::RowLabel},
        {"row-field.source", "Source:", RegionPin::RowField},
        {"row-label.base-key", "Base key:", RegionPin::RowLabel},
        {"row-label.rate", "Target rate (Hz):", RegionPin::RowLabel},
        {"audition.key-label", "Key:", RegionPin::Label},
    };
    for (const RegionPin &pin : kDialogPins)
        if (!appendPin(regions, dialog, dialog, pin))
            return false;
    // The splitter handle is unnamed chrome: pin its band explicitly so its
    // thickness and position are frozen bounds, not just incidental pixels
    // inside the splitter region.
    if (auto *split = dialog.findChild<QSplitter *>(QStringLiteral("sampleSplit")))
        if (!checks::visual::appendRequiredRegion(regions, QStringLiteral("splitter.handle"),
                                                  dialog, split->handle(1))) {
            qWarning("sample-editor regions: pin 'splitter.handle' failed");
            return false;
        }
    if (QWidget *loopBody = dialog.findChild<QWidget *>(QStringLiteral("sampleLoopBody"))) {
        static constexpr RegionPin kLoopPins[] = {
            {"loop.range-label", "Loop range (samples):", RegionPin::Label},
            {"loop.range-to", "to", RegionPin::Label},
        };
        for (const RegionPin &pin : kLoopPins)
            appendPin(regions, dialog, *loopBody, pin);
    }
    if (QWidget *advanced = dialog.findChild<QWidget *>(QStringLiteral("sampleAdvancedBody"));
        advanced && advanced->isVisible()) {
        static constexpr RegionPin kAdvancedPins[] = {
            {"advanced.format-label", "Format:", RegionPin::RowLabel},
            {"advanced.format", "Format:", RegionPin::RowField},
            {"advanced.crop-label", "Crop (samples):", RegionPin::RowLabel},
            {"advanced.tune-label", "Fine tune:", RegionPin::RowLabel},
            {"advanced.normalize-label", "Normalize:", RegionPin::RowLabel},
            {"advanced.crop-to", "to", RegionPin::Label},
        };
        for (const RegionPin &pin : kAdvancedPins)
            if (!appendPin(regions, dialog, *advanced, pin))
                return false;
    }
    return true;
}

ImportedSample importFixture(const QByteArray &wav, const QString &path)
{
    ImportedSample sample;
    QString error;
    if (!importAudioBytes(wav, path, &sample, &error))
        qFatal("sample editor visual fixture failed to import: %s", qPrintable(error));
    return sample;
}

// The two WAV fixtures this suite freezes. Byte payload and import path are
// paired only here: importAudioBytes derives the sample name from the path,
// and every baseline renders that name row.
enum class Fixture { Prepared, HiRes };

const char *fixturePath(Fixture fixture)
{
    return fixture == Fixture::HiRes ? "fix/hires_tone.wav" : "fix/prepared_tone.wav";
}

QByteArray fixtureWav(Fixture fixture)
{
    return fixture == Fixture::HiRes ? samplecheck::hiResSampleWav()
                                     : samplecheck::preparedSampleWav();
}

// Every scenario's canonical dialog: theme applied, fixture imported, and the
// geometry the baselines were recorded at. `validator` is the only per-scenario
// constructor input (nameInvalid refuses names); engine/destAdsr drive the
// audition strip.
std::unique_ptr<SampleEditorDialog> makeDialog(const themes::Theme &theme, Fixture fixture,
                                               SampleEditorDialog::NameValidator validator,
                                               AudioEngine *engine = nullptr,
                                               const AuditionSlots::Adsr *destAdsr = nullptr)
{
    themes::apply(*qApp, theme);
    auto dialog = std::make_unique<SampleEditorDialog>(
        importFixture(fixtureWav(fixture), QString::fromLatin1(fixturePath(fixture))),
        std::move(validator), engine, destAdsr);
    dialog->setFixedSize(900, 640);
    return dialog;
}

// The permissive validator: every scenario but nameInvalid registers the
// fixture under a fresh name, so the commit path is always live.
bool acceptCommit(const QString &, QString *)
{
    return true;
}

std::unique_ptr<SampleEditorDialog> makeDialog(const themes::Theme &theme, Fixture fixture)
{
    return makeDialog(theme, fixture, acceptCommit);
}

// Which pin set a scenario freezes. Legacy is exactly the dialog-vanilla and
// dialog-dark chrome recorded before the state matrix existed — those two
// fixtures' region sets must not widen. Every other scenario freezes the full
// state-matrix set.
enum class PinSet { Legacy, Full };

// Shows the dialog when a scenario has not shown it yet, pins the scenario's
// regions, and compares against the frozen baseline. Scenarios that interact
// with the *shown* dialog — scrolling, popups, hover, a deliberately pinned
// focus — settle it with showSettled() themselves first; re-settling here
// would park focus over the state they just established.
void checkShown(const QString &id, SampleEditorDialog &dialog, PinSet pins,
                const QList<checks::visual::Region> &extra = {})
{
    if (!dialog.isVisible())
        checks::visual::showSettled(dialog);
    QList<checks::visual::Region> regions;
    QVERIFY2(pins == PinSet::Legacy ? sampleEditorRegions(dialog, regions)
                                    : sampleEditorFullRegions(dialog, regions),
             "sample editor widgets not found");
    regions.append(extra);
    checks::visual::compareShown(id, dialog, regions);
}

// The loop checkbox is the switch that raises the loop chrome, the seam badge
// and the loop frame — the state most of these baselines exist to freeze.
void setLoopEnabled(SampleEditorDialog &dialog, bool on)
{
    auto *loopOn = child<QCheckBox>(dialog, "sampleLoopOn");
    QVERIFY(loopOn);
    loopOn->setChecked(on);
}

// Opens the Advanced disclosure: the expert rows plus the technical readout.
void openAdvanced(SampleEditorDialog &dialog)
{
    auto *toggle = child<QToolButton>(dialog, "sampleAdvancedToggle");
    QVERIFY(toggle);
    toggle->setChecked(true);
}

// The pattern behind the seam-clean and suggest-status scenarios: re-enabling
// the loop on a zeroed range makes the dialog seed the analyzer's best
// candidate.
void seedLoopSuggestion(SampleEditorDialog &dialog)
{
    auto *loopOn = child<QCheckBox>(dialog, "sampleLoopOn");
    auto *loopStart = child<QSpinBox>(dialog, "sampleLoopStart");
    auto *loopEnd = child<QSpinBox>(dialog, "sampleLoopEnd");
    QVERIFY(loopOn && loopStart && loopEnd);
    loopOn->setChecked(false);
    loopEnd->setValue(0);
    loopStart->setValue(0);
    loopOn->setChecked(true);
}

// Shows the dialog settled, then scrolls the control column to its bottom: the
// expanded Advanced body overflows the column, and its rows only paint — and
// therefore only pin — once the column has laid out and scrolled.
void scrollControlColumnToBottom(SampleEditorDialog &dialog)
{
    checks::visual::showSettled(dialog);
    auto *scroll = child<QScrollArea>(dialog, "sampleScroll");
    QVERIFY(scroll);
    scroll->verticalScrollBar()->setValue(scroll->verticalScrollBar()->maximum());
    QApplication::processEvents();
    checks::visual::parkFocus(dialog);
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
    auto dialog = makeDialog(themes::vanilla(), Fixture::Prepared);
    setLoopEnabled(*dialog, true); // deterministic loop chrome + seam badge
    checkShown(QStringLiteral("sample-editor/dialog-vanilla"), *dialog, PinSet::Legacy);
}

void VisualSampleEditorTest::dialogDark()
{
    auto dialog = makeDialog(themes::darkNeutralHigh(), Fixture::Prepared);
    setLoopEnabled(*dialog, true);
    checkShown(QStringLiteral("sample-editor/dialog-darkneutralhigh"), *dialog, PinSet::Legacy);
}

void VisualSampleEditorTest::oneShotVanilla()
{
    auto dialog = makeDialog(themes::vanilla(), Fixture::Prepared);
    auto *loopBody = child<QWidget>(*dialog, "sampleLoopBody");
    auto *badge = child<QLabel>(*dialog, "sampleSeamBadge");
    QVERIFY(loopBody && badge);
    setLoopEnabled(*dialog, false); // one-shot: the loop frame disappears entirely
    checkShown(QStringLiteral("sample-editor/oneshot-vanilla"), *dialog, PinSet::Full);
    QVERIFY2(!loopBody->isVisible() && !badge->isVisible(),
             "one-shot hides the loop chrome and seam badge");
}

void VisualSampleEditorTest::oneShotDark()
{
    auto dialog = makeDialog(themes::darkNeutralHigh(), Fixture::Prepared);
    setLoopEnabled(*dialog, false);
    checkShown(QStringLiteral("sample-editor/oneshot-darkneutralhigh"), *dialog, PinSet::Full);
}

void VisualSampleEditorTest::seamWarning()
{
    auto dialog = makeDialog(themes::vanilla(), Fixture::HiRes);
    auto *loopStart = child<QSpinBox>(*dialog, "sampleLoopStart");
    auto *loopEnd = child<QSpinBox>(*dialog, "sampleLoopEnd");
    auto *badge = child<QLabel>(*dialog, "sampleSeamBadge");
    QVERIFY(loopStart && loopEnd && badge);
    // A deliberately misaligned loop: deterministic non-clean seam metrics,
    // so the badge shows its amber or red band instead of green.
    loopStart->setValue(2000);
    loopEnd->setValue(2137);
    checkShown(QStringLiteral("sample-editor/seam-warning-vanilla"), *dialog, PinSet::Full);
    QVERIFY2(badge->isVisible() && badge->text() != QStringLiteral("seam: clean"),
             "misaligned loop exposes a non-clean seam badge");
}

void VisualSampleEditorTest::seamFair()
{
    auto dialog = makeDialog(themes::vanilla(), Fixture::HiRes);
    auto *loopStart = child<QSpinBox>(*dialog, "sampleLoopStart");
    auto *loopEnd = child<QSpinBox>(*dialog, "sampleLoopEnd");
    auto *badge = child<QLabel>(*dialog, "sampleSeamBadge");
    QVERIFY(loopStart && loopEnd && badge);
    // The badge is a three-band control (green clean / amber fair / red
    // click); this offset pair lands in the amber band (amp 3, deriv 3 LSB),
    // pinned by text so the band is identifiable, not just "not green".
    loopStart->setValue(1914);
    loopEnd->setValue(2310);
    checkShown(QStringLiteral("sample-editor/seam-fair-vanilla"), *dialog, PinSet::Full);
    QCOMPARE(badge->text(), QStringLiteral("seam: fair"));
}

void VisualSampleEditorTest::seamClean()
{
    auto dialog = makeDialog(themes::vanilla(), Fixture::HiRes);
    auto *badge = child<QLabel>(*dialog, "sampleSeamBadge");
    auto *status = child<QLabel>(*dialog, "sampleSuggestStatus");
    QVERIFY(badge && status);
    // Re-enabling on a zeroed loop seeds the analyzer's best candidate —
    // deterministic clean seam on this fixture (editor.cpp asserts the
    // same metrics) — plus the "loop 1 of N" suggest status.
    seedLoopSuggestion(*dialog);
    checkShown(QStringLiteral("sample-editor/seam-clean-vanilla"), *dialog, PinSet::Full);
    QVERIFY2(badge->isVisible() && badge->text() == QStringLiteral("seam: clean"),
             "auto-populated loop exposes the green seam badge");
    QVERIFY2(status->text().startsWith(QStringLiteral("loop ")),
             "suggest status names the applied candidate");
}

void VisualSampleEditorTest::seamCleanDark()
{
    auto dialog = makeDialog(themes::darkNeutralHigh(), Fixture::HiRes);
    seedLoopSuggestion(*dialog);
    checkShown(QStringLiteral("sample-editor/seam-clean-darkneutralhigh"), *dialog, PinSet::Full);
}

void VisualSampleEditorTest::crossfadeOn()
{
    auto dialog = makeDialog(themes::vanilla(), Fixture::HiRes);
    auto *loopStart = child<QSpinBox>(*dialog, "sampleLoopStart");
    auto *loopEnd = child<QSpinBox>(*dialog, "sampleLoopEnd");
    auto *crossfade = child<QCheckBox>(*dialog, "sampleCrossfade");
    QVERIFY(loopStart && loopEnd && crossfade);
    // Misaligned loop + crossfade bake: the seam inset traces visibly
    // reshape (editor.cpp asserts the windows differ).
    loopStart->setValue(2000);
    loopEnd->setValue(2137);
    crossfade->setChecked(true);
    checkShown(QStringLiteral("sample-editor/crossfade-vanilla"), *dialog, PinSet::Full);
    QVERIFY2(crossfade->isChecked() && dialog->document()->params().crossfadeOn,
             "crossfade bake is on");
}

void VisualSampleEditorTest::crossfadeOnDark()
{
    auto dialog = makeDialog(themes::darkNeutralHigh(), Fixture::HiRes);
    auto *loopStart = child<QSpinBox>(*dialog, "sampleLoopStart");
    auto *loopEnd = child<QSpinBox>(*dialog, "sampleLoopEnd");
    auto *crossfade = child<QCheckBox>(*dialog, "sampleCrossfade");
    QVERIFY(loopStart && loopEnd && crossfade);
    loopStart->setValue(2000);
    loopEnd->setValue(2137);
    crossfade->setChecked(true);
    checkShown(QStringLiteral("sample-editor/crossfade-darkneutralhigh"), *dialog, PinSet::Full);
}

void VisualSampleEditorTest::pitchHint()
{
    auto dialog = makeDialog(themes::vanilla(), Fixture::HiRes);
    auto *pitchApply = child<QPushButton>(*dialog, "samplePitchApply");
    QVERIFY(pitchApply);
    checkShown(QStringLiteral("sample-editor/pitch-hint-vanilla"), *dialog, PinSet::Full);
    // The fixture's smpl metadata disagrees with the detected pitch, so the
    // quiet-agreement chrome shows its one-click adopt button.
    QVERIFY2(pitchApply->isVisible(), "metadata/detection mismatch exposes the adopt button");
}

void VisualSampleEditorTest::advancedVanilla()
{
    auto dialog = makeDialog(themes::vanilla(), Fixture::Prepared);
    auto *body = child<QWidget>(*dialog, "sampleAdvancedBody");
    QVERIFY(body);
    setLoopEnabled(*dialog, true);
    openAdvanced(*dialog); // disclosure open: expert rows + tech readout
    scrollControlColumnToBottom(*dialog);
    QVERIFY2(body->isVisible(), "expanded disclosure shows the expert rows");
    checkShown(QStringLiteral("sample-editor/advanced-vanilla"), *dialog, PinSet::Full);
}

void VisualSampleEditorTest::advancedDark()
{
    auto dialog = makeDialog(themes::darkNeutralHigh(), Fixture::Prepared);
    setLoopEnabled(*dialog, true);
    openAdvanced(*dialog);
    scrollControlColumnToBottom(*dialog);
    checkShown(QStringLiteral("sample-editor/advanced-darkneutralhigh"), *dialog, PinSet::Full);
}

void VisualSampleEditorTest::advancedCropped()
{
    auto dialog = makeDialog(themes::vanilla(), Fixture::Prepared);
    auto *cropEnd = child<QSpinBox>(*dialog, "sampleCropEnd");
    QVERIFY(cropEnd);
    setLoopEnabled(*dialog, true);
    openAdvanced(*dialog);
    // A non-zero crop exercises the dimmed outside-crop overlay on the
    // waveform — never drawn in the default full-range state.
    cropEnd->setValue(32);
    scrollControlColumnToBottom(*dialog);
    checkShown(QStringLiteral("sample-editor/advanced-cropped-vanilla"), *dialog, PinSet::Full);
}

void VisualSampleEditorTest::suggestStatus()
{
    auto dialog = makeDialog(themes::vanilla(), Fixture::HiRes);
    auto *tryLoop = child<QPushButton>(*dialog, "sampleTryLoop");
    auto *status = child<QLabel>(*dialog, "sampleSuggestStatus");
    QVERIFY(tryLoop && status);
    seedLoopSuggestion(*dialog);
    checks::visual::showSettled(*dialog);
    QVERIFY2(status->text().startsWith(QStringLiteral("loop ")),
             "suggest status names the applied candidate");
    // Cycle to the next candidate so the "loop 2 of N" text is pinned too.
    tryLoop->click();
    QApplication::processEvents();
    checks::visual::parkFocus(*dialog);
    checkShown(QStringLiteral("sample-editor/suggest-status-vanilla"), *dialog, PinSet::Full);
}

void VisualSampleEditorTest::nameInvalid()
{
    auto dialog =
        makeDialog(themes::vanilla(), Fixture::Prepared, [](const QString &, QString *error) {
            *error = QStringLiteral("a sample with this name is already registered");
            return false;
        });
    auto *addButton = child<QPushButton>(*dialog, "sampleAddButton");
    auto *status = child<QLabel>(*dialog, "sampleNameStatus");
    QVERIFY(addButton && status);
    checkShown(QStringLiteral("sample-editor/name-invalid-vanilla"), *dialog, PinSet::Full);
    QVERIFY2(!addButton->isEnabled() && !status->text().isEmpty(),
             "rejected name disables the commit and shows the refusal");
}

void VisualSampleEditorTest::editTarget()
{
    auto dialog = makeDialog(themes::vanilla(), Fixture::Prepared);
    auto *nameEdit = child<QLineEdit>(*dialog, "sampleNameEdit");
    auto *addButton = child<QPushButton>(*dialog, "sampleAddButton");
    QVERIFY(nameEdit && addButton);
    dialog->setEditTarget(QStringLiteral("prepared_tone"));
    checkShown(QStringLiteral("sample-editor/edit-target-vanilla"), *dialog, PinSet::Full);
    QVERIFY2(nameEdit->isReadOnly() && addButton->text() == QStringLiteral("Save Sample"),
             "edit-target mode fixes the name and renames the commit");
}

void VisualSampleEditorTest::auditionStrip()
{
    ScopedNullAudioBackend nullBackend;
    AudioEngine engine;
    QString audioError;
    QVERIFY2(engine.init(&audioError), qPrintable(audioError));
    const AuditionSlots::Adsr destAdsr;
    auto dialog =
        makeDialog(themes::vanilla(), Fixture::Prepared, acceptCommit, &engine, &destAdsr);
    auto *play = child<QPushButton>(*dialog, "sampleAuditionPlay");
    auto *key = child<QSpinBox>(*dialog, "sampleAuditionKey");
    auto *destAdsrBox = child<QCheckBox>(*dialog, "sampleDestAdsr");
    QVERIFY(play && key && destAdsrBox);
    checkShown(QStringLiteral("sample-editor/audition-vanilla"), *dialog, PinSet::Full);
    QVERIFY2(play->isEnabled() && key->isEnabled() && destAdsrBox->isVisible(),
             "a live engine enables the audition strip and shows the ADSR option");
    QCOMPARE(play->text(), QStringLiteral("Play"));
}

void VisualSampleEditorTest::scrolled()
{
    auto dialog = makeDialog(themes::vanilla(), Fixture::Prepared);
    auto *scroll = child<QScrollArea>(*dialog, "sampleScroll");
    QVERIFY(scroll);
    setLoopEnabled(*dialog, true);
    checks::visual::showSettled(*dialog);
    // Squeeze-then-scroll: a short window keeps the sections at their layout
    // minimums and scrolls the control column instead of squashing them.
    dialog->setFixedSize(900, 280);
    QApplication::processEvents();
    checks::visual::parkFocus(*dialog);
    QVERIFY2(scroll->verticalScrollBar()->maximum() > 0, "short window scrolls the control column");
    // Under the pinned Fusion style the bar is classically painted, not a
    // transient macOS overlay — pin its band explicitly.
    QScrollBar *bar = scroll->verticalScrollBar();
    QVERIFY2(bar->isVisibleTo(dialog.get()), "the squeezed column must show its scrollbar");
    checkShown(QStringLiteral("sample-editor/scrolled-vanilla"), *dialog, PinSet::Full,
               {{QStringLiteral("scrolled.scrollbar"),
                 QRect(bar->mapTo(dialog.get(), QPoint(0, 0)), bar->size())}});
}

void VisualSampleEditorTest::splitterMin()
{
    auto dialog = makeDialog(themes::vanilla(), Fixture::Prepared);
    auto *split = child<QSplitter>(*dialog, "sampleSplit");
    WaveformView *wave = dialog->waveform();
    QVERIFY(split && wave);
    setLoopEnabled(*dialog, true);
    checks::visual::showSettled(*dialog);
    // Waveform squeezed to its minimum height; the control column stretches.
    split->setSizes({wave->minimumSizeHint().height(), 10000});
    QApplication::processEvents();
    checks::visual::parkFocus(*dialog);
    checkShown(QStringLiteral("sample-editor/splitter-min-vanilla"), *dialog, PinSet::Full);
}

void VisualSampleEditorTest::ratePopup()
{
    auto dialog = makeDialog(themes::vanilla(), Fixture::Prepared);
    checks::visual::showSettled(*dialog);
    checks::visual::compareComboPopup(*child<QComboBox>(*dialog, "sampleRateCombo"),
                                      QStringLiteral("sample-editor/rate-popup-vanilla"));
}

void VisualSampleEditorTest::normalizePopup()
{
    auto dialog = makeDialog(themes::vanilla(), Fixture::Prepared);
    openAdvanced(*dialog);
    scrollControlColumnToBottom(*dialog);
    checks::visual::compareComboPopup(*child<QComboBox>(*dialog, "sampleNormalizeMode"),
                                      QStringLiteral("sample-editor/normalize-popup-vanilla"));
}

void VisualSampleEditorTest::normalizeOneshot()
{
    auto dialog = makeDialog(themes::vanilla(), Fixture::Prepared);
    auto *normalize = child<QComboBox>(*dialog, "sampleNormalizeMode");
    auto *gain = child<QLabel>(*dialog, "sampleGainReadout");
    QVERIFY(normalize && gain);
    setLoopEnabled(*dialog, true);
    openAdvanced(*dialog);
    // One-shot normalize applies a real gain: the readout changes and the
    // waveform trace rescales.
    normalize->setCurrentIndex(2);
    scrollControlColumnToBottom(*dialog);
    checkShown(QStringLiteral("sample-editor/normalize-oneshot-vanilla"), *dialog, PinSet::Full);
    QVERIFY2(gain->text() != QStringLiteral("gain 0.0 dB"), "normalize applies a gain");
}

void VisualSampleEditorTest::customRate()
{
    auto dialog = makeDialog(themes::vanilla(), Fixture::Prepared);
    auto *rateCombo = child<QComboBox>(*dialog, "sampleRateCombo");
    QVERIFY(rateCombo && rateCombo->lineEdit());
    setLoopEnabled(*dialog, true);
    checks::visual::showSettled(*dialog);
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
    checks::visual::parkFocus(*dialog);
    QCOMPARE(dialog->document()->params().targetRate, 8000.0);
    checkShown(QStringLiteral("sample-editor/custom-rate-vanilla"), *dialog, PinSet::Full);
}

void VisualSampleEditorTest::zoomPan()
{
    auto dialog = makeDialog(themes::vanilla(), Fixture::HiRes);
    checks::visual::showSettled(*dialog);
    WaveformView *wave = dialog->waveform();
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
    checks::visual::parkFocus(*dialog);
    checkShown(QStringLiteral("sample-editor/zoom-pan-vanilla"), *dialog, PinSet::Full);
}

void VisualSampleEditorTest::midDrag()
{
    auto dialog = makeDialog(themes::vanilla(), Fixture::HiRes);
    checks::visual::showSettled(*dialog);
    WaveformView *wave = dialog->waveform();
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
    checkShown(QStringLiteral("sample-editor/mid-drag-vanilla"), *dialog, PinSet::Full);
    // Release so the gesture does not leak into the next scenario.
    checks::events::sendMouse(*wave, QEvent::MouseButtonRelease, QPointF(to), Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
}

void VisualSampleEditorTest::playhead()
{
    auto dialog = makeDialog(themes::vanilla(), Fixture::Prepared);
    setLoopEnabled(*dialog, true);
    checks::visual::showSettled(*dialog);
    // The deterministic substitute for the audition playhead: setPlayhead is
    // public, so pin the 1px line without running the 33 ms timer.
    dialog->waveform()->setPlayhead(10);
    QApplication::processEvents();
    checkShown(QStringLiteral("sample-editor/playhead-vanilla"), *dialog, PinSet::Full);
}

void VisualSampleEditorTest::handleHover()
{
    auto dialog = makeDialog(themes::vanilla(), Fixture::Prepared);
    setLoopEnabled(*dialog, true);
    checks::visual::showSettled(*dialog);
    WaveformView *wave = dialog->waveform();
    QVERIFY(wave);
    // Hover-only move onto a loop handle: WaveformView paints the hovered
    // handle with the 2px emphasis pen — the only cue a handle is grabbable.
    // A port that renders hover identically to idle loses that cue silently.
    const QPoint handle = wave->handlePoint(WaveformView::LoopStartHandle);
    checks::events::sendMouse(*wave, QEvent::MouseMove, QPointF(handle), Qt::NoButton, Qt::NoButton,
                              Qt::NoModifier);
    QApplication::processEvents();
    checkShown(QStringLiteral("sample-editor/handle-hover-vanilla"), *dialog, PinSet::Full);
}

void VisualSampleEditorTest::loopOutOfCrop()
{
    auto dialog = makeDialog(themes::vanilla(), Fixture::Prepared);
    auto *cropStart = child<QSpinBox>(*dialog, "sampleCropStart");
    auto *loopStart = child<QSpinBox>(*dialog, "sampleLoopStart");
    auto *badge = child<QLabel>(*dialog, "sampleSeamBadge");
    auto *summary = child<QLabel>(*dialog, "sampleOutputSummary");
    QVERIFY(cropStart && loopStart && badge && summary);
    setLoopEnabled(*dialog, true);
    openAdvanced(*dialog);
    // Loop markers outside the crop: the pipeline drops the loop and warns,
    // but the loop frame stays visible and editable — the one state where
    // the surface promises an action the render does not deliver.
    cropStart->setValue(loopStart->value() + 100);
    checkShown(QStringLiteral("sample-editor/loop-out-of-crop-vanilla"), *dialog, PinSet::Full);
    QVERIFY2(!dialog->document()->processed().looped,
             "loop markers outside the crop must disable the render's loop");
    QVERIFY2(summary->text().contains(QStringLiteral("loop disabled")),
             "the summary must carry the loop-disabled warning");
    QVERIFY2(!badge->isVisibleTo(dialog.get()), "no seam badge without a rendered loop");
}

void VisualSampleEditorTest::focusedControl()
{
    auto dialog = makeDialog(themes::vanilla(), Fixture::Prepared);
    auto *loopOn = child<QCheckBox>(*dialog, "sampleLoopOn");
    QVERIFY(loopOn);
    checks::visual::showSettled(*dialog);
    // Every other baseline parks focus on Cancel; this one freezes the focus
    // indicator on a non-text control (a text field's caret blinks and would
    // make the grab nondeterministic). The offscreen platform never grants
    // real activation (activateWindow() is a no-op there), so the
    // toolkit-level active window is set directly.
    QT_WARNING_PUSH
    QT_WARNING_DISABLE_DEPRECATED
    QApplication::setActiveWindow(dialog.get());
    QT_WARNING_POP
    QApplication::processEvents();
    loopOn->setFocus(Qt::MouseFocusReason);
    QApplication::processEvents();
    QVERIFY2(QApplication::focusWidget() == loopOn,
             "the loop checkbox must hold the focus for the focus-ring pin");
    checkShown(QStringLiteral("sample-editor/focused-control-vanilla"), *dialog, PinSet::Full);
}

void VisualSampleEditorTest::controlHover()
{
    auto dialog = makeDialog(themes::vanilla(), Fixture::Prepared);
    checks::visual::showSettled(*dialog);
    // One representative control-hover row: enough to catch a port that drops
    // hover feedback wholesale, without baseline-bloating every control.
    auto *add = child<QPushButton>(*dialog, "sampleAddButton");
    QVERIFY(add);
    QVERIFY2(QTest::qWaitForWindowExposed(dialog.get(), 2000),
             "the dialog must be exposed before pointer input");
    QWindow *window = dialog->windowHandle();
    QVERIFY(window);
    const QPoint point = window->mapFromGlobal(add->mapToGlobal(add->rect().center()));
    QEnterEvent enter(point, point, window->mapToGlobal(point));
    QCoreApplication::sendEvent(window, &enter);
    QTest::mouseMove(window, point);
    QTRY_VERIFY2_WITH_TIMEOUT(add->underMouse(), "the pointer must rest on the Add button", 2000);
    checkShown(QStringLiteral("sample-editor/control-hover-vanilla"), *dialog, PinSet::Full);
}

void VisualSampleEditorTest::keepSource()
{
    auto dialog = makeDialog(themes::vanilla(), Fixture::Prepared);
    auto *rateCombo = child<QComboBox>(*dialog, "sampleRateCombo");
    QVERIFY(rateCombo);
    // The identity-rate preset: no resample, the agbp word passes through,
    // and the summary/tech-detail numbers take the other branch.
    rateCombo->setCurrentIndex(0);
    checkShown(QStringLiteral("sample-editor/keep-source-vanilla"), *dialog, PinSet::Full);
    QCOMPARE(dialog->document()->params().targetRate, dialog->document()->source().sampleRate);
}

void VisualSampleEditorTest::emptyCrop()
{
    auto dialog = makeDialog(themes::vanilla(), Fixture::Prepared);
    auto *cropStart = child<QSpinBox>(*dialog, "sampleCropStart");
    auto *cropEnd = child<QSpinBox>(*dialog, "sampleCropEnd");
    QVERIFY(cropStart && cropEnd);
    openAdvanced(*dialog);
    // The degenerate render the UI can reach: the pipeline clamps cropEnd to
    // >= cropStart, so the minimal crop is a single sample — dimmed waveform,
    // no seam inset, "17 bytes ROM".
    const int frames = int(dialog->document()->source().frameCount());
    cropStart->setValue(frames - 1);
    cropEnd->setValue(frames);
    checkShown(QStringLiteral("sample-editor/empty-crop-vanilla"), *dialog, PinSet::Full);
    QCOMPARE(dialog->document()->processed().size, quint32(1));
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
