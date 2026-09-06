#include "checks/midi/tst_midiroundtrip.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QTemporaryDir>
#include <QtTest>

#include "core/smf.h"

namespace {

bool compileMid(const QString &mid2agbPath, const QStringList &flags, const QString &midPath,
                QByteArray &assembly, QString &error)
{
    assembly.clear();
    error.clear();
    const QString outputPath = midPath.left(midPath.size() - 4) + QStringLiteral(".s");
    auto process = QProcess{};
    auto arguments = flags;
    arguments << midPath << outputPath;
    process.start(mid2agbPath, arguments);
    if (!process.waitForFinished(15000)) {
        error = QStringLiteral("mid2agb timed out");
        return false;
    }
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        error = QStringLiteral("mid2agb failed: %1")
                    .arg(QString::fromLocal8Bit(process.readAllStandardError()).trimmed());
        return false;
    }

    auto output = QFile{outputPath};
    if (!output.open(QIODevice::ReadOnly)) {
        error = QStringLiteral("mid2agb produced no output");
        return false;
    }
    assembly = output.readAll();
    return true;
}

bool writeBytes(const QString &path, const QByteArray &bytes, QString &error)
{
    auto file = QFile{path};
    if (!file.open(QIODevice::WriteOnly)) {
        error = QStringLiteral("cannot write %1: %2").arg(path, file.errorString());
        return false;
    }
    if (file.write(bytes) != bytes.size()) {
        error = QStringLiteral("incomplete write to %1: %2").arg(path, file.errorString());
        return false;
    }
    return true;
}

QString firstDiffLine(const QByteArray &left, const QByteArray &right)
{
    const QList<QByteArray> leftLines = left.split('\n');
    const QList<QByteArray> rightLines = right.split('\n');
    const int sharedCount = qMin(leftLines.size(), rightLines.size());
    for (int index = 0; index < sharedCount; ++index) {
        if (leftLines[index] != rightLines[index]) {
            return QStringLiteral("line %1: '%2' vs '%3'")
                .arg(index + 1)
                .arg(QString::fromLatin1(leftLines[index]).trimmed(),
                     QString::fromLatin1(rightLines[index]).trimmed());
        }
    }
    return QStringLiteral("line count %1 vs %2").arg(leftLines.size()).arg(rightLines.size());
}

} // namespace

MidiRoundtripTest::MidiRoundtripTest(QString projectRoot, QString mid2agbPath)
    : m_projectRoot(std::move(projectRoot))
    , m_mid2agbPath(std::move(mid2agbPath))
{}

void MidiRoundtripTest::initTestCase()
{
    QVERIFY2(!m_projectRoot.isEmpty(), "roundtrip requires a staged project root");
    auto error = QString{};
    QVERIFY2(m_project.open(m_projectRoot, &error), qPrintable(error));

    const auto compiler = QFileInfo{m_mid2agbPath};
    QVERIFY2(compiler.isFile(),
             qPrintable(QStringLiteral("mid2agb binary not found at %1").arg(m_mid2agbPath)));
    QVERIFY2(compiler.isExecutable(),
             qPrintable(QStringLiteral("mid2agb binary is not executable: %1").arg(m_mid2agbPath)));
}

void MidiRoundtripTest::songM2Roundtrip_data()
{
    QTest::addColumn<int>("songIndex");
    QVERIFY2(m_project.isOpen(), "roundtrip project did not open in initTestCase");

    int rows = 0;
    const auto &songs = m_project.songs();
    for (int index = 0; index < songs.size(); ++index) {
        const SongInfo &song = songs[index];
        if (!song.isPlayable())
            continue;
        QTest::newRow(qPrintable(song.label)) << index;
        ++rows;
    }
    QVERIFY2(rows > 0, "roundtrip project contains no playable MIDI songs");
}

void MidiRoundtripTest::songM2Roundtrip()
{
    QFETCH(int, songIndex);
    const auto &songs = m_project.songs();
    QVERIFY2(songIndex >= 0 && songIndex < songs.size(), "roundtrip song data row is out of range");
    const SongInfo &song = songs[songIndex];
    QVERIFY2(song.isPlayable(), "roundtrip data row is not playable");

    auto originalFile = QFile{song.midPath};
    QVERIFY2(originalFile.open(QIODevice::ReadOnly),
             qPrintable(QStringLiteral("cannot read %1").arg(song.midPath)));
    const QByteArray originalBytes = originalFile.readAll();

    auto smf = SmfFile{};
    auto error = QString{};
    QVERIFY2(SmfFile::read(originalBytes, &smf, &error), qPrintable(error));
    const QByteArray savedBytes = smf.write();

    auto scratch = QTemporaryDir{};
    QVERIFY2(scratch.isValid(), "could not create per-song roundtrip scratch directory");
    const auto scratchDir = QDir{scratch.path()};
    QVERIFY2(scratchDir.mkpath(QStringLiteral("orig")), "could not create original MIDI directory");
    QVERIFY2(scratchDir.mkpath(QStringLiteral("saved")), "could not create saved MIDI directory");

    const QString name = QFileInfo{song.midPath}.fileName();
    QVERIFY2(name.endsWith(QStringLiteral(".mid"), Qt::CaseInsensitive),
             qPrintable(QStringLiteral("playable song has a non-MIDI path: %1").arg(song.midPath)));
    const QString originalMidi = scratchDir.filePath(QStringLiteral("orig/") + name);
    const QString savedMidi = scratchDir.filePath(QStringLiteral("saved/") + name);
    QVERIFY2(writeBytes(originalMidi, originalBytes, error), qPrintable(error));
    QVERIFY2(writeBytes(savedMidi, savedBytes, error), qPrintable(error));

    auto originalAssembly = QByteArray{};
    QVERIFY2(compileMid(m_mid2agbPath, song.cfg.rawFlags, originalMidi, originalAssembly, error),
             qPrintable(QStringLiteral("%1 original: %2").arg(song.label, error)));
    auto savedAssembly = QByteArray{};
    QVERIFY2(compileMid(m_mid2agbPath, song.cfg.rawFlags, savedMidi, savedAssembly, error),
             qPrintable(QStringLiteral("%1 saved: %2").arg(song.label, error)));
    QVERIFY2(originalAssembly == savedAssembly,
             qPrintable(QStringLiteral("%1 assembly differs — %2")
                            .arg(song.label, firstDiffLine(originalAssembly, savedAssembly))));
}

int runRoundTrip(const QString &projectRoot, const QString &mid2agbPath,
                 const QStringList &qtArguments)
{
    auto test = MidiRoundtripTest{projectRoot, mid2agbPath};
    auto arguments = QStringList{QStringLiteral("roundtrip")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
