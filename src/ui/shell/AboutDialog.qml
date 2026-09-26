import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts

// Help > About porydaw: the QMessageBox::about body from the old MainWindow
// (version, description, links and credits), restyled onto GridPalette ink.
// Width derives from the application font; the window palette owns the popup
// chrome, and the body text keeps windowText on the dialog surface. Links
// render in body ink per the ThemedWindow link convention.
//
// Sizing follows the settings-dialog convention: fixed font-derived geometry
// instead of content-driven implicit sizes. The body lays out bottom-up in a
// ColumnLayout (the SongConfirmDialog pattern in the same Basic.Dialog
// family) and never reads the dialog's available width, so the dialog's
// implicitHeight no longer feeds back into its own content.
Basic.Dialog {
    id: about
    objectName: "shellAboutDialog"
    required property QtObject colors
    required property QtObject applicationSession
    required property real baseFontPx
    // Qt exposes no qVersion() binding, so the numeric Qt version from the
    // old "Running on Qt" line cannot be rendered; the host application
    // version feeds the heading when set.
    property string porydawVersion: Qt.application.version
    title: qsTr("About porydaw")
    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    focus: true
    standardButtons: Dialog.Close
    font: Qt.font(applicationSession.typographyFonts.body)
    width: Math.min(parent.width - 4 * baseFontPx,
                    aboutMetrics.averageCharacterWidth * 68 + 4 * baseFontPx)
    height: Math.min(parent.height - 4 * baseFontPx,
                     bodyColumn.implicitHeight + about.topPadding + about.bottomPadding
                     + (about.header && about.header.visible
                        ? about.header.implicitHeight + about.spacing : 0)
                     + (about.footer && about.footer.visible
                        ? about.footer.implicitHeight + about.spacing : 0))
    FontMetrics {
        id: aboutMetrics
        font: about.font
    }
    contentItem: ColumnLayout {
        id: bodyColumn
        Label {
            objectName: "shellAboutBody"
            Layout.fillWidth: true
            textFormat: Text.RichText
            wrapMode: Text.WordWrap
            color: about.colors.windowText
            linkColor: about.colors.windowText
            onLinkActivated: link => Qt.openUrlExternally(link)
            text: qsTr("<h3>porydaw %1</h3>"
                       + "<p>A music editor for the Pok\u00e9mon generation 3 "
                       + "decompilation projects "
                       + "(<a href=\"https://github.com/pret/pokeruby\">pokeruby</a>, "
                       + "<a href=\"https://github.com/pret/pokeemerald\">pokeemerald</a>, "
                       + "and <a href=\"https://github.com/pret/pokefirered\">"
                       + "pokefirered</a>).</p>"
                       + "<p>In Porydaw, load your decomp project directory to load "
                       + "the music-related project data. Then, play, edit, and "
                       + "create music. It sounds just like it does in-game. When "
                       + "saving, Porydaw writes and creates the necessary files "
                       + "directly into the decomp project. It also supports "
                       + "importing MIDI files, making it easy to whip up songs and "
                       + "voicegroups for brand new songs.</p>"
                       + "<p>Porydaw is designed for both music beginners and power "
                       + "users who are familiar with DAW programs. If you've used "
                       + "Sappy or Anvil Studio for your musical needs in the past, "
                       + "then Porydaw is for you! If you're a power user who loves "
                       + "your existing DAW (FL Studio, Reaper, etc.), give Porydaw "
                       + "a try\u2014but if you can't be pulled away, the "
                       + "<a href=\"https://github.com/huderlem/poryaaaa\">poryaaaa "
                       + "CLAP plugin</a> helps serve that power-user workflow.</p>"
                       + "<p>Running on Qt.</p>"
                       + "<p><a href=\"https://github.com/huderlem/porydaw\">"
                       + "github.com/huderlem/porydaw</a></p>").arg(
                           about.porydawVersion.length > 0 ? " " + about.porydawVersion : "")
        }
    }
}
