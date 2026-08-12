import AppKit
import SlopadEditorAppKit
import SlopadEditorArchive

private struct HostSaveToken: Equatable, Sendable {
    let documentID: String
    let generation: Int
    let storageVersion: Int
}

private struct HostEncodeResult: Sendable {
    let token: HostSaveToken
    let data: Data
    let encodeDuration: Duration
}

private enum HostPersistenceOutcome: Sendable {
    case persisted(HostEncodeResult)
    case stale(HostSaveToken)
    case failed(HostSaveToken)
}

private enum HostCommitProbeError: Error {
    case forcedFailure
}

/// Deterministic fixture-only synchronization for the commit/result-delivery gap. Waiting
/// happens off MainActor; production ownership remains the admission gate and persistence actor.
private final class HostCommitGapHook: @unchecked Sendable {
    private let committingToken: HostSaveToken
    private let registeringToken: HostSaveToken
    private let condition = NSCondition()
    private var commitAdmitted = false
    private var registrationBlocked = false
    private var releaseCommit = false

    init(committingToken: HostSaveToken, registeringToken: HostSaveToken) {
        self.committingToken = committingToken
        self.registeringToken = registeringToken
    }

    func commitWasAdmittedAndWait(_ token: HostSaveToken) {
        guard token == committingToken else { return }
        condition.lock()
        commitAdmitted = true
        condition.broadcast()
        while !releaseCommit {
            condition.wait()
        }
        condition.unlock()
    }

    func observesRegistration(_ token: HostSaveToken) -> Bool {
        token == registeringToken
    }

    func registrationWasBlockedByCommit() {
        condition.lock()
        registrationBlocked = true
        condition.broadcast()
        condition.unlock()
    }

    func waitUntilCommitIsAdmitted() {
        condition.lock()
        while !commitAdmitted {
            condition.wait()
        }
        condition.unlock()
    }

    func waitUntilRegistrationIsBlockedThenReleaseCommit() {
        condition.lock()
        while !registrationBlocked {
            condition.wait()
        }
        releaseCommit = true
        condition.broadcast()
        condition.unlock()
    }
}

/// The persistence actor owns this admission authority. `nonisolated` forwarding lets the
/// MainActor publish a newly captured token synchronously, before its persistence task can
/// be delayed in the actor mailbox. Every access is protected by the same lock.
private final class HostTokenAdmissionGate: @unchecked Sendable {
    private struct State {
        var activeDocument: (id: String, generation: Int)?
        var latestToken: HostSaveToken?
        var persistedToken: HostSaveToken?
    }

    private let lock = NSLock()
    private let commitGapHook: HostCommitGapHook?
    private var state = State()

    init(commitGapHook: HostCommitGapHook?) {
        self.commitGapHook = commitGapHook
    }

    func activateDocument(id: String, generation: Int) {
        lock.lock()
        defer { lock.unlock() }
        state.activeDocument = (id, generation)
        state.latestToken = nil
        state.persistedToken = nil
    }

    func register(_ token: HostSaveToken) {
        if commitGapHook?.observesRegistration(token) == true {
            guard !lock.try() else {
                lock.unlock()
                preconditionFailure("new registration was not serialized behind admitted commit")
            }
            commitGapHook?.registrationWasBlockedByCommit()
            lock.lock()
        } else {
            lock.lock()
        }
        defer { lock.unlock() }
        guard isForActiveDocument(token, state: state) else { return }
        if let latestToken = state.latestToken,
            token.storageVersion <= latestToken.storageVersion
        {
            return
        }
        state.latestToken = token
        state.persistedToken = nil
    }

    func isLatest(_ token: HostSaveToken) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.latestToken == token && isForActiveDocument(token, state: state)
    }

    func commitIfLatest(
        _ token: HostSaveToken,
        operation: () throws -> Void
    ) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard state.latestToken == token, isForActiveDocument(token, state: state) else {
            return false
        }
        commitGapHook?.commitWasAdmittedAndWait(token)
        try operation()
        state.persistedToken = token
        return true
    }

    func persistedToken() -> HostSaveToken? {
        lock.lock()
        defer { lock.unlock() }
        return state.persistedToken
    }

    private func isForActiveDocument(_ token: HostSaveToken, state: State) -> Bool {
        state.activeDocument?.id == token.documentID
            && state.activeDocument?.generation == token.generation
    }
}

