import AppKit
import Foundation
import SlopadEditorEngine

// MARK: - AppKitCustomBlockProvider

/// Supplies the view for one family of host-defined custom blocks.
///
/// The host owns the view and everything inside it. The editor owns where it sits, how it is
/// clipped, when it scrolls, and when it goes away — so a provider never positions its own
/// view and never reads the scroll position.
///
/// The editor also never asks a provider how tall a block is. Height comes from the
/// `CustomBlockSizing` seam, which is `Sendable` and synchronous; the view is laid out to
/// the height that answered, not the other way round.
@MainActor
public protocol AppKitCustomBlockProvider {
    /// Whether this provider handles `typeID`.
    ///
    /// A `false` answer is ordinary, not an error: an archive can outlive the app version
    /// that understood its blocks, and those blocks still render as a placeholder.
    func handles(typeID: String) -> Bool

    /// Creates a view for a block of `typeID`, or recycles one previously released.
    func makeBody(typeID: String) -> NSView

    /// Applies a payload to a mounted view.
    ///
    /// Called on mount and again whenever the payload changes, so a provider updates in
    /// place rather than rebuilding.
    func update(_ body: NSView, typeID: String, version: Int, payload: Data)

    /// Reports that a view left the visible region and will not be positioned again unless
    /// it is mounted afresh.
    func recycle(_ body: NSView)
}

extension AppKitCustomBlockProvider {
    public func recycle(_ body: NSView) {}
}

// MARK: - AppKitCustomBlockMountController

/// Keeps host views in step with the visible custom blocks of a render snapshot.
///
/// It is deliberately a plain reconciler over values: given the visible blocks and a body
/// rect for each, it decides what to mount, update, move, and release. The AppKit work it
/// performs — adding a subview, setting a frame — is the smallest part; the part worth
/// testing is the decision, so the decision is separated from a mounted window.
@MainActor
final class AppKitCustomBlockMountController {
    struct MountedBody {
        let typeID: String
        let view: NSView
        var version: Int
        var payload: Data
        var frame: CGRect
    }

    private(set) var mounted: [BlockID: MountedBody] = [:]
    var provider: (any AppKitCustomBlockProvider)?

    /// One visible custom block, reduced to what mounting needs.
    ///
    /// The reconciler works over these rather than over `EditorRenderedBlock` so the
    /// decision — mount, update, move, release — can be exercised without a render snapshot
    /// or a mounted window. Translating a snapshot into them belongs to the controller,
    /// which is also where the body rect is computed.
    struct VisibleBody: Equatable {
        let blockID: BlockID
        let typeID: String
        let version: Int
        let payload: Data
        let frame: CGRect
    }

    /// Reconciles mounted views against the custom blocks currently visible.
    ///
    /// The frame arrives already inset by the caller, because the inset belongs to the
    /// drawing side: the editor fills and strokes the block frame for selection, so a body
    /// covering the whole frame would hide the chrome that says the block is selected.
    func reconcile(_ bodies: [VisibleBody], in container: NSView) {
        guard let provider else {
            releaseAll()
            return
        }

        var survivingIDs: Set<BlockID> = []

        for body in bodies where provider.handles(typeID: body.typeID) {
            survivingIDs.insert(body.blockID)

            // A block whose type changed is a different thing wearing the same identity, so
            // its old view is released rather than handed a payload it cannot read.
            if var existing = mounted[body.blockID], existing.typeID == body.typeID {
                if existing.version != body.version || existing.payload != body.payload {
                    provider.update(
                        existing.view,
                        typeID: body.typeID,
                        version: body.version,
                        payload: body.payload
                    )
                    existing.version = body.version
                    existing.payload = body.payload
                }
                if existing.frame != body.frame {
                    existing.view.frame = body.frame
                    existing.frame = body.frame
                }
                mounted[body.blockID] = existing
                continue
            }

            release(body.blockID)
            let view = provider.makeBody(typeID: body.typeID)
            view.frame = body.frame
            container.addSubview(view)
            provider.update(
                view,
                typeID: body.typeID,
                version: body.version,
                payload: body.payload
            )
            mounted[body.blockID] = MountedBody(
                typeID: body.typeID,
                view: view,
                version: body.version,
                payload: body.payload,
                frame: body.frame
            )
        }

        for blockID in mounted.keys where !survivingIDs.contains(blockID) {
            release(blockID)
        }
    }

    func releaseAll() {
        for blockID in mounted.keys {
            release(blockID)
        }
    }

    private func release(_ blockID: BlockID) {
        guard let body = mounted.removeValue(forKey: blockID) else { return }
        body.view.removeFromSuperview()
        provider?.recycle(body.view)
    }
}
