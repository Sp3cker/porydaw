#include <QtTest>

#include <QUndoCommand>
#include <QUndoStack>

#include <memory>
#include <optional>

#include "core/songhistory.h"
#include "project/projectidentity.h"

namespace {

class HistoryCountCommand final : public QUndoCommand
{
  public:
    HistoryCountCommand(int *value, int delta, int gestureId)
        : QUndoCommand(QStringLiteral("count"))
        , m_value(value)
        , m_delta(delta)
        , m_gestureId(gestureId)
    {}

    int id() const override { return m_gestureId; }
    void redo() override { *m_value += m_delta; }
    void undo() override { *m_value -= m_delta; }
    bool mergeWith(const QUndoCommand *other) override
    {
        const auto *const command = dynamic_cast<const HistoryCountCommand *>(other);
        if (!command)
            return false;
        m_delta += command->m_delta;
        setObsolete(m_delta == 0);
        return true;
    }

  private:
    int *m_value;
    int m_delta;
    int m_gestureId;
};

constexpr int kFirstGesture = 0x6863;  // 'hc'
constexpr int kSecondGesture = 0x6864; // 'hd'

void pushMergedCount(SongHistory &history, int &value)
{
    history.pushDocument(std::make_unique<HistoryCountCommand>(&value, 1, kFirstGesture));
    history.pushDocument(std::make_unique<HistoryCountCommand>(&value, 2, kFirstGesture));
}

class ProjectIdentityTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(ProjectIdentityTest)

  public:
    ProjectIdentityTest() = default;

  private slots:
    void songName_acceptRejectRoundtripHash();
    void voicegroupId_rejections_data();
    void voicegroupId_rejections();
    void voicegroupId_normalizationAndSectionHash();
    void savedRecipe_dedupOrderSelection();
    void savedRecipe_selectionFallbacks();
    void savedRecipe_legacySingleLabelAndEmpty();
    void songHistory_startsClean();
    void songHistory_mergePreservesOldestBeforeFreshAfter();
    void songHistory_savedBoundaryRefusesMerge();
    void songHistory_cancellingMergeRemovesEntry();
};

void ProjectIdentityTest::songName_acceptRejectRoundtripHash()
{
    QVERIFY(!SongName::create(QString{}).has_value());

    const std::optional<SongName> first = SongName::create(QStringLiteral("intro"));
    const std::optional<SongName> same = SongName::create(QStringLiteral("intro"));
    const std::optional<SongName> different = SongName::create(QStringLiteral("outro"));
    QVERIFY(first);
    QVERIFY(same);
    QVERIFY(different);
    if (!(first && same && different))
        return;

    QCOMPARE(first->value(), QStringLiteral("intro"));
    QVERIFY(*first == *same);
    QVERIFY(*first != *different);
    QVERIFY(qHash(*first) == qHash(*same));
}

void ProjectIdentityTest::voicegroupId_rejections_data()
{
    QTest::addColumn<QString>("sourcePath");
    QTest::newRow("empty") << QString{};
    QTest::newRow("absolute") << QStringLiteral("/abs/perc.vg");
    QTest::newRow("parent") << QStringLiteral("..");
    QTest::newRow("parent-file") << QStringLiteral("../escape.vg");
    QTest::newRow("nested-parent") << QStringLiteral("drums/../../escape.vg");
    QTest::newRow("project-root") << QStringLiteral(".");
    QTest::newRow("normalizes-to-root") << QStringLiteral("./");
}

void ProjectIdentityTest::voicegroupId_rejections()
{
    QFETCH(QString, sourcePath);
    QVERIFY(!VoicegroupId::create(sourcePath, QString{}).has_value());
}

void ProjectIdentityTest::voicegroupId_normalizationAndSectionHash()
{
    const std::optional<VoicegroupId> normalized =
        VoicegroupId::create(QStringLiteral("./drums//shared/../perc.vg"), QString{});
    QVERIFY(normalized);
    if (!normalized)
        return;
    QCOMPARE(normalized->sourceRelativePath(), QStringLiteral("drums/perc.vg"));
    QVERIFY(normalized->sectionLabel().isEmpty());

    const std::optional<VoicegroupId> kick =
        VoicegroupId::create(QStringLiteral("drums/perc.vg"), QStringLiteral("kick"));
    const std::optional<VoicegroupId> sameKick =
        VoicegroupId::create(QStringLiteral("drums/./perc.vg"), QStringLiteral("kick"));
    const std::optional<VoicegroupId> snare =
        VoicegroupId::create(QStringLiteral("drums/perc.vg"), QStringLiteral("snare"));
    QVERIFY(kick);
    QVERIFY(sameKick);
    QVERIFY(snare);
    if (!(kick && sameKick && snare))
        return;

    QCOMPARE(kick->sectionLabel(), QStringLiteral("kick"));
    QVERIFY(*kick == *sameKick);
    QVERIFY(*kick != *snare);
    QVERIFY(qHash(*kick) == qHash(*sameKick));
}

