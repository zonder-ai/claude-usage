import Foundation

/// Controls how usage is displayed in the macOS menu bar.
/// Raw values are persisted in UserDefaults via @AppStorage — do not change them.
public enum MenuBarStyle: String, CaseIterable {
    case percentage  // [logo] 42%
    case circle      // [logo] + circular progress ring
    case bar         // [logo] + horizontal progress bar
}
