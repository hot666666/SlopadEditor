import Testing

@testable import SlopadMarkdown

@Suite("Markdown decode diagnostics")
struct MarkdownDiagnosticTests {
    @Test("순서 목록 task는 목록 순서와 task 의미를 함께 잃지 않고 진단한다")
    func orderedTaskFailsClosed() throws {
        // Given
        let markdown = "1. [x] conflict"

        // When
        let error = try decodingError(for: markdown)

        // Then
        #expect(
            error.diagnostics == [
                diagnostic(.orderedTask, 1, 1, 1, 16)
            ])
    }

    @Test("title이 있는 link는 destination만 남기지 않고 진단한다")
    func titledLinkFailsClosed() throws {
        // Given
        let markdown = #"before [title](dest "hello") after"#

        // When
        let error = try decodingError(for: markdown)

        // Then
        #expect(
            error.diagnostics == [
                diagnostic(.linkTitle, 1, 8, 1, 29)
            ])
    }

    @Test("빈 label link는 표현 불가능한 0-length mark를 버리지 않고 진단한다")
    func emptyLinkFailsClosed() throws {
        // Given
        let markdown = "[]()"

        // When
        let error = try decodingError(for: markdown)

        // Then
        #expect(
            error.diagnostics == [
                diagnostic(.emptyLink, 1, 1, 1, 5)
            ])
    }

    @Test("table은 향후 issue 50 대상인 typed 진단으로 실패한다")
    func tableFailsClosedWithFutureCapabilityDiagnostic() throws {
        // Given
        let markdown = "| a |\n|---|\n| b |"

        // When
        let error = try decodingError(for: markdown)

        // Then
        #expect(
            error.diagnostics == [
                diagnostic(.table, 1, 1, 3, 6)
            ])
    }

    @Test("image inline HTML raw HTML과 h4는 flatten하거나 생략하지 않고 진단한다")
    func unsupportedImageHTMLAndHeadingFailClosed() throws {
        // Given
        let markdown = "![alt](image.png)\n\n<span>x</span>\n\n<table>\n\n#### h4"

        // When
        let error = try decodingError(for: markdown)

        // Then
        #expect(
            error.diagnostics == [
                diagnostic(.image, 1, 1, 1, 18),
                diagnostic(.html, 3, 1, 3, 7),
                diagnostic(.html, 3, 8, 3, 15),
                diagnostic(.html, 5, 1, 5, 8),
                diagnostic(.heading(level: 4), 7, 1, 7, 8),
            ])
        #expect(!error.diagnostics.isEmpty)
    }

    @Test("h4부터 h6까지는 core heading level로 축소하지 않고 원래 level을 진단한다")
    func unsupportedHeadingLevelsRemainTyped() throws {
        // Given
        let levels = 4...6

        // When / Then
        for level in levels {
            let markdown = String(repeating: "#", count: level) + " heading"
            let error = try decodingError(for: markdown)
            #expect(error.diagnostics.count == 1)
            #expect(error.diagnostics[0].kind == .heading(level: level))
        }
    }

    @Test("여러 unsupported subtree를 source 순서와 UTF8 byte range로 모두 모은다")
    func diagnosticsAggregateInSourceOrderWithUTF8ByteColumns() throws {
        // Given
        let markdown = #"😀 ![a](x) [t](d "x")"#

        // When
        let error = try decodingError(for: markdown)

        // Then
        #expect(
            error.diagnostics == [
                diagnostic(.image, 1, 6, 1, 13),
                diagnostic(.linkTitle, 1, 14, 1, 24),
            ])
    }

    @Test("unsupported 부모 subtree 하나는 내부 unsupported 자식을 추가 진단하지 않는다")
    func unsupportedSubtreeIsReportedMaximallyOnce() throws {
        // Given
        let markdown = "![**alt**](image.png \"title\")"

        // When
        let error = try decodingError(for: markdown)

        // Then
        #expect(error.diagnostics.count == 1)
        #expect(error.diagnostics[0].kind == .image)
    }

    @Test("지원 블록이 함께 있어도 unsupported syntax가 있으면 partial blocks를 반환하지 않는다")
    func unsupportedSyntaxHasNoPartialSuccessValue() throws {
        // Given
        let markdown = "# supported\n\n![unsupported](image.png)\n\nafter"
        var returnedBlocks = false

        // When
        do {
            _ = try SlopadMarkdown.decode(markdown)
            returnedBlocks = true
        } catch {
            // Then
            #expect(error.diagnostics.count == 1)
            #expect(error.diagnostics[0].kind == .image)
        }

        // Then
        #expect(!returnedBlocks)
    }

    @Test("공개 source 위치와 진단 값은 Sendable과 Hashable 계약을 가진다")
    func publicDiagnosticValuesAreSendableAndHashable() {
        // Given
        let value = diagnostic(.html, 1, 1, 1, 2)

        // When
        requireSendable(MarkdownSourcePosition.self)
        requireSendable(MarkdownSourceRange.self)
        requireSendable(MarkdownDiagnostic.self)
        requireSendable(MarkdownDecodingError.self)
        let values: Set<MarkdownDiagnostic> = [value]

        // Then
        #expect(values == [value])
    }

    private func decodingError(for markdown: String) throws -> MarkdownDecodingError {
        var captured: MarkdownDecodingError?
        do {
            _ = try SlopadMarkdown.decode(markdown)
        } catch {
            captured = error
        }
        return try #require(captured)
    }

    private func diagnostic(
        _ kind: MarkdownDiagnostic.Kind,
        _ startLine: Int,
        _ startColumn: Int,
        _ endLine: Int,
        _ endColumn: Int
    ) -> MarkdownDiagnostic {
        MarkdownDiagnostic(
            kind: kind,
            sourceRange: MarkdownSourceRange(
                lowerBound: MarkdownSourcePosition(
                    line: startLine,
                    utf8Column: startColumn
                ),
                upperBound: MarkdownSourcePosition(
                    line: endLine,
                    utf8Column: endColumn
                )
            )
        )
    }

    private func requireSendable<T: Sendable>(_: T.Type) {}
}