private actor HostArchivePersistence {
    private let destination: URL
    private let forceFinalCommitFailure: Bool
    private nonisolated let admissionGate: HostTokenAdmissionGate
    private var holdNextCommit = false
    private var heldCommitContinuation: CheckedContinuation<Void, Never>?
    private var heldCommitWaiter: CheckedContinuation<Void, Never>?

    init(
        destination: URL,
        commitGapHook: HostCommitGapHook? = nil,
        forceFinalCommitFailure: Bool = false
    ) {
        self.destination = destination
        self.forceFinalCommitFailure = forceFinalCommitFailure
        admissionGate = HostTokenAdmissionGate(commitGapHook: commitGapHook)
    }

    nonisolated func activateDocumentSynchronously(id: String, generation: Int) {
        admissionGate.activateDocument(id: id, generation: generation)
    }

    nonisolated func registerSynchronously(_ token: HostSaveToken) {
        admissionGate.register(token)
    }

    nonisolated func persistedTokenSynchronously() -> HostSaveToken? {
        admissionGate.persistedToken()
    }

    func holdNextBeforeCommit() {
        holdNextCommit = true
    }

    func waitUntilCommitIsHeld() async {
        if heldCommitContinuation != nil { return }
        await withCheckedContinuation { continuation in
            heldCommitWaiter = continuation
        }
    }

    func releaseHeldCommit() {
        heldCommitContinuation?.resume()
        heldCommitContinuation = nil
    }

    func persist(
        _ blocks: [EditorBlockInput],
        token: HostSaveToken
    ) async -> HostPersistenceOutcome {
        guard admissionGate.isLatest(token) else {
            return .stale(token)
        }

        let clock = ContinuousClock()
        let start = clock.now
        let data: Data
        do {
            data = try await Task.detached {
                try SlopadEditorArchive.encode(blocks)
            }.value
        } catch {
            return .failed(token)
        }
        let result = HostEncodeResult(
            token: token,
            data: data,
            encodeDuration: start.duration(to: clock.now)
        )

        if holdNextCommit {
            holdNextCommit = false
            await withCheckedContinuation { continuation in
                heldCommitContinuation = continuation
                heldCommitWaiter?.resume()
                heldCommitWaiter = nil
            }
        }

        do {
            guard try commitAtomicallyIfLatest(result) else { return .stale(token) }
        } catch {
            return .failed(token)
        }
        return .persisted(result)
    }

    private func commitAtomicallyIfLatest(_ result: HostEncodeResult) throws -> Bool {
        let fileManager = FileManager.default
        let destination = destination
        let directory = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".slopad-archive-\(UUID().uuidString).tmp")
        try result.data.write(to: temporary)
        defer { try? fileManager.removeItem(at: temporary) }

        // The same gate lock spans final admission, filesystem replacement, and persisted
        // authority publication. This deliberately serializes synchronous registration
        // behind a potentially slow rename; hosts may choose a different atomic store,
        // but must preserve this indivisible commit boundary.
        return try admissionGate.commitIfLatest(result.token) {
            if forceFinalCommitFailure {
                throw HostCommitProbeError.forcedFailure
            }
            let commitFileManager = FileManager.default
            if commitFileManager.fileExists(atPath: destination.path) {
                _ = try commitFileManager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try commitFileManager.moveItem(at: temporary, to: destination)
            }
        }
    }

    func storedData() throws -> Data {
        try Data(contentsOf: destination)
    }

    func storedDataIfPresent() throws -> Data? {
        guard FileManager.default.fileExists(atPath: destination.path) else { return nil }
        return try storedData()
    }

}

@MainActor
private final class HostSaveCoordinator {
    private weak var controller: AppKitEditorViewController?
    private let persistence: HostArchivePersistence
    private let debounce: Duration
    private var documentID: String
    private var generation = 0
    private var nextStorageVersion = 0
    private var latestToken: HostSaveToken?
    private var latestEditorToken: (EditorSessionEpoch, EditorDocumentRevision)?
    private var debounceTask: Task<Void, Never>?
    private var holdNextSubmission = false
    private var heldSubmission: (blocks: [EditorBlockInput], token: HostSaveToken)?
    private var inFlightCount = 0

    private(set) var staleEncodeCount = 0
    private(set) var persistedToken: HostSaveToken?
    private(set) var isDirty = false
    private(set) var snapshotDuration = Duration.zero
    private(set) var encodeDuration = Duration.zero

