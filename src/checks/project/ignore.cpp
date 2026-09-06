#include <QtTest>

#include <QByteArray>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTemporaryDir>

#include <memory>
#include <optional>

#include "project/sidecar.h"

namespace {

bool writeFile(const QString &path, const QByteArray &bytes)
{
    if (!QDir().mkpath(QFileInfo(path).path()))
        return false;
    QFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size();
}

QByteArray readFileBytes(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return file.readAll();
}

class SidecarIgnoreTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(SidecarIgnoreTest)

  public:
    SidecarIgnoreTest() = default;

  private slots:
    void init();
    void cleanup();
    void appendsToExistingLfFile();
    void alreadyPresentSpellingsAreByteNoops_data();
    void alreadyPresentSpellingsAreByteNoops();
    void createsMissingIgnoreFile();
    void nonRepoCreatesSidecarOnly();
    void preservesCrlfOnAppend();
    void repairsMissingTrailingNewline();
    void gitFileCountsAsRepository();
    void subdirectoryAndSecondCallAreByteNoops();
    void commentedEntryDoesNotCountAsPresent();

  private:
    std::optional<QString> freshRoot(bool gitDirectory, QString &error) const;
    static QString ignorePath(const QString &root);

    std::unique_ptr<QTemporaryDir> m_scratch;
};

std::optional<QString> SidecarIgnoreTest::freshRoot(bool gitDirectory, QString &error) const
{
    const QString root = m_scratch->path() + QStringLiteral("/project");
    if (QFileInfo::exists(root)) {
        error = QStringLiteral("synthetic root already exists: %1").arg(root);
        return std::nullopt;
    }
    if (!QDir().mkpath(root)) {
        error = QStringLiteral("could not create synthetic root: %1").arg(root);
        return std::nullopt;
    }
    if (gitDirectory && !QDir().mkpath(root + QStringLiteral("/.git"))) {
        error = QStringLiteral("could not create synthetic .git directory");
        return std::nullopt;
    }
    return root;
}

QString SidecarIgnoreTest::ignorePath(const QString &root)
{
    return root + QStringLiteral("/.gitignore");
}

void SidecarIgnoreTest::init()
{
    m_scratch = std::make_unique<QTemporaryDir>();
    QVERIFY2(m_scratch->isValid(), "could not create isolated ignore fixture");
}

void SidecarIgnoreTest::cleanup()
{
    m_scratch.reset();
}

void SidecarIgnoreTest::appendsToExistingLfFile()
{
    QString error;
    const std::optional<QString> root = freshRoot(true, error);
    QVERIFY2(root, qPrintable(error));
    if (!root)
        return;
    QVERIFY(writeFile(ignorePath(*root), "*.o\nbuild/\n"));
    QVERIFY(Sidecar::ensureDir(*root));
    QVERIFY(QDir(*root + QStringLiteral("/.porydaw")).exists());
    QCOMPARE(readFileBytes(ignorePath(*root)), QByteArray("*.o\nbuild/\n.porydaw/\n"));
}

void SidecarIgnoreTest::alreadyPresentSpellingsAreByteNoops_data()
{
    QTest::addColumn<QByteArray>("spelling");
    QTest::newRow("bare") << QByteArray(".porydaw");
    QTest::newRow("directory") << QByteArray(".porydaw/");
    QTest::newRow("anchored-bare") << QByteArray("/.porydaw");
    QTest::newRow("anchored-directory") << QByteArray("/.porydaw/");
}

void SidecarIgnoreTest::alreadyPresentSpellingsAreByteNoops()
{
    QFETCH(QByteArray, spelling);
    QString error;
    const std::optional<QString> root = freshRoot(true, error);
    QVERIFY2(root, qPrintable(error));
    if (!root)
        return;
    const QByteArray before = QByteArray("*.o\n") + spelling + "\nbuild/\n";
    QVERIFY(writeFile(ignorePath(*root), before));
    QVERIFY(Sidecar::ensureDir(*root));
    QCOMPARE(readFileBytes(ignorePath(*root)), before);
}

