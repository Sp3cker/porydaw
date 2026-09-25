# ``QtBridge``

Build Qt Quick applications with a Swift backend.

## Overview

**Qt Bridge for Swift** is a framework that connects Swift application logic with
[Qt Quick](https://doc.qt.io/qt-6/qtquick-index.html) as the user interface.
It provides a lightweight bridge between the two ecosystems, allowing developers
to write models, services, and business logic in Swift while using
[QML](https://doc.qt.io/qt-6/qmlreference.html) to build modern declarative UIs.

**Qt Bridge for Swift** is designed for developers who want to experiment with
**Qt** and **QML** without commiting to a full C++ application stack. Instead
of rewriting application logic in C++, you can keep your core logic in Swift
while leveraging **Qt**'s mature UI framework and tooling.

The repository includes example applications and project templates demonstrating
the recommended project structure, how to model data in Swift, and how to connect
those models to **QML** views.

> Important:
> **Qt Bridge for Swift** is currently in early preview, and in active development.
Notable limitations include API changes and missing features.
