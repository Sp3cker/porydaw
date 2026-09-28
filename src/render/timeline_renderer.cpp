#include "timeline_renderer.h"

#include "ui/songview/quick/swiftroll/native/font_metrics.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <utility>

#include <QtCore/qmetaobject.h>

using RollProjection::Rect;

namespace {

const QString &velocityText(int velocity)
{
    static const std::array<QString, 128> texts = [] {
        std::array<QString, 128> table;
        for (int i = 0; i < 128; ++i)
            table[size_t(i)] = QString::number(i);
        return table;
    }();
    return texts[size_t(std::clamp(velocity, 0, 127))];
}

const QString &pitchName(int pitch)
{
    static const std::array<QString, 128> names = [] {
        std::array<QString, 128> table;
        for (int i = 0; i < 128; ++i)
            table[size_t(i)] = RollProjection::keyName(i);
        return table;
    }();
    return names[size_t(std::clamp(pitch, 0, 127))];
}

} // namespace

TimelineRenderer::TimelineRenderer(QQuickItem *parent) : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
}

TimelineRenderer::~TimelineRenderer()
{
    clearFontCaches();
}

void TimelineRenderer::sceneChanged()
{
    m_sceneDirty = true;
    polish();
    update();
}

void TimelineRenderer::setBand(int band)
{
    if (m_bandRole == band)
        return;
    m_bandRole = band;
    emit bandChanged();
    sceneChanged();
}

void TimelineRenderer::setContentSource(QObject *source)
{
    if (m_contentSource == source)
        return;
    m_contentSource = source;
    m_contentDirty = true;
    emit contentSourceChanged();
    sceneChanged();
}

void TimelineRenderer::setContentRevision(int revision)
{
    if (m_contentRevision == revision)
        return;
    m_contentRevision = revision;
    m_contentDirty = true;
    emit contentRevisionChanged();
    sceneChanged();
}

void TimelineRenderer::setPixelsPerTick(double v)
{
    if (m_camera.pixelsPerTick == v)
        return;
    m_camera.pixelsPerTick = v;
    emit pixelsPerTickChanged();
    sceneChanged();
}

void TimelineRenderer::setKeyHeight(double v)
{
    if (m_camera.keyHeight == v)
        return;
    m_camera.keyHeight = v;
    emit keyHeightChanged();
    sceneChanged();
}

void TimelineRenderer::setScrollX(double v)
{
    if (m_camera.scrollX == v)
        return;
    m_camera.scrollX = v;
    emit scrollXChanged();
    sceneChanged();
}

void TimelineRenderer::setScrollY(double v)
{
    if (m_camera.scrollY == v)
        return;
    m_camera.scrollY = v;
    emit scrollYChanged();
    sceneChanged();
}

void TimelineRenderer::setDevicePixelRatio(double v)
{
    if (m_camera.dpr == v)
        return;
    m_camera.dpr = v;
    emit devicePixelRatioChanged();
    sceneChanged();
}

void TimelineRenderer::setBandSelectionActive(bool v)
{
    if (m_bandSelectionActive == v)
        return;
    m_bandSelectionActive = v;
    emit bandSelectionActiveChanged();
    sceneChanged();
}

void TimelineRenderer::setBandSelectionX(double v)
{
    if (m_bandSelection.x == v)
        return;
    m_bandSelection.x = v;
    emit bandSelectionXChanged();
    sceneChanged();
}

void TimelineRenderer::setBandSelectionY(double v)
{
    if (m_bandSelection.y == v)
        return;
    m_bandSelection.y = v;
    emit bandSelectionYChanged();
    sceneChanged();
}

void TimelineRenderer::setBandSelectionWidth(double v)
{
    if (m_bandSelection.w == v)
        return;
    m_bandSelection.w = v;
    emit bandSelectionWidthChanged();
    sceneChanged();
}

void TimelineRenderer::setBandSelectionHeight(double v)
{
    if (m_bandSelection.h == v)
        return;
    m_bandSelection.h = v;
    emit bandSelectionHeightChanged();
    sceneChanged();
}

