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
    };
    Q_ENUM(Kind)

    Q_PROPERTY(Kind kind READ kind WRITE setKind NOTIFY kindChanged FINAL)
    explicit TimelineChromeItem(QQuickItem *parent = nullptr);

    Kind kind() const noexcept;
    void setKind(Kind kind);

  signals:
    void kindChanged();

  protected:
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override;

  private:
    Kind m_kind = Kind::Hover;
};

} // namespace songview
