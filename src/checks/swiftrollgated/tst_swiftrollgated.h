#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

class SwiftRollGatedTest final : public QObject
{
    Q_OBJECT

  public:
    SwiftRollGatedTest(QString projectRoot, QString songA, QString songB);

  private slots:
    void initTestCase();
    void cleanupTestCase();

    void testInitialRenderWithoutEdit();
    void testTrackFollow();
    void testEditUndoRedoRefresh();
    void testNon24AndSignatureGeometry();
    void testTwoDocumentsInterleaved();
    void testRemountFreshToken();
    void testBandEditWithoutFocusChange();
    void testBandEditUndoRedoRerender();
    void testEscapeMidDragZeroEffect();
    void testBandLeadingGripDecline();
    void testBandTrailingGripResizeCommitOnce();
    void testViewingInputLive();
    void testTransferredWindowTeardown();
    void testFlagOffAbsence();

  private:
    QString m_projectRoot;
    QString m_songA;
    QString m_songB;
};