void TimelineRenderer::setHoverPitch(int v)
{
    if (m_hoverPitch == v)
        return;
    m_hoverPitch = v;
    emit hoverPitchChanged();
    sceneChanged();
}

void TimelineRenderer::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size())
        sceneChanged();
}

void TimelineRenderer::updatePolish()
{
    ensureScene();
}

QVariantMap TimelineRenderer::noteFace(const QString &primitiveName)
{
    static const QString prefix = QStringLiteral("gridNote_");
    if (!primitiveName.startsWith(prefix))
        return {};
    bool ok = false;
    const quint64 id = QStringView(primitiveName).mid(prefix.size()).toULongLong(&ok);
    if (!ok)
        return {};
    ensureScene();
    for (const PaintedNote &note : m_painted) {
        if (note.id != id)
            continue;
        return {{QStringLiteral("x"), note.box.x},
                {QStringLiteral("y"), note.box.y},
                {QStringLiteral("width"), note.box.w},
                {QStringLiteral("height"), note.box.h},
                {QStringLiteral("fill"), RollProjection::argbToHex(note.box.argb)}};
    }
    return {};
}

void TimelineRenderer::ensureScene()
{
    const int liveRevision =
        m_contentSource ? m_contentSource->property("contentRevision").toInt() : 0;
    if (liveRevision != m_fetchedRevision)
        m_contentDirty = true;
    if (m_contentDirty)
        fetchContent(liveRevision);
    if (m_sceneDirty)
        rebuildScene();
}

void TimelineRenderer::fetchContent(int revision)
{
    m_contentDirty = false;
    m_sceneDirty = true;
    m_fetchedRevision = revision;
    RollContent::Content next;
    if (m_contentSource) {
        QByteArray blob;
        if (!QMetaObject::invokeMethod(m_contentSource.data(), "drawingContent",
                                       Qt::DirectConnection, Q_RETURN_ARG(QByteArray, blob)))
            qFatal("TimelineRenderer: contentSource drawingContent() invocation failed");
        if (!RollContent::decode(blob, next))
            qFatal("TimelineRenderer: malformed drawingContent blob");
    }
    if (next.fonts != m_content.fonts)
        clearFontCaches();
    else if (next.keyboardNames != m_content.keyboardNames)
        m_keyLabelAdvances = AdvanceTable{};
    m_content = std::move(next);
}

void TimelineRenderer::clearFontCaches()
{
    for (SGFontMetrics *metrics : std::as_const(m_fontMetrics))
        sgf_destroy(metrics);
    m_fontMetrics.clear();
    m_keyLabelFit = FitMemo{};
    m_noteValueFit = FitMemo{};
    m_noteNameAdvances = AdvanceTable{};
    m_noteValueAdvances = AdvanceTable{};
    m_keyLabelAdvances = AdvanceTable{};
}

SGFontMetrics *TimelineRenderer::metricsFor(uint8_t fontId, int pixelSize)
{
    const RollContent::FontSpec *spec = m_content.font(fontId);
    if (!spec)
        return nullptr;
    const int size = pixelSize > 0 ? pixelSize : spec->pixelSize;
    const quint64 key = quint64(fontId) << 32 | quint32(size);
    if (auto it = m_fontMetrics.constFind(key); it != m_fontMetrics.constEnd())
        return it.value();
    SGFontMetrics *metrics =
        sgf_create(spec->family.toUtf8().constData(), size, spec->weight, spec->letterSpacing);
    m_fontMetrics.insert(key, metrics);
    return metrics;
}

int TimelineRenderer::fittedPixelSize(uint8_t fontId, double rowHeight, FitMemo &memo)
{
    if (memo.pixelSize > 0 && memo.rowHeight == rowHeight)
        return memo.pixelSize;
    SGFontMetrics *base = metricsFor(fontId, 0);
    if (!base)
        return 0;
    memo = FitMemo{rowHeight, sgf_fit(base, rowHeight)};
    return memo.pixelSize;
}

