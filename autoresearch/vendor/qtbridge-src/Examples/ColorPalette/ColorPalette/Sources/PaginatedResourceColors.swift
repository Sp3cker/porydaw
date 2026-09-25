// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

import QtBridge
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor
@QtBridgeable
public class Color : @MainActor Codable {

    public var color: String
    public var id: Int
    public var name: String
    public var pantone_value: String

    public init(
        color: String,
        id: Int,
        name: String,
        pantone_value: String
    ) {
        self.color = color
        self.id = id
        self.name = name
        self.pantone_value = pantone_value
    }

    private enum CodingKeys: String, CodingKey {
        case color
        case id
        case name
        case pantone_value
    }
}

@QtBridgeable
public class PaginatedResourceColors: AbstractResource, QmlInstantiable {
    @QtTracked public var data: QListModel<Color> = QListModel()

    public var page: Int = 1
    public var pages: Int = 0
    public var path: String = ""

    private struct ColorsResponse: Codable {
        let page: Int
        let totalPages: Int
        let data: [Color]?

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

    public func refreshCurrentPage() {
        guard let request = api?.createRequest(path: path, queryItems: [
            URLQueryItem(name: "page", value: String(page))
        ]) else { return }

        Task {
            do {
                let (responseData, response) = try await URLSession.shared.data(for: request)
                guard response.isSuccessful() else { throw URLError(.badServerResponse) }
                let decoded = try JSONDecoder().decode(ColorsResponse.self, from: responseData)
                self.pages = decoded.totalPages
                self.page = decoded.page
                self.data = QListModel(decoded.data ?? [])
            } catch {
                print("Request failed:", error)
                refreshRequestFailed()
            }
        }
    }

    public func update(newData: [String: QVariantSettable], id: Int) {
        guard let request = api?.createRequest(path: path + "/\(id)", method: .put, jsonData: newData) else { return }

        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard response.isSuccessful() else { throw URLError(.badServerResponse) }
                refreshCurrentPage()
            } catch {
                print("Update failed:", error)
            }
        }
    }

    public func add(newData: [String: QVariantSettable]) {
        guard let request = api?.createRequest(path: path, method: .post, jsonData: newData) else { return }

        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard response.isSuccessful() else { throw URLError(.badServerResponse) }
                refreshCurrentPage()
            } catch {
                print("Add failed:", error)
            }
        }
    }

    public func remove(id: Int) {
        guard let request = api?.createRequest(path: path + "/\(id)", method: .delete) else { return }

        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard response.isSuccessful() else { throw URLError(.badServerResponse) }
                refreshCurrentPage()
            } catch {
                print("Remove failed:", error)
            }
        }
    }

    private func refreshRequestFailed() {
        if page != 1 {
            // A failed refresh. If we weren't on page 1, try that.
            // Last resource on current page might have been deleted, causing a failure
            setPage(newPage: 1)
        } else {
            // Refresh failed and we we're already on page 1 => clear data
            pages = 0
            data.reset(to: [])
        }
    }
}
