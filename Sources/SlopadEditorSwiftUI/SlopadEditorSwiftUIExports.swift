// A SwiftUI host declares one product and writes `import SlopadEditorSwiftUI`. Re-exporting the
// platform vocabulary means it does not also have to depend on `SlopadAppKit` just to name
// the block, selection and action values it already needs — and it keeps the downstream
// fixture honest, since a single-product dependency is what a real host writes.
//
// This adds no vocabulary of its own; every name below is `SlopadAppKit`'s. That module
// remains the curated platform surface.

public import SlopadAppKit

// MARK: - Host Document Vocabulary

public typealias BlockID = SlopadAppKit.BlockID
public typealias BlockKind = SlopadAppKit.BlockKind
public typealias BlockMarkerKind = SlopadAppKit.BlockMarkerKind
public typealias BlockContent = SlopadAppKit.BlockContent
public typealias EditorBlockInput = SlopadAppKit.EditorBlockInput
public typealias EditorSelection = SlopadAppKit.EditorSelection
public typealias BlockSelection = SlopadAppKit.BlockSelection
public typealias TextSelection = SlopadAppKit.TextSelection
public typealias TextPosition = SlopadAppKit.TextPosition
public typealias TextRange = SlopadAppKit.TextRange

// MARK: - Host Observation Vocabulary

public typealias EditorUpdate = SlopadAppKit.EditorUpdate
public typealias EditorSessionEpoch = SlopadAppKit.EditorSessionEpoch
public typealias EditorDocumentRevision = SlopadAppKit.EditorDocumentRevision
public typealias EditorDocumentSnapshot = SlopadAppKit.EditorDocumentSnapshot
public typealias EditorHistoryState = SlopadAppKit.EditorHistoryState

// MARK: - Host Action and Style Vocabulary

public typealias AppKitEditorAction = SlopadAppKit.AppKitEditorAction
public typealias AppKitEditorStyle = SlopadAppKit.AppKitEditorStyle
public typealias AppKitBlockChromeRenderer = SlopadAppKit.AppKitBlockChromeRenderer
public typealias AppKitBlockChromeRenderContext = SlopadAppKit.AppKitBlockChromeRenderContext
public typealias AppKitDefaultBlockChromeRenderer = SlopadAppKit.AppKitDefaultBlockChromeRenderer
