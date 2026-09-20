// Visual baseline check for the standalone widget-window fixtures the
// prototype's "Standalone Widget Fixture" drop-down opens. Each kind is built
// by the shared sgw_createWindowFixture factory (the same code the prototype
// launches), shown non-modally, and frozen through checks::visual::compare so
// the QWidget→QML port has a per-window appearance contract.
//
// The three file dialogs are captured with DontUseNativeDialog: the native
// macOS panel is an OS-rendered NSWindow that QWidget::grab cannot see, so the
// baseline pins the Qt fallback the fixture configures. Everything else is a
// real QWidget surface.

#include "checks/visual/visualbaseline.h"
#include "checks/visual/visualfixture.h"

#include <QApplication>
#include <QCoreApplication>
#include <QDialog>
#include <QFileDialog>
#include <QList>
#include <QString>
#include <QTemporaryDir>
#include <QtTest>

#include <memory>

#include "widget_window_fixtures.h"

namespace {

// Every fixture kind this check freezes, each with its baseline id: the one
// place kind numbers and frozen identifiers meet.
struct FixtureKind {
    int kind;
    const char *id;
};

constexpr FixtureKind kFixtureKinds[] = {
    {SgwWindowSettings, "windowfixture/settings"},
    {SgwWindowSampleEditor, "windowfixture/sample-editor"},
    {SgwWindowSf2Picker, "windowfixture/sf2-picker"},
    {SgwWindowImportMidi, "windowfixture/import-midi"},
    {SgwWindowNewVoicegroup, "windowfixture/new-voicegroup"},
    {SgwWindowExportWav, "windowfixture/export-wav"},
    {SgwWindowProgress, "windowfixture/progress"},
    {SgwWindowOpenFile, "windowfixture/open-file"},
    {SgwWindowSaveFile, "windowfixture/save-file"},
    {SgwWindowDirectory, "windowfixture/directory"},
    {SgwWindowConfirmation, "windowfixture/confirmation"},
    {SgwWindowError, "windowfixture/error"},
    {SgwWindowAbout, "windowfixture/about"},
};

// The frozen baseline id for `kind`; empty for a kind the table does not know,
// which expectFixture turns into a loud failure.
QString kindId(int kind)
{
    for (const FixtureKind &entry : kFixtureKinds)
        if (entry.kind == kind)
            return QString::fromLatin1(entry.id);
    return {};
}

// Directory the file dialogs list: empty by construction on every run, which
// the caller's working directory is not. The test object owns the
// QTemporaryDir and publishes its path here, because the configuration hook is
// a plain function pointer and cannot capture the test object.
QString g_emptyFixtureDirectoryPath;

// Configure a file-dialog fixture for capture: the Qt fallback panel (the
// native macOS one is not a QWidget surface) listing that empty directory.
void configureFileDialog(QDialog &dialog)
{
    auto *file = qobject_cast<QFileDialog *>(&dialog);
    QVERIFY2(file, qPrintable(QStringLiteral("fixture dialog %1 is not a QFileDialog")
                                  .arg(QString::fromLatin1(dialog.metaObject()->className()))));
    file->setOption(QFileDialog::DontUseNativeDialog, true);
    file->setDirectory(g_emptyFixtureDirectoryPath);
}

} // namespace

class VisualWindowFixturesTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(VisualWindowFixturesTest)

  public:
    VisualWindowFixturesTest() = default;

  private slots:
    void initTestCase();

    void settingsFixture();
    void sampleEditorFixture();
    void sf2PickerFixture();
    void importMidiFixture();
    void newVoicegroupFixture();
    void exportWavFixture();
    void progressFixture();
    void openFileFixture();
    void saveFileFixture();
    void directoryFixture();
    void confirmationFixture();
    void errorFixture();
    void aboutFixture();

  private:
    // Build, show, and freeze one fixture kind. `configure` runs between
    // creation and show for kind-specific setup (the file dialogs).
    void expectFixture(int kind, void (*configure)(QDialog &) = nullptr);

    // The file dialogs list this directory; it starts empty and disappears
    // with the test object, so no run can see another run's listing.
    QTemporaryDir m_emptyFixtureDirectory;
};

void VisualWindowFixturesTest::initTestCase()
{
    checks::visual::prepare(*static_cast<QApplication *>(QCoreApplication::instance()));
    QVERIFY2(m_emptyFixtureDirectory.isValid(), "could not create the empty fixture directory");
    g_emptyFixtureDirectoryPath = m_emptyFixtureDirectory.path();
}

void VisualWindowFixturesTest::expectFixture(int kind, void (*configure)(QDialog &))
{
    const QString id = kindId(kind);
    QVERIFY2(!id.isEmpty(),
             qPrintable(QStringLiteral("fixture kind %1 has no baseline id").arg(kind)));

    std::unique_ptr<QDialog> dialog(sgw_createWindowFixture(kind));
    QVERIFY2(dialog, qPrintable(QStringLiteral("fixture kind %1 returned null").arg(kind)));
    if (configure)
        configure(*dialog);
    // A first show sizes a dialog that never requested a size to its layout
    // (clamped to its minimum), and the frozen baselines captured exactly that
    // size. checks::visual::showSettled re-applies the size requested before
    // the show, so request that same size here — an unpinned dialog would
    // request Qt's 640x480 default and the captured surface would change.
    if (!dialog->testAttribute(Qt::WA_Resized))
        dialog->resize(dialog->sizeHint().expandedTo(dialog->minimumSize()));
    checks::visual::showSettled(*dialog);

    // Dialogs with no named children (the mirror forms, progress, and the
    // message boxes) still pin their whole surface under a stable region;
    // compareShown merges these over the automatic descendant regions.
    QList<checks::visual::Region> regions;
    regions.append({QStringLiteral("fixture.surface"), dialog->rect()});
    checks::visual::compareShown(id, *dialog, regions);
}

void VisualWindowFixturesTest::settingsFixture()
{
    expectFixture(SgwWindowSettings);
}

void VisualWindowFixturesTest::sampleEditorFixture()
{
    expectFixture(SgwWindowSampleEditor);
}

void VisualWindowFixturesTest::sf2PickerFixture()
{
    expectFixture(SgwWindowSf2Picker);
}

void VisualWindowFixturesTest::importMidiFixture()
{
    expectFixture(SgwWindowImportMidi);
}

void VisualWindowFixturesTest::newVoicegroupFixture()
{
    expectFixture(SgwWindowNewVoicegroup);
}

void VisualWindowFixturesTest::exportWavFixture()
{
    expectFixture(SgwWindowExportWav);
}

void VisualWindowFixturesTest::progressFixture()
{
    expectFixture(SgwWindowProgress);
}

void VisualWindowFixturesTest::openFileFixture()
{
    expectFixture(SgwWindowOpenFile, configureFileDialog);
}

void VisualWindowFixturesTest::saveFileFixture()
{
    expectFixture(SgwWindowSaveFile, configureFileDialog);
}

void VisualWindowFixturesTest::directoryFixture()
{
    expectFixture(SgwWindowDirectory, configureFileDialog);
}

void VisualWindowFixturesTest::confirmationFixture()
{
    expectFixture(SgwWindowConfirmation);
}

void VisualWindowFixturesTest::errorFixture()
{
    expectFixture(SgwWindowError);
}

void VisualWindowFixturesTest::aboutFixture()
{
    expectFixture(SgwWindowAbout);
}

int runVisualWindowFixturesCheck(QApplication &, const QStringList &qtArguments)
{
    VisualWindowFixturesTest test;
    QStringList arguments{QStringLiteral("visual-windowfixtures")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "windowfixtures.moc"
