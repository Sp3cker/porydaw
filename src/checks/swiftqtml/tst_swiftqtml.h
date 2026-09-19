#pragma once

#include <QObject>

class SwiftQtMlTest final : public QObject
{
    Q_OBJECT

  private slots:
    void initTestCase();
    void cleanupTestCase();

    void testPresenterPropertyBinding();
    void testInPlaceRowMutation();
    void testRowReplacement();
    void testInsertRemovePreservesTargets();
    void testReorderTargetsIntendedRow();
    void testResetWithStaleQmlReference();
    void testPendingMutationThenTeardown();
    void testObjectReturnCapability();
};
