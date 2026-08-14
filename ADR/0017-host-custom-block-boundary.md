# 0017 - 호스트 정의 커스텀 블록을 불투명 atomic leaf로 admit한다

Date: 2026-08-14

## Status

Proposed.

이 기록은 구현 이전 제안이다. 출하된 동작에 대한 서술이 아니며 그렇게 인용해서는 안 된다.
여기서 이름 붙인 타입 중 오늘 소스에 존재하는 것은 없다.

높이 sizer의 격리, 본문 호스팅 방식, 포커스 정책 세 가지 결정에 막혀 있다. 이들은
[커스텀 블록 설계 질문](../docs/CUSTOM_BLOCK_DESIGN_QUESTIONS.md)에 D1–D3으로 기록돼 있다.
세 결정 모두 타깃 그래프를 바꾸므로 그것들이 닫히기 전에는 이 ADR을 승인할 수 없다.

## Context

임베딩 앱은 의미가 에디터가 아니라 앱에 속하는 문서 블록이 필요하다. 첫 후보 소비자는 앱이
소유한 Todo를 표시한다. 이는 canonical 에디터 콘텐츠인 built-in `BlockKind.todo(isChecked:)`
체크리스트 항목과는 다른 것이며, 이름 충돌 자체가 한 번은 짚어야 할 위험이다.

