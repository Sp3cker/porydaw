#pragma once

#include <QByteArray>
#include <QCoreApplication>
#include <QMetaObject>
#include <QString>
#include <QWidget>

#include <cstdio>
#include <cstdint>
#include <memory>

#include "core/miditimeline.h"
#include "core/songdocument.h"
#include "project/decompproject.h"
#include "ui/songview.h"
#include "checkinput.hpp"

struct UndoCheckpoint
{
    int index = 0;
};

class RollCheckFixture
{
public:
    explicit RollCheckFixture(const QString &songLabel)
        : m_songLabel(songLabel)
    {
    }

    ~RollCheckFixture()
    {
        m_view.setDocument(nullptr);
        m_view.setSong(nullptr, nullptr);
    }

    RollCheckFixture(const RollCheckFixture &) = delete;
    RollCheckFixture &operator=(const RollCheckFixture &) = delete;

    bool open(const QString &projectRoot, QString *error)
    {
        if (!m_project.open(projectRoot, error))
            return false;
        const auto *song = static_cast<const SongInfo *>(nullptr);
        for (const auto &candidate : m_project.songs())
        {
            if (candidate.label == m_songLabel && candidate.isPlayable())
                song = &candidate;
        }
        if (!song)
        {
            *error = QStringLiteral("no playable song %1").arg(m_songLabel);
            return false;
        }
        if (!m_document.load(*song, error))
            return false;
        m_baseline = m_document.smf().write();
        m_timeline = m_document.buildTimeline(48000.0);
        m_view.resize(1280, 800);
        m_view.setSong(m_timeline.get(), nullptr);
        m_view.setDocument(&m_document);
        m_documentChanged = QObject::connect(
            &m_document, &SongDocument::documentChanged, &m_view, [this]
            {
                auto rebuiltTimeline = m_document.buildTimeline(48000.0);
                m_view.updateSong(rebuiltTimeline.get());
                m_timeline = std::move(rebuiltTimeline);
            },
            Qt::DirectConnection);
        m_view.setGridMinDenom(4);
        m_view.show();
        QCoreApplication::processEvents();
        (void)m_view.grab();
        m_roll = m_view.findChild<QWidget *>(QStringLiteral("pianoRoll"));
        m_automationLanes =
            m_view.findChild<QWidget *>(QStringLiteral("automationArea"));
        if (!m_roll || m_roll->width() <= songview::kKeyboardW ||
            m_roll->height() <= 0)
        {
            fail("piano roll not found or not laid out");
            return false;
        }
        if (!check_input::focusShortcutTarget(*m_roll))
        {
            fail("shortcut focus contract failed: could not activate the piano-roll "
                 "window and focus its target");
            return false;
        }
        m_track = m_view.selectedTrack();
        if (m_document.engineTrackCount() <= m_track)
        {
            fail("no engine track to draw on");
            return false;
        }
        return true;
    }

    SongDocument &document()
    {
        return m_document;
    }

    SongView &view()
    {
        return m_view;
    }

    QWidget &roll()
    {
        return *m_roll;
    }

    QWidget *automationLanes()
    {
        return m_automationLanes;
    }

    const MidiTimeline &timeline() const
    {
        return *m_timeline;
    }

    int track() const
    {
        return m_track;
    }

    const QByteArray &baseline() const
    {
        return m_baseline;
    }

    void processEvents() const
    {
        QCoreApplication::processEvents();
    }

    void fail(const char *what)
    {
        std::fprintf(stderr, "rollcheck: FAIL %s: %s\n",
                     qUtf8Printable(m_songLabel), what);
        ++m_failures;
    }

    int failures() const
    {
        return m_failures;
    }

    UndoCheckpoint undoCheckpoint()
    {
        return {m_document.undoStack()->index()};
    }

    int activeUndoDelta(UndoCheckpoint checkpoint)
    {
        return m_document.undoStack()->index() - checkpoint.index;
    }

    void undoTo(UndoCheckpoint checkpoint)
    {
        while (m_document.undoStack()->index() > checkpoint.index)
            m_document.undoStack()->undo();
    }

    void verifyScenarioUndoAndBaseline(const char *scenario,
                                       UndoCheckpoint checkpoint,
                                       int expectedUndoDelta)
    {
        const auto actualUndoDelta = activeUndoDelta(checkpoint);
        if (actualUndoDelta != expectedUndoDelta)
        {
            const auto message =
                QStringLiteral("%1 pushed %2 undo commands; expected %3")
                    .arg(QString::fromLatin1(scenario))
                    .arg(actualUndoDelta)
                    .arg(expectedUndoDelta)
                    .toUtf8();
            fail(message.constData());
        }
        undoTo(checkpoint);
        if (m_document.smf().write() != m_baseline)
        {
            const auto message =
                QStringLiteral("%1 did not restore the original bytes after undo")
                    .arg(QString::fromLatin1(scenario))
                    .toUtf8();
            fail(message.constData());
        }
    }

private:
    DecompProject m_project;
    SongDocument m_document;
    std::unique_ptr<MidiTimeline> m_timeline;
    SongView m_view;
    QByteArray m_baseline;
    QString m_songLabel;
    QMetaObject::Connection m_documentChanged;
    QWidget *m_roll = nullptr;
    QWidget *m_automationLanes = nullptr;
    int m_track = -1;
    int m_failures = 0;
};

void runRollStaticViewScenario(RollCheckFixture &fixture);
void runRollDrawnNotesScenario(RollCheckFixture &fixture,
                               const QString &screenshotPath);
void runRollEditingScenario(RollCheckFixture &fixture);
void runRollNavigationScenario(RollCheckFixture &fixture);
void runRollTimeRangeScenario(RollCheckFixture &fixture);
void runRollTrackHeaderScenario(RollCheckFixture &fixture);
