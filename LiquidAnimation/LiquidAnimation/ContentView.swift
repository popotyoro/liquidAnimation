import SwiftUI

struct ContentView: View {
    @State private var controls: FluidControls
    @State private var selectedTab: LiquidDemoTab
    @State private var showsSettings = false

    init(controls: FluidControls = FluidControls(), initialTab: LiquidDemoTab = .pour) {
        _controls = State(initialValue: controls)
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("注ぐ", systemImage: "drop", value: LiquidDemoTab.pour) {
                LiquidPourDemoView(controls: controls, isActive: selectedTab == .pour) {
                    showsSettings = true
                }
            }
            Tab("溜める", systemImage: "rectangle.stack", value: LiquidDemoTab.fill) {
                LiquidFillDemoView(controls: controls, openSettings: { showsSettings = true })
            }
        }
        .sheet(isPresented: $showsSettings) {
            FluidSettingsView(controls: controls)
                .presentationDetents([.medium, .large])
        }
        .alert("液体の計算を続けられません", isPresented: Binding(
            get: { controls.error != nil },
            set: { if !$0 { controls.error = nil; controls.reset() } }
        )) {
            Button("リセット") { controls.error = nil; controls.reset() }
        } message: {
            Text(controls.error ?? "")
        }
    }
}

#Preview {
    ContentView()
}
