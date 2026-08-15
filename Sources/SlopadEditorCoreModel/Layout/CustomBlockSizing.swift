import Foundation

// MARK: - CustomBlockSizing

/// Answers how tall a host-defined custom block is at a given width.
///
/// A custom block is not text, so the text backend cannot measure it. This is the seam the
/// host answers instead — and it is a plain function over the payload rather than a view,
/// because ``BlockMeasuring`` is `Sendable` and synchronous while an `NSView`'s intrinsic
/// size can only be read on the main actor.
///
/// The consequence is deliberate: the view does not decide the height. It is laid out to
/// the height this returns. A host whose body has genuine intrinsic sizing reproduces that
/// calculation here, outside the view.
public protocol CustomBlockSizing: Sendable {
    /// The height for one custom block, or `nil` when this sizer does not handle `typeID`.
    ///
    /// Returning `nil` is the ordinary answer for a type the host did not register — an
    /// archive can outlive the app version that understood it — and the editor falls back
    /// to the unsupported placeholder rather than treating it as an error.
    func height(
        typeID: String,
        version: Int,
        payload: Data,
        availableWidth: Double,
        depth: Int
    ) -> Double?
}

// MARK: - CustomBlockMeasuring

/// Wraps a text backend so custom blocks are answered by a host sizer and everything else
/// is delegated unchanged.
///
/// Composing at this level keeps `BlockLayout`, the measurement cache, and the text-layout
/// seam untouched: they keep asking one `BlockMeasuring` for a height, and the branch on
/// block kind lives in one place instead of spreading through the layout pass.
public struct CustomBlockMeasuring: BlockMeasuring {
    /// Height used for a custom block whose `typeID` has no registered sizer.
    ///
    /// It exists so an unsupported block still occupies a selectable, movable row rather
    /// than collapsing to nothing, which would make it invisible to the person holding the
    /// document.
    public static let unsupportedPlaceholderHeight: Double = 36

    private let base: any BlockMeasuring
    private let sizing: (any CustomBlockSizing)?

    public init(base: any BlockMeasuring, sizing: (any CustomBlockSizing)?) {
        self.base = base
        self.sizing = sizing
    }

    public func measure(_ request: BlockMeasureRequest) -> BlockMeasurement {
        guard case .custom(let typeID, let version, let payload) = request.kind else {
            return base.measure(request)
        }

        let height = sizing?.height(
            typeID: typeID,
            version: version,
            payload: payload,
            availableWidth: request.availableWidth,
            depth: request.depth
        )

        // A sizer that returns a non-finite or negative height is answering nonsense, and
        // propagating it would corrupt the height index rather than fail loudly. Treat it
        // the same as an unhandled type.
        guard let height, height.isFinite, height >= 0 else {
            return BlockMeasurement(height: Self.unsupportedPlaceholderHeight)
        }
        return BlockMeasurement(height: height)
    }
}
