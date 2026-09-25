// Copyright (C) 2023 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtQuick 2.15
import QtTest 1.3
import QtBridgeTest 1.0

TestCase {
    name: "CustomTypeQListModel"
    when: windowShown

    SignalSpy {
        id: rowsInsertedSpy
        target: PhoneBookModel.phoneBook
        signalName: "rowsInserted"
    }
    SignalSpy {
        id: rowsRemovedSpy
        target: PhoneBookModel.phoneBook
        signalName: "rowsRemoved"
    }
    SignalSpy {
        id: modelResetSpy
        target: PhoneBookModel.phoneBook
        signalName: "modelReset"
    }
    SignalSpy {
        id: dataChangedSpy
        target: PhoneBookModel.phoneBook
        signalName: "dataChanged"
    }
    SignalSpy {
        id: phoneBookChangedSpy
        target: PhoneBookModel
        signalName: "phoneBookChanged"
    }

    ListView {
        id: view
        width: 8
        height: 8
        model: PhoneBookModel.phoneBook
        delegate: Item {
            width: 1
            height: 1
            required property string firstName
            required property string lastName
            required property string phoneNo
        }
    }

    function test_a_initialSetup() {
        compare(view.count, 2)
        compare(view.model.data(view.model.index(0,0), Qt.UserRole), "Michael")
        compare(view.model.data(view.model.index(0,0), Qt.UserRole + 1), "Scott")
        compare(view.model.data(view.model.index(0,0), Qt.UserRole + 2), "03-134-993")
        compare(view.model.data(view.model.index(1,0), Qt.UserRole), "Pam")
        compare(view.model.data(view.model.index(1,0), Qt.UserRole + 1), "Beasly")
        compare(view.model.data(view.model.index(1,0), Qt.UserRole + 2), "13-579-246")
    }

    function test_addString() {
        rowsInsertedSpy.clear()
        PhoneBookModel.addContact("Dwight K.", "Schrute", "1-800-984-3672")
        tryCompare(view, "count", 3, 200)
        compare(rowsInsertedSpy.count, 1)
    }

    function test_checkRowCount() {
        compare(view.count, 3)
        compare(view.model.rowCount(), 3)
    }

    function test_readDataFunc() {
        // Read data via data() and UserRole
        compare(view.count, 3)
        compare(view.model.data(view.model.index(0,0), Qt.UserRole), "Michael")
        compare(view.model.data(view.model.index(0,0), Qt.UserRole + 1), "Scott")
        compare(view.model.data(view.model.index(0,0), Qt.UserRole + 2), "03-134-993")
        compare(view.model.data(view.model.index(1,0), Qt.UserRole), "Pam")
        compare(view.model.data(view.model.index(1,0), Qt.UserRole + 1), "Beasly")
        compare(view.model.data(view.model.index(1,0), Qt.UserRole + 2), "13-579-246")
        compare(view.model.data(view.model.index(2,0), Qt.UserRole), "Dwight K.")
        compare(view.model.data(view.model.index(2,0), Qt.UserRole + 1), "Schrute")
        compare(view.model.data(view.model.index(2,0), Qt.UserRole + 2), "1-800-984-3672")
    }

    function test_readDataProp() {
        // Read data via delegate properties
        compare(view.count, 3)
        view.currentIndex = 0
        compare(view.currentItem.firstName, "Michael")
        compare(view.currentItem.lastName, "Scott")
        compare(view.currentItem.phoneNo, "03-134-993")
        view.currentIndex = 1
        compare(view.currentItem.firstName, "Pam")
        compare(view.currentItem.lastName, "Beasly")
        compare(view.currentItem.phoneNo, "13-579-246")
        view.currentIndex = 2
        compare(view.currentItem.firstName, "Dwight K.")
        compare(view.currentItem.lastName, "Schrute")
        compare(view.currentItem.phoneNo, "1-800-984-3672")
    }

    function test_removeContact() {
        rowsRemovedSpy.clear()
        let idx = view.model.index(0,0)
        PhoneBookModel.removeContact(2)
        tryCompare(view, "count", 2, 200)
        compare(view.model.data(idx, Qt.UserRole), "Michael")
        compare(view.model.data(idx, Qt.UserRole + 1), "Scott")
        compare(view.model.data(idx, Qt.UserRole + 2), "03-134-993")
        // Check if the delegate has also been updated
        view.currentIndex = 1
        compare(view.currentItem.firstName, "Pam")
        compare(view.currentItem.lastName, "Beasly")
        compare(view.currentItem.phoneNo, "13-579-246")
        compare(rowsRemovedSpy.count, 1)
    }

    function test_replaceContact() {
        rowsInsertedSpy.clear()
        rowsRemovedSpy.clear()
        let idx = view.model.index(0,0)
        compare(view.model.data(idx, Qt.UserRole), "Michael")
        compare(view.model.data(idx, Qt.UserRole + 1), "Scott")
        compare(view.model.data(idx, Qt.UserRole + 2), "03-134-993")
        PhoneBookModel.replaceContact(0, "Jim", "Halpert", "07-030-413")
        tryCompare(view, "count", 2, 200)
        compare(view.model.data(idx, Qt.UserRole), "Jim")
        compare(view.model.data(idx, Qt.UserRole + 1), "Halpert")
        compare(view.model.data(idx, Qt.UserRole + 2), "07-030-413")
        idx = view.model.index(1,0)
        compare(view.model.data(idx, Qt.UserRole), "Pam")
        compare(view.model.data(idx, Qt.UserRole + 1), "Beasly")
        compare(view.model.data(idx, Qt.UserRole + 2), "13-579-246")
        compare(dataChangedSpy.count, 1)
    }

    function test_replaceModel() {
        phoneBookChangedSpy.clear()
        const idx = view.model.index(0,0)
        PhoneBookModel.replacePhoneBook()
        tryCompare(view, "count", 1, 200)
        compare(view.model.data(idx, Qt.UserRole), "Jane")
        compare(view.model.data(idx, Qt.UserRole + 1), "Doe")
        compare(view.model.data(idx, Qt.UserRole + 2), "13-579-246")
        compare(phoneBookChangedSpy.count, 1)
    }

    function test_setData() {
        dataChangedSpy.clear()
        const idx = view.model.index(0,0)
        compare(view.model.data(idx, Qt.UserRole), "Jane")
        compare(view.model.data(idx, Qt.UserRole + 1), "Doe")
        compare(view.model.data(idx, Qt.UserRole + 2), "13-579-246")
        // Unchanged values shouldn't fire signals
        view.model.setData(idx, "Jane", Qt.UserRole)
        view.model.setData(idx, "Doe", Qt.UserRole + 1)
        view.model.setData(idx, "13-579-246", Qt.UserRole + 2)
        compare(dataChangedSpy.count, 0)
        // New values
        view.model.setData(idx, "Creed", Qt.UserRole)
        view.model.setData(idx, "Bratton", Qt.UserRole + 1)
        view.model.setData(idx, "000-000-000", Qt.UserRole + 2)
        compare(view.model.data(idx, Qt.UserRole), "Creed")
        compare(view.model.data(idx, Qt.UserRole + 1), "Bratton")
        compare(view.model.data(idx, Qt.UserRole + 2), "000-000-000")
        // Index out-of-range returns false - no crash, no signal
        const ok = view.model.setData(view.model.index(999,0), Qt.UserRole + 2)
        compare(ok, false)
        compare(dataChangedSpy.count, 3)
    }

    function test_updatePhoneNo() {
        dataChangedSpy.clear()
        const idx = view.model.index(0,0)
        compare(view.model.data(idx, Qt.UserRole), "Creed")
        compare(view.model.data(idx, Qt.UserRole + 1), "Bratton")
        compare(view.model.data(idx, Qt.UserRole + 2), "000-000-000")
        PhoneBookModel.updatePhoneNo(0, "11-333-445")
        compare(view.model.data(idx, Qt.UserRole), "Creed")
        compare(view.model.data(idx, Qt.UserRole + 1), "Bratton")
        compare(view.model.data(idx, Qt.UserRole + 2), "11-333-445")
        tryCompare(view, "count", 1, 200)
    }

    function test_xeraseContacts() {
        modelResetSpy.clear()
        PhoneBookModel.eraseContacts()
        tryCompare(view, "count", 0, 200)
        compare(modelResetSpy.count, 1)
    }
}
