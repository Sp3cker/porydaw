#include "tst_swiftqtml.h"

#include <QAbstractItemModel>
#include <QCoreApplication>
#include <QEvent>
#include <QMetaObject>
#include <QMutex>
#include <QMutexLocker>
#include <QObject>
#include <QPointer>
#include <QQmlError>
#include <QQuickItem>
#include <QQuickView>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVariant>
#include <QtLogging>
#include <QtTest/QTest>
#include <memory>

extern "C" void sqp_register_probe_types();

namespace {

QMutex messageMutex;
QStringList qtMessages;
QtMessageHandler previousMessageHandler = nullptr;

void probeMessageHandler(QtMsgType type, const QMessageLogContext &context, const QString &message)
{
    const bool isFailureMessage =
        type == QtWarningMsg || type == QtCriticalMsg || type == QtFatalMsg;
    if (isFailureMessage) {
        QMutexLocker lock(&messageMutex);
        const QString source =
            context.file ? QString::fromUtf8(context.file) : QStringLiteral("<unknown>");
        qtMessages.append(QStringLiteral("Qt[%1] %2:%3: %4")
                              .arg(int(type))
                              .arg(source)
                              .arg(context.line)
                              .arg(message));
    } else if (previousMessageHandler) {
        previousMessageHandler(type, context, message);
    }
}

void clearCapturedMessages()
{
    QMutexLocker lock(&messageMutex);
    qtMessages.clear();
}

QString capturedMessages()
{
    QMutexLocker lock(&messageMutex);
    return qtMessages.join(QLatin1Char('\n'));
}

// Identical double flush to selectionkey::settle() in
// src/checks/selectionkey/primitives.h. This target does not link the
// selectionkey harness objects.
void settle()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

QString describeErrors(const QList<QQmlError> &errors)
{
    QStringList descriptions;
    descriptions.reserve(errors.size());
    for (const QQmlError &error : errors)
        descriptions.append(error.toString());
    return descriptions.join(QLatin1Char('\n'));
}

std::unique_ptr<QQuickView> loadProbe(QString &error)
{
    clearCapturedMessages();
    auto view = std::make_unique<QQuickView>();
    view->setResizeMode(QQuickView::SizeRootObjectToView);
    view->resize(320, 240);
    view->setSource(QUrl(QStringLiteral("qrc:/swiftqtml/BridgeProbe.qml")));
    if (view->status() != QQuickView::Ready) {
        error = describeErrors(view->errors());
        return {};
    }
    settle();
    return view;
}

bool invoke(QObject *root, const char *method)
{
    return root && QMetaObject::invokeMethod(root, method, Qt::DirectConnection);
}

bool invokeString(QObject *object, const char *method, const QString &value)
{
    return object &&
           QMetaObject::invokeMethod(object, method, Qt::DirectConnection, Q_ARG(QString, value));
}

QObject *named(QObject *root, const QString &objectName)
{
    return root ? root->findChild<QObject *>(objectName, Qt::FindChildrenRecursively) : nullptr;
}

QObject *delegateAt(QObject *root, int slot)
{
    QObject *const probe = named(root, QStringLiteral("delegateProbe"));
    if (!probe || slot < 0 || slot >= probe->property("count").toInt())
        return nullptr;
    QVariant result;
    if (!QMetaObject::invokeMethod(probe, "itemAt", Qt::DirectConnection,
                                   Q_RETURN_ARG(QVariant, result),
                                   Q_ARG(QVariant, QVariant(slot)))) {
        return nullptr;
    }
    return result.value<QQuickItem *>();
}

QObject *rowDelegate(QObject *root, int domainKey)
{
    QObject *const probe = named(root, QStringLiteral("delegateProbe"));
    const int count = probe ? probe->property("count").toInt() : 0;
    for (int slot = 0; slot < count; ++slot) {
        QObject *const delegate = delegateAt(root, slot);
        if (delegate && delegate->property("domainKey").toInt() == domainKey)
            return delegate;
    }
    return nullptr;
}

QObject *rowText(QObject *root, int domainKey)
{
    auto *const delegate = qobject_cast<QQuickItem *>(rowDelegate(root, domainKey));
    if (!delegate)
        return nullptr;
    const QString expectedName = QStringLiteral("rowText_%1").arg(domainKey);
    for (QQuickItem *const child : delegate->childItems()) {
        if (child && child->objectName() == expectedName)
            return child;
    }
    return nullptr;
}

QString textOf(QObject *object)
{
    return object ? object->property("text").toString() : QString();
}

int serialOf(QObject *object)
{
    return object ? object->property("delegateSerial").toInt() : -1;
}

int indexOf(QObject *object)
{
    return object ? object->property("index").toInt() : -1;
}

QString probeDiagnostics(QObject *root, const QQuickView *view)
{
    QStringList details;
    details.append(QStringLiteral("viewStatus=%1").arg(view ? int(view->status()) : -1));
    if (QObject *const repeater = named(root, QStringLiteral("rowRepeater"))) {
        details.append(QStringLiteral("repeaterCount=%1").arg(repeater->property("count").toInt()));
        const QVariant modelValue = repeater->property("model");
        details.append(
            QStringLiteral("modelType=%1").arg(QString::fromLatin1(modelValue.metaType().name())));
        QObject *const modelObject = modelValue.value<QObject *>();
        if (auto *const model = qobject_cast<QAbstractItemModel *>(modelObject)) {
            details.append(QStringLiteral("modelRowCount=%1").arg(model->rowCount()));
            QStringList roles;
            const auto roleNames = model->roleNames();
            for (auto it = roleNames.cbegin(); it != roleNames.cend(); ++it)
                roles.append(
                    QStringLiteral("%1=%2").arg(it.key()).arg(QString::fromUtf8(it.value())));
            roles.sort();
            details.append(QStringLiteral("roles=[%1]").arg(roles.join(QStringLiteral(", "))));
        }
    } else {
        details.append(QStringLiteral("rowRepeater=<missing>"));
    }
    const QString messages = capturedMessages();
    details.append(messages.isEmpty() ? QStringLiteral("qtMessages=<none>")
                                      : QStringLiteral("qtMessages:\n%1").arg(messages));
    return details.join(QLatin1Char('\n'));
}

} // namespace

