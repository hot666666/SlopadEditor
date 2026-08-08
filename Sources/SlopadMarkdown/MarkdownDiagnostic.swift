import SlopadCoreModel

/// A position in Markdown source text.
///
/// Lines and UTF-8 byte columns are both one-based.
public struct MarkdownSourcePosition: Hashable, Sendable {
    public let line: Int
    public let utf8Column: Int

    init(line: Int, utf8Column: Int) {
        precondition(line >= 1, "Markdown source lines are one-based")
        precondition(utf8Column >= 1, "Markdown source columns are one-based")
        self.line = line
        self.utf8Column = utf8Column
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.line == rhs.line {
            return lhs.utf8Column < rhs.utf8Column
        }
        return lhs.line < rhs.line
    }
}

/// A half-open range in Markdown source text.
public struct MarkdownSourceRange: Hashable, Sendable {
    public let lowerBound: MarkdownSourcePosition
    public let upperBound: MarkdownSourcePosition

    init(lowerBound: MarkdownSourcePosition, upperBound: MarkdownSourcePosition) {
        precondition(
            lowerBound == upperBound || lowerBound < upperBound,
            "Markdown source range must be ordered"
        )
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }
}

/// One fail-closed Markdown decoding diagnostic.
public struct MarkdownDiagnostic: Hashable, Sendable {
    /// The typed reason decoding cannot produce a lossless canonical value.
    public enum Kind: Hashable, Sendable {
        /// GFM tables are deferred to issue #50.
        case table
        case image
        case html
        case heading(level: Int)
        case orderedTask
        case linkTitle
        case emptyLink
        case blockDirective
        case customBlock
        case customInline
        case inlineAttributes
        case symbolLink
        case doxygenCommand
        /// The parser boundary rejects deeper block-container nesting before constructing an AST.
        case excessiveNesting(maximumDepth: Int)
    }

    public let kind: Kind
    public let sourceRange: MarkdownSourceRange
}

/// An all-or-nothing Markdown decoding failure.
///
/// `diagnostics` is guaranteed to be nonempty and ordered by source occurrence.
public struct MarkdownDecodingError: Error, Hashable, Sendable {
    public let diagnostics: [MarkdownDiagnostic]

    init(diagnostics: [MarkdownDiagnostic]) {
        precondition(!diagnostics.isEmpty, "A decoding error requires a diagnostic")
        self.diagnostics = diagnostics
    }
}

/// One fail-closed Markdown encoding diagnostic.
///
/// Markdown output does not exist when encoding fails, so diagnostics identify canonical
/// input by block identity rather than by a source-text range.
public struct MarkdownEncodingDiagnostic: Hashable, Sendable {
    /// The typed reason encoding cannot produce a lossless Markdown value.
    public enum Kind: Hashable, Sendable {
        case emptyDocument
        case duplicateBlockID
        case missingParent
        case cycle
        case noncanonicalDepthFirstOrder
        case unsupportedChildHierarchy
        case excessiveNesting(maximumDepth: Int)
        case noncanonicalInlineMarks
        case crossingInlineMarks
        case intersectingLinks
        case unsupportedInlineCodeNesting
        case inlineCodeContainsLineBreak
        case unrepresentableText
        case nonemptyDivider
        case inlineMarksInCodeBlock
        case codeBlockRequiresTrailingLineBreak
        case invalidCodeBlockLanguage
        case invalidOrderedListRestart
        case invalidLinkDestination
        case ambiguousEmptyContainer
        case unrepresentableEmptyParagraph
    }

    public let kind: Kind
    public let blockID: BlockID?

    init(kind: Kind, blockID: BlockID?) {
        self.kind = kind
        self.blockID = blockID
    }
}

/// An all-or-nothing Markdown encoding failure.
///
/// `diagnostics` is guaranteed to be nonempty and ordered by canonical input occurrence.
public struct MarkdownEncodingError: Error, Hashable, Sendable {
    public let diagnostics: [MarkdownEncodingDiagnostic]

    init(diagnostics: [MarkdownEncodingDiagnostic]) {
        precondition(!diagnostics.isEmpty, "An encoding error requires a diagnostic")
        self.diagnostics = diagnostics
    }
}
