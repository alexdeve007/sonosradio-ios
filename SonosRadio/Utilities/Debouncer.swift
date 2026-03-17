import Foundation

actor Debouncer {
    private var task: Task<Void, Never>?
    private let interval: Duration

    init(interval: Duration = .milliseconds(100)) {
        self.interval = interval
    }

    func debounce(operation: @Sendable @escaping () async -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            await operation()
        }
    }
}
