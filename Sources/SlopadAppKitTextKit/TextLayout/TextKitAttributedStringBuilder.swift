import AppKit
import Foundation
import SlopadCoreModel

// MARK: - TextKitAttributedStringBuilder

enum TextKitAttributedStringBuilder {
    static func attributedString(
        for request: BlockMeasureRequest,
        style: TextKitEditorStyle
    ) -> NSAttributedString {
        attributedString(
            for: request,
            style: style,
            baseFont: baseFont(for: request.kind, style: style)
        )
    }

    static func attributedString(
        for request: BlockMeasureRequest,
        style: TextKitEditorStyle,
        baseFont: NSFont
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = style.lineHeightMultiple

        let measuredText = request.text.isEmpty ? " " : request.text
        let attributed = NSAttributedString(
            string: measuredText,
            attributes: textAttributes(
                font: baseFont,
                paragraph: paragraph,
                languageIdentifier: style.languageIdentifier
            )
        )
        let mutable = NSMutableAttributedString(attributedString: attributed)
        guard !request.text.isEmpty else { return mutable }

        for run in request.inlineRuns where !run.range.isEmpty {
            let range = run.range.textKitNSRange(in: request.text)
            guard range.location >= 0, NSMaxRange(range) <= mutable.length else { continue }

            var attributes = textAttributes(
                font: inlineFont(from: baseFont, marks: run.marks),
                paragraph: paragraph,
                languageIdentifier: style.languageIdentifier
            )
            if let link = linkDestination(in: run.marks) {
                attributes[.link] = link
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            mutable.addAttributes(attributes, range: range)
        }

        return mutable
    }

    private static func textAttributes(
        font: NSFont,
        paragraph: NSParagraphStyle,
        languageIdentifier: String?
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        if let languageIdentifier, !languageIdentifier.isEmpty {
            attributes[.languageIdentifier] = languageIdentifier
        }
        return attributes
    }

    static func baseFont(for kind: BlockKind, style: TextKitEditorStyle) -> NSFont {
        switch kind {
        case .heading(let level):
            let multiplier: Double
            switch level {
            case .h1:
                multiplier = 1.65
            case .h2:
                multiplier = 1.35
            case .h3:
                multiplier = 1.18
            }
            return systemOrNamedFont(
                named: style.fontName,
                size: style.fontSize * multiplier,
                weight: .semibold
            )
        case .codeBlock:
            return NSFont.monospacedSystemFont(ofSize: style.fontSize, weight: .regular)
        default:
            return systemOrNamedFont(named: style.fontName, size: style.fontSize, weight: .regular)
        }
    }

    static func inlineFont(
        from baseFont: NSFont,
        marks: Set<BlockContent.InlineMark.Kind>
    ) -> NSFont {
        let codeFont =
            marks.contains(.code)
            ? NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.95, weight: .regular)
            : baseFont

        let manager = NSFontManager.shared
        var font = codeFont
        if marks.contains(.bold) {
            font = manager.convert(font, toHaveTrait: .boldFontMask)
        }
        if marks.contains(.italic) {
            font = manager.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }

    static func systemOrNamedFont(
        named fontName: String,
        size: Double,
        weight: NSFont.Weight
    ) -> NSFont {
        if fontName == "System" {
            return NSFont.systemFont(ofSize: size, weight: weight)
        }

        let namedFont =
            NSFont(name: fontName, size: size)
            ?? NSFont.systemFont(ofSize: size, weight: weight)
        guard weight != .regular else { return namedFont }
        return NSFontManager.shared.convert(namedFont, toHaveTrait: .boldFontMask)
    }

    static func linkDestination(in marks: Set<BlockContent.InlineMark.Kind>) -> String? {
        for mark in marks {
            if case .link(let destination) = mark {
                return destination
            }
        }
        return nil
    }
}
