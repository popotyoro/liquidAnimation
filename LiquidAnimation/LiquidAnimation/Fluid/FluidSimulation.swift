import Foundation
import Metal

/// 物理モデルと、GPUが読む共有メモリを所有する。
/// WaterModelがDoubleで計算した結果を、描画用のFloatへ変換する。
final class FluidSimulation {
    let model: WaterModel
    let surfaceBuffer: any MTLBuffer
    let streamBuffer: any MTLBuffer
    let splashBuffer: any MTLBuffer
    let bubbleBuffer: any MTLBuffer
    private(set) var bubbleVertexCount = 0
    private(set) var splashVertexCount = 0
    private(set) var streamVertexCount = 0

    init(device: any MTLDevice, aspectRatio: Double) throws {
        model = WaterModel(aspectRatio: aspectRatio)
        guard let surface = device.makeBuffer(length: model.columnCount * MemoryLayout<Float>.stride,
                                              options: .storageModeShared),
              let stream = device.makeBuffer(length: WaterModel.maximumStreamVertices * MemoryLayout<WaterVertex>.stride,
                                             options: .storageModeShared),
              let splash = device.makeBuffer(length: WaterModel.maximumDrops * 6 * MemoryLayout<WaterVertex>.stride,
                                             options: .storageModeShared),
              let bubbles = device.makeBuffer(length: WaterModel.maximumBubbles * 6 * MemoryLayout<BubbleVertex>.stride,
                                              options: .storageModeShared) else {
            throw FluidError.unavailable("水面の描画メモリを確保できませんでした。")
        }
        surfaceBuffer = surface
        streamBuffer = stream
        splashBuffer = splash
        bubbleBuffer = bubbles
    }

    /// CPU上の最新状態を共有バッファへ転送する。
    /// 呼び出し側は、前フレームのGPU使用が完了した後にだけ書き換えること。
    func uploadSurface() {
        let heights = surfaceBuffer.contents().bindMemory(to: Float.self, capacity: model.columnCount)
        for i in model.depths.indices { heights[i] = Float(model.depths[i] / model.height) }
        bubbleVertexCount = upload(model.bubbleVertices(), to: bubbleBuffer)
        splashVertexCount = upload(model.splashVertices(), to: splashBuffer)
        streamVertexCount = upload(model.streamVertices(), to: streamBuffer)
    }

    private func upload<Vertex>(_ vertices: [Vertex], to buffer: any MTLBuffer) -> Int {
        vertices.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress, !bytes.isEmpty {
                memcpy(buffer.contents(), base, bytes.count)
            }
        }
        return vertices.count
    }
}
