// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

import Foundation
import QtBridge

@MainActor
@QtBridgeable
public class Message {
    var author: String
    var textmessage: String
    var date:   String

    public init(author: String, textmessage: String, date: String) {
        self.author = author
        self.textmessage = textmessage
        self.date = date
    }
}

@MainActor
@QtBridgeable
public class ChatModel {

    public var msgs: QListModel<Message> = []

    public init() {
        msgs.append(Message(author: "Special Agent Dale Cooper",
                            textmessage: "The owls are not what they seem.",
                            date: "Feb 1989"))
    }

    private let replies = [
        "Hello!",
        "Damn good coffee!",
        "See you at the Roadhouse.",
        "Every day, once a day, give yourself a present.",
        "Another case, another day.",
        "I have no idea where this will lead us.",
        "Let’s talk at the sheriff’s station.",
        "A path is formed by laying one stone at a time.",
        "I’ll bring the tape recorder."
    ]

    public func insertReply(author: String,  text: String, date: String) {
        msgs.append(Message(author: author, textmessage: text, date: date))
        if author == "Me", !text.isEmpty {
            msgs.append(Message(author: "Special Agent Dale Cooper",
                                textmessage: replies.randomElement() ?? "…",
                                date: Date.now.formatted(date: .omitted, time: .shortened)
                )
            )
        }
    }

    public func clearMessages() {
        msgs.reset()
    }
}
