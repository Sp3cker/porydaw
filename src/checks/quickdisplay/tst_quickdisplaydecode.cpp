#include "checks/quickdisplay/tst_quickdisplaydecode.h"

#include <QAbstractListModel>
#include <QQuickItem>
#include <QtTest>

#include <quickdisplaylistitem.h>

#include <cstring>

namespace checks {
namespace {

constexpr int kPackedRole = Qt::UserRole + 1;

/// Minimal model answering the packedRows role with a blob laid out exactly
/// like Swift's SceneRectPacking.pack(includeStrings: true):
/// u32 count, then per row {4×f32 x,y,w,h; u32 argb; u16 nameLen; utf8 name;
/// u16 colorLen; utf8 fillColor} little-endian.
class PackedRowsModel final : public QAbstractListModel
{
  public:
    void setRows(int count, int nameLen, int colorLen)
    {
        beginResetModel();
        m_rows = count;
        m_nameLen = nameLen;
        m_colorLen = colorLen;
        endResetModel();
    }

    int rowCount(const QModelIndex & = {}) const override { return m_rows; }

    QHash<int, QByteArray> roleNames() const override { return {{kPackedRole, "packedRows"}}; }

    QVariant data(const QModelIndex &index, int role) const override
    {
        if (role != kPackedRole || !index.isValid())
            return {};

        QByteArray blob;
        const auto stride = qsizetype(22 + m_nameLen + m_colorLen);
        blob.reserve(4 + m_rows * stride);
        auto appendU32 = [&blob](quint32 value) {
            char raw[4];
            qToLittleEndian(value, raw);
            blob.append(raw, 4);
        };
        auto appendU16 = [&blob](quint16 value) {
            char raw[2];
            qToLittleEndian(value, raw);
            blob.append(raw, 2);
        };
        appendU32(quint32(m_rows));
        const QByteArray name(m_nameLen, 'n');
        const QByteArray color(m_colorLen, '#');
        for (int row = 0; row < m_rows; ++row) {
            const float box[4] = {float(row), 0.0f, 8.0f, 8.0f};
            char raw[16];
            std::memcpy(raw, box, sizeof(raw));
            blob.append(raw, sizeof(raw));
            appendU32(0xFF336699u);
            appendU16(quint16(m_nameLen));
            blob.append(name);
            appendU16(quint16(m_colorLen));
            blob.append(color);
        }
        return blob;
    }

  private:
    int m_rows = 0;
    int m_nameLen = 0;
    int m_colorLen = 0;
};

} // namespace

void QuickDisplayDecodeTest::packedRowsDecodePast64KiB()
{
    // 2000 rows at 44B stride ≈ 88KiB: the boundary lands mid-stream and the
    // old decode broke at the straddling row, exposing only a prefix.
    PackedRowsModel model;
    model.setRows(2000, 12, 8);

    QuickDisplayListItem item;
    item.setExposeRows(true);
    item.setRects(&model);

    QCOMPARE(model.rowCount(), 2000);
    QCOMPARE(item.childItems().size(), 2000);
}

void QuickDisplayDecodeTest::packedRowsDecodeAtBoundaryAlignments()
{
    // Sweep blob sizes so the 64KiB boundary lands inside name fields,
    // color fields and fixed headers alike; every layout must decode fully.
    for (int nameLen : {0, 1, 12, 40}) {
        PackedRowsModel model;
        model.setRows(1500, nameLen, nameLen > 40 ? 0 : 8);

        QuickDisplayListItem item;
        item.setExposeRows(true);
        item.setRects(&model);

        QCOMPARE(item.childItems().size(), model.rowCount());
    }
}

} // namespace checks

int runQuickDisplayDecodeCheck(const QStringList &qtArguments)
{
    checks::QuickDisplayDecodeTest test;
    QStringList arguments{QStringLiteral("quickdisplay-decode")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
