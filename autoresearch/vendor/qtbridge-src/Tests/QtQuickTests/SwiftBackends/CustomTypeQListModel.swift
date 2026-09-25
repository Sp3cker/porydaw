// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtBridge
import Foundation

@MainActor
@QtBridgeable
public class Contact {
    var firstName: String
    var lastName: String
    var phoneNo: String

    public init(_ firstName: String, _ lastName: String, _ phoneNo: String) {
        self.firstName = firstName
        self.lastName = lastName
        self.phoneNo = phoneNo
    }
}

@MainActor
@QtBridgeable
public class PhoneBookModel {

    public var phoneBook: QListModel<Contact> = [Contact("Michael", "Scott", "03-134-993"),
                                                 Contact("Pam", "Beasly", "13-579-246")]

    public var replacingModel: QListModel<Contact> = [Contact("Jane", "Doe", "13-579-246")]

    public func addContact(firstName: String, lastName: String, phoneNo: String) {
        phoneBook.append(Contact(firstName, lastName, phoneNo))
    }

    public func removeContact(at index: Int) {
        phoneBook.remove(at: index)
    }

    public func replaceContact(at index: Int, firstName: String, lastName: String, phoneNo: String) {
        phoneBook[index] = Contact(firstName, lastName, phoneNo)
    }

    public func updatePhoneNo(at index: Int, phoneNo: String) {
        phoneBook[index].phoneNo = phoneNo
    }

    public func replacePhoneBook() {
        phoneBook = replacingModel
    }

    public func eraseContacts() {
        phoneBook.reset()
    }
}
