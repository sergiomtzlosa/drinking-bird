import SwiftUI

@MainActor
final class BirdViewModel: ObservableObject {
    @Published private(set) var snapshot = PhysicsState.initial()
    @Published var dials = Dials.standard {
        didSet {
            guard dials != oldValue else { return }
            Task { await simulation.setDials(dials) }
        }
    }

    private let simulation = SimulationRunner()
    private var started = false

    init() {
        guard !started else { return }
        started = true
        Task { await watchSimulation() }
    }

    private func watchSimulation() async {
        let stream = await simulation.stream()
        for await state in stream {
            guard !Task.isCancelled else { break }
            snapshot = state
        }
    }

    func restart() {
        Task { await simulation.restart(dials) }
    }

    func applyPreset(_ preset: Dials) {
        dials = preset
    }
}

/// Owns and advances the engine on a background executor, publishing snapshots
/// to the main actor. The engine itself never touches UI types.
actor SimulationRunner {
    private var engine = SimulationEngine(dials: .standard)
    private var currentTimeScale: Double

    init() {
        currentTimeScale = Dials.standard.timeScale
    }

    func setDials(_ dials: Dials) {
        currentTimeScale = dials.timeScale
    }

    func restart(_ dials: Dials) {
        engine = SimulationEngine(dials: dials)
    }

    func stream() -> AsyncStream<PhysicsState> {
        return AsyncStream { continuation in
            let task = Task {
                var lastWall = DispatchTime.now()
                while !Task.isCancelled {
                    let now = DispatchTime.now()
                    let wallSeconds = Double(now.uptimeNanoseconds - lastWall.uptimeNanoseconds) / 1e9
                    lastWall = now
                    let simSeconds = min(wallSeconds, 0.1) * currentTimeScale
                    engine.advance(simSeconds: simSeconds)
                    continuation.yield(engine.state)
                    try? await Task.sleep(nanoseconds: 16_000_000)  // ~60 fps feed
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
