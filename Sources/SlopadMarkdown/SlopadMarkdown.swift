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
}
