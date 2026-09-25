# Qt Bridge - Swift - Pre Release

> Copyright (C) 2025 The Qt Company Ltd.
> SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

## Contents

1. [Introduction](#introduction)
2. [Status](#status)
3. [Supported platforms](#supported-platforms)
4. [Requirements](#requirements)
5. [Installing Qt Bridge](#installing-qt-bridge)
    1. [Importing Qt Bridge as a remote package](#importing-qt-bridge-as-a-remote-package)
    2. [Importing Qt Bridge as a local package](#importing-qt-bridge-as-a-local-package)
    3. [Disable Library Validation Entitlement](#disable-library-validation-entitlement)
6. [Running examples](#running-examples)
7. [Using Xcode templates](#using-xcode-templates)
8. [Stay in touch](#stay-in-touch)
9. [Terms and Conditions](#terms-and-conditions)

## Introduction

Qt Bridge for Swift is a bridge between Swift and QML, designed to write application logic in
Swift while using Qt Quick for the UI. Bridging mechanism is based on Swift and C++
interoperability.

Qt Bridge for Swift is intended for Apple developers who want to experiment with Qt and/or QML
without committing to a full C++ application. The repository includes example applications
and Xcode templates that demonstrate the recommended project structure, how to model data
and logic in Swift, and how to connect those models to QML views.

Detailed documentation can be found [here](https://doc-snapshots.qt.io/qtbridges-dev/qtbridges-swift-index.html).

## Status

Qt Bridge for Swift is currently in early preview, and in active development.

Notable limitations include:
- APIs may change or even be removed.
- There are many known issues and missing features.

## Supported platforms

The following platforms are currently supported:
- **macOS (Apple Silicon)**
- **Linux (x86_64, aarch64)**
- **Windows (x64, MSVC 2022)**

Support for additional platforms is planned in the future.

## Requirements

### Swift
- **Swift 6.2** or later

### For Swift Package Manager builds
- **macOS 14** or later
- [Xcode](https://developer.apple.com/xcode/) or [Swift Package Manager](https://github.com/swiftlang/swift-package-manager)

### For CMake builds
- **macOS 14** or later (for macOS), **Linux** or **Windows 11**
- [CMake](https://cmake.org/) **3.22** or later
- [Ninja](https://ninja-build.org/)
- [Qt](https://www.qt.io/) **6.10** or later

## Installing Qt Bridge

Qt Bridge can be added to your project via Swift Package Manager or CMake.

### Importing Qt Bridge as a remote package

#### Add via Xcode

1. In Xcode, select *File* → *Add Package Dependencies*.
2. Enter https://github.com/qt/qtbridge-swift
3. Enable Swift-C++ interoperability:
    1. Go to the target's *Build Settings*.
    2. Switch the filter to *All + Combined*.
    3. Search for *Interoperability*.
    4. Under *Swift Compiler - Language*, set *C++ and Objective-C Interoperability* mode to *C++/Objective-C++*.

#### Add via Package.swift

1. Specify the Qt Bridge package URL in the dependencies section.
2. Link the *QtBridge* product to your target.
3. Enable Swift-C++ interoperability in *swiftSettings* with .*interoperabilityMode(.Cxx)* mode.
```
dependencies: [
    .package(url: "https://github.com/qt/qtbridge-swift", exact: "0.2.0-beta")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "QtBridge", package: "qtbridge-swift")
        ],
        swiftSettings: [
            .interoperabilityMode(.Cxx)
        ]
    )
]
```

#### Add via CMakeLists.txt

For CMake-based projects, use `FetchContent` to fetch Qt Bridge from the repository:
```cmake
cmake_minimum_required(VERSION 3.22)
project(MyApp LANGUAGES CXX Swift)

add_executable(MyApp Sources/app.swift)

include(FetchContent)
FetchContent_Declare(QtBridge
    GIT_REPOSITORY https://github.com/qt/qtbridge-swift.git
    GIT_TAG 0.2.0-beta
)
FetchContent_MakeAvailable(QtBridge)

target_link_libraries(MyApp PRIVATE QtBridge)
```

Configure and build with Ninja:
```sh
cmake -G Ninja -B build
cmake --build build
```

**Note:** Qt 6.10+ must be in your `PATH` or set via `CMAKE_PREFIX_PATH`.

### Importing Qt Bridge as a local package

Firstly, clone the [Qt Bridge for Swift repo](https://github.com/qt/qtbridge-swift):

```sh
git clone https://github.com/qt/qtbridge-swift
cd qtbridge-swift
git checkout 0.2.0-beta
```

#### Add via Xcode

1. In Xcode, select *File* → *Add Package Dependencies*.
2. Click the *Add Local* button and select the folder that contains cloned Qt Bridge repo.
3. Enable Swift-C++ interoperability:
    1. Go to the target's *Build Settings*.
    2. Switch the filter to *All + Combined*.
    3. Search for *Interoperability*.
    4. Under *Swift Compiler - Language*, set *C++ and Objective-C Interoperability* mode to *C++/Objective-C++*.

#### Add via Package.swift

1. Specify a path to the cloned Qt Bridge repo in the dependencies section.
2. Link *QtBridge* product to your target.
3. Enable Swift-C++ interoperability in *swiftSettings* with .*interoperabilityMode(.Cxx)* mode.

```
dependencies: [
    .package(path: "path/to/qtbridge-swift")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "QtBridge", package: "qtbridge-swift")
        ],
        swiftSettings: [
            .interoperabilityMode(.Cxx)
        ]
    )
]
```

#### Add via CMakeLists.txt

For local development, point `FetchContent` at your local clone:
```cmake
cmake_minimum_required(VERSION 3.22)
project(MyApp LANGUAGES CXX Swift)

add_executable(MyApp Sources/app.swift)

include(FetchContent)
FetchContent_Declare(QtBridge
    SOURCE_DIR "path/to/qtbridge-swift"
)
FetchContent_MakeAvailable(QtBridge)

target_link_libraries(MyApp PRIVATE QtBridge)
```
Configure and build with Ninja:

```sh
cmake -G Ninja -B build
cmake --build build
```

### Disable Library Validation Entitlement

When you use a Team in Xcode and enable automatic signing, Xcode may enable the
**Hardened Runtime** for the generated macOS app target. With Hardened Runtime enabled,
macOS enforces **library validation**, which restricts the app to loading only system
libraries and libraries signed with a compatible signature. Qt Bridge loads additional
Qt frameworks at runtime, and this can cause the app to fail to launch when library
validation is enabled.

To fix this:

1. Open the *Signing & Capabilities* tab.
2. Select your app target.
3. Expand *Hardened Runtime*.
4. Manually chech *Disable Library Validation*.

Alternatively, you can disable *Hardened Runtime* entirely by clicking *Delete* next to
it, but disabling Library Validation alone is sufficient.

## Running examples

**Examples** directory contains simple projects implemented with Qt Bridge. For instance,
to build and run MinimalApp:

### With Xcode

```sh
cd qtbridge-swift/Examples/MinimalApp

xcodebuild \
  -project MinimalApp.xcodeproj \
  -scheme MinimalApp \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  build

open build/Build/Products/Debug/MinimalApp.app
```

### With CMake
```sh
cd qtbridge-swift/Examples/MinimalApp/MinimalApp
cmake -G Ninja -B build
cmake --build build

# Run the application
open build/MinimalApp.app   # macOS
./build/MinimalApp          # Linux
```

## Using Xcode templates

**Templates** directory contains:

- **a project template** for starting a new Swift + QML macOS application
- **file templates** for adding Swift models and QML views

### Installing the templates into Xcode

Copy `Templates` folder into `~/Library/Developer/Xcode/Templates/`.

### Creating a new project from the Qt Bridge project template

1. Open Xcode.
2. Choose *Create New Project...*
3. In the template chooser, select the *macOS* platform.
4. Scroll down to *Qt Bridge* section.
5. Select the *Qt Bridge* project template and click *Next*.
6. Fill in the template options:
  - *Product Name* – the name of the application (also used for the target name and
  bundle name).
  - *Organization Identifier* – a reverse-DNS identifier such as com.example.
  - *Model Type Name* – the Swift type used as the backend model, for example MyModel.
  - *QML File Name* – the base name of the initial QML file, without the .qml
  extension (for example main or myView).
  - *Model Context Name* – the name under which the model is exposed to QML, usually in
  lowerCamelCase (for example myModel).
- Choose a location for the project and click *Create*.

7. The generated project will contain:

- an application entry point with `@main`,
- a Swift model type with the name you provided,
- a QML file with the chosen base name, already included in the app’s bundle
resources,
- a macOS app target with Swift/C++ interoperability enabled

8. The project template sets up the application structure, but you still need to add the
Qt Bridge as a package dependency.

### Running the example application

The generated project may fail to launch if **Hardened Runtime** is enabled because
Qt Bridge dynamically loads Qt frameworks at runtime. To fix this, you need to disable
**Library Validation**. For detailed instructions, see [Disable Library Validation Entitlement](#disable-library-validation-entitlement).

At this point, the example application is ready to run. You can do so, by pressing
the *Run* button. The project template configures the basic build settings and
target configuration. For more advanced configuration, you can adjust
*Build Settings* in the project navigator.

## Stay in touch

Feel free to reach out on our [Qt Bridges forum](https://forum.qt.io/category/78/qt-bridges)
or join the [Qt Bridges Discord](https://discord.com/invite/WNdGHnHagP) server.

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
