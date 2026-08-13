// A SwiftUI host declares one product and writes `import SlopadEditorSwiftUI`. Re-exporting the
// platform vocabulary means it does not also have to depend on `SlopadEditorAppKit` just to name
// the block, selection and action values it already needs — and it keeps the downstream
// fixture honest, since a single-product dependency is what a real host writes.
//
// This adds no vocabulary of its own; every name below is `SlopadEditorAppKit`'s. That module
// remains the curated platform surface.

public import SlopadEditorAppKit

// MARK: - Host Document Vocabulary

public typealias BlockID = SlopadEditorAppKit.BlockID
public typealias BlockKind = SlopadEditorAppKit.BlockKind
public typealias BlockMarkerKind = SlopadEditorAppKit.BlockMarkerKind
public typealias BlockContent = SlopadEditorAppKit.BlockContent
public typealias EditorBlockInput = SlopadEditorAppKit.EditorBlockInput
public typealias EditorSelection = SlopadEditorAppKit.EditorSelection
public typealias BlockSelection = SlopadEditorAppKit.BlockSelection
public typealias TextSelection = SlopadEditorAppKit.TextSelection
public typealias TextPosition = SlopadEditorAppKit.TextPosition
public typealias TextRange = SlopadEditorAppKit.TextRange

// MARK: - Host Observation Vocabulary

public typealias EditorUpdate = SlopadEditorAppKit.EditorUpdate
public typealias EditorSessionEpoch = SlopadEditorAppKit.EditorSessionEpoch
public typealias EditorDocumentRevision = SlopadEditorAppKit.EditorDocumentRevision
public typealias EditorDocumentSnapshot = SlopadEditorAppKit.EditorDocumentSnapshot
public typealias EditorHistoryState = SlopadEditorAppKit.EditorHistoryState

// MARK: - Host Action and Style Vocabulary

public typealias AppKitEditorAction = SlopadEditorAppKit.AppKitEditorAction
public typealias AppKitEditorStyle = SlopadEditorAppKit.AppKitEditorStyle
public typealias AppKitBlockChromeRenderer = SlopadEditorAppKit.AppKitBlockChromeRenderer
public typealias AppKitBlockChromeRenderContext = SlopadEditorAppKit.AppKitBlockChromeRenderContext
public typealias AppKitDefaultBlockChromeRenderer = SlopadEditorAppKit.AppKitDefaultBlockChromeRenderer
