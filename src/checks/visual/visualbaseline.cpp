#include "checks/visual/visualbaseline.h"

#include "ui/applicationstartup.h"
#include "ui/theme/themeresolver.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"

#include <algorithm>
#include <tuple>

#include <QApplication>
#include <QDir>
#include <QEvent>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMap>
#include <QPixmap>
#include <QRegion>
#include <QScreen>
#include <QSet>
#include <QTemporaryDir>
#include <QWidget>
#include <QWindow>

#ifndef PORYDAW_CHECK_SOURCE_DIR
#define PORYDAW_CHECK_SOURCE_DIR ""
#endif

namespace checks::visual {
namespace {

// Per-channel RGB tolerance for raster comparison. Flat fills must match
// essentially exactly; 2 absorbs only sub-pixel antialias resampling noise.
constexpr int kChannelTolerance = 2;
// Per-region mismatch budget: at most 0.5% of a region's pixels may exceed
// the channel tolerance, capped so a small icon or border can never vanish
// inside a large allowance. Regions under 200 device pixels get zero budget.
constexpr int kRegionBudgetDivisor = 200;
constexpr int kRegionBudgetCap = 64;
// Uncovered (outside every region) pixels get the same 0.5% budget with a
// larger cap; geometry and named regions still pin everything that matters.
constexpr int kUncoveredBudgetCap = 256;

int g_fontPx = 0;
// Requested native screen DPR (PORYDAW_VISUAL_SCREEN_DPR); 0 = unrestricted.
qreal g_requestedScreenDpr = 0;

void fail(QString *error, const QString &message)
{
    if (error)
        *error = message;
}

QString platformName()
{
#if defined(Q_OS_MACOS)
    return QStringLiteral("macos");
#elif defined(Q_OS_WIN)
    return QStringLiteral("windows");
#else
    return QStringLiteral("linux");
#endif
}

int fontPx()
{
    if (g_fontPx > 0)
        return g_fontPx;
    const auto value = qEnvironmentVariable("PORYDAW_VISUAL_FONT_PX", "12");
    return value == QStringLiteral("16") ? 16 : 12;
}

QString profileFor(const QImage &image)
{
    // Preserve the actual DPR: fractional factors (1.25) must not collide with
    // integer profiles. Integers stay "dpr1"/"dpr2"; fractions encode with '_'
    // for the decimal point, trimmed to at most three decimals ("dpr1_25").
    const auto dpr = image.devicePixelRatio();
    auto dprText = QString::number(dpr, 'f', 3);
    while (dprText.endsWith(QLatin1Char('0')))
        dprText.chop(1);
    if (dprText.endsWith(QLatin1Char('.')))
        dprText.chop(1);
    dprText.replace(QLatin1Char('.'), QLatin1Char('_'));
    return QStringLiteral("%1-dpr%2-font%3").arg(platformName(), dprText).arg(fontPx());
}

QString fixtureRoot()
{
    return QDir(QString::fromUtf8(PORYDAW_CHECK_SOURCE_DIR))
        .absoluteFilePath(QStringLiteral("src/checks/fixtures/visual"));
}

QString artifactRoot()
{
    const auto configured = qEnvironmentVariable("PORYDAW_VISUAL_ARTIFACT_DIR");
    if (!configured.isEmpty())
        return configured;
    return QDir::temp().absoluteFilePath(QStringLiteral("porydaw-visual-artifacts"));
}

bool recordingEnabled()
{
    return qEnvironmentVariable("PORYDAW_RECORD_VISUAL_BASELINES") == QStringLiteral("1");
}

/// Moves each newly shown top-level window onto the requested-DPR screen
/// before the registry's NativeCheckWindowPlacement reads availableGeometry.
/// Installed after that filter, so it runs first; transient popups keep
/// inheriting their host's screen.
class ScreenPinning final : public QObject
{
  public:
    explicit ScreenPinning(QScreen *screen, QObject *parent) : QObject(parent), m_screen(screen) {}

