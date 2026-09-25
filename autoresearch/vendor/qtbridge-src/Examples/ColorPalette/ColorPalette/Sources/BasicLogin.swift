// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

import QtBridge
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@QtBridgeable
public class BasicLogin: AbstractResource, QmlInstantiable {
    public var user: String = ""
    public var userId: Int = 0
    public var loggedIn: Bool = false
    public var loginPath: String = ""
    public var logoutPath: String = ""

    required public override init() {
        super.init()
    }

    private struct LoginResponse: Codable {
        let token: String
    }

    public func login(jsonData: [String: QVariantSettable]) {
        guard let request = api?.createRequest(path: loginPath, method: .post, jsonData: jsonData) else { return }

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard response.isSuccessful() else { throw URLError(.badServerResponse) }
                let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: data)
                api?.commonHeaders["token"] = loginResponse.token
                user = jsonData["email"] as? String ?? ""
                userId = jsonData["id"] as? Int ?? 0
                loggedIn = true
            } catch {
                print("Login failed:", error)
            }
        }
    }

    public func logout() {
        guard let request = api?.createRequest(path: logoutPath, method: .post) else { return }

        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard response.isSuccessful() else { throw URLError(.badServerResponse) }
                api?.commonHeaders.removeValue(forKey: "token")
                user = ""
                userId = 0
                loggedIn = false
            } catch {
                print("Logout failed:", error)
            }
        }
    }
}
