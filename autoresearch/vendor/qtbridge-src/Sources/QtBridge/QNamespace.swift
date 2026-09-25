// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import Foundation
import QtBridgeCpp

internal struct ItemDataRole {
    public static let DisplayRole = Int32(QtBridgeCpp.Qt.DisplayRole.rawValue)
    public static let DecorationRole = Int32(QtBridgeCpp.Qt.DecorationRole.rawValue)
    public static let EditRole = Int32(QtBridgeCpp.Qt.EditRole.rawValue)
    public static let ToolTipRole = Int32(QtBridgeCpp.Qt.ToolTipRole.rawValue)
    public static let StatusTipRole = Int32(QtBridgeCpp.Qt.StatusTipRole.rawValue)
    public static let WhatsThisRole = Int32(QtBridgeCpp.Qt.WhatsThisRole.rawValue)
    // Metadata
    public static let FontRole = Int32(QtBridgeCpp.Qt.FontRole.rawValue)
    public static let TextAlignmentRole =
        Int32(QtBridgeCpp.Qt.TextAlignmentRole.rawValue)
    public static let BackgroundRole = Int32(QtBridgeCpp.Qt.BackgroundRole.rawValue)
    public static let ForegroundRole = Int32(QtBridgeCpp.Qt.ForegroundRole.rawValue)
    public static let CheckStateRole = Int32(QtBridgeCpp.Qt.CheckStateRole.rawValue)
    // Accessibility
    public static let AccessibleTextRole =
        Int32(QtBridgeCpp.Qt.AccessibleTextRole.rawValue)
    public static let AccessibleDescriptionRole =
        Int32(QtBridgeCpp.Qt.AccessibleDescriptionRole.rawValue)
    // More general purpose
    public static let SizeHintRole = Int32(QtBridgeCpp.Qt.SizeHintRole.rawValue)
    public static let InitialSortOrderRole =
        Int32(QtBridgeCpp.Qt.InitialSortOrderRole.rawValue)
    // Internal UiLib roles
    public static let DisplayPropertyRole =
        Int32(QtBridgeCpp.Qt.DisplayPropertyRole.rawValue)
    public static let DecorationPropertyRole =
        Int32(QtBridgeCpp.Qt.DecorationPropertyRole.rawValue)
    public static let ToolTipPropertyRole =
        Int32(QtBridgeCpp.Qt.ToolTipPropertyRole.rawValue)
    public static let StatusTipPropertyRole =
        Int32(QtBridgeCpp.Qt.StatusTipPropertyRole.rawValue)
    public static let WhatsThisPropertyRole =
        Int32(QtBridgeCpp.Qt.WhatsThisPropertyRole.rawValue)
    // Reserved
    public static let UserRole = Int32(QtBridgeCpp.Qt.UserRole.rawValue)
}

internal struct ItemFlags {
    public static let NoItemFlags = Int32(QtBridgeCpp.Qt.NoItemFlags.rawValue)
    public static let ItemIsSelectable = Int32(QtBridgeCpp.Qt.ItemIsSelectable.rawValue)
    public static let ItemIsEditable = Int32(QtBridgeCpp.Qt.ItemIsEditable.rawValue)
    public static let ItemIsDragEnabled = Int32(QtBridgeCpp.Qt.ItemIsDragEnabled.rawValue)
    public static let ItemIsDropEnabled = Int32(QtBridgeCpp.Qt.ItemIsDropEnabled.rawValue)
    public static let ItemIsUserCheckable = Int32(QtBridgeCpp.Qt.ItemIsUserCheckable.rawValue)
    public static let ItemIsEnabled = Int32(QtBridgeCpp.Qt.ItemIsEnabled.rawValue)
    public static let ItemIsAutoTristate = Int32(QtBridgeCpp.Qt.ItemIsAutoTristate.rawValue)
    public static let ItemNeverHasChildren = Int32(QtBridgeCpp.Qt.ItemNeverHasChildren.rawValue)
    public static let ItemIsUserTristate = Int32(QtBridgeCpp.Qt.ItemIsUserTristate.rawValue)
}