void SidecarIgnoreTest::createsMissingIgnoreFile()
{
    QString error;
    const std::optional<QString> root = freshRoot(true, error);
    QVERIFY2(root, qPrintable(error));
    if (!root)
        return;
    QVERIFY(Sidecar::ensureDir(*root));
    QCOMPARE(readFileBytes(ignorePath(*root)), QByteArray(".porydaw/\n"));
}

void SidecarIgnoreTest::nonRepoCreatesSidecarOnly()
{
    QString error;
    const std::optional<QString> root = freshRoot(false, error);
    QVERIFY2(root, qPrintable(error));
    if (!root)
        return;
    QVERIFY(Sidecar::ensureDir(*root));
    QVERIFY(QDir(*root + QStringLiteral("/.porydaw")).exists());
    QVERIFY(!QFileInfo::exists(ignorePath(*root)));
}

void SidecarIgnoreTest::preservesCrlfOnAppend()
{
    QString error;
    const std::optional<QString> root = freshRoot(true, error);
    QVERIFY2(root, qPrintable(error));
    if (!root)
        return;
    QVERIFY(writeFile(ignorePath(*root), "*.o\r\nbuild/\r\n"));
    QVERIFY(Sidecar::ensureDir(*root));
    QCOMPARE(readFileBytes(ignorePath(*root)), QByteArray("*.o\r\nbuild/\r\n.porydaw/\r\n"));
}

void SidecarIgnoreTest::repairsMissingTrailingNewline()
{
    QString error;
    const std::optional<QString> root = freshRoot(true, error);
    QVERIFY2(root, qPrintable(error));
    if (!root)
        return;
    QVERIFY(writeFile(ignorePath(*root), "*.o\nbuild/"));
    QVERIFY(Sidecar::ensureDir(*root));
    QCOMPARE(readFileBytes(ignorePath(*root)), QByteArray("*.o\nbuild/\n.porydaw/\n"));
}

void SidecarIgnoreTest::gitFileCountsAsRepository()
{
    QString error;
    const std::optional<QString> root = freshRoot(false, error);
    QVERIFY2(root, qPrintable(error));
    if (!root)
        return;
    QVERIFY(writeFile(*root + QStringLiteral("/.git"), "gitdir: ../.git/worktrees/proj\n"));
    QVERIFY(Sidecar::ensureDir(*root));
    QCOMPARE(readFileBytes(ignorePath(*root)), QByteArray(".porydaw/\n"));
}

void SidecarIgnoreTest::subdirectoryAndSecondCallAreByteNoops()
{
    QString error;
    const std::optional<QString> root = freshRoot(true, error);
    QVERIFY2(root, qPrintable(error));
    if (!root)
        return;
    QVERIFY(Sidecar::ensureDir(*root, QStringLiteral("samples")));
    QVERIFY(QDir(*root + QStringLiteral("/.porydaw/samples")).exists());
    const QByteArray once = readFileBytes(ignorePath(*root));
    QCOMPARE(once, QByteArray(".porydaw/\n"));
    QVERIFY(Sidecar::ensureDir(*root));
    QCOMPARE(readFileBytes(ignorePath(*root)), once);
}

void SidecarIgnoreTest::commentedEntryDoesNotCountAsPresent()
{
    QString error;
    const std::optional<QString> root = freshRoot(true, error);
    QVERIFY2(root, qPrintable(error));
    if (!root)
        return;
    QVERIFY(writeFile(ignorePath(*root), "# .porydaw/\n"));
    QVERIFY(Sidecar::ensureDir(*root));
    QCOMPARE(readFileBytes(ignorePath(*root)), QByteArray("# .porydaw/\n.porydaw/\n"));
}

} // namespace

int runIgnoreCheck(const QStringList &qtArguments)
{
    SidecarIgnoreTest test;
    QStringList arguments{QStringLiteral("sidecar-ignore")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "ignore.moc"
