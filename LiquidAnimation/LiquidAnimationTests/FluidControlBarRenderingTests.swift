import Foundation
import SwiftUI
import Testing
import UIKit
@testable import LiquidAnimation

@MainActor
struct FluidControlBarRenderingTests {
    @Test("注水バーの操作と計測値を通常・拡大文字で描画できる",
          arguments: [DynamicTypeSize.large, .xxxLarge])
    func metricsRemainVisible(textSize: DynamicTypeSize) throws {
        let controls = FluidControls()
        controls.framesPerSecond = 60
        controls.gpuMilliseconds = 1.2
        controls.simulationMilliseconds = 3.4
        controls.insertedFraction = 0.5

        let content = FluidControlBar(controls: controls, openSettings: {})
            .frame(width: 360)
            .padding(16)
            .background(Color(uiColor: .systemGroupedBackground))
            .environment(\.dynamicTypeSize, textSize)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let data = try #require(UIImage(cgImage: image).pngData())
        let name = textSize == .large ? "standard" : "large-text"
        let url = URL.temporaryDirectory.appendingPathComponent("fluid-controls-\(name).png")
        try data.write(to: url)
        print("Control bar render: \(url.path)")
    }
}
