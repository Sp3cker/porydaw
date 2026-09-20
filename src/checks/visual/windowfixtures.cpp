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

#include <QApplication>
#include <QCoreApplication>
#include <QDialog>
#include <QDialogButtonBox>
#include <QDir>
#include <QFileDialog>
#include <QList>
#include <QPushButton>
#include <QRect>
#include <QSet>
#include <QString>
#include <QTabBar>
#include <QWidget>
#include <QtTest>

#include <memory>

#include "widget_window_fixtures.h"

namespace {

// Move focus off any text field so a blinking caret never enters the raster;
// mirrors the dialog suite's parkFocus.
void parkFocus(QWidget &widget)
{
    QWidget *anchor = widget.findChild<QTabBar *>();
    if (!anchor)
        if (auto *buttons = widget.findChild<QDialogButtonBox *>())
            anchor = buttons->button(QDialogButtonBox::Cancel);
    if (!anchor)
        anchor = widget.findChild<QPushButton *>();
    if (anchor && anchor->isVisible() && anchor->focusPolicy() != Qt::NoFocus)
        anchor->setFocus(Qt::OtherFocusReason);
    else if (QWidget *focused = QApplication::focusWidget())
        if (focused == &widget || widget.isAncestorOf(focused))
            focused->clearFocus();
    QApplication::processEvents();
}

void showSettled(QWidget &widget)
{
    widget.show();
    QApplication::processEvents();
    parkFocus(widget);
}

// A stable empty directory for the file dialogs: their listing must not
// depend on the caller's working directory contents or timestamps.
QString emptyFixtureDir()
{
    static const QString path = [] {
        const QString dir =
            QDir::temp().absoluteFilePath(QStringLiteral("porydaw-windowfixture-empty"));
        QDir{}.mkpath(dir);
        return dir;
    }();
    return path;
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
    // Build, show, and freeze one fixture kind under `id`. `configure` runs
    // between creation and show for kind-specific setup (file dialogs).
    void expectFixture(int kind, const QString &id,
                       const std::function<void(QDialog &)> &configure = {});
};

void VisualWindowFixturesTest::initTestCase()
{
    checks::visual::prepare(*static_cast<QApplication *>(QCoreApplication::instance()));
}

void VisualWindowFixturesTest::expectFixture(int kind, const QString &id,
                                             const std::function<void(QDialog &)> &configure)
{
    std::unique_ptr<QDialog> dialog(sgw_createWindowFixture(kind));
    QVERIFY2(dialog, qPrintable(QStringLiteral("fixture kind %1 returned null").arg(kind)));
    if (configure)
        configure(*dialog);
    showSettled(*dialog);

    QList<checks::visual::Region> regions = checks::visual::widgetRegions(*dialog);
    // Dialogs with no named children (the mirror forms, progress, and the
    // message boxes) still pin their whole surface under a stable region.
    regions.append({QStringLiteral("fixture.surface"), dialog->rect()});
    QString error;
    QVERIFY2(checks::visual::compareWidget(id, *dialog, regions, &error), qPrintable(error));
    dialog->close();
}

void VisualWindowFixturesTest::settingsFixture()
{
    expectFixture(SgwWindowSettings, QStringLiteral("windowfixture/settings"));
}

void VisualWindowFixturesTest::sampleEditorFixture()
{
    expectFixture(SgwWindowSampleEditor, QStringLiteral("windowfixture/sample-editor"));
}

void VisualWindowFixturesTest::sf2PickerFixture()
{
    expectFixture(SgwWindowSf2Picker, QStringLiteral("windowfixture/sf2-picker"));
}

void VisualWindowFixturesTest::importMidiFixture()
{
    expectFixture(SgwWindowImportMidi, QStringLiteral("windowfixture/import-midi"));
}

void VisualWindowFixturesTest::newVoicegroupFixture()
{
    expectFixture(SgwWindowNewVoicegroup, QStringLiteral("windowfixture/new-voicegroup"));
}

void VisualWindowFixturesTest::exportWavFixture()
{
    expectFixture(SgwWindowExportWav, QStringLiteral("windowfixture/export-wav"));
}

void VisualWindowFixturesTest::progressFixture()
{
    expectFixture(SgwWindowProgress, QStringLiteral("windowfixture/progress"));
}

void VisualWindowFixturesTest::openFileFixture()
{
    expectFixture(SgwWindowOpenFile, QStringLiteral("windowfixture/open-file"),
                  [](QDialog &dialog) {
                      auto &file = static_cast<QFileDialog &>(dialog);
                      file.setOption(QFileDialog::DontUseNativeDialog, true);
                      // Pin the listing to a stable empty directory: the default working
                      // directory's contents and timestamps change between runs.
                      file.setDirectory(emptyFixtureDir());
                  });
}

void VisualWindowFixturesTest::saveFileFixture()
{
    expectFixture(SgwWindowSaveFile, QStringLiteral("windowfixture/save-file"),
                  [](QDialog &dialog) {
                      auto &file = static_cast<QFileDialog &>(dialog);
                      file.setOption(QFileDialog::DontUseNativeDialog, true);
                      file.setDirectory(emptyFixtureDir());
                  });
}

void VisualWindowFixturesTest::directoryFixture()
{
    expectFixture(SgwWindowDirectory, QStringLiteral("windowfixture/directory"),
                  [](QDialog &dialog) {
                      auto &file = static_cast<QFileDialog &>(dialog);
                      file.setOption(QFileDialog::DontUseNativeDialog, true);
                      file.setDirectory(emptyFixtureDir());
                  });
}

void VisualWindowFixturesTest::confirmationFixture()
{
    expectFixture(SgwWindowConfirmation, QStringLiteral("windowfixture/confirmation"));
}

void VisualWindowFixturesTest::errorFixture()
{
    expectFixture(SgwWindowError, QStringLiteral("windowfixture/error"));
}

void VisualWindowFixturesTest::aboutFixture()
{
    expectFixture(SgwWindowAbout, QStringLiteral("windowfixture/about"));
}

int runVisualWindowFixturesCheck(QApplication &, const QStringList &qtArguments)
{
    VisualWindowFixturesTest test;
    QStringList arguments{QStringLiteral("visual-windowfixtures")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "windowfixtures.moc"
