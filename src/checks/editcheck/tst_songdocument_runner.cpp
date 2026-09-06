#include "checks/editcheck/tst_songdocument.h"

#include <QtTest>
#include <utility>

#include "checks/editcheck/tst_songdocument_support.h"

EditCheckTest::EditCheckTest(QString projectRoot) : m_projectRoot(std::move(projectRoot)) {}

void EditCheckTest::initTestCase()
{
    QVERIFY2(!m_projectRoot.isEmpty(), "editcheck requires its staged project root");

    DecompProject project;
    QString error;
    QVERIFY2(project.open(m_projectRoot, &error), qPrintable(error));
    m_songs = project.songs();
    for (const SongInfo &song : m_songs) {
        if (!song.isPlayable())
            continue;
        PlayableSong playable;
        playable.info = song;
        SongDocument document;
        QVERIFY2(document.load(song, &error), qPrintable(error));
        SongEligibility &eligibility = playable.eligibility;
        eligibility.editableTrack = songdocument_test::firstEditableTrack(document) >= 0;
        eligibility.canAddTrack = document.canAddTrack();
        eligibility.multiTrack = document.engineTrackCount() >= 2;
        m_playableSongs.push_back(playable);
    }
    QVERIFY2(!m_playableSongs.isEmpty(), "editcheck corpus staged no playable songs");
}

void EditCheckTest::addSongRows(SongCapability capability) const
{
    QTest::addColumn<QString>("songLabel");
    int rows = 0;
    for (const PlayableSong &song : m_playableSongs) {
        if (!eligible(song, capability))
            continue;
        QTest::newRow(song.info.label.toUtf8().constData()) << song.info.label;
        ++rows;
    }
    if (rows == 0) {
        // A required contract family with no eligible song must fail
        // loudly, never pass vacuously.
        QTest::newRow("required") << QString();
    }
}

bool EditCheckTest::eligible(const PlayableSong &song, SongCapability capability) const
{
    const SongEligibility &shape = song.eligibility;
    switch (capability) {
    case SongCapability::Playable:
        return true;
    case SongCapability::EditableTrack:
        return shape.editableTrack;
    case SongCapability::AddTrack:
        return shape.canAddTrack;
    case SongCapability::DuplicateTrack:
        return shape.editableTrack && shape.canAddTrack;
    case SongCapability::ReorderableTrack:
        return shape.editableTrack && shape.multiTrack;
    }
    return false;
}

SongInfo EditCheckTest::songForLabel(const QString &label) const
{
    for (const SongInfo &song : m_songs) {
        if (song.label == label)
            return song;
    }
    return {};
}

int runEditCheck(const QStringList &checkArguments, const QStringList &qtArguments)
{
    EditCheckTest test(checkArguments.value(0));
    QStringList arguments{QStringLiteral("editcheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

int runScaleCheck(const QStringList &checkArguments, const QStringList &qtArguments)
{
    Q_UNUSED(checkArguments);
    ScaleCheckTest test;
    QStringList arguments{QStringLiteral("scalecheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

int runNoteIdentityCheck(const QStringList &checkArguments, const QStringList &qtArguments)
{
    Q_UNUSED(checkArguments);
    NoteIdentityCheckTest test;
    QStringList arguments{QStringLiteral("noteidcheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