    init(
        controller: AppKitEditorViewController,
        persistence: HostArchivePersistence,
        documentID: String,
        debounce: Duration = .milliseconds(5)
    ) {
        self.controller = controller
        self.persistence = persistence
        self.documentID = documentID
        self.debounce = debounce
    }

    func activate() {
        persistence.activateDocumentSynchronously(id: documentID, generation: generation)
    }

    func observeCommittedChange(_ update: EditorUpdate) {
        guard let revision = update.committedDocumentRevision else { return }
        latestEditorToken = (update.epoch, revision)
        isDirty = true
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            captureLatestCommittedSnapshot()
        }
    }

    func replaceHostDocument(id: String) {
        documentID = id
        generation += 1
        latestToken = nil
        latestEditorToken = nil
        persistedToken = nil
        isDirty = false
        debounceTask?.cancel()
        holdNextSubmission = false
        heldSubmission = nil
        persistence.activateDocumentSynchronously(id: documentID, generation: generation)
    }

    func saveExplicitly() {
        debounceTask?.cancel()
        _ = controller?.commitActiveComposition()
        debounceTask?.cancel()
        captureLatestCommittedSnapshot()
    }

    func captureForSmoke() {
        captureLatestCommittedSnapshot()
    }

    func captureImmediatelyForProbe(holdSubmission: Bool = false) {
        debounceTask?.cancel()
        debounceTask = nil
        holdNextSubmission = holdSubmission
        captureLatestCommittedSnapshot()
    }

    func submitHeldPersistence() {
        guard let heldSubmission else { preconditionFailure("no held persistence submission") }
        self.heldSubmission = nil
        submitPersistence(heldSubmission.blocks, token: heldSubmission.token)
    }

    var isIdle: Bool {
        inFlightCount == 0 && debounceTask == nil && heldSubmission == nil
    }

    private func captureLatestCommittedSnapshot() {
        debounceTask = nil
        guard let controller else { return }
        let clock = ContinuousClock()
        let start = clock.now
        let snapshot = controller.documentSnapshot
        snapshotDuration = start.duration(to: clock.now)

        if let latestEditorToken {
            precondition(snapshot.epoch == latestEditorToken.0)
            precondition(snapshot.revision == latestEditorToken.1)
        }

        nextStorageVersion += 1
        let token = HostSaveToken(
            documentID: documentID,
            generation: generation,
            storageVersion: nextStorageVersion
        )
        let blocks = snapshot.blocks
        latestToken = token
        persistence.registerSynchronously(token)
        if holdNextSubmission {
            holdNextSubmission = false
            heldSubmission = (blocks, token)
            return
        }
        submitPersistence(blocks, token: token)
    }

    private func submitPersistence(_ blocks: [EditorBlockInput], token: HostSaveToken) {
        inFlightCount += 1
        Task { [weak self, persistence] in
            let outcome = await persistence.persist(blocks, token: token)
            self?.finishPersistence(outcome)
        }
    }

    private func finishPersistence(_ outcome: HostPersistenceOutcome) {
        defer { inFlightCount -= 1 }
        switch outcome {
        case .stale(let token):
            staleEncodeCount += 1
            if token == latestToken { isDirty = true }
        case .failed(let token):
            guard isCurrent(token) else { return }
            isDirty = true
        case .persisted(let result):
            guard isCurrent(result.token) else {
                staleEncodeCount += 1
                return
            }
            encodeDuration = result.encodeDuration
            persistedToken = result.token
            isDirty = false
        }
    }

    private func isCurrent(_ token: HostSaveToken) -> Bool {
        token == latestToken
            && token.documentID == documentID
            && token.generation == generation
    }
}