  protected:
    bool eventFilter(QObject *object, QEvent *event) override
    {
        if (event->type() != QEvent::Show)
            return false;
        auto *window = qobject_cast<QWindow *>(object);
        if (!window || window->parent() || window->transientParent() ||
            (window->type() != Qt::Window && window->type() != Qt::Dialog))
            return false;
        window->setScreen(m_screen);
        return false;
    }

  private:
    QScreen *m_screen;
};

QScreen *selectScreen(qreal requestedDpr)
{
    for (auto *screen : QGuiApplication::screens()) {
        if (qAbs(screen->devicePixelRatio() - requestedDpr) < 0.01)
            return screen;
    }
    return nullptr;
}

/// Validates id and regions against the image's logical-pixel space.
bool validateInput(const QString &id, const QImage &image, const QList<Region> &regions,
                   QString *error)
{
    if (id.isEmpty() || id.startsWith(QLatin1Char('/')) || id.contains(QStringLiteral(".."))) {
        fail(error, QStringLiteral("visual: invalid baseline id '%1'").arg(id));
        return false;
    }
    if (image.isNull() || image.width() <= 0 || image.height() <= 0) {
        fail(error, QStringLiteral("visual: '%1' capture is null or empty").arg(id));
        return false;
    }
    if (regions.isEmpty()) {
        fail(error, QStringLiteral("visual: '%1' declares no regions").arg(id));
        return false;
    }
    const auto logical = QRect{QPoint{0, 0}, image.deviceIndependentSize().toSize()};
    auto names = QSet<QString>{};
    for (const auto &region : regions) {
        if (region.name.isEmpty()) {
            fail(error, QStringLiteral("visual: '%1' has an unnamed region").arg(id));
            return false;
        }
        if (names.contains(region.name)) {
            fail(error, QStringLiteral("visual: '%1' duplicates region '%2'").arg(id, region.name));
            return false;
        }
        names.insert(region.name);
        if (region.bounds.isEmpty() || !logical.contains(region.bounds)) {
            fail(error, QStringLiteral("visual: '%1' region '%2' bounds %3x%4+%5+%6 are empty or "
                                       "outside the %7x%8 image")
                            .arg(id, region.name)
                            .arg(region.bounds.width())
                            .arg(region.bounds.height())
                            .arg(region.bounds.x())
                            .arg(region.bounds.y())
                            .arg(logical.width())
                            .arg(logical.height()));
            return false;
        }
    }
    return true;
}

QJsonObject regionJson(const Region &region)
{
    return QJsonObject{
        {QStringLiteral("name"), region.name},         {QStringLiteral("x"), region.bounds.x()},
        {QStringLiteral("y"), region.bounds.y()},      {QStringLiteral("w"), region.bounds.width()},
        {QStringLiteral("h"), region.bounds.height()},
    };
}

bool recordBaseline(const QString &basePath, const QString &profile, const QImage &image,
                    const QList<Region> &regions, QString *error)
{
    const auto directory = QFileInfo{basePath}.absolutePath();
    if (!QDir{}.mkpath(directory)) {
        fail(error, QStringLiteral("visual: cannot create baseline directory %1").arg(directory));
        return false;
    }
    if (!image.save(basePath + QStringLiteral(".png"))) {
        fail(error, QStringLiteral("visual: cannot write %1.png").arg(basePath));
        return false;
    }
    auto regionArray = QJsonArray{};
    for (const auto &region : regions)
        regionArray.push_back(regionJson(region));
    const auto logical = image.deviceIndependentSize();
    const auto document = QJsonDocument{QJsonObject{
        {QStringLiteral("profile"), profile},
        {QStringLiteral("image"),
         QJsonObject{
             {QStringLiteral("width"), qRound(logical.width())},
             {QStringLiteral("height"), qRound(logical.height())},
             {QStringLiteral("dpr"), image.devicePixelRatio()},
         }},
        {QStringLiteral("regions"), regionArray},
        {QStringLiteral("environment"),
         QJsonObject{
             {QStringLiteral("os"), platformName()},
             {QStringLiteral("qt"), QStringLiteral(QT_VERSION_STR)},
             {QStringLiteral("fontPx"), fontPx()},
         }},
    }};
    auto file = QFile{basePath + QStringLiteral(".json")};
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        fail(error, QStringLiteral("visual: cannot write %1.json").arg(basePath));
        return false;
    }
    file.write(document.toJson(QJsonDocument::Indented));
    return true;
}

struct Expected {
    QSize logicalSize;
    qreal dpr = 1.0;
    QList<Region> regions;
};

bool loadExpected(const QString &basePath, Expected &expected, QString *error)
{
    auto file = QFile{basePath + QStringLiteral(".json")};
    if (!file.open(QIODevice::ReadOnly)) {
        fail(error, QStringLiteral("visual: cannot read %1.json").arg(basePath));
        return false;
    }
    const auto document = QJsonDocument::fromJson(file.readAll());
    const auto root = document.object();
    const auto imageObject = root.value(QStringLiteral("image")).toObject();
    expected.logicalSize = QSize{imageObject.value(QStringLiteral("width")).toInt(),
                                 imageObject.value(QStringLiteral("height")).toInt()};
    expected.dpr = imageObject.value(QStringLiteral("dpr")).toDouble(1.0);
    for (const auto value : root.value(QStringLiteral("regions")).toArray()) {
        const auto object = value.toObject();
        expected.regions.push_back(Region{object.value(QStringLiteral("name")).toString(),
                                          QRect{object.value(QStringLiteral("x")).toInt(),
                                                object.value(QStringLiteral("y")).toInt(),
                                                object.value(QStringLiteral("w")).toInt(),
                                                object.value(QStringLiteral("h")).toInt()}});
    }
    if (expected.logicalSize.isEmpty() || expected.regions.isEmpty()) {
        fail(error, QStringLiteral("visual: %1.json is malformed").arg(basePath));
        return false;
    }
    return true;
}

/// Counts pixels whose per-channel RGB distance exceeds kChannelTolerance.
/// `deviceRect` is in device pixels; both images must share size and format
/// expectations (converted to Format_RGB32 for comparison).
qint64 mismatchedPixels(const QImage &actual, const QImage &expected, const QRect &deviceRect,
                        QImage *diff)
{
    auto mismatches = qint64{0};
    for (auto y = deviceRect.top(); y <= deviceRect.bottom(); ++y) {
        for (auto x = deviceRect.left(); x <= deviceRect.right(); ++x) {
            const auto a = actual.pixelColor(x, y);
            const auto e = expected.pixelColor(x, y);
            const auto delta = std::max(
                {qAbs(a.red() - e.red()), qAbs(a.green() - e.green()), qAbs(a.blue() - e.blue())});
            if (delta > kChannelTolerance) {
                ++mismatches;
                if (diff)
                    diff->setPixelColor(x, y, QColor{255, 0, 0});
            }
        }
    }
    return mismatches;
}

QString writeArtifacts(const QString &id, const QImage &actual, const QImage &expected,
                       const QImage &diff, const QString &summary)
{
    const auto directory =
        QDir{artifactRoot()}.absoluteFilePath(QStringLiteral("%1/%2").arg(profileFor(actual), id));
    if (!QDir{}.mkpath(directory))
        return {};
    actual.save(directory + QStringLiteral("/actual.png"));
    expected.save(directory + QStringLiteral("/expected.png"));
    diff.save(directory + QStringLiteral("/diff.png"));
    auto file = QFile{directory + QStringLiteral("/summary.txt")};
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        file.write(summary.toUtf8());
    return directory;
}

bool compareInRoot(const QString &root, const QString &profile, const QString &id,
                   const QImage &image, const QList<Region> &regions, bool allowRecording,
                   QString *error)
{
    if (!validateInput(id, image, regions, error))
        return false;
    const auto basePath = QDir{root}.absoluteFilePath(QStringLiteral("%1/%2").arg(profile, id));
    const auto jsonExists = QFileInfo::exists(basePath + QStringLiteral(".json"));
    const auto pngExists = QFileInfo::exists(basePath + QStringLiteral(".png"));
    if (!jsonExists || !pngExists) {
        if (allowRecording && recordingEnabled())
            return recordBaseline(basePath, profile, image, regions, error);
        fail(error, QStringLiteral("visual: missing baseline %1.{json,png}; record it with "
                                   "PORYDAW_RECORD_VISUAL_BASELINES=1 and review the new fixtures")
                        .arg(basePath));
        return false;
    }

    auto expected = Expected{};
    if (!loadExpected(basePath, expected, error))
        return false;
    auto expectedImage = QImage{basePath + QStringLiteral(".png")};
    if (expectedImage.isNull()) {
        fail(error, QStringLiteral("visual: cannot decode %1.png").arg(basePath));
        return false;
    }

    const auto logical = image.deviceIndependentSize().toSize();
    if (logical != expected.logicalSize) {
        fail(error, QStringLiteral("visual: '%1' logical size %2x%3 differs from baseline %4x%5")
                        .arg(id)
                        .arg(logical.width())
                        .arg(logical.height())
                        .arg(expected.logicalSize.width())
                        .arg(expected.logicalSize.height()));
        return false;
    }
    if (qAbs(image.devicePixelRatio() - expected.dpr) > 0.01) {
        fail(error, QStringLiteral("visual: '%1' DPR %2 differs from baseline %3")
                        .arg(id)
                        .arg(image.devicePixelRatio())
                        .arg(expected.dpr));
        return false;
    }

    // Frozen geometry: identical name set and exact logical bounds.
    auto expectedByName = QMap<QString, QRect>{};
    for (const auto &region : expected.regions)
        expectedByName.insert(region.name, region.bounds);
    auto actualByName = QMap<QString, QRect>{};
    for (const auto &region : regions)
        actualByName.insert(region.name, region.bounds);
    for (const auto &name : expectedByName.keys()) {
        if (!actualByName.contains(name)) {
            fail(error,
                 QStringLiteral("visual: '%1' is missing baseline region '%2'").arg(id, name));
            return false;
        }
    }
    for (const auto &name : actualByName.keys()) {
        if (!expectedByName.contains(name)) {
            fail(error, QStringLiteral("visual: '%1' adds unrecorded region '%2'").arg(id, name));
            return false;
        }
        if (actualByName.value(name) != expectedByName.value(name)) {
            const auto actual = actualByName.value(name);
            const auto frozen = expectedByName.value(name);
            fail(error, QStringLiteral("visual: '%1' region '%2' bounds %3x%4+%5+%6 differ from "
                                       "baseline %7x%8+%9+%10")
                            .arg(id, name)
                            .arg(actual.width())
                            .arg(actual.height())
                            .arg(actual.x())
                            .arg(actual.y())
                            .arg(frozen.width())
                            .arg(frozen.height())
                            .arg(frozen.x())
                            .arg(frozen.y()));
            return false;
        }
    }

    // Raster comparison in device pixels, per region with a bounded budget.
    const auto dpr = image.devicePixelRatio();
    auto actual32 = image.convertToFormat(QImage::Format_RGB32);
    auto expected32 = expectedImage.convertToFormat(QImage::Format_RGB32);
    if (actual32.size() != expected32.size()) {
        fail(error, QStringLiteral("visual: '%1' device size %2x%3 differs from baseline %4x%5")
                        .arg(id)
                        .arg(actual32.width())
                        .arg(actual32.height())
                        .arg(expected32.width())
                        .arg(expected32.height()));
        return false;
    }
    auto diff = actual32.copy();
    auto covered = QRegion{};
    auto summary = QString{};
    auto failed = false;
    for (const auto &region : regions) {
        const auto deviceRect =
            QRect{qRound(region.bounds.x() * dpr), qRound(region.bounds.y() * dpr),
                  qRound(region.bounds.width() * dpr), qRound(region.bounds.height() * dpr)}
                .intersected(actual32.rect());
        covered += QRegion{deviceRect};
        const auto mismatches = mismatchedPixels(actual32, expected32, deviceRect, &diff);
        const auto budget = qMin<qint64>(
            kRegionBudgetCap, deviceRect.width() * deviceRect.height() / kRegionBudgetDivisor);
        if (mismatches > budget) {
            failed = true;
            summary += QStringLiteral("region '%1': %2 mismatched pixels (budget %3)\n")
                           .arg(region.name)
                           .arg(mismatches)
                           .arg(budget);
        }
    }
    const auto uncovered = QRegion{actual32.rect()} - covered;
    auto uncoveredPixels = qint64{0};
    auto uncoveredMismatches = qint64{0};
    for (const auto &rect : uncovered) {
        uncoveredPixels += qint64(rect.width()) * rect.height();
        uncoveredMismatches += mismatchedPixels(actual32, expected32, rect, &diff);
    }
    const auto uncoveredBudget =
        qMin<qint64>(kUncoveredBudgetCap, uncoveredPixels / kRegionBudgetDivisor);
    if (uncoveredMismatches > uncoveredBudget) {
        failed = true;
        summary += QStringLiteral("uncovered area: %1 mismatched pixels (budget %2)\n")
                       .arg(uncoveredMismatches)
                       .arg(uncoveredBudget);
    }
    if (!failed)
        return true;
    const auto directory = writeArtifacts(id, actual32, expected32, diff, summary);
    fail(error, QStringLiteral("visual: '%1' raster mismatch under %2; artifacts in %3\n%4")
                    .arg(id, profile, directory, summary));
    return false;
}

} // namespace