double TimelineRenderer::advance(uint8_t fontId, int pixelSize, int index, const QString &text,
                                 AdvanceTable &table)
{
    if (table.pixelSize != pixelSize) {
        table = AdvanceTable{};
        table.pixelSize = pixelSize;
    }
    const bool cacheable = index >= 0 && index < 128;
    if (cacheable && table.known[size_t(index)])
        return table.width[size_t(index)];
    SGFontMetrics *metrics = metricsFor(fontId, pixelSize);
    const double width = metrics ? sgf_advance(metrics, text.toUtf8().constData()) : 0;
    if (cacheable) {
        table.width[size_t(index)] = width;
        table.known[size_t(index)] = true;
    }
    return width;
}

void TimelineRenderer::rebuildScene()
{
    m_sceneDirty = false;
    m_under.clear();
    m_over.clear();
    m_labels.clear();
    m_painted.clear();
    m_hasPreview = false;
    if (!m_content.hasMetrics || !m_camera.finite() || width() <= 0 || height() <= 0)
        return;
    if (m_bandRole == 0)
        buildPlot();
    else if (m_bandRole == 1)
        buildKeyboard();
}

RollRender::Label *TimelineRenderer::appendLabel(const Rect &rect, QString text, uint8_t fontId,
                                                 int pixelSize, int horizontalAlignment,
                                                 uint32_t argb)
{
    const RollContent::FontSpec *spec = m_content.font(fontId);
    if (!spec)
        return nullptr;
    RollRender::Label &label = m_labels.emplace_back();
    label.rect = rect;
    label.text = std::move(text);
    label.family = spec->family;
    label.pixelSize = pixelSize > 0 ? pixelSize : spec->pixelSize;
    label.weight = spec->weight;
    label.letterSpacing = spec->letterSpacing;
    label.horizontalAlignment = horizontalAlignment;
    label.color = argb;
    return &label;
}

void TimelineRenderer::buildPlot()
{
    const RollScene::Frame frame{m_content, m_camera, width(), height()};
    const RollScene::BandSelection band{m_bandSelectionActive, m_bandSelection};
    RollScene::appendRows(frame, m_under);
    RollScene::appendPreRollMask(frame, m_under);
    RollScene::appendTimeGrid(frame, m_under);
    RollScene::appendNoteFills(frame, m_visibleNotes, m_under, m_painted);
    m_hasPreview = RollScene::drawPreviewBox(frame, m_previewBox);
    if (m_hasPreview)
        m_under.push_back(m_previewBox);
    appendNoteLabels();
    RollScene::appendNoteFrames(frame, m_painted, m_hasPreview ? &m_previewBox : nullptr, band,
                                m_over);
    RollScene::appendBandSelection(frame, band, m_over);
    RollScene::appendTimeSelection(frame, m_over);
    RollScene::appendLoop(frame, m_over);
}

