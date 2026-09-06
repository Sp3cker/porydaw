#include "checks/nativegraphics/tst_renderingplayhead.h"

#include <QtTest>

#include <QImage>
#include <QRect>

#include <utility>

#include "checks/support/quickframebuffer.h"

RenderingPlayheadTest::RenderingPlayheadTest(QString projectRoot, QString songLabel)
    : m_projectRoot(std::move(projectRoot))
    , m_songLabel(std::move(songLabel))
{}

void RenderingPlayheadTest::devicePixelRect()
{
    const QRect logicalRect{3, 2, 5, 4};
    QImage dprOne{QSize{16, 10}, QImage::Format_ARGB32_Premultiplied};
    dprOne.setDevicePixelRatio(1.0);
    QCOMPARE(checks::support::devicePixelRect(dprOne, logicalRect), logicalRect);

    QImage dprTwo{QSize{32, 20}, QImage::Format_ARGB32_Premultiplied};
    dprTwo.setDevicePixelRatio(2.0);
    const QRect doubleRect{6, 4, 10, 8};
    QCOMPARE(checks::support::devicePixelRect(dprTwo, logicalRect), doubleRect);

    QImage dprOnePointFive{QSize{12, 14}, QImage::Format_ARGB32_Premultiplied};
    dprOnePointFive.setDevicePixelRatio(1.5);
    const QRect fractionalRect{4, 3, 8, 6};
    const QRect roundingRect{1, 1, 4, 4};
    QCOMPARE(checks::support::devicePixelRect(dprOnePointFive, logicalRect), fractionalRect);
    QCOMPARE(checks::support::devicePixelRect(dprOnePointFive, QRect{1, 1, 2, 2}), roundingRect);
}