`docs/ROADMAP.md`는 "구체적 소비자가 확장/보존 계약을 증명할 때까지" `BlockKind`와 인라인 마크
어휘를 닫아 두고, [Epic #67](https://github.com/hot666666/SlopadEditor/issues/67)은 동적
`BlockKind`/플러그인 레지스트리를 non-goal로 명시한다. 후보 소비자는 별도 downstream 저장소에
있고 그쪽에서 Future로 잡혀 있어 이 설계가 필요로 하는 시점에 증명을 공급할 수 없다. 따라서
증명은 Markdown과 archive 경계가 그랬듯 저장소 안의 fixture와 debug 호스트에서 나와야 한다.

현재 소스가 답의 형태를 제약한다.

| 사실 | 근거 |
| --- | --- |
| `BlockKind`는 8개 case의 닫힌 enum이다 | `Sources/SlopadEditorCoreModel/Document/BlockKind.swift` |
| `BlockKind`를 exhaustive하게 분기하는 프로덕션 파일이 7개 타깃에 걸쳐 9개다 | Markdown 인코더, Archive V1 인코더/디코더/preflight, TextKit chrome 지표, AppKit chrome 렌더러, BlockLayout full pass, 클립보드 write plan, Session 렌더링 |
| atomic한 `divider`를 포함한 모든 블록이 하나의 좁은 `BlockMeasuring` capability로 측정되고, 블록 자신의 값에서 파생된 키로 캐시된다 | `Sources/SlopadEditorBlockLayout/TextLayout/TextLayoutCache.swift:29-45, 83-102` |
| capability 분리가 "a future non-text block type" 자리를 이미 예약해 두었다 | `Sources/SlopadEditorCoreModel/Layout/BlockTextLayoutProtocol.swift:1-10, 69-74` |
| 그 capability는 `Sendable`이고 동기이며, 출하된 백엔드는 뷰가 아니라 락으로 보호된 컨텍스트로 만족시킨다 | `BlockTextLayoutProtocol.swift:13-15`, `TextKitLayoutContext.swift:8-10` |
| 출하된 유일한 비텍스트 atomic leaf는 `divider`다 | `BlockKind+TextCapability.swift:8-18`, `EditorSession+Rendering.swift:413-421` |
| archive 봉투는 `formatVersion:1`로 고정돼 있고 다른 버전에는 fail-closed다 | `ArchiveV1Encoder.swift:10`, `SlopadEditorArchive.swift:67-74` |
| 블록 chrome은 clip된 `CGContext`에 그리기 전용이다 | `Sources/SlopadEditorAppKitUI/AppKitBlockChromeRenderer.swift:10-36` |
| 블록 히트 라우팅에는 세 영역이 있다 | `Sources/SlopadEditorCoreModel/Interaction/BlockHitRegion.swift` |

기록된 실패 패턴 두 개가 해법 공간을 제한한다. `docs/LESSONS_LEARNED.md`의
*Treating an Appearance Hook as a Whole Text Renderer Seam*은 두 번째 고수준 페인트 훅 추가를
금지하고, *Moving Engine Semantics into Native View/Input Hosts*는 네이티브 뷰가 캐럿·선택·
composition·블록 전이 의미를 결정하는 것을 금지한다.

## Decision

다음 조건 아래 하나의 canonical 커스텀 블록을 불투명 atomic leaf로 admit한다. P1–P9는 이 설계가
확정으로 보는 부분이고, 확정하지 못한 부분은 다음 절에 있으며 승인을 막는다.

**P1 — canonical 표현은 불투명하다.** 커스텀 블록은 안정적인 호스트 `typeID`, 호스트 `version`,
불투명 payload를 가진다. 에디터는 공통 불변식(identity, 유일성, canonical 순서, leaf 여부,
payload 크기 예산)만 검증하고 호스트의 의미를 절대 디코딩하지 않는다. 커스텀 블록은
`isTextCapable == false`이며 canonical 인라인 텍스트나 마크를 갖지 않는다.

payload가 canonical `Block` 값 안에 있어야 한다는 것은 취향이 아니라 정확성 요구다. 측정 캐시는
블록 자신의 값에서 키를 만들므로, payload가 그 키가 읽지 못하는 곳에 있으면 편집 후 낡은 높이가
반환된다.

**P2 — 1차 커스텀 블록은 leaf다.** 자식 에디터 블록을 담을 수 없다. 컨테이너는 별도의 불변식
집합을 가진 별도의 미래 결정이다.

**P3 — provider는 에디터 인스턴스마다 주입된다.** 전역 레지스트리도, 프로세스 전역 타입 테이블도,
동적 발견도 없다. 이로써 Epic #67의 non-goal이 유지된다. 닫힌 `BlockKind` 어휘가 불투명 case
하나를 얻는 것이지 플러그인 시스템을 얻는 것이 아니다.

**P4 — 미지의 타입은 정확히 보존된다.** 등록된 provider가 없는 `typeID`의 블록은 읽기 전용 미지원
placeholder로 표시되며 identity·타입·버전·payload를 바이트 단위로 유지한다. 선택·이동·복사·삭제는
계속 가능하다. 호스트가 재구성할 수 없는 문서는 렌더링할 수 없는 문서보다 나쁘기 때문이다.

**P5 — 리뷰된 patch는 기본적으로 미지의 커스텀 블록을 보존한다.** `applyDocumentPatch`는 provider가
등록되지 않은 커스텀 블록을 삭제·재타이핑·재버전·payload 재작성하는 post-image를, 호출자가 명시적
호스트 capability를 갖지 않는 한 거부한다. 이는 patch 생산자에 대한 예의 규칙이 아니라
`Document+CanonicalReplacementValidation`의 새 canonical replacement 불변식이다. 그러지 않으면
문서를 Markdown으로 왕복시킨 assistant가 앱 소유 콘텐츠를 조용히 삭제한다.

P4와 P5는 같은 연산에 경로별로 다른 답을 준다. 사용자가 미지의 블록을 직접 삭제하는 것은
허용되고, patch가 같은 일을 하는 것은 capability 없이 거부된다. 이는 의도된 것이다. 직접 조작은
사람이 그 순간 보고 한 행위이고, patch는 일괄 교체라 조용한 소실이 위험이다.

**P6 — 포맷 경계는 fail-closed를 유지한다.** `SlopadEditorMarkdown`의 encode와 decode는 미지원
`typeID`를 지목하는 타입 있는 진단과 함께 실패한다. 코덱은 호스트 훅도, 손실 허용 fallback도 얻지
않는다. 호스트별 변환은 코덱 밖에서, canonical 블록 값에 대해, encode 전이나 decode 후에 일어난다.
구조화 클립보드는 payload를 싣고, 평문 fallback은 payload 바이트가 아니라 결정적 placeholder를
내보낸다.

이 계약은 비대칭이다. encode는 호스트가 미리 변환하면 통과할 수 있지만 decode는 커스텀 블록을
생산할 수 없다. 따라서 export → import 왕복은 커스텀 블록을 영구히 잃는다.

**P7 — 에디터가 모든 의미 표면을 유지한다.** hover rail(`+`, 드래그 핸들, 블록 메뉴), 히트 라우팅,
드래그 앤 드롭, 블록 선택, 캐럿과 텍스트 선택, 텍스트 렌더링, IME는 에디터 소유로 남는다.
provider는 자기 블록 본문만 렌더링한다.

**P8 — 이미지와 테이블은 custom이 아니라 built-in이다.** 이들은
[#50](https://github.com/hot666666/SlopadEditor/issues/50)과 그 후속 아래 canonical 에디터 능력이
된다. 호스트 탈출구로 우회하면 같은 문서 의미에 소유자가 둘 생긴다.

**P9 — AI 결과는 블록 종류가 아니다.** 외부 Markdown은 canonical 블록으로 디코딩되어 기존
epoch/revision/selection CAS와 함께 `documentContextSnapshot()` / `applyDocumentPatch(_:)`로
들어온다. AI 응답 블록은 존재하지 않는다.

## 의도적으로 결정하지 않은 것

아래는 승인을 막는다. 각각이 어느 타깃이 계약을 소유하는지를 바꾸므로, 하나를 추측하면
`AGENTS.md`가 문서를 먼저 고치라고 말하는 바로 그 intent/source 불일치를 만들어낸다.

- **D1 — sizer의 격리와 입력.** 측정 seam은 이미 존재하고 비텍스트 블록 자리를 이미 예약해
  두었다. 열려 있는 것은 더 좁다. 그 capability는 `Sendable`이고 동기이며 출하된 백엔드가 뷰가
  아니라 락으로 보호된 컨텍스트로 만족시키므로, provider는 이 seam을 통해 살아 있는 `NSView`에게
  크기를 물을 수 없다.
- **D2 — 본문 호스팅 방식.** `AppKitBlockChromeRenderer`는 상호작용 컨트롤을 담을 수 없고, 두 번째
  페인트 훅 추가는 기록된 실패 패턴이다.
- **D3 — 포커스와 포인터 정책.** 캔버스 `NSTextInputClient` 계약을 지키려면 키보드 first responder를
  넘길 수 없다. 포인터 상호작용은 별개의 축이며 같은 답을 갖지 않는다.

## 승인 시 필요한 개정

승인은 국소적 변경이 아니다. 승인된 기록 넷을 개정하며, 각 개정은 후속 정리가 아니라 같은 결정의
일부다.

| 기록 | 필요한 개정 |
| --- | --- |
| [ADR 0012](0012-host-embedding-contract.md) | 세 번째 시험은 네이티브 키·IME·포인터·reveal·페인트 파이프라인 위의 호스트 훅을 금지한다. 블록 본문을 그리는 provider는 페인트·히트 테스트·경우에 따라 포커스에 참여한다. 자체 경계를 가진 명시적이고 좁은 예외가 필요하거나, 세 번째 시험이 그대로 성립할 때까지 메커니즘을 다시 다듬어야 한다. 같은 시험이 provider 주입 지점에도 적용된다. provider 집합은 동기화된 액션도 값 관찰도 아니다 |
| [ADR 0015](0015-version-native-archive-and-keep-storage-host-owned.md) | 봉투는 `formatVersion:1`이고 그 외에는 fail-closed다. 커스텀 블록은 V2와, V1 리더가 V2 문서를 어떻게 다루는지에 대한 명시된 정책, 그리고 기존 바이트/깊이/멤버 예산 안의 payload 예산을 요구한다 |
| [ADR 0013](0013-markdown-format-boundary.md) | 미지원 커스텀 블록 진단 case가 추가된다. fail-closed 계약 자체는 변하지 않는다 |
| `docs/ROADMAP.md`, `docs/ARCHITECTURE.md` | 닫힌 `BlockKind` 제약, 소유권 표, 런타임 경로 표가 각각 커스텀 블록 소유자와 경로를 얻는다 |

## Consequences

- 닫힌 enum에 불투명 case 하나가 추가된다. 레지스트리보다 작은 약속이지만, 여전히 7개 타깃의
  exhaustive switch 9곳이 답을 내놓아야 한다. 각 답은 컴파일러가 시키는 잡일이 아니라 경계 결정이다.
- archive는 이전 리더가 넘을 수 없는 버전 경계를 얻는다. 호스트 콘텐츠를 canonical 문서에 담기로 한
  선택의 대가다.
- 커스텀 블록을 가진 문서는 Markdown으로 내보낼 수 없다. export가 필요한 호스트는 코덱 밖에서 자기
  블록을 먼저 변환해야 하고, 그렇게 해도 왕복으로는 돌아오지 않는다.
- 에디터가 호스트로부터 캔버스 안쪽 픽셀을 받는 첫 계약을 갖게 된다. D2가 무엇을 정하든, 그 경계가
  위 실패 패턴들이 가장 쌓이기 쉬운 곳이므로 단위 테스트만이 아니라 자체 fixture가 필요하다.
- D2가 호스트 `NSView`를 고르면 그 뷰들이 접근성 트리에 자동으로 올라간다. 그러면
  [#94](https://github.com/hot666666/SlopadEditor/issues/94)의 cycle-safe 요구가 병행 항목이 아니라
  선행 조건이 된다.
- 순서: 이 작업은 Epic #67이 닫힌 뒤 시작한다. 미완인 #70/#71/#74/#76 트랙과 owner를 공유하며,
  canonical·IME·TextKit 변경은 두 writer를 견디지 못한다.
