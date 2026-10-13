/// How often the app should re-read Core Audio. Nobody watches the list while the popover is
/// closed, so scanning is demand-driven: fast while the list is on screen, relaxed while something
/// still needs a background look, and off otherwise.
public enum ScanPolicy {
    public static let active: Double = 1
    public static let background: Double = 5

    /// Seconds between scans, or nil for "do not scan on a timer".
    /// - `listVisible`: the menu bar popover or the Settings window is open.
    /// - `menuBarIconShown`: the icon's idle/active state needs refreshing.
    /// - `reaping`: auto-quit of headless browsers is on, so it must keep watching.
    public static func interval(listVisible: Bool, menuBarIconShown: Bool, reaping: Bool) -> Double? {
        if listVisible { return active }
        if menuBarIconShown || reaping { return background }
        return nil
    }
}
