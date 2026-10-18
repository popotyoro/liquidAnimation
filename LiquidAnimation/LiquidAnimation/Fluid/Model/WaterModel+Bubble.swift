extension WaterModel {
    /// 水中の装飾用気泡。水量には含めない。
    struct Bubble {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var radius: Double
        var age: Double
        var lifetime: Double
        var phase: Double
        var isCarbonated = false
    }
}