void SwiftQtMlTest::initTestCase()
{
    previousMessageHandler = qInstallMessageHandler(probeMessageHandler);
    sqp_register_probe_types();
}

void SwiftQtMlTest::cleanupTestCase()
{
    qInstallMessageHandler(previousMessageHandler);
    previousMessageHandler = nullptr;
}

void SwiftQtMlTest::testPresenterPropertyBinding()
{
    QString error;
    auto view = loadProbe(error);
    QVERIFY2(view != nullptr, qUtf8Printable(error));
    QObject *const root = view->rootObject();
    QObject *const presenter = named(root, QStringLiteral("bridgeProbe"));
    QObject *const status = named(root, QStringLiteral("statusText"));
    QVERIFY(presenter != nullptr);
    QVERIFY(status != nullptr);
    QCOMPARE(textOf(status), QStringLiteral("idle"));

    QVERIFY(invokeString(presenter, "setStatusText", QStringLiteral("ready")));
    settle();

    QCOMPARE(textOf(status), QStringLiteral("ready"));
}

void SwiftQtMlTest::testInPlaceRowMutation()
{
    QString error;
    auto view = loadProbe(error);
    QVERIFY2(view != nullptr, qUtf8Printable(error));
    QObject *const root = view->rootObject();
    QVERIFY(invoke(root, "seedDefaultRows"));
    settle();

    QObject *const middle = rowDelegate(root, 202);
    QObject *const middleText = rowText(root, 202);
    QVERIFY2(middle != nullptr, qUtf8Printable(probeDiagnostics(root, view.get())));
    QVERIFY2(middleText != nullptr, qUtf8Printable(probeDiagnostics(root, view.get())));
    const int originalSerial = serialOf(middle);
    QCOMPARE(textOf(middleText), QStringLiteral("Beta:20"));

    QVERIFY(invoke(root, "mutateMiddleDirect"));
    settle();

    // QListModel has emitted no dataChanged signal, so its copied delegate
    // role remains unchanged even though the BridgeRow object was mutated.
    QCOMPARE(textOf(middleText), QStringLiteral("Beta:20"));
    QCOMPARE(serialOf(middle), originalSerial);

    QVERIFY(invoke(root, "replaceMiddleSameRow"));
    settle();

    QCOMPARE(textOf(middleText), QStringLiteral("Beta direct:20"));
    QCOMPARE(serialOf(middle), originalSerial);
}

void SwiftQtMlTest::testRowReplacement()
{
    QString error;
    auto view = loadProbe(error);
    QVERIFY2(view != nullptr, qUtf8Printable(error));
    QObject *const root = view->rootObject();
    QVERIFY(invoke(root, "seedDefaultRows"));
    settle();

    QObject *const oldDelegate = rowDelegate(root, 202);
    QVERIFY2(oldDelegate != nullptr, qUtf8Printable(probeDiagnostics(root, view.get())));
    const int originalSerial = serialOf(oldDelegate);

    QVERIFY(invoke(root, "replaceMiddleWithNewRow"));
    settle();

    QObject *const replacement = rowDelegate(root, 404);
    QObject *const replacementText = rowText(root, 404);
    QVERIFY2(replacement != nullptr, qUtf8Printable(probeDiagnostics(root, view.get())));
    QVERIFY2(replacementText != nullptr, qUtf8Printable(probeDiagnostics(root, view.get())));
    QCOMPARE(textOf(replacementText), QStringLiteral("Delta:44"));
    QCOMPARE(serialOf(replacement), originalSerial);

    QVERIFY(invoke(named(root, QStringLiteral("bridgeProbe")), "actViaSelectedRow"));
    settle();

    QCOMPARE(textOf(named(root, QStringLiteral("actionLogText"))), QStringLiteral("202:Beta"));
    QCOMPARE(textOf(replacementText), QStringLiteral("Delta:44"));
}

