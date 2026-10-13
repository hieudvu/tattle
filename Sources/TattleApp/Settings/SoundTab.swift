import SwiftUI

/// Same live list as the menu-bar popover, for people who keep Tattle out of
/// the menu bar and open the app instead.
struct SoundTab: View {
    let noise: NoiseModel?

    var body: some View {
        ScrollView {
            if let noise {
                NoiseList(model: noise)
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
            }
        }
    }
}
