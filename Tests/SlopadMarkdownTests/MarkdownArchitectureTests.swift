import Foundation
import Testing

@Suite("Markdown architecture boundary")
struct MarkdownArchitectureTests {
    @Test("Markdown import는 adapter 내부의 internal import만 허용해 AST 공개 누출을 막는다")
    func markdownImportsStayInternalAndInsideAdapter() throws {
        // Given
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: sources,
                includingPropertiesForKeys: nil
            )
        )
        var markdownImports: [(path: String, line: String)] = []

        // When
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            for declaration in markdownModuleImports(in: source) {
                markdownImports.append((fileURL.path, declaration))
            }
        }

        // Then
        #expect(!markdownImports.isEmpty)
        for markdownImport in markdownImports {
            #expect(markdownImport.path.contains("/Sources/SlopadMarkdown/"))
            #expect(markdownImport.line == "internal import Markdown")
        }
    }

    @Test("Markdown import scanner는 scoped attribute access-level 변형을 모두 찾는다")
    func markdownImportScannerRecognizesEveryDeclarationShape() {
        // Given
        let imports = [
            "import Markdown",
            "internal import Markdown",
            "public import Markdown",
            "import struct Markdown.Document",
            "internal import enum Markdown.ParseOptions",
            "@testable import Markdown",
            "@_exported import Markdown",
            "@_implementationOnly import Markdown",
            "@preconcurrency public import Markdown",
            "public import Markdown // trailing comments cannot hide an import",
        ]
        let nonImports = [
            "import MarkdownUI",
            "import Other.Markdown",
            "let example = \"import Markdown\"",
            "// import Markdown",
            "internal import MarkdownSupport",
        ]

        // When / Then
        for declaration in imports {
            #expect(isMarkdownModuleImport(declaration))
        }
        for declaration in nonImports {
            #expect(!isMarkdownModuleImport(declaration))
        }
    }

    @Test("Markdown import scanner는 semicolon statement를 찾고 comment와 string은 무시한다")
    func markdownImportScannerFindsSemicolonStatementsWithoutFalsePositives() {
        // Given
        let source = """
            import Foundation; import Markdown
            @preconcurrency public import Markdown; import struct Markdown.Document
            let string = "import Markdown; import Markdown"
            // import Markdown; import Markdown
            /* import Markdown; import Markdown */
            """

        // When
        let imports = markdownModuleImports(in: source)

        // Then
        #expect(
            imports == [
                "import Markdown",
                "@preconcurrency public import Markdown",
                "import struct Markdown.Document",
            ]
        )
    }

    private func markdownModuleImports(in source: String) -> [String] {
        sourceStatements(in: source).filter(isMarkdownModuleImport)
    }

    private func sourceStatements(in source: String) -> [String] {
        var statements: [String] = []
        var statement = ""
        var index = source.startIndex

        func appendStatement() {
            let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                statements.append(trimmed)
            }
            statement.removeAll(keepingCapacity: true)
        }

        while index < source.endIndex {
            if source[index].isNewline || source[index] == ";" {
                appendStatement()
                index = source.index(after: index)
            } else if source[index...].hasPrefix("//") {
                skipLineComment(in: source, index: &index)
                statement.append(" ")
            } else if source[index...].hasPrefix("/*") {
                skipBlockComment(in: source, index: &index)
                statement.append(" ")
            } else if let rawDelimiterCount = rawStringDelimiterCount(in: source, at: index) {
                skipStringLiteral(
                    in: source,
                    index: &index,
                    rawDelimiterCount: rawDelimiterCount
                )
                statement.append(" ")
            } else {
                statement.append(source[index])
                index = source.index(after: index)
            }
        }
        appendStatement()
        return statements
    }

    private func skipLineComment(in source: String, index: inout String.Index) {
        index = source.index(index, offsetBy: 2)
        while index < source.endIndex, !source[index].isNewline {
            index = source.index(after: index)
        }
    }

    private func skipBlockComment(in source: String, index: inout String.Index) {
        var depth = 1
        index = source.index(index, offsetBy: 2)

        while index < source.endIndex, depth > 0 {
            if source[index...].hasPrefix("/*") {
                depth += 1
                index = source.index(index, offsetBy: 2)
            } else if source[index...].hasPrefix("*/") {
                depth -= 1
                index = source.index(index, offsetBy: 2)
            } else {
                index = source.index(after: index)
            }
        }
    }

    private func rawStringDelimiterCount(in source: String, at index: String.Index) -> Int? {
        var delimiterEnd = index
        var rawDelimiterCount = 0
        while delimiterEnd < source.endIndex, source[delimiterEnd] == "#" {
            rawDelimiterCount += 1
            delimiterEnd = source.index(after: delimiterEnd)
        }
        guard delimiterEnd < source.endIndex, source[delimiterEnd] == "\"" else { return nil }
        return rawDelimiterCount
    }

    private func skipStringLiteral(
        in source: String,
        index: inout String.Index,
        rawDelimiterCount: Int
    ) {
        index = source.index(index, offsetBy: rawDelimiterCount)
        let isMultiline = source[index...].hasPrefix("\"\"\"")
        let openingLength = isMultiline ? 3 : 1
        index = source.index(index, offsetBy: openingLength)

        while index < source.endIndex {
            if rawDelimiterCount == 0, source[index] == "\\" {
                index = source.index(after: index)
                if index < source.endIndex {
                    index = source.index(after: index)
                }
                continue
            }

            let closingLength = isMultiline ? 3 : 1
            let closingQuotes = String(repeating: "\"", count: closingLength)
            if source[index...].hasPrefix(closingQuotes) {
                let delimiterStart = source.index(index, offsetBy: closingLength)
                var delimiterEnd = delimiterStart
                var matchedDelimiterCount = 0
                while delimiterEnd < source.endIndex,
                    source[delimiterEnd] == "#",
                    matchedDelimiterCount < rawDelimiterCount
                {
                    matchedDelimiterCount += 1
                    delimiterEnd = source.index(after: delimiterEnd)
                }
                if matchedDelimiterCount == rawDelimiterCount {
                    index = delimiterEnd
                    return
                }
            }

            index = source.index(after: index)
        }
    }

    private func isMarkdownModuleImport(_ line: String) -> Bool {
        line.wholeMatch(
            of:
                #/^\s*(?:(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\r\n]*\))?)\s+)*(?:(?:private|fileprivate|internal|package|public|open)\s+)?import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?Markdown(?:\.[A-Za-z_][A-Za-z0-9_]*)*\s*;?\s*(?://.*)?$/#
        ) != nil
    }
}
