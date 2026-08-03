import AppKit

// MARK: - AppKitDragAutoscrollKind

enum AppKitDragAutoscrollKind {
    case blockDrag
    case blockSelectionRectangle
    case blockSelectionExtension
}

// MARK: - AppKitDragAutoscrollController

@MainActor
final class AppKitDragAutoscrollController {
    // MARK: - Private Types

    private enum UX {
        static let edgeInset: CGFloat = 48
        static let minimumActiveInset: CGFloat = 12
        static let minimumBoundsHeight: CGFloat = 1
        static let minimumScrollStep: CGFloat = 3
        static let maximumScrollStep: CGFloat = 24
        static let scrollEpsilon: CGFloat = 0.5
        static let tickInterval: TimeInterval = 1.0 / 60.0
    }

    private struct Context {
        var kind: AppKitDragAutoscrollKind
        var visiblePoint: CGPoint
    }

    // MARK: - Dependencies

    private let visibleBounds: @MainActor () -> CGRect
    private let documentHeight: @MainActor () -> CGFloat
    private let scrollToY: @MainActor (CGFloat) -> Void
    private let applyDragUpdate: @MainActor (AppKitDragAutoscrollKind, CGPoint) -> Bool

    // MARK: - State

    private var context: Context?
    private var timer: Timer?

    // MARK: - Init

    init(
        visibleBounds: @escaping @MainActor () -> CGRect,
        documentHeight: @escaping @MainActor () -> CGFloat,
        scrollToY: @escaping @MainActor (CGFloat) -> Void,
        applyDragUpdate: @escaping @MainActor (AppKitDragAutoscrollKind, CGPoint) -> Bool
    ) {
        self.visibleBounds = visibleBounds
        self.documentHeight = documentHeight
        self.scrollToY = scrollToY
        self.applyDragUpdate = applyDragUpdate
    }

    // MARK: - Public

    func update(
        kind: AppKitDragAutoscrollKind,
        documentPoint: CGPoint
    ) {
        let bounds = visibleBounds()
        context = Context(
            kind: kind,
            visiblePoint: CGPoint(
                x: documentPoint.x - bounds.origin.x,
                y: documentPoint.y - bounds.origin.y
            )
        )

        if scrollStep(for: context?.visiblePoint ?? .zero, in: bounds) == 0 {
            stopTimer()
        } else {
            startTimer()
        }
    }

    func stop() {
        context = nil
        stopTimer()
    }

    // MARK: - Timer

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: UX.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Scrolling

    private func tick() {
        guard let context else {
            stopTimer()
            return
        }

        let bounds = visibleBounds()
        let step = scrollStep(for: context.visiblePoint, in: bounds)
        guard step != 0 else {
            stopTimer()
            return
        }

        let maxY = max(0, documentHeight() - bounds.height)
        guard maxY > 0 else {
            stopTimer()
            return
        }

        let targetY = min(max(bounds.origin.y + step, 0), maxY)
        guard abs(targetY - bounds.origin.y) > UX.scrollEpsilon else {
            stopTimer()
            return
        }

        scrollToY(targetY)

        let scrolledBounds = visibleBounds()
        let documentPoint = CGPoint(
            x: scrolledBounds.origin.x + context.visiblePoint.x,
            y: scrolledBounds.origin.y + context.visiblePoint.y
        )
        if !applyDragUpdate(context.kind, documentPoint) {
            stop()
        }
    }

    private func scrollStep(for visiblePoint: CGPoint, in bounds: CGRect) -> CGFloat {
        guard bounds.height > UX.minimumBoundsHeight else { return 0 }
        let activeInset = min(UX.edgeInset, max(UX.minimumActiveInset, bounds.height / 3))

        if visiblePoint.y < activeInset {
            return -scaledStep(distance: activeInset - visiblePoint.y, activeInset: activeInset)
        }

        let bottomEdgeStart = bounds.height - activeInset
        if visiblePoint.y > bottomEdgeStart {
            return scaledStep(distance: visiblePoint.y - bottomEdgeStart, activeInset: activeInset)
        }

        return 0
    }

    private func scaledStep(distance: CGFloat, activeInset: CGFloat) -> CGFloat {
        let proximity = min(1, max(0, distance / activeInset))
        return UX.minimumScrollStep + (UX.maximumScrollStep - UX.minimumScrollStep) * proximity
    }
}