void TimelineRenderer::appendNoteLabels()
{
    const RollContent::Content &c = m_content;
    const RollContent::Metrics &m = c.metrics;
    if (!(c.modes & RollContent::modeTypographyAvailable))
        return;
    const double pixel = m_camera.pixel();
    const uint32_t light = c.color(RollPaletteSlot::NoteLabelLight);
    const uint32_t dark = c.color(RollPaletteSlot::NoteLabelDark);

    if (c.modes & RollContent::modeShowVelocityValues) {
        const double rowHeight = std::floor(m_camera.keyHeight - pixel);
        const int fit = fittedPixelSize(RollContent::fontNoteValue, rowHeight, m_noteValueFit);
        if (fit <= 0)
            return;
        const int size = std::max(1, fit - 1);
        SGFontMetrics *value = metricsFor(RollContent::fontNoteValue, size);
        if (!value || !(sgf_extents(value).height <= rowHeight))
            return;
        auto addValue = [&](const Rect &box, int velocity) {
            const QString &text = velocityText(velocity);
            const double width =
                advance(RollContent::fontNoteValue, size, velocity, text, m_noteValueAdvances);
            if (!(box.w >= width + m.valueAllowance))
                return;
            appendLabel(box, text, RollContent::fontNoteValue, size, Qt::AlignHCenter,
                        RollProjection::aaContrastInk(box.argb, light, dark));
        };
        for (const PaintedNote &note : m_painted) {
            if (!(note.flags & RollContent::noteGhost))
                addValue(note.box, note.velocity);
        }
        if (m_hasPreview)
            addValue(m_previewBox, c.drawPreview.lastVelocity);
        return;
    }

    if (!(c.modes & RollContent::modeNoteName))
        return;
    SGFontMetrics *name = metricsFor(RollContent::fontNoteName, 0);
    if (!name)
        return;
    const double spaceHalf = m.spaceHalf;
    if (!(m_camera.keyHeight >= 12.0
          && sgf_extents(name).height <= std::floor(m_camera.keyHeight - pixel - 2 * spaceHalf)))
        return;
    for (const PaintedNote &note : m_painted) {
        if (note.flags & RollContent::noteGhost)
            continue;
        const QString &text = pitchName(note.pitch);
        const double width =
            advance(RollContent::fontNoteName, 0, note.pitch, text, m_noteNameAdvances);
        if (!(note.box.w >= spaceHalf + width + m.spaceTwo))
            continue;
        const Rect rect{note.box.x + spaceHalf, note.box.y + spaceHalf,
                        std::max(0.0, note.box.w - 2 * spaceHalf),
                        std::max(0.0, note.box.h - 2 * spaceHalf)};
        appendLabel(rect, text, RollContent::fontNoteName, 0, Qt::AlignLeft,
                    RollProjection::aaContrastInk(note.box.argb, light, dark));
    }
}

void TimelineRenderer::buildKeyboard()
{
    const RollScene::Frame frame{m_content, m_camera, width(), height()};
    RollScene::appendKeys(frame, m_hoverPitch, m_under, m_over);
    if (m_content.modes & RollContent::modeTypographyAvailable)
        appendKeyLabels();
}

void TimelineRenderer::appendKeyLabels()
{
    const RollContent::Content &c = m_content;
    const RollProjection::Camera &cam = m_camera;
    const int fit = fittedPixelSize(RollContent::fontKeyLabel, cam.keyHeight, m_keyLabelFit);
    if (fit <= 0)
        return;
    const double H = height();
    const double keyboardWidth = c.metrics.keyboardWidth;
    const double inset = c.metrics.keyLabelRightInset;
    const int rowCount = int(c.rows.size());
    for (int row = 0; row < rowCount; ++row) {
        const int pitch = c.rows[size_t(row)].pitch;
        const bool black = RollProjection::isBlackKey(pitch);
        if (!c.drumMode && (black || pitch % 12 != 0))
            continue;
        const double top = cam.viewRowTop(row);
        const double bottom = cam.viewRowBottom(row);
        if (bottom <= 0 || top >= H)
            continue;
        const QString &name = c.keyboardNames[size_t(pitch)];
        const QString &text = name.isEmpty() ? pitchName(pitch) : name;
        const double labelWidth = c.drumMode
            ? std::max(keyboardWidth - inset,
                       advance(RollContent::fontKeyLabel, fit, pitch, text, m_keyLabelAdvances)
                           + inset)
            : keyboardWidth - inset;
        const bool drumBlack = c.drumMode && black;
        const Rect rect{0, top, labelWidth, bottom - top};
        RollRender::Label *label = appendLabel(
            rect, text, RollContent::fontKeyLabel, fit, Qt::AlignRight,
            c.color(drumBlack ? RollPaletteSlot::KeyboardWhite : RollPaletteSlot::KeyboardLabel));
        if (label && c.drumMode) {
            label->hasBackground = true;
            label->background = Rect{rect.x, rect.y, rect.w, rect.h,
                                     c.color(drumBlack ? RollPaletteSlot::KeyboardBlack
                                                       : RollPaletteSlot::KeyboardWhite)};
        }
    }
}