void SwiftQtMlTest::testInsertRemovePreservesTargets()
{
    QString error;
    auto view = loadProbe(error);
    QVERIFY2(view != nullptr, qUtf8Printable(error));
    QObject *const root = view->rootObject();
    QVERIFY(invoke(root, "seedDefaultRows"));
    settle();

    QObject *const alpha = rowDelegate(root, 101);
    QObject *const gamma = rowDelegate(root, 303);
    QVERIFY2(alpha != nullptr, qUtf8Printable(probeDiagnostics(root, view.get())));
    QVERIFY2(gamma != nullptr, qUtf8Printable(probeDiagnostics(root, view.get())));
    const int alphaSerial = serialOf(alpha);
    const int gammaSerial = serialOf(gamma);

    QVERIFY(invoke(root, "insertHeadRemoveMiddle"));
    settle();

    QObject *const repeater = named(root, QStringLiteral("rowRepeater"));
    QVERIFY(repeater != nullptr);
    QCOMPARE(repeater->property("count").toInt(), 3);
    QVERIFY2(rowDelegate(root, 100) != nullptr, qUtf8Printable(probeDiagnostics(root, view.get())));
    QVERIFY2(rowDelegate(root, 101) != nullptr, qUtf8Printable(probeDiagnostics(root, view.get())));
    QVERIFY2(rowDelegate(root, 303) != nullptr, qUtf8Printable(probeDiagnostics(root, view.get())));
    QCOMPARE(indexOf(rowDelegate(root, 100)), 0);
    QCOMPARE(indexOf(rowDelegate(root, 101)), 1);
    QCOMPARE(indexOf(rowDelegate(root, 303)), 2);
    QVERIFY(rowDelegate(root, 202) == nullptr);
    QCOMPARE(serialOf(rowDelegate(root, 101)), alphaSerial);
    QCOMPARE(serialOf(rowDelegate(root, 303)), gammaSerial);

    QVERIFY(invoke(named(root, QStringLiteral("bridgeProbe")), "actViaSelectedRow"));
    settle();
    QCOMPARE(textOf(named(root, QStringLiteral("actionLogText"))), QStringLiteral("303:Gamma"));
}

void SwiftQtMlTest::testReorderTargetsIntendedRow()
{
    QString error;
    auto view = loadProbe(error);
    QVERIFY2(view != nullptr, qUtf8Printable(error));
    QObject *const root = view->rootObject();
    QVERIFY(invoke(root, "seedDefaultRows"));
    settle();

    QObject *const alpha = rowDelegate(root, 101);
    QVERIFY2(alpha != nullptr, qUtf8Printable(probeDiagnostics(root, view.get())));
    const int originalSerial = serialOf(alpha);

    QVERIFY(invoke(root, "removeInsertFirstToLast"));
    settle();

    QVERIFY2(rowDelegate(root, 202) != nullptr, qUtf8Printable(probeDiagnostics(root, view.get())));
    QVERIFY2(rowDelegate(root, 303) != nullptr, qUtf8Printable(probeDiagnostics(root, view.get())));
    QVERIFY2(rowDelegate(root, 101) != nullptr, qUtf8Printable(probeDiagnostics(root, view.get())));
    QCOMPARE(indexOf(rowDelegate(root, 202)), 0);
    QCOMPARE(indexOf(rowDelegate(root, 303)), 1);
    QCOMPARE(indexOf(rowDelegate(root, 101)), 2);
    QVERIFY(serialOf(rowDelegate(root, 101)) != originalSerial);
    QVERIFY(invoke(named(root, QStringLiteral("bridgeProbe")), "actViaSelectedRow"));
    settle();
    QCOMPARE(textOf(named(root, QStringLiteral("actionLogText"))), QStringLiteral("101:Alpha"));
}

