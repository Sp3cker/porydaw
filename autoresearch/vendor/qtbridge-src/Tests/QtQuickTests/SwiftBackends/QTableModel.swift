// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtBridge

@MainActor
@QtBridgeable
public class Person {
    var givenName: String
    var lastName: String
    var house: String
    var spellNumber: Int
    var isStudent: Bool

    public init(givenName: String,
                lastName: String,
                house: String,
                spellNumber: Int,
                isStudent: Bool) {
        self.givenName = givenName
        self.lastName = lastName
        self.house = house
        self.spellNumber = spellNumber
        self.isStudent = isStudent
    }
}

@MainActor
@QtBridgeable
public class TableModel {
    public var table: QTableModel<Person>
    public var resultBuilderTestTable: QTableModel<Person>

    public init() {
        let people: [Person] = [
            Person(givenName: "Harry", lastName: "Potter", house: "Gryffindor",
                   spellNumber: 15, isStudent: true),
            Person(givenName: "Ron", lastName: "Weasley", house: "Gryffindor",
                   spellNumber: 14, isStudent: true),
            Person(givenName: "Hermione", lastName: "Granger", house: "Gryffindor",
                   spellNumber: 50, isStudent: true),
            Person(givenName: "Minerva", lastName: "McGonagall", house: "Gryffindor",
                   spellNumber: 150, isStudent: false)
        ]

        self.table = QTableModel(people) {
                QTableColumn("Name", value: \Person.givenName)
                QTableColumn("Last Name", value: \Person.lastName)
        }

        self.resultBuilderTestTable = QTableModel(people) {
            let cols = [
                QTableColumn("House", value: \Person.house),
                QTableColumn("Number of known spells", value: \Person.spellNumber),
                QTableColumn("Name", value: \Person.givenName),
                QTableColumn("Last Name", value: \Person.lastName),
                QTableColumn("Is still a student", value: \.isStudent)
            ]

            for col in cols {
                if !(col.header == "Name" || col.header == "Last Name") {
                    col
                }
            }
        }
    }

    // Columns
    public func appendColumn() {
        table.appendColumn(QTableColumn("House", value: \.house))
    }

    public func appendColumns() {
        table.appendColumns([QTableColumn("Number of known spells", value: \.spellNumber),
                             QTableColumn("Is still a student", value: \.isStudent)])
    }

    public func insertColumn(at index: Int) {
        table.insertColumn(QTableColumn("House", value: \.house), at: index)
    }

    public func insertTwoColumnsAt(index: Int) {
        table.insertColumns([QTableColumn("Number of known spells", value: \.spellNumber),
                             QTableColumn("Is still a student", value: \.isStudent)], at: index)
    }

    public func moveColumn(at index: Int, newIndex: Int) {
        table.moveColumn(at: index, to: newIndex)
    }

    public func moveColumns(start: Int, end: Int, index: Int) {
        table.moveColumns(from: start..<end+1, to: index)
    }

    public func removeColumn(at index: Int) {
        table.removeColumn(at: index)
    }

    public func removeColumns(start: Int, end: Int) {
        table.removeColumns(in: start..<end+1)
    }
    // Rows
    public func appendRow(givenName: String, lastName: String, house: String,
                          spellNumber: Int, isStudent: Bool) {
        table.appendRow(Person(givenName: givenName, lastName: lastName, house: house,
                               spellNumber: spellNumber, isStudent: isStudent))
    }

    public func appendRows(givenNames: [String], lastNames: [String], houses: [String],
                           spellNumbers: Int, areStudents: Bool) {
        table.appendRows([Person(givenName: givenNames[0], lastName: lastNames[0], house: houses[0],
                                 spellNumber: spellNumbers, isStudent: areStudents),
                          Person(givenName: givenNames[1], lastName: lastNames[1], house: houses[1],
                                 spellNumber: spellNumbers, isStudent: areStudents)])
    }

    public func insertRow(givenName: String, lastName: String, house: String,
                          spellNumber: Int, isStudent: Bool, at index: Int) {
        table.insertRow(Person(givenName: givenName, lastName: lastName, house: house,
                               spellNumber: spellNumber, isStudent: isStudent), at: index)
    }

    public func insertRows(givenNames: [String], lastNames: [String], houses: [String],
                           spellNumbers: Int, areStudents: Bool, at index: Int) {
        table.insertRows([Person(givenName: givenNames[0], lastName: lastNames[0], house: houses[0],
                                 spellNumber: spellNumbers, isStudent: areStudents),
                          Person(givenName: givenNames[1], lastName: lastNames[1], house: houses[1],
                                 spellNumber: spellNumbers, isStudent: areStudents)], at: index)
    }

    public func moveRow(at index: Int, to newIndex: Int) {
        table.moveRow(at: index, to: newIndex)
    }

    public func moveRows(start: Int, end: Int, index: Int) {
        table.moveRows(from: start..<end+1, to: index)
    }

    public func removeRow(at index: Int) {
        table.removeRow(at: index)
    }

    public func removeRows(start: Int, end: Int) {
        table.removeRows(in: start..<end+1)
    }
    // Cell
    public func setHouse(value: String, row: Int, column: Int) {
        table.setValue(value, row: row, column: column)
    }

    public func replaceModel() {
        table = resultBuilderTestTable
    }

    public func resetModel() {
        table.reset()
    }
}
