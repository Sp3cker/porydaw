// Copyright (C) 2023 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtQuick 2.15
import QtTest 1.3
import QtBridgeTest 1.0

TestCase {
    name: "TableModelView"
    when: windowShown

    SignalSpy {
        id: tableChangedSpy
        target: TableModel
        signalName: "tableChanged"
    }
    SignalSpy {
        id: rowsInsertedSpy
        target: TableModel.table
        signalName: "rowsInserted"
    }
    SignalSpy {
        id: rowsMovedSpy
        target: TableModel.table
        signalName: "rowsMoved"
    }
    SignalSpy {
        id: rowsRemovedSpy
        target: TableModel.table
        signalName: "rowsRemoved"
    }
    SignalSpy {
        id: columnsInsertedSpy
        target: TableModel.table
        signalName: "columnsInserted"
    }
    SignalSpy {
        id: layoutChangedSpy
        target: TableModel.table
        signalName: "layoutChanged"
    }
    SignalSpy {
        id: columnsRemovedSpy
        target: TableModel.table
        signalName: "columnsRemoved"
    }
    SignalSpy {
        id: modelResetSpy
        target: TableModel.table
        signalName: "modelReset"
    }
    SignalSpy {
        id: dataChangedSpy
        target: TableModel.table
        signalName: "dataChanged"
    }

    TableView {
        id: tableView
        width: 400
        height: 300
        columnSpacing: 1
        rowSpacing: 1
        clip: true
        model: TableModel.table

        delegate: Rectangle {
            implicitWidth: 1
            implicitHeight: 1
        }
    }

    function test_a_initialSetup() {
        compare(tableView.columns, 2)
        compare(tableView.rows, 4)
        compare(tableView.model.headerData(0, Qt.Horizontal, Qt.DisplayRole), "Name")
        compare(tableView.model.headerData(1, Qt.Horizontal, Qt.DisplayRole), "Last Name")
        // Valid index
        // Read data via data()
        compare(tableView.model.data(tableView.model.index(0,0), Qt.DisplayRole), "Harry")
        compare(tableView.model.data(tableView.model.index(0,1), Qt.DisplayRole), "Potter")
        compare(tableView.model.data(tableView.model.index(1,0), Qt.DisplayRole), "Ron")
        compare(tableView.model.data(tableView.model.index(1,1), Qt.DisplayRole), "Weasley")
        compare(tableView.model.data(tableView.model.index(2,0), Qt.DisplayRole), "Hermione")
        compare(tableView.model.data(tableView.model.index(2,1), Qt.DisplayRole), "Granger")
        compare(tableView.model.data(tableView.model.index(3,0), Qt.DisplayRole), "Minerva")
        compare(tableView.model.data(tableView.model.index(3,1), Qt.DisplayRole), "McGonagall")
        // Invalid index
        compare(tableView.model.data(tableView.model.index(500,0), Qt.DisplayRole), undefined)
    }

    function test_appendColumn() {
        columnsInsertedSpy.clear()
        compare(tableView.columns, 2)
        compare(tableView.model.headerData(0, Qt.Horizontal, Qt.DisplayRole), "Name")
        compare(tableView.model.headerData(1, Qt.Horizontal, Qt.DisplayRole), "Last Name")
        TableModel.appendColumn()
        tryCompare(tableView, "columns", 3, 200)
        compare(tableView.model.headerData(2, Qt.Horizontal, Qt.DisplayRole), "House")
        compare(columnsInsertedSpy.count, 1)
    }

    function test_appendColumns() {
        columnsInsertedSpy.clear()
        compare(tableView.columns, 3)
        compare(tableView.model.headerData(0, Qt.Horizontal, Qt.DisplayRole), "Name")
        compare(tableView.model.headerData(1, Qt.Horizontal, Qt.DisplayRole), "Last Name")
        compare(tableView.model.headerData(2, Qt.Horizontal, Qt.DisplayRole), "House")
        TableModel.appendColumns()
        tryCompare(tableView, "columns", 5, 200)
        compare(tableView.model.headerData(3, Qt.Horizontal, Qt.DisplayRole), "Number of known spells")
        compare(tableView.model.headerData(4, Qt.Horizontal, Qt.DisplayRole), "Is still a student")
        compare(columnsInsertedSpy.count, 1)
    }

    function test_appendRow() {
        rowsInsertedSpy.clear()
        compare(tableView.rows, 4)
        TableModel.appendRow("Draco", "Malfoy", "Slytherin", 25, true)
        tryCompare(tableView, "rows", 5, 200)
        compare(tableView.model.data(tableView.model.index(4,0), Qt.DisplayRole), "Draco")
        compare(tableView.model.data(tableView.model.index(4,1), Qt.DisplayRole), "Malfoy")
        compare(tableView.model.data(tableView.model.index(4,2), Qt.DisplayRole), "Slytherin")
        compare(tableView.model.data(tableView.model.index(4,3), Qt.DisplayRole), 25)
        compare(tableView.model.data(tableView.model.index(4,4), Qt.DisplayRole), true)
        compare(rowsInsertedSpy.count, 1)
    }

    function test_appendRows() {
        rowsInsertedSpy.clear()
        compare(tableView.rows, 5)
        TableModel.appendRows(["Vincent", "Gregory"], ["Crabbe", "Goyle"], ["Slytherin", "Slytherin"],
                              5, true)
        tryCompare(tableView, "rows", 7, 200)
        compare(tableView.model.data(tableView.model.index(5,0), Qt.DisplayRole), "Vincent")
        compare(tableView.model.data(tableView.model.index(5,1), Qt.DisplayRole), "Crabbe")
        compare(tableView.model.data(tableView.model.index(5,2), Qt.DisplayRole), "Slytherin")
        compare(tableView.model.data(tableView.model.index(5,3), Qt.DisplayRole), 5)
        compare(tableView.model.data(tableView.model.index(5,4), Qt.DisplayRole), true)

        compare(tableView.model.data(tableView.model.index(6,0), Qt.DisplayRole), "Gregory")
        compare(tableView.model.data(tableView.model.index(6,1), Qt.DisplayRole), "Goyle")
        compare(tableView.model.data(tableView.model.index(6,2), Qt.DisplayRole), "Slytherin")
        compare(tableView.model.data(tableView.model.index(6,3), Qt.DisplayRole), 5)
        compare(tableView.model.data(tableView.model.index(6,4), Qt.DisplayRole), true)
        compare(rowsInsertedSpy.count, 1)
    }

    function test_aremoveColumn() {
        columnsRemovedSpy.clear()
        compare(tableView.columns, 5)
        compare(tableView.model.headerData(0, Qt.Horizontal, Qt.DisplayRole), "Name")
        compare(tableView.model.headerData(1, Qt.Horizontal, Qt.DisplayRole), "Last Name")
        compare(tableView.model.headerData(2, Qt.Horizontal, Qt.DisplayRole), "House")
        compare(tableView.model.headerData(3, Qt.Horizontal, Qt.DisplayRole), "Number of known spells")
        compare(tableView.model.headerData(4, Qt.Horizontal, Qt.DisplayRole), "Is still a student")
        // Valid index
        TableModel.removeColumn(3)
        tryCompare(tableView, "columns", 4, 200)
        compare(tableView.model.headerData(0, Qt.Horizontal, Qt.DisplayRole), "Name")
        compare(tableView.model.headerData(1, Qt.Horizontal, Qt.DisplayRole), "Last Name")
        compare(tableView.model.headerData(2, Qt.Horizontal, Qt.DisplayRole), "House")
        compare(tableView.model.headerData(3, Qt.Horizontal, Qt.DisplayRole), "Is still a student")
        compare(columnsRemovedSpy.count, 1)
        // Invalid index
        columnsRemovedSpy.clear()
        TableModel.removeColumn(5)
        tryCompare(tableView, "columns", 4, 200)
        compare(columnsRemovedSpy.count, 0)
    }

    function test_aremoveColumns() {
        columnsRemovedSpy.clear()
        compare(tableView.columns, 4)
        compare(tableView.model.headerData(2, Qt.Horizontal, Qt.DisplayRole), "House")
        compare(tableView.model.headerData(3, Qt.Horizontal, Qt.DisplayRole), "Is still a student")
        // Valid index
        TableModel.removeColumns(2, 3)
        tryCompare(tableView, "columns", 2, 200)
        compare(tableView.model.headerData(0, Qt.Horizontal, Qt.DisplayRole), "Name")
        compare(tableView.model.headerData(1, Qt.Horizontal, Qt.DisplayRole), "Last Name")
        compare(columnsRemovedSpy.count, 1)
        // Invalid index
        columnsRemovedSpy.clear()
        TableModel.removeColumns(2, 3)
        tryCompare(tableView, "columns", 2, 200)
        compare(columnsRemovedSpy.count, 0)
    }

    function test_aremoveRow() {
        rowsRemovedSpy.clear()
        compare(tableView.rows, 7)
        // Valid index
        TableModel.removeRow(5)
        tryCompare(tableView, "rows", 6, 200)
        compare(rowsRemovedSpy.count, 1)
        // Invalid index
        rowsRemovedSpy.clear()
        TableModel.removeRow(7)
        tryCompare(tableView, "rows", 6, 200)
        compare(rowsRemovedSpy.count, 0)
    }

    function test_aremoveRows() {
        rowsRemovedSpy.clear()
        compare(tableView.rows, 6)
        // Valid index
        TableModel.removeRows(4, 5)
        tryCompare(tableView, "rows", 4, 200)
        compare(rowsRemovedSpy.count, 1)
        // Invalid index
        rowsRemovedSpy.clear()
        TableModel.removeRows(4, 500)
        tryCompare(tableView, "rows", 4, 200)
        compare(rowsRemovedSpy.count, 0)
    }

    function test_insertColumn() {
        columnsInsertedSpy.clear()
        compare(tableView.columns, 2)
        compare(tableView.model.headerData(0, Qt.Horizontal, Qt.DisplayRole), "Name")
        compare(tableView.model.headerData(1, Qt.Horizontal, Qt.DisplayRole), "Last Name")
        // Valid index
        TableModel.insertColumn(0)
        tryCompare(tableView, "columns", 3, 200)
        compare(tableView.model.headerData(0, Qt.Horizontal, Qt.DisplayRole), "House")
        compare(tableView.model.headerData(1, Qt.Horizontal, Qt.DisplayRole), "Name")
        compare(tableView.model.headerData(2, Qt.Horizontal, Qt.DisplayRole), "Last Name")
        compare(columnsInsertedSpy.count, 1)
        // Invalid index
        columnsInsertedSpy.clear()
        TableModel.insertColumn(100)
        tryCompare(tableView, "columns", 3, 200)
        compare(columnsInsertedSpy.count, 0)
    }

    function test_insertColumns() {
        columnsInsertedSpy.clear()
        compare(tableView.columns, 3)
        compare(tableView.model.headerData(0, Qt.Horizontal, Qt.DisplayRole), "House")
        compare(tableView.model.headerData(1, Qt.Horizontal, Qt.DisplayRole), "Name")
        compare(tableView.model.headerData(2, Qt.Horizontal, Qt.DisplayRole), "Last Name")
        // Valid index
        TableModel.insertTwoColumnsAt(3)
        tryCompare(tableView, "columns", 5, 200)
        compare(tableView.model.headerData(0, Qt.Horizontal, Qt.DisplayRole), "House")
        compare(tableView.model.headerData(1, Qt.Horizontal, Qt.DisplayRole), "Name")
        compare(tableView.model.headerData(2, Qt.Horizontal, Qt.DisplayRole), "Last Name")
        compare(tableView.model.headerData(3, Qt.Horizontal, Qt.DisplayRole), "Number of known spells")
        compare(tableView.model.headerData(4, Qt.Horizontal, Qt.DisplayRole), "Is still a student")
        compare(columnsInsertedSpy.count, 1)
        // Invalid index
        columnsInsertedSpy.clear()
        TableModel.insertTwoColumnsAt(50)
        tryCompare(tableView, "columns", 5, 200)
        compare(columnsInsertedSpy.count, 0)
    }

    function test_moveColumn() {
        layoutChangedSpy.clear()
        compare(tableView.columns, 5)
        compare(tableView.model.headerData(0, Qt.Horizontal, Qt.DisplayRole), "House")
        compare(tableView.model.headerData(1, Qt.Horizontal, Qt.DisplayRole), "Name")
        compare(tableView.model.headerData(2, Qt.Horizontal, Qt.DisplayRole), "Last Name")
        compare(tableView.model.headerData(3, Qt.Horizontal, Qt.DisplayRole), "Number of known spells")
        compare(tableView.model.headerData(4, Qt.Horizontal, Qt.DisplayRole), "Is still a student")
        // Valid index
        // Move left
        TableModel.moveColumn(4, 0)
        compare(tableView.columns, 5)
        compare(tableView.model.headerData(0, Qt.Horizontal, Qt.DisplayRole), "Is still a student")
        compare(tableView.model.headerData(1, Qt.Horizontal, Qt.DisplayRole), "House")
        compare(tableView.model.headerData(2, Qt.Horizontal, Qt.DisplayRole), "Name")
        compare(tableView.model.headerData(3, Qt.Horizontal, Qt.DisplayRole), "Last Name")
        compare(tableView.model.headerData(4, Qt.Horizontal, Qt.DisplayRole), "Number of known spells")
        compare(layoutChangedSpy.count, 1)
        // Move right
        TableModel.moveColumn(1, 3)
        compare(tableView.model.headerData(0, Qt.Horizontal, Qt.DisplayRole), "Is still a student")
        compare(tableView.model.headerData(1, Qt.Horizontal, Qt.DisplayRole), "Name")
        compare(tableView.model.headerData(2, Qt.Horizontal, Qt.DisplayRole), "Last Name")
        compare(tableView.model.headerData(3, Qt.Horizontal, Qt.DisplayRole), "House")
        compare(tableView.model.headerData(4, Qt.Horizontal, Qt.DisplayRole), "Number of known spells")
        compare(layoutChangedSpy.count, 2)
        // Destination equals start
        TableModel.moveColumn(0, 0)
        tryCompare(layoutChangedSpy, "count", 2, 200)
        // Invalid index
        TableModel.moveColumn(10, 3)
        tryCompare(layoutChangedSpy, "count", 2, 200)
    }

    function test_moveColumns() {
        layoutChangedSpy.clear()
        compare(tableView.columns, 5)
        compare(tableView.model.headerData(0, Qt.Horizontal, Qt.DisplayRole), "Is still a student")
        compare(tableView.model.headerData(1, Qt.Horizontal, Qt.DisplayRole), "Name")
        compare(tableView.model.headerData(2, Qt.Horizontal, Qt.DisplayRole), "Last Name")
        compare(tableView.model.headerData(3, Qt.Horizontal, Qt.DisplayRole), "House")
        compare(tableView.model.headerData(4, Qt.Horizontal, Qt.DisplayRole), "Number of known spells")
        // Move left
        TableModel.moveColumns(1, 2, 0)
        compare(tableView.columns, 5)
        compare(tableView.model.headerData(0, Qt.Horizontal, Qt.DisplayRole), "Name")
        compare(tableView.model.headerData(1, Qt.Horizontal, Qt.DisplayRole), "Last Name")
        compare(tableView.model.headerData(2, Qt.Horizontal, Qt.DisplayRole), "Is still a student")
        compare(tableView.model.headerData(3, Qt.Horizontal, Qt.DisplayRole), "House")
        compare(tableView.model.headerData(4, Qt.Horizontal, Qt.DisplayRole), "Number of known spells")
        compare(layoutChangedSpy.count, 1)
        // Move right
        TableModel.moveColumns(0, 1, 2)
        compare(tableView.columns, 5)
        compare(tableView.model.headerData(0, Qt.Horizontal, Qt.DisplayRole), "Is still a student")
        compare(tableView.model.headerData(1, Qt.Horizontal, Qt.DisplayRole), "House")
        compare(tableView.model.headerData(2, Qt.Horizontal, Qt.DisplayRole), "Name")
        compare(tableView.model.headerData(3, Qt.Horizontal, Qt.DisplayRole), "Last Name")
        compare(tableView.model.headerData(4, Qt.Horizontal, Qt.DisplayRole), "Number of known spells")
        compare(layoutChangedSpy.count, 2)
        // Destination equals start
        TableModel.moveColumns(0, 2, 0)
        tryCompare(layoutChangedSpy, "count", 2, 200)
        // Invalid index
        TableModel.moveColumns(0, 1, 30)
        tryCompare(layoutChangedSpy, "count", 2, 200)
    }

    function test_insertRow() {
        rowsInsertedSpy.clear()
        compare(tableView.rows, 4)
        // Valid index
        TableModel.insertRow("Draco", "Malfoy", "Slytherin", 25, true, 0)
        tryCompare(tableView, "rows", 5, 200)
        compare(tableView.model.data(tableView.model.index(0,0), Qt.DisplayRole), "Slytherin")
        compare(tableView.model.data(tableView.model.index(0,1), Qt.DisplayRole), "Draco")
        compare(tableView.model.data(tableView.model.index(0,2), Qt.DisplayRole), "Malfoy")
        compare(tableView.model.data(tableView.model.index(0,3), Qt.DisplayRole), 25)
        compare(tableView.model.data(tableView.model.index(0,4), Qt.DisplayRole), true)
        compare(rowsInsertedSpy.count, 1)
        // Invalid index
        rowsInsertedSpy.clear()
        TableModel.insertRow("Pansy", "Parkinson", "Slytherin", 25, true, 150)
        compare(tableView.rows, 5)
        compare(rowsInsertedSpy.count, 0)
    }

    function test_insertRows() {
        rowsInsertedSpy.clear()
        compare(tableView.rows, 5)
        // Valid index
        TableModel.insertRows(["Cedric", "Cho"], ["Diggory", "Chang"], ["Hufflepuff", "Hufflepuff"],
                              30, true, 4)
        tryCompare(tableView, "rows", 7, 200)
        compare(tableView.model.data(tableView.model.index(4,0), Qt.DisplayRole), "Hufflepuff")
        compare(tableView.model.data(tableView.model.index(4,1), Qt.DisplayRole), "Cedric")
        compare(tableView.model.data(tableView.model.index(4,2), Qt.DisplayRole), "Diggory")
        compare(tableView.model.data(tableView.model.index(4,3), Qt.DisplayRole), 30)
        compare(tableView.model.data(tableView.model.index(4,4), Qt.DisplayRole), true)

        compare(tableView.model.data(tableView.model.index(5,0), Qt.DisplayRole), "Hufflepuff")
        compare(tableView.model.data(tableView.model.index(5,1), Qt.DisplayRole), "Cho")
        compare(tableView.model.data(tableView.model.index(5,2), Qt.DisplayRole), "Chang")
        compare(tableView.model.data(tableView.model.index(5,3), Qt.DisplayRole), 30)
        compare(tableView.model.data(tableView.model.index(5,4), Qt.DisplayRole), true)
        compare(rowsInsertedSpy.count, 1)
        // Invalid index
        TableModel.insertRows(["Cedric", "Cho"], ["Diggory", "Chang"], ["Hufflepuff", "Hufflepuff"],
                              30, true, 100)
        tryCompare(tableView, "rows", 7, 200)
    }

    function test_moveRow() {
        compare(tableView.model.headerData(0, Qt.Horizontal, Qt.DisplayRole), "Is still a student")
        compare(tableView.model.headerData(1, Qt.Horizontal, Qt.DisplayRole), "House")
        compare(tableView.model.headerData(2, Qt.Horizontal, Qt.DisplayRole), "Name")
        compare(tableView.model.headerData(3, Qt.Horizontal, Qt.DisplayRole), "Last Name")
        compare(tableView.model.headerData(4, Qt.Horizontal, Qt.DisplayRole), "Number of known spells")
        rowsMovedSpy.clear()
        compare(tableView.rows, 7)
        compare(tableView.model.data(tableView.model.index(4,0), Qt.DisplayRole), true)
        compare(tableView.model.data(tableView.model.index(4,1), Qt.DisplayRole), "Hufflepuff")
        compare(tableView.model.data(tableView.model.index(4,2), Qt.DisplayRole), "Cedric")
        compare(tableView.model.data(tableView.model.index(4,3), Qt.DisplayRole), "Diggory")
        compare(tableView.model.data(tableView.model.index(4,4), Qt.DisplayRole), 30)
        // Valid index
        // Move up
        TableModel.moveRow(4, 0)
        compare(tableView.rows, 7)
        compare(tableView.model.data(tableView.model.index(0,0), Qt.DisplayRole), true)
        compare(tableView.model.data(tableView.model.index(0,1), Qt.DisplayRole), "Hufflepuff")
        compare(tableView.model.data(tableView.model.index(0,2), Qt.DisplayRole), "Cedric")
        compare(tableView.model.data(tableView.model.index(0,3), Qt.DisplayRole), "Diggory")
        compare(tableView.model.data(tableView.model.index(0,4), Qt.DisplayRole), 30)
        compare(rowsMovedSpy.count, 1)
        // Move down
        TableModel.moveRow(0, 4)
        compare(tableView.model.data(tableView.model.index(4,0), Qt.DisplayRole), true)
        compare(tableView.model.data(tableView.model.index(4,1), Qt.DisplayRole), "Hufflepuff")
        compare(tableView.model.data(tableView.model.index(4,2), Qt.DisplayRole), "Cedric")
        compare(tableView.model.data(tableView.model.index(4,3), Qt.DisplayRole), "Diggory")
        compare(tableView.model.data(tableView.model.index(4,4), Qt.DisplayRole), 30)
        compare(rowsMovedSpy.count, 2)
        // Destination equals start
        TableModel.moveRow(0, 0)
        tryCompare(rowsMovedSpy, "count", 2, 200)
        // Invalid index
        TableModel.moveRow(10, 4)
        tryCompare(rowsMovedSpy, "count", 2, 200)
    }

    function test_moveRows() {
        rowsMovedSpy.clear()
        compare(tableView.rows, 7)
        compare(tableView.model.data(tableView.model.index(0,0), Qt.DisplayRole), true)
        compare(tableView.model.data(tableView.model.index(0,1), Qt.DisplayRole), "Slytherin")
        compare(tableView.model.data(tableView.model.index(0,2), Qt.DisplayRole), "Draco")
        compare(tableView.model.data(tableView.model.index(0,3), Qt.DisplayRole), "Malfoy")
        compare(tableView.model.data(tableView.model.index(0,4), Qt.DisplayRole), 25)

        compare(tableView.model.data(tableView.model.index(1,0), Qt.DisplayRole), true)
        compare(tableView.model.data(tableView.model.index(1,1), Qt.DisplayRole), "Gryffindor")
        compare(tableView.model.data(tableView.model.index(1,2), Qt.DisplayRole), "Harry")
        compare(tableView.model.data(tableView.model.index(1,3), Qt.DisplayRole), "Potter")
        compare(tableView.model.data(tableView.model.index(1,4), Qt.DisplayRole), 15)
        // Valid index
        // Move down
        TableModel.moveRows(0, 1, 5)
        compare(tableView.model.data(tableView.model.index(5,0), Qt.DisplayRole), true)
        compare(tableView.model.data(tableView.model.index(5,1), Qt.DisplayRole), "Slytherin")
        compare(tableView.model.data(tableView.model.index(5,2), Qt.DisplayRole), "Draco")
        compare(tableView.model.data(tableView.model.index(5,3), Qt.DisplayRole), "Malfoy")
        compare(tableView.model.data(tableView.model.index(5,4), Qt.DisplayRole), 25)

        compare(tableView.model.data(tableView.model.index(6,0), Qt.DisplayRole), true)
        compare(tableView.model.data(tableView.model.index(6,1), Qt.DisplayRole), "Gryffindor")
        compare(tableView.model.data(tableView.model.index(6,2), Qt.DisplayRole), "Harry")
        compare(tableView.model.data(tableView.model.index(6,3), Qt.DisplayRole), "Potter")
        compare(tableView.model.data(tableView.model.index(6,4), Qt.DisplayRole), 15)
        compare(rowsMovedSpy.count, 1)
        // Move up
        TableModel.moveRows(5, 6, 0)
        compare(tableView.model.data(tableView.model.index(0,0), Qt.DisplayRole), true)
        compare(tableView.model.data(tableView.model.index(0,1), Qt.DisplayRole), "Slytherin")
        compare(tableView.model.data(tableView.model.index(0,2), Qt.DisplayRole), "Draco")
        compare(tableView.model.data(tableView.model.index(0,3), Qt.DisplayRole), "Malfoy")
        compare(tableView.model.data(tableView.model.index(0,4), Qt.DisplayRole), 25)

        compare(tableView.model.data(tableView.model.index(1,0), Qt.DisplayRole), true)
        compare(tableView.model.data(tableView.model.index(1,1), Qt.DisplayRole), "Gryffindor")
        compare(tableView.model.data(tableView.model.index(1,2), Qt.DisplayRole), "Harry")
        compare(tableView.model.data(tableView.model.index(1,3), Qt.DisplayRole), "Potter")
        compare(tableView.model.data(tableView.model.index(1,4), Qt.DisplayRole), 15)
        compare(rowsMovedSpy.count, 2)
        // Destination equals start
        TableModel.moveRows(7, 8, 7)
        tryCompare(rowsMovedSpy, "count", 2, 200)
        // Invalid index
        TableModel.moveRows(7, 8, 0)
        tryCompare(rowsMovedSpy, "count", 2, 200)
    }

    function test_setData() {
        dataChangedSpy.clear()
        compare(tableView.model.data(tableView.model.index(5,0), Qt.DisplayRole), true)
        compare(tableView.model.data(tableView.model.index(5,1), Qt.DisplayRole), "Hufflepuff")
        compare(tableView.model.data(tableView.model.index(5,2), Qt.DisplayRole), "Cho")
        compare(tableView.model.data(tableView.model.index(5,3), Qt.DisplayRole), "Chang")
        compare(tableView.model.data(tableView.model.index(5,4), Qt.DisplayRole), 30)
        // Valid index
        // Using setValue()
        TableModel.setHouse("Gryffindor", 5, 1)
        compare(dataChangedSpy.count, 1)
        compare(tableView.model.data(tableView.model.index(5,0), Qt.DisplayRole), true)
        compare(tableView.model.data(tableView.model.index(5,1), Qt.DisplayRole), "Gryffindor")
        compare(tableView.model.data(tableView.model.index(5,2), Qt.DisplayRole), "Cho")
        compare(tableView.model.data(tableView.model.index(5,3), Qt.DisplayRole), "Chang")
        compare(tableView.model.data(tableView.model.index(5,4), Qt.DisplayRole), 30)
        // Using setData()
        dataChangedSpy.clear()
        const idx = tableView.model.index(5, 1)
        compare(tableView.model.data(idx, Qt.DisplayRole), "Gryffindor")
        tableView.model.setData(idx, "Ravenclaw", Qt.EditRole)
        compare(tableView.model.data(idx, Qt.DisplayRole), "Ravenclaw")
        compare(dataChangedSpy.count, 1)
        // Invalid index
        dataChangedSpy.clear()
        const invalid_idx = tableView.model.index(150, 0)
        // setData()
        tableView.model.setData(invalid_idx, "Ravenclaw", Qt.EditRole)
        // setValue()
        TableModel.setHouse("Gryffindor", 500, 0)
        compare(dataChangedSpy.count, 0)
    }

    function test_xReplaceModelAndVerifyResultBuilder() {
        tableChangedSpy.clear()
        // Old model
        compare(tableView.rows, 7)
        compare(tableView.columns, 5)
        TableModel.replaceModel()
        tryCompare(tableChangedSpy, "count", 1, 200)
        // New model
        tryCompare(tableView, "rows", 4, 200)
        tryCompare(tableView, "columns", 3, 200)
        compare(tableView.model.headerData(0, Qt.Horizontal, Qt.DisplayRole), "House")
        compare(tableView.model.headerData(1, Qt.Horizontal, Qt.DisplayRole), "Number of known spells")
        compare(tableView.model.headerData(2, Qt.Horizontal, Qt.DisplayRole), "Is still a student")
    }

    function test_xResetModel() {
        modelResetSpy.clear()
        TableModel.resetModel()
        tryCompare(tableView, "rows", 0, 200)
        tryCompare(tableView, "columns", 0, 200)
        compare(modelResetSpy.count, 1)
    }
}