void SwiftQtMlTest::testResetWithStaleQmlReference()
{
    QString error;
    auto view = loadProbe(error);
    QVERIFY2(view != nullptr, qUtf8Printable(error));
    QObject *const root = view->rootObject();
    QVERIFY(invoke(root, "seedDefaultRows"));
    settle();

    QVERIFY(invoke(root, "resetWithFreshRows"));
    settle();
    QVERIFY(rowDelegate(root, 202) == nullptr);
    QVERIFY2(rowText(root, 901) != nullptr, qUtf8Printable(probeDiagnostics(root, view.get())));
    QVERIFY2(rowText(root, 902) != nullptr, qUtf8Printable(probeDiagnostics(root, view.get())));
    QCOMPARE(textOf(rowText(root, 901)), QStringLiteral("Fresh A:91"));
    QCOMPARE(textOf(rowText(root, 902)), QStringLiteral("Fresh B:92"));

    QVERIFY(invoke(named(root, QStringLiteral("bridgeProbe")), "actViaSelectedRow"));
    settle();

    QCOMPARE(textOf(named(root, QStringLiteral("actionLogText"))), QStringLiteral("202:Beta"));
    QCOMPARE(textOf(rowText(root, 901)), QStringLiteral("Fresh A:91"));
    QCOMPARE(textOf(rowText(root, 902)), QStringLiteral("Fresh B:92"));
    QCOMPARE(view->status(), QQuickView::Ready);
    QCOMPARE(capturedMessages(), QString());
}

void SwiftQtMlTest::testPendingMutationThenTeardown()
{
    QString error;
    auto view = loadProbe(error);
    QVERIFY2(view != nullptr, qUtf8Printable(error));
    QObject *const root = view->rootObject();
    QVERIFY(invoke(root, "seedDefaultRows"));
    settle();

    QPointer<QObject> presenter(named(root, QStringLiteral("bridgeProbe")));
    QVERIFY(!presenter.isNull());
    QVERIFY(invoke(root, "mutateMiddleDirect"));

    QQuickView *const doomedView = view.release();
    doomedView->deleteLater();
    QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
    QCoreApplication::processEvents();
    settle();
    QVERIFY(presenter.isNull());
    const QString doomedMessages = capturedMessages();
    QCOMPARE(doomedMessages, QString());

    auto freshView = loadProbe(error);
    QVERIFY2(freshView != nullptr, qUtf8Printable(error));
    QObject *const freshRoot = freshView->rootObject();
    QVERIFY(invoke(freshRoot, "seedDefaultRows"));
    settle();
    QVERIFY2(rowText(freshRoot, 202) != nullptr,
             qUtf8Printable(probeDiagnostics(freshRoot, freshView.get())));
    QCOMPARE(textOf(rowText(freshRoot, 202)), QStringLiteral("Beta:20"));
    QCOMPARE(textOf(named(freshRoot, QStringLiteral("actionLogText"))), QString());
    QCOMPARE(capturedMessages(), QString());
}

void SwiftQtMlTest::testObjectReturnCapability()
{
    QString error;
    auto view = loadProbe(error);
    QVERIFY2(view != nullptr, qUtf8Printable(error));
    QObject *const root = view->rootObject();
    QVERIFY(invoke(root, "seedDefaultRows"));
    settle();

    QVERIFY(invoke(root, "inspectMadeRow"));
    settle();
    QCOMPARE(textOf(named(root, QStringLiteral("returnedTitleText"))), QStringLiteral("Returned"));

    QObject *const state = named(root, QStringLiteral("probeState"));
    QVERIFY(state != nullptr);
    QVERIFY(invoke(root, "inspectSelectedPresent"));
    settle();
    QCOMPARE(state->property("selectedIsNull").toBool(), false);
    QCOMPARE(textOf(named(root, QStringLiteral("selectedTitleText"))), QStringLiteral("Beta"));

    QVERIFY(invoke(root, "inspectSelectedMissing"));
    settle();
    QCOMPARE(state->property("selectedIsNull").toBool(), true);
    QCOMPARE(textOf(named(root, QStringLiteral("selectedTitleText"))), QStringLiteral("<null>"));
    QCOMPARE(capturedMessages(), QString());

    // Static M0 boundary assertion: object-argument slot invocation is
    // Unsupported (crashes) at this pin+patch. The evidence home is the M0
    // capability probe table in docs/plans/qtbridge-integration-contract.md.
    // On 2026-09-19, two pre-isolation parent-process runs observed SIGSEGV
    // from invoke(root, "attemptObjectArgumentCall"); lldb stopped in QtQml
    // OUTLINED_FUNCTION_2 while its accessor dereferenced a dead/garbage
    // object. Do not execute that process-killing probe in this check.
}

int runSwiftQtMlCheck(const QString &projectRoot, const QString &songA, const QString &songB,
                      const QStringList &qtArguments)
{
    Q_UNUSED(projectRoot)
    Q_UNUSED(songA)
    Q_UNUSED(songB)

    SwiftQtMlTest test;
    QStringList arguments = {QStringLiteral("swiftqtml")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
