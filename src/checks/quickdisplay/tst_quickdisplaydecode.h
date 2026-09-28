#pragma once

// QuickDisplayList packed-blob decode: the C++ item bounds-checked string
// lengths through a quint16 cast, so a blob past 64KiB silently dropped every
// row after the one straddling that boundary. These cases feed synthetic
// models whose blobs span the boundary and assert every row decodes.

#include <QObject>

namespace checks {

class QuickDisplayDecodeTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(QuickDisplayDecodeTest)

  public:
    QuickDisplayDecodeTest() = default;

  private slots:
    void packedRowsDecodePast64KiB();
    void packedRowsDecodeAtBoundaryAlignments();
};

} // namespace checks
