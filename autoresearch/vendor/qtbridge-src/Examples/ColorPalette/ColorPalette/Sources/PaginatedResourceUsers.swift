// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

import QtBridge
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@QtBridgeable
public class User : QObjectBuildable, @MainActor Codable {
    public var avatar: String
    public var email: String
    public var id: Int

    public init(avatar: String,
                email: String,
                id: Int)
    {
        self.avatar = avatar
        self.email = email
        self.id = id
    }

    private enum CodingKeys: String, CodingKey {
        case avatar, email, id
    }
}

@QtBridgeable
public class PaginatedResourceUsers: AbstractResource, QmlInstantiable {
    @QtTracked public var data: QListModel<User> = QListModel()

    public var page: Int = 1
    public var pages: Int = 0
    public var path: String = ""

    private struct UsersResponse: Codable {
        let page: Int
        let totalPages: Int
        let data: [User]?

        enum CodingKeys: String, CodingKey {
            case page
            case totalPages = "total_pages"
            case data
        }
    }

    required public override init() {
        super.init()
    }

    public func setPage(newPage: Int) {
        self.page = newPage
        refreshCurrentPage()
    }

    public func avatar(userId: Int) -> String {
        return data.first { $0.id == userId }?.avatar ?? ""
    }

    public func refreshCurrentPage() {
        guard let request = api?.createRequest(path: path, queryItems: [
            URLQueryItem(name: "page", value: String(page))
        ]) else { return }

        Task {
            do {
                let (responseData, response) = try await URLSession.shared.data(for: request)
                guard response.isSuccessful() else { throw URLError(.badServerResponse) }
                let decoded = try JSONDecoder().decode(UsersResponse.self, from: responseData)
                self.pages = decoded.totalPages
                self.page = decoded.page
                self.data = QListModel(decoded.data ?? [])
            } catch {
                print("Request failed:", error)
            }
        }
    }
}
