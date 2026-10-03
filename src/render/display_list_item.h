#pragma once

#include "display_list.h"

#include <QtCore/qbytearray.h>
#include <QtCore/qobject.h>
#include <QtCore/qpointer.h>
#include <QtCore/qvariant.h>
#include <QtQml/qqmlregistration.h>
#include <QtQuick/qquickitem.h>

class DisplayList : public QQuickItem
{
    Q_OBJECT
    QML_NAMED_ELEMENT(DisplayList)
    Q_PROPERTY(QObject *source READ source WRITE setSource NOTIFY sourceChanged FINAL)
    Q_PROPERTY(int list READ list WRITE setList NOTIFY listChanged FINAL)
    Q_PROPERTY(int revision READ revision WRITE setRevision NOTIFY revisionChanged FINAL)
    Q_PROPERTY(int fetchedRevision READ fetchedRevision NOTIFY fetchedRevisionChanged FINAL)
    Q_PROPERTY(double loopStartId READ loopStartId CONSTANT FINAL)
    Q_PROPERTY(double loopEndId READ loopEndId CONSTANT FINAL)
    Q_DISABLE_COPY_MOVE(DisplayList)

  public:
    explicit DisplayList(QQuickItem *parent = nullptr);
    ~DisplayList() override;

    [[nodiscard]] QObject *source() const { return m_source; }
    void setSource(QObject *source);
    [[nodiscard]] int list() const { return m_list; }
    void setList(int list);
    [[nodiscard]] int revision() const { return m_revision; }
    void setRevision(int revision);
    [[nodiscard]] int fetchedRevision() const { return m_fetchedRevision; }
    [[nodiscard]] double loopStartId() const { return double(PD_DL_ID_LOOP_START); }
    [[nodiscard]] double loopEndId() const { return double(PD_DL_ID_LOOP_END); }
    Q_INVOKABLE QVariantMap face(double id) const;

  signals:
    void sourceChanged();
    void listChanged();
    void revisionChanged();
    void fetchedRevisionChanged();

  protected:
    void itemChange(ItemChange change, const ItemChangeData &data) override;
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override;

  private:
    void pullFrame();
    void clearFrame();

    QPointer<QObject> m_source;
    QMetaObject::Connection m_sourceDestroyed;
    QMetaObject::Connection m_afterAnimating;
    int m_list = 0;
    int m_revision = 0;
    int m_fetchedRevision = -1;
    QByteArray m_blob;
    PdDlView m_view = {};
};
