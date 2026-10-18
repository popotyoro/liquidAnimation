import Foundation
import Testing
@testable import LiquidAnimation

struct BeerFoamTests {
    @Test("着水のない空の容器には泡も白濁も生じない")
    func emptyContainerRemainsClear() {
        var foam = BeerFoam()
        foam.advance(by: 1, arrivingArea: 0, landedArea: 0, capacity: 1)
        #expect(foam.liquidArea == 0)
        #expect(foam.cloudiness == 0)
    }

    @Test("着水した液体の一部が泡になり液中が白濁する")
    func arrivalsCreateFoamAndCloudiness() {
        var foam = BeerFoam()
        foam.advance(by: 1 / 60, arrivingArea: 0.1, landedArea: 0.1, capacity: 1)
        #expect(foam.liquidArea > 0 && foam.liquidArea < 0.1)
        #expect(foam.cloudiness > 0 && foam.cloudiness <= 1)
    }

    @Test("着水が止まると6秒で泡の保持液量が約37パーセントへ減る")
    func foamDrainsAfterArrivalsStop() {
        var foam = pouringFoam()
        let initialArea = foam.liquidArea
        let initialCloudiness = foam.cloudiness
        foam.advance(by: 6, arrivingArea: 0, landedArea: 0.1, capacity: 1)
        #expect(abs(foam.liquidArea / initialArea - exp(-1.0)) < 1e-12)
        #expect(foam.cloudiness < initialCloudiness)
    }

    @Test("着水のない期間の排液と白濁の減衰は時間の分割数に依存しない")
    func drainageIsIndependentOfTimePartition() {
        var whole = pouringFoam()
        var divided = whole
        whole.advance(by: 6, arrivingArea: 0, landedArea: 0.1, capacity: 1)
        for _ in 0..<360 {
            divided.advance(by: 1 / 60, arrivingArea: 0, landedArea: 0.1, capacity: 1)
        }
        #expect(abs(whole.liquidArea - divided.liquidArea) < 1e-12)
        #expect(abs(whole.cloudiness - divided.cloudiness) < 1e-12)
    }

    private func pouringFoam() -> BeerFoam {
        var foam = BeerFoam()
        foam.advance(by: 1 / 60, arrivingArea: 0.1, landedArea: 0.1, capacity: 1)
        return foam
    }
}
