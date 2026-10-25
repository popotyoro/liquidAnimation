/// プリセット内部の近似係数。実測物性値ではなく、現在の浅水モデルで違いを出す調整値。
/// 粘度は運動量減衰・着水・飛沫・水流形状で近似し、粘性応力は解かない。
nonisolated struct FluidMaterial: Sendable {
    var momentumDamping = 2.8
    var inletSpeed = 1.6
    var splashScale = 1.0
    var impactScale = 1.0
    var streamWobble = 1.0
    var bubbleRadiusScale = 1.0
    var entrainmentInterval = 0.045
    /// nilなら溶存ガスの装飾用気泡を生成しない。単位は秒。
    var carbonationInterval: Double?
    var separatesTail = true
}
