pragma ComponentBehavior: Bound

import QtQuick
import PorydawApp as App

FocusScope {
    id: page
    required property App.SongTabSession applicationSession
    readonly property App.PianoGrid gridModel: applicationSession.songOpen
                                              ? applicationSession.gridPresenter() : null
    readonly property real plotOrigin: gridModel
                                       ? (gridModel.trackHeaderWidth || 0) + gridModel.keyboardWidth : 0
    readonly property real plotWidth: Math.max(width - plotOrigin, 0)
    property real baseFontPx: gridModel ? gridModel.baseFontPx : applicationSession.timeSigHost.baseFontPx

    signal bodyFactsChanged()
    onWidthChanged: page.bodyFactsChanged()
    onHeightChanged: page.bodyFactsChanged()
    onPlotOriginChanged: page.bodyFactsChanged()
    onBaseFontPxChanged: page.bodyFactsChanged()
    Component.onCompleted: page.bodyFactsChanged()
}
