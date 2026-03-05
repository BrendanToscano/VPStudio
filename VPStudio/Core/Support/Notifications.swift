import Foundation

extension Notification.Name {
    static let libraryDidChange = Notification.Name("VPStudio.LibraryDidChange")
    static let tasteProfileDidChange = Notification.Name("VPStudio.TasteProfileDidChange")
    static let downloadsDidChange = Notification.Name("VPStudio.DownloadsDidChange")
    static let environmentsDidChange = Notification.Name("VPStudio.EnvironmentsDidChange")
    static let indexersDidChange = Notification.Name("VPStudio.IndexersDidChange")
    static let tmdbApiKeyDidChange = Notification.Name("VPStudio.TMDBApiKeyDidChange")
    static let tabSelectionDidChange = Notification.Name("VPStudio.TabSelectionDidChange")
    static let discoverRefreshRequested = Notification.Name("VPStudio.DiscoverRefreshRequested")
    static let setupDidComplete = Notification.Name("VPStudio.SetupDidComplete")

    // Immersive space control bridge
    static let immersiveTapCatcherDidFire = Notification.Name("VPStudio.ImmersiveTapCatcherDidFire")
    static let immersiveControlTogglePlayPause = Notification.Name("VPStudio.ImmersiveControl.TogglePlayPause")
    static let immersiveControlSeekBack = Notification.Name("VPStudio.ImmersiveControl.SeekBack")
    static let immersiveControlSeekForward = Notification.Name("VPStudio.ImmersiveControl.SeekForward")
    static let immersiveControlSeekToPercent = Notification.Name("VPStudio.ImmersiveControl.SeekToPercent")
    static let immersiveControlPreviousChapter = Notification.Name("VPStudio.ImmersiveControl.PreviousChapter")
    static let immersiveControlNextChapter = Notification.Name("VPStudio.ImmersiveControl.NextChapter")
    static let immersiveControlCycleRate = Notification.Name("VPStudio.ImmersiveControl.CycleRate")
    static let immersiveControlToggleSubtitles = Notification.Name("VPStudio.ImmersiveControl.ToggleSubtitles")
    static let immersiveControlToggleAudio = Notification.Name("VPStudio.ImmersiveControl.ToggleAudio")
    static let immersiveControlRequestEnvironmentSwitch = Notification.Name("VPStudio.ImmersiveControl.RequestEnvironmentSwitch")
    static let immersiveControlDismiss = Notification.Name("VPStudio.ImmersiveControl.Dismiss")
    static let immersiveControlCycleScreenSize = Notification.Name("VPStudio.ImmersiveControl.CycleScreenSize")

    // Main window lifecycle
    static let mainWindowDidActivate = Notification.Name("mainWindowDidActivate")
}
