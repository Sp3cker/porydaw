// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

import QtBridge
import Foundation

@QtBridgeable
public class RestService: QmlInstantiableStatus {
    public let sslSupported: Bool = true
    private let api: ServiceApi = ServiceApi()

    required public init() {
    }

    public func setUrl(url: String) {
        guard let baseUrl = URL(string: url) else {
            return
        }

        if (baseUrl == api.baseUrl) {
            return
        }

        api.baseUrl = baseUrl

        // reqres.in requires an API-key, see https://reqres.in/signup
        if ((baseUrl.host()?.starts(with: "reqres")) != nil) {
            api.commonHeaders = ["x-api-key": "reqres-free-v1"]
        }
    }

    public func componentComplete() {
        for child in qmlChildren {
            if let resource = child as? AbstractResource {
                resource.api = api
            }
        }
    }
}
