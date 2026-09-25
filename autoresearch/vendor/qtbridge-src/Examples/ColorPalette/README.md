# Qt Bridge - Swift - ColorPalette Client Example

> Copyright (C) 2025 The Qt Company Ltd.
> SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

## Table of Contents

1. [Overview](#overview)
2. [Backend Options](#backend-options)
3. [Terms and Conditions](#terms-and-conditions)

## Overview

A QML-based color palette client written in Swift using QtBridge for Swift.
This example demonstrates how to connect a Swift backend to a QML frontend
and interact with a REST API.

## Backend Options

You can run the client against one of two backends:

### 1. Public REST API Test Server

A public demo API available at https://reqres.in

- Requires an API key (see reqres.in for details)
- Provides sample users and color data
- Changes (add/edit/delete) are **not persisted**

### 2. Local Qt-based REST API Server

You can build and run the official Qt C++ example:
https://doc.qt.io/qt-6/qthttpserver-colorpalette-example.html

- Runs a local server with full functionality
- Supports Create, Read, Update, and Delete operations

## Terms and Conditions

If you, your employer, or the legal entity you act on behalf of hold commercial license(s) with a Qt
Group entity, Qt Bridges constitutes Pre-Release Code under the Qt License/Frame Agreement governing
those licenses, and that agreement's terms and conditions relating to Pre-Release Code apply to your
use of Qt Bridges as found in this repo.
This Qt Bridges repo may provide links or access to third-party libraries or code (collectively
"Third-Party Software") to implement various functions. Use or distribution of Third-Party Software
is discretionary and in all respects subject to applicable license terms of applicable third-party
right holders.

### Additional Terms and Conditions

The Qt Bridge for Swift is built using the Swift programming language and related tools provided by
the Swift Project.
Swift and its associated components are licensed under the Apache License, Version 2.0 with Runtime
Library Exception
