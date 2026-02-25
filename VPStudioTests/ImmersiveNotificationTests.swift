import Foundation
import Testing
@testable import VPStudio

@Suite("Immersive Notification Names")
struct ImmersiveNotificationTests {

    @Test("All immersive control notifications have unique names")
    func uniqueNames() {
        let names: [Notification.Name] = [
            .immersiveTapCatcherDidFire,
            .immersiveControlTogglePlayPause,
            .immersiveControlSeekBack,
            .immersiveControlSeekForward,
            .immersiveControlSeekToPercent,
            .immersiveControlPreviousChapter,
            .immersiveControlNextChapter,
            .immersiveControlCycleRate,
            .immersiveControlToggleSubtitles,
            .immersiveControlToggleAudio,
            .immersiveControlRequestEnvironmentSwitch,
            .immersiveControlDismiss,
            .immersiveControlCycleScreenSize,
        ]
        let rawValues = names.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count, "All notification names must be unique")
    }

    @Test("All immersive control notifications use VPStudio prefix")
    func vpStudioPrefix() {
        let names: [Notification.Name] = [
            .immersiveTapCatcherDidFire,
            .immersiveControlTogglePlayPause,
            .immersiveControlSeekBack,
            .immersiveControlSeekForward,
            .immersiveControlSeekToPercent,
            .immersiveControlPreviousChapter,
            .immersiveControlNextChapter,
            .immersiveControlCycleRate,
            .immersiveControlToggleSubtitles,
            .immersiveControlToggleAudio,
            .immersiveControlRequestEnvironmentSwitch,
            .immersiveControlDismiss,
            .immersiveControlCycleScreenSize,
        ]
        for name in names {
            #expect(name.rawValue.hasPrefix("VPStudio."), "\(name.rawValue) missing VPStudio prefix")
        }
    }

    @Test("SeekToPercent notification carries NSNumber payload")
    func seekToPercentPayload() {
        let percent = 0.42
        let notification = Notification(
            name: .immersiveControlSeekToPercent,
            object: NSNumber(value: percent)
        )
        let recovered = (notification.object as? NSNumber)?.doubleValue
        #expect(recovered == percent)
    }

    @Test("New notification names exist for chapter navigation")
    func chapterNotifications() {
        // These should compile — verifying they exist.
        _ = Notification.Name.immersiveControlPreviousChapter
        _ = Notification.Name.immersiveControlNextChapter
    }

    @Test("New notification names exist for secondary controls")
    func secondaryControlNotifications() {
        _ = Notification.Name.immersiveControlCycleRate
        _ = Notification.Name.immersiveControlToggleSubtitles
        _ = Notification.Name.immersiveControlToggleAudio
        _ = Notification.Name.immersiveControlRequestEnvironmentSwitch
        _ = Notification.Name.immersiveControlDismiss
        _ = Notification.Name.immersiveControlCycleScreenSize
    }
}
