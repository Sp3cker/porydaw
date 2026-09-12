#include <QtTest>

#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QUndoStack>

#include <algorithm>
#include <cstdint>
#include <limits>
#include <memory>
#include <optional>

#include "checks/support/songfixture.h"
#include "core/songdocument.h"

namespace {

QByteArray readFileBytes(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return file.readAll();
}

int firstNonemptyTrack(const SongDocument &document)
{
    for (int track = 0; track < document.engineTrackCount(); ++track)
        if (!document.notesForTrack(track).empty())
            return track;
    return -1;
}

struct EditWindow {
    int track = -1;
    uint64_t base = 0;
};

std::optional<EditWindow> emptyTailWindow(const SongDocument &document, int track)
{
    uint64_t lastEnd = 0;
    for (const SmfTrack &smfTrack : document.smf().tracks)
        lastEnd = std::max(lastEnd, uint64_t(smfTrack.endTick));
    constexpr uint64_t kRequiredTail = 96 + 528;
    if (lastEnd > std::numeric_limits<uint64_t>::max() - kRequiredTail)
        return std::nullopt;

    const uint64_t base = lastEnd + 96;
    const uint64_t windowEnd = base + 528;
    for (const DocNote &note : document.notesForTrack(track))
        if (note.tick < windowEnd && document.noteEndTick(note) > base)
            return std::nullopt;
    return EditWindow{track, base};
}

struct SavedEdit {
    EditWindow window;
    uint64_t expectedLoopStart = 0;
    QString cfgPath;
    QList<QByteArray> cfgBefore;
};

bool saveEditedDocument(SongDocument &document, const EditWindow &window, SavedEdit &saved,
                        QString &error)
{
    saved.window = window;
    saved.cfgPath = QFileInfo(document.midPath()).dir().filePath(QStringLiteral("midi.cfg"));
    saved.cfgBefore = readFileBytes(saved.cfgPath).split('\n');

    document.addNote(window.track, window.base, 72, 24, 93);
    const uint64_t oldLoopStart = document.loopTick(false);
    saved.expectedLoopStart =
        oldLoopStart == std::numeric_limits<uint64_t>::max() ? 0 : oldLoopStart + 24;
    document.setLoopTick(false, static_cast<int64_t>(saved.expectedLoopStart));
    SongCfg cfg = document.cfg();
    cfg.masterVolume = 111;
    document.setCfg(cfg);
    return document.save(&error);
}

bool isExactSongCfgLine(const QByteArray &line, const QString &songLabel)
{
    return line.startsWith(songLabel.toUtf8() + ".mid:");
}

class ProjectSaveTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(ProjectSaveTest)

  public:
    ProjectSaveTest(QString stagedRoot, QString songLabel, QString mid2agbPath)
        : m_stagedRoot(std::move(stagedRoot))
        , m_songLabel(std::move(songLabel))
        , m_mid2agbPath(std::move(mid2agbPath))
    {}

  private slots:
    void init();
    void cleanup();
    void saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes();
    void savedIdentityUndoRedoAndStaleSnapshot();
    void savedMidiCompilesWhenAvailable();

  private:
    std::unique_ptr<checks::LoadedSong> load(QString &error) const;
    std::optional<EditWindow> requireEmptyTail(SongDocument &document, QString &reason) const;

    QString m_stagedRoot;
    QString m_songLabel;
    QString m_mid2agbPath;
    std::unique_ptr<checks::ProjectFixture> m_project;
};

std::unique_ptr<checks::LoadedSong> ProjectSaveTest::load(QString &error) const
{
    return checks::LoadedSong::load(m_project->root(), m_songLabel, error);
}

std::optional<EditWindow> ProjectSaveTest::requireEmptyTail(SongDocument &document,
                                                            QString &reason) const
{
    const int track = firstNonemptyTrack(document);
    if (track < 0) {
        reason = QStringLiteral("fixture song has no nonempty engine track");
        return std::nullopt;
    }
    const std::optional<EditWindow> window = emptyTailWindow(document, track);
    if (!window)
        reason = QStringLiteral(
            "fixture has no collision-free [base, base + 528) tail for the save identity edits");
    return window;
}

void ProjectSaveTest::init()
{
    QString error;
    m_project = checks::ProjectFixture::copyOf(m_stagedRoot, error);
    QVERIFY2(m_project, qPrintable(error));
}

void ProjectSaveTest::cleanup()
{
    m_project.reset();
}

void ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes()
{
    QString error;
    std::unique_ptr<checks::LoadedSong> loaded = load(error);
    QVERIFY2(loaded, qPrintable(error));
    if (!loaded)
        return;
    SongDocument &document = loaded->document();
    const std::optional<EditWindow> window = requireEmptyTail(document, error);
    if (!window) {
        if (error.startsWith(QStringLiteral("fixture has no collision-free")))
            QSKIP(qPrintable(error));
        QFAIL(qPrintable(error));
    }

    SavedEdit saved;
    QVERIFY2(saveEditedDocument(document, *window, saved, error), qPrintable(error));
    QVERIFY(!document.isDirty());

    std::unique_ptr<checks::LoadedSong> reloaded = load(error);
    QVERIFY2(reloaded, qPrintable(error));
    if (!reloaded)
        return;
    SongDocument &afterReload = reloaded->document();
    DocNote savedNote;
    QVERIFY(afterReload.findNote(saved.window.track, saved.window.base, 72, &savedNote));
    QCOMPARE(savedNote.velocity, 93);
    QCOMPARE(savedNote.duration, 24);
    QCOMPARE(afterReload.cfg().masterVolume, 111);
    QCOMPARE(afterReload.loopTick(false), saved.expectedLoopStart);

    const QList<QByteArray> cfgAfter = readFileBytes(saved.cfgPath).split('\n');
    QCOMPARE(cfgAfter.size(), saved.cfgBefore.size());
    if (cfgAfter.size() != saved.cfgBefore.size())
        return;
    for (qsizetype index = 0; index < cfgAfter.size(); ++index) {
        const bool isSongLine = isExactSongCfgLine(saved.cfgBefore[index], m_songLabel);
        if (!isSongLine)
            QCOMPARE(cfgAfter[index], saved.cfgBefore[index]);
    }
}

void ProjectSaveTest::savedIdentityUndoRedoAndStaleSnapshot()
{
    QString error;
    std::unique_ptr<checks::LoadedSong> loaded = load(error);
    QVERIFY2(loaded, qPrintable(error));
    if (!loaded)
        return;
    SongDocument &document = loaded->document();
    const std::optional<EditWindow> window = requireEmptyTail(document, error);
    if (!window) {
        if (error.startsWith(QStringLiteral("fixture has no collision-free")))
            QSKIP(qPrintable(error));
        QFAIL(qPrintable(error));
    }

    SavedEdit saved;
    QVERIFY2(saveEditedDocument(document, *window, saved, error), qPrintable(error));
    QVERIFY(!document.isDirty());
    const int savedUndoCount = document.undoStack()->count();

    document.addNote(saved.window.track, saved.window.base + 480, 74, 24, 90);
    QVERIFY(document.isDirty());
    document.undoStack()->undo();
    QVERIFY(!document.isDirty());
    document.undoStack()->redo();
    QVERIFY(document.isDirty());

    const SongSaveSnapshot stale = document.captureSaveSnapshot();
    document.addNote(saved.window.track, saved.window.base + 504, 76, 24, 90);
    document.didSave(stale, true);
    QVERIFY(document.isDirty());
    document.undoStack()->undo();
    QVERIFY(document.isDirty());
    document.undoStack()->undo();
    QVERIFY(!document.isDirty());
    QCOMPARE(document.undoStack()->count(), savedUndoCount + 2);
}

void ProjectSaveTest::savedMidiCompilesWhenAvailable()
{
    QString error;
    std::unique_ptr<checks::LoadedSong> loaded = load(error);
    QVERIFY2(loaded, qPrintable(error));
    if (!loaded)
        return;
    SongDocument &document = loaded->document();
    const std::optional<EditWindow> window = requireEmptyTail(document, error);
    if (!window) {
        if (error.startsWith(QStringLiteral("fixture has no collision-free")))
            QSKIP(qPrintable(error));
        QFAIL(qPrintable(error));
    }

    SavedEdit saved;
    QVERIFY2(saveEditedDocument(document, *window, saved, error), qPrintable(error));
    const QString mid2agb = m_mid2agbPath.isEmpty()
                                ? m_project->root() + QStringLiteral("/tools/mid2agb/mid2agb")
                                : m_mid2agbPath;
    if (!QFileInfo::exists(mid2agb))
        QSKIP(qPrintable(QStringLiteral("mid2agb is unavailable at %1").arg(mid2agb)));

    QStringList arguments = document.cfg().rawFlags;
    const QString outSource =
        document.midPath().left(document.midPath().size() - 4) + QStringLiteral(".s");
    arguments << document.midPath() << outSource;
    QProcess compiler;
    compiler.start(mid2agb, arguments);
    QVERIFY2(compiler.waitForStarted(15000), qPrintable(compiler.errorString()));
    QVERIFY2(compiler.waitForFinished(15000), qPrintable(compiler.errorString()));
    QCOMPARE(compiler.exitStatus(), QProcess::NormalExit);
    QCOMPARE(compiler.exitCode(), 0);
}

} // namespace

int runSaveCheck(const QString &stagedRoot, const QString &songLabel, const QString &mid2agbPath,
                 const QStringList &qtArguments)
{
    ProjectSaveTest test(stagedRoot, songLabel, mid2agbPath);
    QStringList arguments{QStringLiteral("project-save")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "save.moc"
