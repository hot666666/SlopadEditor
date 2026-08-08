import SlopadCoreModel

/// Stateless Markdown conversion into Slopad's canonical block-input vocabulary.
public enum SlopadMarkdown {
    /// Decodes Markdown without retaining or exposing parser state.
    ///
    /// Every successful call creates fresh block identifiers. Unsupported syntax fails
    /// closed with all maximal unsupported subtrees reported in source order.
    ///
    /// ```swift
    /// let blocks = try SlopadMarkdown.decode("# Title")
    /// ```
    public static func decode(
        _ markdown: String
    ) throws(MarkdownDecodingError) -> [EditorBlockInput] {
        var decoder = MarkdownDecoder(markdown: markdown)
        let result = decoder.decode()
        guard result.diagnostics.isEmpty else {
            throw MarkdownDecodingError(diagnostics: result.diagnostics)
        }
        return result.blocks
    }

    /// Encodes canonical block inputs as deterministic Markdown.
    ///
    /// The inputs must be a canonical parent-before-child depth-first tree. A successful
    /// result is guaranteed to decode to the same kinds, contents, and tree shape, except
    /// for newly created block identifiers. Unsupported canonical shapes fail closed and
    /// return no partial Markdown string.
    ///
    /// ```swift
    /// let markdown = try SlopadMarkdown.encode(blocks)
    /// ```
    public static func encode(
        _ blocks: [EditorBlockInput]
    ) throws(MarkdownEncodingError) -> String {
        var encoder = MarkdownEncoder(blocks: blocks)
        let result = encoder.encode()
        guard result.diagnostics.isEmpty else {
            throw MarkdownEncodingError(diagnostics: result.diagnostics)
        }
        return result.markdown
    }
}
