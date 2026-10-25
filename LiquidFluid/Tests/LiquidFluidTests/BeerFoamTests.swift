import Foundation
import Testing
@testable import LiquidFluid

/// 各ケースで値型の泡を作り、後始末はローカル値の破棄で完了する。
struct BeerFoamTests {
    @Test("着水のない空の容器には泡の保持液量が生じない")
    func emptyContainerDoesNotDevelopFoam() {
        // 準備
        var foam = BeerFoam()

        // 実行
        foam.advance(by: 1, arrivingArea: 0, landedArea: 0, capacity: 1)

        // 検証
        #expect(foam.liquidArea == 0)
    }

    @Test("着水のない空の容器は白濁しない")
    func emptyContainerRemainsClear() {
        // 準備
        var foam = BeerFoam()

        // 実行
        foam.advance(by: 1, arrivingArea: 0, landedArea: 0, capacity: 1)

        // 検証
        #expect(foam.cloudiness == 0)
    }

    @Test("着水した液体の一部が泡に保持される")
    func arrivalsCreateFoam() {
        // 準備
        var foam = BeerFoam()

        // 実行
        foam.advance(by: 1 / 60, arrivingArea: 0.1, landedArea: 0.1, capacity: 1)

        // 検証
        #expect(foam.liquidArea > 0)
        #expect(foam.liquidArea < 0.1)
    }

    @Test("着水すると液中の白濁度が0より大きく1以下になる")
    func arrivalsCreateCloudiness() {
        // 準備
        var foam = BeerFoam()

        // 実行
        foam.advance(by: 1 / 60, arrivingArea: 0.1, landedArea: 0.1, capacity: 1)

        // 検証
        #expect(foam.cloudiness > 0)
        #expect(foam.cloudiness <= 1)
    }

    @Test("着水が止まると6秒で泡の保持液量が約37パーセントへ減る")
    func foamDrainsAfterArrivalsStop() {
        // 準備
        var foam = pouringFoam()
        let initialArea = foam.liquidArea

        // 実行
        foam.advance(by: 6, arrivingArea: 0, landedArea: 0.1, capacity: 1)

        // 検証
        #expect(abs(foam.liquidArea / initialArea - exp(-1.0)) < 1e-12)
    }

    @Test("着水が止まると液中の白濁度が下がる")
    func cloudinessFadesAfterArrivalsStop() {
        // 準備
        var foam = pouringFoam()
        let initialCloudiness = foam.cloudiness

        // 実行
        foam.advance(by: 6, arrivingArea: 0, landedArea: 0.1, capacity: 1)

        // 検証
        #expect(foam.cloudiness < initialCloudiness)
    }

    @Test("着水のない期間の泡の排液量は時間の分割数に依存しない")
    func drainageIsIndependentOfTimePartition() {
        // 準備
        var whole = pouringFoam()
        var divided = whole

        // 実行
        whole.advance(by: 6, arrivingArea: 0, landedArea: 0.1, capacity: 1)
        for _ in 0..<360 {
            divided.advance(by: 1 / 60, arrivingArea: 0, landedArea: 0.1, capacity: 1)
        }

        // 検証
        #expect(abs(whole.liquidArea - divided.liquidArea) < 1e-12)
    }

    @Test("着水のない期間の白濁度の減衰は時間の分割数に依存しない")
    func clearingIsIndependentOfTimePartition() {
        // 準備
        var whole = pouringFoam()
        var divided = whole

        // 実行
        whole.advance(by: 6, arrivingArea: 0, landedArea: 0.1, capacity: 1)
        for _ in 0..<360 {
            divided.advance(by: 1 / 60, arrivingArea: 0, landedArea: 0.1, capacity: 1)
        }

        // 検証
        #expect(abs(whole.cloudiness - divided.cloudiness) < 1e-12)
    }

    private func pouringFoam() -> BeerFoam {
        var foam = BeerFoam()
        foam.advance(by: 1 / 60, arrivingArea: 0.1, landedArea: 0.1, capacity: 1)
        return foam
    }
}