@main
@MainActor
private struct AppKitArchiveLifecycleProbe {
    static func main() async throws {
        _ = NSApplication.shared
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SlopadDownstreamArchiveHost", isDirectory: true)
            .appendingPathComponent("document.slopad")
        try? FileManager.default.removeItem(at: storageURL)

        let blockID: BlockID = "preserved-id"
        let controller = AppKitEditorViewController(
            blocks: [
                EditorBlockInput(id: blockID, content: BlockContent(text: "initial"))
            ],
            selection: .caret(blockID: blockID, offset: 7)
        )
        let window = mountedWindow(controller)
        let firstToken = HostSaveToken(
            documentID: "host-document-1", generation: 0, storageVersion: 1
        )
        let secondToken = HostSaveToken(
            documentID: "host-document-1", generation: 0, storageVersion: 2
        )
        let commitGapHook = HostCommitGapHook(
            committingToken: firstToken,
            registeringToken: secondToken
        )
        let persistence = HostArchivePersistence(
            destination: storageURL,
            commitGapHook: commitGapHook
        )
        let coordinator = HostSaveCoordinator(
            controller: controller,
            persistence: persistence,
            documentID: "host-document-1"
        )
        coordinator.activate()
        controller.onUpdate = { [weak coordinator] update in
            coordinator?.observeCommittedChange(update)
        }

        // V1 holds the admission lock after its latest-token check. V2 capture then proves
        // synchronous registration cannot acquire that lock. An off-main condition waiter
        // releases V1, allowing its rename + persisted update to finish atomically; V2
        // registration runs next and invalidates V1 persisted authority before MainActor
        // can apply V1's result.
        _ = controller.perform(
            .insertText(" first"),
            makeFirstResponder: false,
            scrollSelectionIntoView: false
        )
        coordinator.captureImmediatelyForProbe()
        let firstCapturedBlocks = controller.documentSnapshot.blocks
        await Task.detached {
            commitGapHook.waitUntilCommitIsAdmitted()
        }.value

        _ = controller.perform(
            .insertText(" second"),
            makeFirstResponder: false,
            scrollSelectionIntoView: false
        )
        let commitReleaser = Task.detached {
            commitGapHook.waitUntilRegistrationIsBlockedThenReleaseCommit()
        }
        coordinator.captureImmediatelyForProbe(holdSubmission: true)
        await commitReleaser.value

        let storedBeforeNewSubmission = try await persistence.storedData()
        let decodedBeforeNewSubmission = try SlopadEditorArchive.decode(storedBeforeNewSubmission)
        let persistedBeforeNewSubmission = persistence.persistedTokenSynchronously()
        precondition(decodedBeforeNewSubmission == firstCapturedBlocks)
        precondition(persistedBeforeNewSubmission == nil)
        precondition(coordinator.persistedToken == nil)
        precondition(coordinator.isDirty)

        coordinator.submitHeldPersistence()
        try await waitUntil("latest-only save did not finish") {
            coordinator.persistedToken?.storageVersion == 2
                && !coordinator.isDirty
                && coordinator.isIdle
        }
        let latestBlocks = try SlopadEditorArchive.decode(await persistence.storedData())
        precondition(latestBlocks == controller.documentSnapshot.blocks)
        precondition(
            coordinator.staleEncodeCount == 1,
            "Expected one stale encode, found \(coordinator.staleEncodeCount)"
        )
        try await runFailedCommitProbe()

        // Autosave never closes active composition. Its delayed snapshot remains the last
        // committed document even while the AppKit text client has marked text.
        _ = controller.perform(
            .insertText(" before-composition"),
            makeFirstResponder: true,
            scrollSelectionIntoView: false
        )
        controller.setFocused(true)
        let textInput = window.firstResponder as? NSTextInputClient
        precondition(textInput != nil)
        textInput?.setMarkedText(
            " marked",
            selectedRange: NSRange(location: 7, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        let committedBeforeExplicitSave = controller.documentSnapshot.blocks
        try await waitUntil("composition autosave did not finish") {
            coordinator.persistedToken?.storageVersion == 3 && !coordinator.isDirty
        }
        let autosavedDuringComposition = try SlopadEditorArchive.decode(await persistence.storedData())
        precondition(autosavedDuringComposition == committedBeforeExplicitSave)

        // Explicit save owns the flush policy, then captures the new committed snapshot.
        coordinator.saveExplicitly()
        try await waitUntil("explicit composition save did not finish") {
            coordinator.persistedToken?.storageVersion == 4 && !coordinator.isDirty
        }
        let explicitlySaved = try SlopadEditorArchive.decode(await persistence.storedData())
        precondition(explicitlySaved == controller.documentSnapshot.blocks)
        precondition(explicitlySaved != committedBeforeExplicitSave)

        // Reload passes decoded values directly through the public reset boundary. Archive
        // identity survives while Session epoch/revision start a new lifecycle. A pending
        // completion from the old host document generation is discarded.
        await persistence.holdNextBeforeCommit()
        _ = controller.perform(
            .insertText(" stale-before-switch"),
            makeFirstResponder: false,
            scrollSelectionIntoView: false
        )
        coordinator.captureImmediatelyForProbe()
        await persistence.waitUntilCommitIsHeld()
        let epochBeforeReset = controller.documentSnapshot.epoch
        coordinator.replaceHostDocument(id: "host-document-2")
        controller.resetDocument(blocks: explicitlySaved, selection: .inactive)
        await persistence.releaseHeldCommit()
        try await waitUntil("old document generation encode did not drain") {
            coordinator.isIdle
        }
        precondition(controller.documentSnapshot.epoch != epochBeforeReset)
        precondition(controller.documentSnapshot.revision.rawValue == 0)
        precondition(controller.documentSnapshot.blocks.map(\.id) == explicitlySaved.map(\.id))
        precondition(controller.documentSnapshot.blocks.first?.id == blockID)
        precondition(coordinator.staleEncodeCount == 2)
        let storedAfterSwitch = try SlopadEditorArchive.decode(await persistence.storedData())
        precondition(storedAfterSwitch == explicitlySaved)

        if CommandLine.arguments.contains("--large-document-smoke") {
            try await runLargeDocumentSmoke(persistence: persistence)
        }

        controller.setFocused(false)
        window.orderOut(nil)
        window.contentViewController = nil
        window.close()
    }

    private static func runLargeDocumentSmoke(
        persistence: HostArchivePersistence
    ) async throws {
        let blocks = (0..<10_000).map { index in
            EditorBlockInput(
                id: BlockID("large-\(index)"),
                content: BlockContent(text: "block \(index)")
            )
        }
        let controller = AppKitEditorViewController(blocks: blocks, selection: .inactive)
        let window = mountedWindow(controller)
        let coordinator = HostSaveCoordinator(
            controller: controller,
            persistence: persistence,
            documentID: "large-document",
            debounce: .zero
        )
        coordinator.activate()
        coordinator.captureForSmoke()
        try await waitUntil("large-document archive smoke did not finish", timeout: .seconds(30)) {
            coordinator.persistedToken != nil && !coordinator.isDirty
        }
        let decoded = try SlopadEditorArchive.decode(await persistence.storedData())
        precondition(decoded.count == 10_000)
        print(
            "SLOPAD_ARCHIVE_SMOKE blocks=10000 snapshot_ms=\(milliseconds(coordinator.snapshotDuration)) encode_ms=\(milliseconds(coordinator.encodeDuration)) threshold=none latest_only=true"
        )
        window.orderOut(nil)
        window.contentViewController = nil
        window.close()
    }

    private static func runFailedCommitProbe() async throws {
        let fileManager = FileManager.default
        let failureDestination = fileManager.temporaryDirectory
            .appendingPathComponent("SlopadDownstreamArchiveHost", isDirectory: true)
            .appendingPathComponent("forced-final-commit-failure.slopad")
        try? fileManager.removeItem(at: failureDestination)
        defer { try? fileManager.removeItem(at: failureDestination) }

        let token = HostSaveToken(
            documentID: "failure-document", generation: 0, storageVersion: 1
        )
        let persistence = HostArchivePersistence(
            destination: failureDestination,
            forceFinalCommitFailure: true
        )
        persistence.activateDocumentSynchronously(
            id: token.documentID, generation: token.generation)
        persistence.registerSynchronously(token)

        let outcome = await persistence.persist(
            [EditorBlockInput(id: "failure", content: BlockContent(text: "failure"))],
            token: token
        )
        guard case .failed(let failedToken) = outcome else {
            preconditionFailure("forced final commit failure unexpectedly committed")
        }
        precondition(failedToken == token)
        precondition(persistence.persistedTokenSynchronously() == nil)
        let storedAfterFailure = try await persistence.storedDataIfPresent()
        precondition(storedAfterFailure == nil)
    }

    private static func mountedWindow(_ controller: AppKitEditorViewController) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 320),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.contentViewController = controller
        window.makeKeyAndOrderFront(nil)
        controller.view.frame = window.contentView?.bounds ?? .zero
        controller.view.layoutSubtreeIfNeeded()
        precondition(controller.view.window === window)
        return window
    }

    private static func waitUntil(
        _ message: @autoclosure () -> String,
        timeout: Duration = .seconds(5),
        condition: @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        precondition(condition(), message())
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
