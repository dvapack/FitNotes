import UIKit

enum ScreenWakeLockController {
    static func setEnabled(_ isEnabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = isEnabled
    }
}
