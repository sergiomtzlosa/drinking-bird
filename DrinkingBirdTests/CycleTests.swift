import XCTest
@testable import DrinkingBird

/// End-to-end cycle behavior of the whole engine.
final class CycleTests: XCTestCase {
    var engine = SimulationEngine(dials: .standard)

    func run(_ seconds: Double, engine engineToUse: inout SimulationEngine) {
        let steps = Int(seconds / SimulationEngine.substep)
        for _ in 0 ..< steps {
            engineToUse.step(dt: SimulationEngine.substep)
        }
    }

    func testDefaultDialsProduceRepeatingDrinkCycles() throws {
        run(600, engine: &engine)
        XCTAssertGreaterThanOrEqual(engine.state.cycleCount, 4,
            "The bird should drink several times within 600 simulated seconds.")
        if let period = engine.state.lastCyclePeriod {
            XCTAssertGreaterThan(period, 5, "A drink cycle shouldn't be comically fast.")
            XCTAssertLessThan(period, 200, "A drink cycle shouldn't be comically slow.")
        }
    }

    func testTipFiresWhenHeadIsFilledManually() {
        var fresh = SimulationEngine(dials: Dials(roomTemperature: 22, humidity: 0.0, airflow: 0.0))
        fresh.state.headLiquidVolume = 0.6 * BirdGeometry.headCapacity
        fresh.state.bulbLiquidVolume = BirdGeometry.liquidChargeVolume - fresh.state.headLiquidVolume
        run(3, engine: &fresh)
        XCTAssertTrue(fresh.state.beakInWater, "A head-heavy bird must tip and drink.")
    }

    func testHighHumidityStallsTheBird() {
        var stalled = SimulationEngine(dials: Dials(humidity: 0.95, airflow: 0.0))
        run(600, engine: &stalled)
        XCTAssertFalse(stalled.state.beakInWater,
            "At ~95% RH the felt can barely evaporate — the toy stalls.")
        XCTAssertEqual(stalled.state.cycleCount, 0)
    }

    func testVaporEqualizationIsFiniteNotInstantaneous() {
        var fresh = SimulationEngine(dials: .standard)
        fresh.state.headLiquidVolume = 0.5 * BirdGeometry.headCapacity
        // Force the tip so the vapor shortcut opens.
        run(3, engine: &fresh)
        XCTAssertTrue(fresh.state.beakInWater)
        let dPAtContact = abs(fresh.state.pressureDelta)
        // Advance a little: ΔP must be shrinking, but not yet zero.
        run(0.05, engine: &fresh)
        let dPLater = abs(fresh.state.pressureDelta)
        XCTAssertLessThan(dPLater, dPAtContact, "Vapor shortcut should be pulling ΔP down.")
        XCTAssertGreaterThan(dPLater, 0.02 * dPAtContact, "…but strictly finite-time.")
    }

    func testDichloromethaneAlsoCompletesCycles() {
        var dcm = SimulationEngine(dials: Dials(fluid: .dichloromethane))
        run(600, engine: &dcm)
        XCTAssertGreaterThanOrEqual(dcm.state.cycleCount, 1,
            "The classic DCM toy should also drink (much faster than IPA).")
        if let period = dcm.state.lastCyclePeriod {
            XCTAssertGreaterThan(period, 3, "Sanity: not comically fast.")
        }
    }

    func testNoNaNAndBoundedAngleOverLongRun() {
        run(900, engine: &engine)
        XCTAssertFalse(engine.state.angle.isNaN)
        XCTAssertFalse(engine.state.angularVelocity.isNaN)
        XCTAssertFalse(engine.state.headTemperature.isNaN)
        XCTAssertLessThanOrEqual(engine.state.angle, BirdGeometry.contactAngle + 1e-9)
        XCTAssertGreaterThanOrEqual(engine.state.angle, BirdGeometry.maxBackwardLean - 1e-9)
    }
}