void prepare(QApplication &app)
{
    const auto value = qEnvironmentVariable("PORYDAW_VISUAL_FONT_PX", "12");
    const bool applicationFont = value == QStringLiteral("application");
    if (!applicationFont && value != QStringLiteral("12") && value != QStringLiteral("16")) {
        qFatal(
            "visual: PORYDAW_VISUAL_FONT_PX must be \"application\", \"12\" or \"16\", got \"%s\"",
            qPrintable(value));
    }
    // Optional native-screen pin: PORYDAW_VISUAL_SCREEN_DPR selects a real
    // display whose devicePixelRatio matches, so captures exercise an actual
    // 1x/2x framebuffer instead of QT_SCALE_FACTOR simulation. Absent env
    // leaves screen selection to the platform. No matching screen is fatal —
    // never fall back to a different profile.
    const auto dprValue = qEnvironmentVariable("PORYDAW_VISUAL_SCREEN_DPR");
    if (!dprValue.isEmpty()) {
        bool ok = false;
        const auto requested = dprValue.toDouble(&ok);
        if (!ok || requested <= 0) {
            qFatal("visual: PORYDAW_VISUAL_SCREEN_DPR must be a positive number, got \"%s\"",
                   qPrintable(dprValue));
        }
        auto *screen = selectScreen(requested);
        if (!screen) {
            qFatal("visual: PORYDAW_VISUAL_SCREEN_DPR=%s but no connected screen has that "
                   "devicePixelRatio; connect a matching display or unset the variable",
                   qPrintable(dprValue));
        }
        g_requestedScreenDpr = requested;
        app.installEventFilter(new ScreenPinning(screen, &app));
    }
    QApplication::setStyle(QStringLiteral("fusion"));
    // Legacy suites pin a font profile. Application-font suites follow the
    // production startup path without replacing the platform's base size.
    if (!applicationFont) {
        auto font = app.font();
        font.setPixelSize(value.toInt());
        app.setFont(font);
    }
    if (!ui::initializeApplication(app))
        qFatal("visual: ui::initializeApplication failed");
    g_fontPx = *typography::baseFontPx();
    themes::apply(app, themes::vanilla());
}

