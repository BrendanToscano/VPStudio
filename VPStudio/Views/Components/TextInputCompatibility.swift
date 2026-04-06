import SwiftUI

extension View {
    @ViewBuilder
    func disableAutomaticTextEntryAdjustments() -> some View {
        #if os(macOS)
        self
            .autocorrectionDisabled()
        #else
        self
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        #endif
    }
}
