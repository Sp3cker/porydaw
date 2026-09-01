#pragma once

#include <QQuickItem>

namespace songview {

class TimelineChromeItem : public QQuickItem
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(TimelineChromeItem)

  public:
    enum class Kind : quint8 {
        Hover,
        Edit,
        Playhead,
    };
    Q_ENUM(Kind)

    enum class RulerTriangle : quint8 {
        None,
        Down,
        Up,
    };
    Q_ENUM(RulerTriangle)

    Q_PROPERTY(Kind kind READ kind WRITE setKind NOTIFY kindChanged FINAL)
    Q_PROPERTY(bool playing READ playing WRITE setPlaying NOTIFY playingChanged FINAL)
    Q_PROPERTY(RulerTriangle rulerTriangle READ rulerTriangle WRITE setRulerTriangle NOTIFY
                   rulerTriangleChanged FINAL)

    explicit TimelineChromeItem(QQuickItem *parent = nullptr);

    Kind kind() const noexcept;
    void setKind(Kind kind);
    bool playing() const noexcept;
    void setPlaying(bool playing);
    RulerTriangle rulerTriangle() const noexcept;
    void setRulerTriangle(RulerTriangle rulerTriangle);

  signals:
    void kindChanged();
    void playingChanged();
    void rulerTriangleChanged();

  protected:
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override;

  private:
    Kind m_kind = Kind::Hover;
    bool m_playing = false;
    RulerTriangle m_rulerTriangle = RulerTriangle::None;
};

} // namespace songview