bool compare(const QString &id, const QImage &image, const QList<Region> &regions, QString *error)
{
    // A requested native screen DPR must be what was actually captured —
    // never record or verify against a different profile silently.
    if (g_requestedScreenDpr > 0 && qAbs(image.devicePixelRatio() - g_requestedScreenDpr) > 0.01) {
        fail(error, QStringLiteral("visual: '%1' captured DPR %2 but PORYDAW_VISUAL_SCREEN_DPR=%3 "
                                   "was requested; the window did not land on the pinned screen")
                        .arg(id)
                        .arg(image.devicePixelRatio())
                        .arg(g_requestedScreenDpr));
        return false;
    }
    return compareInRoot(fixtureRoot(), profileFor(image), id, image, regions,
                         /*allowRecording=*/true, error);
}

bool compareWidget(const QString &id, QWidget &widget, const QList<Region> &regions, QString *error)
{
    const auto image = widget.grab().toImage();
    if (image.isNull()) {
        fail(error, QStringLiteral("visual: '%1' widget grab is null").arg(id));
        return false;
    }
    return compare(id, image, regions, error);
}

QList<Region> widgetRegions(QWidget &root)
{
    auto regions = QList<Region>{};
    const auto children = root.findChildren<QWidget *>();
    for (const auto *child : children) {
        const auto name = child->objectName();
        if (name.isEmpty() || name.startsWith(QStringLiteral("qt_")))
            continue;
        if (!child->isVisible() || child->isWindow())
            continue;
        // visibleRegion() is the child's rendered extent in its own
        // coordinates, already clipped by every ancestor viewport up to the
        // window — nominal geometry() would report scroll-clipped children at
        // full size. Map the clipped region into root coordinates and keep
        // its bounding rect; a fully clipped child contributes nothing.
        const auto visible = child->visibleRegion();
        if (visible.isEmpty())
            continue;
        auto mapped = QRegion{};
        for (const auto &rect : visible)
            mapped += QRegion{QRect{child->mapTo(&root, rect.topLeft()), rect.size()}};
        const auto bounds = mapped.boundingRect();
        if (bounds.isEmpty())
            continue;
        regions.push_back(Region{name, bounds});
    }
    std::sort(regions.begin(), regions.end(), [](const auto &a, const auto &b) {
        if (a.name != b.name)
            return a.name < b.name;
        const auto &ra = a.bounds;
        const auto &rb = b.bounds;
        return std::make_tuple(ra.y(), ra.x(), ra.width(), ra.height()) <
               std::make_tuple(rb.y(), rb.x(), rb.width(), rb.height());
    });
    return regions;
}

