import AppKit
import Combine
import Sparkle

@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var canCheckForUpdates: Bool = false

    private let updaterController: SPUStandardUpdaterController
    private let bridge: UpdaterBridge
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let bridge = UpdaterBridge()
        self.bridge = bridge
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: bridge,
            userDriverDelegate: bridge
        )

        updaterController.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &cancellables)
        canCheckForUpdates = updaterController.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }
}

// Sparkle's delegate protocols are not `@MainActor`-annotated, so the
// conformance has to be on a nonisolated type. The bridge just hops to the
// main actor before touching AppKit.
private final class UpdaterBridge: NSObject, SPUStandardUserDriverDelegate, SPUUpdaterDelegate, @unchecked Sendable {
    nonisolated func standardUserDriverWillShowModalAlert() {
        Task { @MainActor in
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
