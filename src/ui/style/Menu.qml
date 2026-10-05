pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Fusion as Fusion

// Fusion's Menu whose action rows are this style's MenuItem.
Fusion.Menu {
    delegate: MenuItem {}
}