bool selfTest(QString *error)
{
    auto scratch = QTemporaryDir{};
    if (!scratch.isValid()) {
        fail(error, QStringLiteral("visual: selfTest cannot create scratch directory"));
        return false;
    }
    const auto profile = QStringLiteral("selftest");
    const auto id = QStringLiteral("synthetic/fill");
    const auto region = Region{QStringLiteral("fill"), QRect{0, 0, 40, 20}};

    auto baseline = QImage{40, 20, QImage::Format_RGB32};
    baseline.fill(QColor{80, 120, 160});
    if (!recordBaseline(scratch.filePath(QStringLiteral("%1/%2").arg(profile, id)), profile,
                        baseline, {region}, error))
        return false;

    // Exact replay must pass.
    if (!compareInRoot(scratch.path(), profile, id, baseline, {region},
                       /*allowRecording=*/false, error)) {
        fail(error, QStringLiteral("visual: selfTest exact replay failed: %1")
                        .arg(error ? *error : QString{}));
        return false;
    }
    const auto shifted = Region{region.name, region.bounds.adjusted(0, 0, -1, 0)};
    if (compareInRoot(scratch.path(), profile, id, baseline, {shifted},
                      /*allowRecording=*/false, nullptr)) {
        fail(error, QStringLiteral("visual: selfTest accepted a 1px bound change"));
        return false;
    }
    // A modest flat-fill color change must fail.
    auto recolored = baseline;
    recolored.fill(QColor{96, 120, 160});
    if (compareInRoot(scratch.path(), profile, id, recolored, {region},
                      /*allowRecording=*/false, nullptr)) {
        fail(error, QStringLiteral("visual: selfTest accepted a flat-fill color change"));
        return false;
    }
    // A missing baseline must fail even though recording is unavailable here.
    if (compareInRoot(scratch.path(), profile, QStringLiteral("synthetic/absent"), baseline,
                      {region}, /*allowRecording=*/false, nullptr)) {
        fail(error, QStringLiteral("visual: selfTest accepted a missing baseline"));
        return false;
    }
    return true;
}

} // namespace checks::visual
