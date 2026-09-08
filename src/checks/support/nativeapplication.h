#pragma once

namespace checks {

// Gives an unbundled Cocoa check executable a foreground-capable AppKit
// application before a native-window harness creates its first window.
bool prepareNativeApplication();

} // namespace checks
