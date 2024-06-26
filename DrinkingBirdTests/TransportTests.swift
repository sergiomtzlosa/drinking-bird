import XCTest
@testable import DrinkingBird

/// Thermodynamic + fluid invariants, independent of the mechanics layer.
final class TransportTests: XCTestCase {
    let dcm = FluidParams.dichloromethane
    let ipa = FluidParams.isopropanol

    func testSaturationPressureMatchesKnownValues() {
        // DCM boils at 39.6 °C → 1 atm by construction (tolerance covers rounding).
        XCTAssertEqual(ThermodynamicsModel.saturationPressure(dcm, celsius: 39.6), 101_325, accuracy: 600)
        // And IPA boils at 82.5 °C.
        XCTAssertEqual(ThermodynamicsModel.saturationPressure(ipa, celsius: 82.5), 101_325, accuracy: 600)
        // Monotone in temperature.
        XCTAssertGreaterThan(
            ThermodynamicsModel.saturationPressure(dcm, celsius: 25),
            ThermodynamicsModel.saturationPressure(dcm, celsius: 20))
    }

    func testLevelRisesWhenBulbIsWarmer() {
        var state = SimulationEngine(dials: .standard)
        for _ in 0 ..< 2_500 { state.step(dt: SimulationEngine.substep) }
        XCTAssertGreaterThan(state.state.neckColumnFraction, 0.02,
            "A thermal gradient should visibly start pumping the column.")
        XCTAssertGreaterThanOrEqual(state.state.pressureDelta, 0)
    }

    func testEvaporationIsMonotonicInAirflow() {
        let atRest = ThermodynamicsModel.evaporationPower(
            fluid: ipa, headTemperature: 18, roomTemperature: 22,
            humidity: 0.4, airflow: 0.0, moisture: 1.0)
        let withDraft = ThermodynamicsModel.evaporationPower(
            fluid: ipa, headTemperature: 18, roomTemperature: 22,
            humidity: 0.4, airflow: 1.5, moisture: 1.0)
        XCTAssertGreaterThan(withDraft, atRest)
    }

    func testHumidityKillsEvaporation() {
        let dryAir = ThermodynamicsModel.evaporationPower(
            fluid: ipa, headTemperature: 18, roomTemperature: 22,
            humidity: 0.05, airflow: 0.3, moisture: 1.0)
        let soakedAir = ThermodynamicsModel.evaporationPower(
            fluid: ipa, headTemperature: 18, roomTemperature: 22,
            humidity: 0.98, airflow: 0.3, moisture: 1.0)
        XCTAssertGreaterThan(dryAir, soakedAir * 10)
        XCTAssertEqual(soakedAir, 0, accuracy: 0.15)
    }

    func testLiquidMassIsConservedOverLongRun() {
        let charge = BirdGeometry.liquidChargeVolume
        var engine = SimulationEngine(dials: .standard)
        for _ in 0 ..< 10_000 { engine.step(dt: SimulationEngine.substep) }
        let s = engine.state
        XCTAssertEqual(s.bulbLiquidVolume + s.headLiquidVolume + s.neckLiquidVolume,
                       charge, accuracy: 1e-12)
        XCTAssertGreaterThanOrEqual(s.bulbLiquidVolume, -1e-15)
        XCTAssertGreaterThanOrEqual(s.headLiquidVolume, -1e-15)
        XCTAssertGreaterThanOrEqual(s.neckLiquidVolume, -1e-15)
    }

    func testColumnFillStaysPhysical() {
        var engine = SimulationEngine(dials: .standard)
        for _ in 0 ..< 10_000 { engine.step(dt: SimulationEngine.substep) }
        let s = engine.state
        XCTAssertLessThanOrEqual(s.neckColumnFraction, 1.0 + 1e-9)
        XCTAssertLessThanOrEqual(s.headLiquidVolume, BirdGeometry.headCapacity + 1e-12)
    }
}
