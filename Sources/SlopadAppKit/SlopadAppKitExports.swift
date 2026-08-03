public import SlopadAppKitUI
public import SlopadEngine

// MARK: - AppKit Platform Surface

public typealias AppKitEditorViewController = SlopadAppKitUI.AppKitEditorViewController
public typealias AppKitEditorStyle = SlopadAppKitUI.AppKitEditorStyle
public typealias AppKitEditorAction = SlopadAppKitUI.AppKitEditorAction
public typealias AppKitBlockChromeRenderer = SlopadAppKitUI.AppKitBlockChromeRenderer
public typealias AppKitBlockChromeRenderContext =
    SlopadAppKitUI.AppKitBlockChromeRenderContext
public typealias AppKitDefaultBlockChromeRenderer =
    SlopadAppKitUI.AppKitDefaultBlockChromeRenderer

// MARK: - Host Document Vocabulary

public typealias BlockID = SlopadEngine.BlockID
public typealias BlockKind = SlopadEngine.BlockKind
public typealias BlockMarkerKind = SlopadEngine.BlockMarkerKind
public typealias BlockContent = SlopadEngine.BlockContent
public typealias EditorBlockInput = SlopadEngine.EditorBlockInput
public typealias EditorSelection = SlopadEngine.EditorSelection
public typealias BlockSelection = SlopadEngine.BlockSelection
public typealias TextSelection = SlopadEngine.TextSelection
public typealias TextPosition = SlopadEngine.TextPosition
public typealias TextRange = SlopadEngine.TextRange
public typealias TextComposition = SlopadEngine.TextComposition
public typealias TextAffinity = SlopadEngine.TextAffinity
public typealias TextNavigationContext = SlopadEngine.TextNavigationContext

// MARK: - Host Observation Vocabulary

public typealias EditorUpdate = SlopadEngine.EditorUpdate
public typealias EditorDocumentRevision = SlopadEngine.EditorDocumentRevision
public typealias EditorDocumentSnapshot = SlopadEngine.EditorDocumentSnapshot
public typealias EditorDocumentSource = SlopadEngine.EditorDocumentSource
public typealias EditorDocumentContextSnapshot = SlopadEngine.EditorDocumentContextSnapshot
public typealias EditorDocumentPatch = SlopadEngine.EditorDocumentPatch
public typealias EditorDocumentTransactionError = SlopadEngine.EditorDocumentTransactionError
public typealias EditorSelectedContent = SlopadEngine.EditorSelectedContent
public typealias EditorSelectedText = SlopadEngine.EditorSelectedText
public typealias EditorSelectedTextFragment = SlopadEngine.EditorSelectedTextFragment
public typealias EditorSelectedBlocks = SlopadEngine.EditorSelectedBlocks
public typealias EditorSessionSnapshot = SlopadEngine.EditorSessionSnapshot
public typealias EditorSnapshotRevision = SlopadEngine.EditorSnapshotRevision
public typealias EditorHistoryState = SlopadEngine.EditorHistoryState
public typealias EditorRenderedBlock = SlopadEngine.EditorRenderedBlock
public typealias EditorRect = SlopadEngine.EditorRect
public typealias BlockMeasureRequest = SlopadEngine.BlockMeasureRequest
public typealias EditorSessionActiveTextInputDescriptor =
    SlopadEngine.EditorSessionActiveTextInputDescriptor
public typealias EditorTextRenderDescriptor = SlopadEngine.EditorTextRenderDescriptor
public typealias EditorBlockDragState = SlopadEngine.EditorBlockDragState
public typealias EditorBlockSelectionRectangleState =
    SlopadEngine.EditorBlockSelectionRectangleState