void ProjectIdentityTest::savedRecipe_dedupOrderSelection()
{
    const SavedWorkspaceRecipe recipe =
        normalizeSavedRecipe(QStringLiteral("/projects/demo"),
                             {QStringLiteral("b"), QString{}, QStringLiteral("a"),
                              QStringLiteral("b"), QStringLiteral("c"), QStringLiteral("a")},
                             QStringLiteral("a"));
    QCOMPARE(recipe.projectPath, QStringLiteral("/projects/demo"));
    QCOMPARE(recipe.orderedSongs.size(), 3);
    if (recipe.orderedSongs.size() != 3)
        return;
    QCOMPARE(recipe.orderedSongs[0].value(), QStringLiteral("b"));
    QCOMPARE(recipe.orderedSongs[1].value(), QStringLiteral("a"));
    QCOMPARE(recipe.orderedSongs[2].value(), QStringLiteral("c"));
    QVERIFY(recipe.selected);
    if (recipe.selected)
        QCOMPARE(recipe.selected->value(), QStringLiteral("a"));
}

void ProjectIdentityTest::savedRecipe_selectionFallbacks()
{
    const SavedWorkspaceRecipe missing = normalizeSavedRecipe(
        QString{}, {QStringLiteral("a"), QStringLiteral("b")}, QStringLiteral("gone"));
    QVERIFY(missing.selected);
    if (missing.selected)
        QCOMPARE(missing.selected->value(), QStringLiteral("a"));

    const SavedWorkspaceRecipe empty =
        normalizeSavedRecipe(QString{}, {QStringLiteral("a"), QStringLiteral("b")}, QString{});
    QVERIFY(empty.selected);
    if (empty.selected)
        QCOMPARE(empty.selected->value(), QStringLiteral("a"));
}

void ProjectIdentityTest::savedRecipe_legacySingleLabelAndEmpty()
{
    const SavedWorkspaceRecipe legacy =
        normalizeSavedRecipe(QString{}, {QString{}, QString{}}, QStringLiteral("solo"));
    QCOMPARE(legacy.orderedSongs.size(), 1);
    if (legacy.orderedSongs.size() == 1)
        QCOMPARE(legacy.orderedSongs[0].value(), QStringLiteral("solo"));
    QVERIFY(legacy.selected);
    if (legacy.selected)
        QCOMPARE(legacy.selected->value(), QStringLiteral("solo"));

    const SavedWorkspaceRecipe empty = normalizeSavedRecipe(QString{}, {}, QString{});
    QVERIFY(empty.orderedSongs.isEmpty());
    QVERIFY(!empty.selected);
}

void ProjectIdentityTest::songHistory_startsClean()
{
    QUndoStack stack;
    SongHistory history(stack);
    QVERIFY(history.currentDocumentIdentity() == history.savedDocumentIdentity());
}

void ProjectIdentityTest::songHistory_mergePreservesOldestBeforeFreshAfter()
{
    QUndoStack stack;
    SongHistory history(stack);
    int value = 0;
    const DocumentStateIdentity base = history.savedDocumentIdentity();

    pushMergedCount(history, value);
    const DocumentStateIdentity merged = history.currentDocumentIdentity();
    QCOMPARE(stack.count(), 1);
    QCOMPARE(value, 3);
    QVERIFY(merged != base);

    stack.undo();
    QCOMPARE(value, 0);
    QVERIFY(history.currentDocumentIdentity() == base);
    stack.redo();
    QCOMPARE(value, 3);
    QVERIFY(history.currentDocumentIdentity() == merged);
}

void ProjectIdentityTest::songHistory_savedBoundaryRefusesMerge()
{
    QUndoStack stack;
    SongHistory history(stack);
    int value = 0;

    pushMergedCount(history, value);
    const DocumentStateIdentity merged = history.currentDocumentIdentity();
    history.markDocumentSaved(merged);
    history.pushDocument(std::make_unique<HistoryCountCommand>(&value, 4, kFirstGesture));
    const DocumentStateIdentity afterRefusal = history.currentDocumentIdentity();
    QCOMPARE(stack.count(), 2);
    QCOMPARE(value, 7);
    QVERIFY(afterRefusal != merged);

    stack.undo();
    QCOMPARE(value, 3);
    QVERIFY(history.currentDocumentIdentity() == merged);
}

void ProjectIdentityTest::songHistory_cancellingMergeRemovesEntry()
{
    QUndoStack stack;
    SongHistory history(stack);
    int value = 0;

    pushMergedCount(history, value);
    history.markDocumentSaved(history.currentDocumentIdentity());
    history.pushDocument(std::make_unique<HistoryCountCommand>(&value, 4, kFirstGesture));
    const DocumentStateIdentity afterRefusal = history.currentDocumentIdentity();
    history.pushDocument(std::make_unique<HistoryCountCommand>(&value, 1, kSecondGesture));
    history.pushDocument(std::make_unique<HistoryCountCommand>(&value, -1, kSecondGesture));

    QCOMPARE(stack.count(), 2);
    QCOMPARE(value, 7);
    QVERIFY(history.currentDocumentIdentity() == afterRefusal);
}

} // namespace

int runProjectIdentityCheck(const QStringList &qtArguments)
{
    ProjectIdentityTest test;
    QStringList arguments{QStringLiteral("project-identity")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "identity.moc"
