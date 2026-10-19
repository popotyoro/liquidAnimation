import SwiftUI

struct LiquidPourDemoView: View {
    let controls: FluidControls
    let isActive: Bool
    let openSettings: () -> Void

    var body: some View {
        DemoBackground(kind: controls.configuration.kind)
            .liquidOverlay(controls: controls, ignoresSafeArea: true, isActive: isActive)
            .overlay(alignment: .bottom) {
                FluidControlBar(controls: controls, openSettings: openSettings)
                    .padding(.horizontal).padding(.bottom, 8)
            }
    }
}
