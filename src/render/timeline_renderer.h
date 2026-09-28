#pragma once

#include "roll_content.h"
#include "roll_projection.h"
#include "roll_scene.h"

#include <QtCore/qhash.h>
#include <QtCore/qobject.h>
#include <QtCore/qpointer.h>
#include <QtCore/qstring.h>
#include <QtCore/qvariant.h>
#include <QtQml/qqmlregistration.h>
#include <QtQuick/qquickitem.h>

#include <array>
#include <vector>

struct SGFontMetrics;

namespace RollRender {

struct Label {
    RollProjection::Rect rect;
    RollProjection::Rect background;
    bool hasBackground = false;
    QString text;
    QString family;
    int pixelSize = 0;
    int weight = 0;
    double letterSpacing = 0;
    int horizontalAlignment = 0;
    uint32_t color = 0;
};

} // namespace RollRender

class TimelineRenderer : public QQuickItem
{
    Q_OBJECT
    QML_NAMED_ELEMENT(TimelineRenderer)
    Q_PROPERTY(int band READ band WRITE setBand NOTIFY bandChanged)
    Q_PROPERTY(QObject *contentSource READ contentSource WRITE setContentSource
                   NOTIFY contentSourceChanged)
    Q_PROPERTY(int contentRevision READ contentRevision WRITE setContentRevision
                   NOTIFY contentRevisionChanged)
    Q_PROPERTY(double pixelsPerTick READ pixelsPerTick WRITE setPixelsPerTick
                   NOTIFY pixelsPerTickChanged)
    Q_PROPERTY(double keyHeight READ keyHeight WRITE setKeyHeight NOTIFY keyHeightChanged)
    Q_PROPERTY(double scrollX READ scrollX WRITE setScrollX NOTIFY scrollXChanged)
    Q_PROPERTY(double scrollY READ scrollY WRITE setScrollY NOTIFY scrollYChanged)
    Q_PROPERTY(double devicePixelRatio READ devicePixelRatio WRITE setDevicePixelRatio
                   NOTIFY devicePixelRatioChanged)
    Q_PROPERTY(bool bandSelectionActive READ bandSelectionActive WRITE setBandSelectionActive
                   NOTIFY bandSelectionActiveChanged)
    Q_PROPERTY(double bandSelectionX READ bandSelectionX WRITE setBandSelectionX
                   NOTIFY bandSelectionXChanged)
    Q_PROPERTY(double bandSelectionY READ bandSelectionY WRITE setBandSelectionY
                   NOTIFY bandSelectionYChanged)
    Q_PROPERTY(double bandSelectionWidth READ bandSelectionWidth WRITE setBandSelectionWidth
                   NOTIFY bandSelectionWidthChanged)
    Q_PROPERTY(double bandSelectionHeight READ bandSelectionHeight WRITE setBandSelectionHeight
                   NOTIFY bandSelectionHeightChanged)
    Q_PROPERTY(int hoverPitch READ hoverPitch WRITE setHoverPitch NOTIFY hoverPitchChanged)

  public:
    explicit TimelineRenderer(QQuickItem *parent = nullptr);
    ~TimelineRenderer() override;

    Q_INVOKABLE QVariantMap noteFace(const QString &primitiveName);

    [[nodiscard]] int band() const { return m_bandRole; }
    void setBand(int band);
    [[nodiscard]] QObject *contentSource() const { return m_contentSource; }
    void setContentSource(QObject *source);
    [[nodiscard]] int contentRevision() const { return m_contentRevision; }
    void setContentRevision(int revision);
    [[nodiscard]] double pixelsPerTick() const { return m_camera.pixelsPerTick; }
    void setPixelsPerTick(double v);
    [[nodiscard]] double keyHeight() const { return m_camera.keyHeight; }
    void setKeyHeight(double v);
    [[nodiscard]] double scrollX() const { return m_camera.scrollX; }
    void setScrollX(double v);
    [[nodiscard]] double scrollY() const { return m_camera.scrollY; }
    void setScrollY(double v);
    [[nodiscard]] double devicePixelRatio() const { return m_camera.dpr; }
    void setDevicePixelRatio(double v);
    [[nodiscard]] bool bandSelectionActive() const { return m_bandSelectionActive; }
    void setBandSelectionActive(bool v);
    [[nodiscard]] double bandSelectionX() const { return m_bandSelection.x; }
    void setBandSelectionX(double v);
    [[nodiscard]] double bandSelectionY() const { return m_bandSelection.y; }
    void setBandSelectionY(double v);
    [[nodiscard]] double bandSelectionWidth() const { return m_bandSelection.w; }
    void setBandSelectionWidth(double v);
    [[nodiscard]] double bandSelectionHeight() const { return m_bandSelection.h; }
    void setBandSelectionHeight(double v);
    [[nodiscard]] int hoverPitch() const { return m_hoverPitch; }
    void setHoverPitch(int v);

  signals:
    void bandChanged();
    void contentSourceChanged();
    void contentRevisionChanged();
    void pixelsPerTickChanged();
    void keyHeightChanged();
    void scrollXChanged();
    void scrollYChanged();
    void devicePixelRatioChanged();
    void bandSelectionActiveChanged();
    void bandSelectionXChanged();
    void bandSelectionYChanged();
    void bandSelectionWidthChanged();
    void bandSelectionHeightChanged();
    void hoverPitchChanged();

  protected:
    void updatePolish() override;
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

  private:
    using PaintedNote = RollScene::PaintedNote;
    struct AdvanceTable {
        int pixelSize = -1;
        std::array<double, 128> width{};
        std::array<bool, 128> known{};
    };

    struct FitMemo {
        double rowHeight = -1;
        int pixelSize = 0;
    };

    void sceneChanged();
    void ensureScene();
    void fetchContent(int revision);
    void rebuildScene();
    void buildPlot();
    void buildKeyboard();
    void appendNoteLabels();
    void appendKeyLabels();
    RollRender::Label *appendLabel(const RollProjection::Rect &rect, QString text, uint8_t fontId,
                                   int pixelSize, int horizontalAlignment, uint32_t argb);
    SGFontMetrics *metricsFor(uint8_t fontId, int pixelSize);
    int fittedPixelSize(uint8_t fontId, double rowHeight, FitMemo &memo);
    double advance(uint8_t fontId, int pixelSize, int pitch, const QString &text,
                   AdvanceTable &table);
    void clearFontCaches();

    RollProjection::Camera m_camera;
    RollProjection::Rect m_bandSelection;
    bool m_bandSelectionActive = false;
    int m_hoverPitch = -1;
    int m_bandRole = 0;
    QPointer<QObject> m_contentSource;
    int m_contentRevision = 0;
    bool m_contentDirty = true;
    int m_fetchedRevision = -1;
    bool m_sceneDirty = true;
    RollContent::Content m_content;

    std::vector<PaintedNote> m_painted;
    std::vector<uint32_t> m_visibleNotes;
    std::vector<RollProjection::Rect> m_under;
    std::vector<RollProjection::Rect> m_over;
    std::vector<RollRender::Label> m_labels;
    RollProjection::Rect m_previewBox;
    bool m_hasPreview = false;

    QHash<quint64, SGFontMetrics *> m_fontMetrics;
    FitMemo m_keyLabelFit;
    FitMemo m_noteValueFit;
    AdvanceTable m_noteNameAdvances;
    AdvanceTable m_noteValueAdvances;
    AdvanceTable m_keyLabelAdvances;
};
