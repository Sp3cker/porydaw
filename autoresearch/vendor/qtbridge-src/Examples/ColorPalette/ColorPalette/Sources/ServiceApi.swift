// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public class ServiceApi {
    public var baseUrl: URL?
    public var commonHeaders: [String: String] = [:]

    enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    func createRequest(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: HTTPMethod = .get,
        jsonData: [String: Any]? = nil
    ) -> URLRequest? {
        guard let baseUrl else { return nil }

        guard var components = URLComponents(
            url: baseUrl.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else { return nil }

        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.allHTTPHeaderFields = commonHeaders

        if let jsonData, method != .get,
           let body = try? JSONSerialization.data(withJSONObject: jsonData) {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }
}
