import SlopadCoreModel
import SlopadEditorMarkdownInputRules
import Testing

@testable import SlopadEditorModel

// MARK: - EditorInputRuleRunner

@Suite("입력 규칙 실행기")
struct EditorInputRuleRunnerTests {
    private let runner = EditorInputRuleRunner(rules: MarkdownInputRules.all)

    @Test("트리거가 아닌 문자는 규칙을 전혀 돌리지 않는다")
    func nonTriggerNeverScans() {
        // Given: 규칙이 절대 호출되면 안 된다는 것을 매처 자체가 감시한다.
        nonisolated(unsafe) var matchCalls = 0
        let watched = EditorInputRuleRunner(rules: [
            EditorInputRule(triggers: [" "], scanLimit: 8) { _ in
                matchCalls += 1
                return nil
            }
        ])

        // When: 한글·영문·숫자 — 마크다운 문법을 닫을 수 없는 문자들
        for committed in ["한", "글", "a", "Z", "7", "가나다"] {
            _ = watched.effect(committedText: committed, candidate: candidate("# 제목", caretOffset: 2))
        }

        // Then
        #expect(matchCalls == 0)
    }

    @Test("트리거 문자여야 규칙이 돌아간다")
    func triggerReachesTheRule() {
        // Given / When
        let effect = runner.effect(committedText: " ", candidate: candidate("# ", caretOffset: 2))

        // Then
        #expect(effect == .convertBlock(removing: TextRange(0, 2), to: .heading(level: .h1)))
    }

    @Test("모든 prefix 규칙이 이전과 같은 결과를 낸다")
    func portsEveryPrefixRule() {
        // Given
        let cases: [(text: String, closing: String, kind: BlockKind)] = [
            ("# ", " ", .heading(level: .h1)),
            ("## ", " ", .heading(level: .h2)),
            ("### ", " ", .heading(level: .h3)),
            ("- ", " ", .unorderedListItem),
            ("* ", " ", .unorderedListItem),
            ("> ", " ", .quote),
            ("[x] ", " ", .todo(isChecked: true)),
            ("[X] ", " ", .todo(isChecked: true)),
            ("[ ] ", " ", .todo(isChecked: false)),
            ("[] ", " ", .todo(isChecked: false)),
            ("```", "`", .codeBlock(language: nil)),
            ("1. ", " ", .orderedListItem(restartNumber: nil)),
            ("7. ", " ", .orderedListItem(restartNumber: 7)),
        ]

        for entry in cases {
            // When
            let effect = runner.effect(
                committedText: entry.closing, candidate: candidate(entry.text, caretOffset: entry.text.count))

            // Then
            #expect(
                effect == .convertBlock(removing: TextRange(0, entry.text.count), to: entry.kind),
                "\(entry.text) 가 \(entry.kind) 로 변환되어야 한다")
        }
    }

    @Test("불완전한 문법은 리터럴로 남는다")
    func incompleteSyntaxStaysLiteral() {
        // Given
        let rejected: [(text: String, closing: String)] = [
            ("#", "#"),
            ("####", " "),
            ("- x ", " "),
            ("[x]", "]"),
            (". ", " "),
            ("1234567890. ", " "),
            ("a. ", " "),
        ]

        for entry in rejected {
            // When
            let effect = runner.effect(
                committedText: entry.closing, candidate: candidate(entry.text, caretOffset: entry.text.count))

            // Then
            #expect(effect == nil, "\(entry.text) 는 변환되면 안 된다")
        }
    }

    @Test("스캔 범위를 넘어선 위치에서는 매칭하지 않는다")
    func staysWithinTheScanLimit() {
        // Given: 스캔 상한을 넘는 caret. 긴 문단이 짧은 문단보다 비싸지지 않게 하는 성질이다.
        let local = " "

        // When
        let effect = runner.effect(
            committedText: " ",
            candidate: candidate(local, caretOffset: 1, baseOffset: 400)
        )

        // Then
        #expect(effect == nil)
    }

    @Test("커밋된 텍스트의 마지막 문자만 본다")
    func onlyTheLastCommittedCharacterGates() {
        // Given: IME 확정처럼 여러 글자가 한 번에 들어와도 마지막 글자가 trigger를 결정한다.
        // When
        let closes = runner.effect(committedText: "IME ", candidate: candidate("# ", caretOffset: 2))
        let doesNot = runner.effect(committedText: " IME", candidate: candidate("# ", caretOffset: 2))

        // Then
        #expect(closes != nil)
        #expect(doesNot == nil)
    }

    private func candidate(
        _ text: String,
        caretOffset: Int,
        baseOffset: Int = 0
    ) -> EditorInputRuleCandidate {
        EditorInputRuleCandidate(
            text: text,
            caretOffset: caretOffset,
            baseOffset: baseOffset
        )
    }
}
