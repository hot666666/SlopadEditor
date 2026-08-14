# 커스텀 블록 · 프레젠테이션 · 자동화 — 미결 설계 질문

## 이 문서의 지위

구현 이전 제안이자 결정 대기열이다. **이 문서의 어떤 절도 계약이 아니다.** 오늘의 동작은
현재 소스와 테스트가 정의하고, 경계는 [Architecture](ARCHITECTURE.md)와 승인된
[ADR](../ADR/README.md)이 정의한다. 이 문서가 이름 붙인 타입은 아직 존재하지 않는다.

[ADR 0017](../ADR/0017-host-custom-block-boundary.md)은 아래 질문들이 닫히기 전에는 승인될 수
없다. 이전 핸드오프가 ADR 0016 리네임 이전 이름과 PR #90–#93 이전의 접근성 상태를 기준으로
쓰여 있었기 때문에, 정정된 사실도 함께 기록한다.

일정: 이 트랙은 [Epic #67](https://github.com/hot666666/SlopadEditor/issues/67)이 닫힌 뒤
시작한다. 질문에 답하고 개정안을 준비하는 일은 지금 할 수 있고, 코드는 할 수 없다.

## 정정된 현재 상태

| 낡은 서술 | 현재 소스 |
| --- | --- |
| 리네임 이전 패키지 접두사로 표기된 모든 모듈과 파일 경로 | 전체 타깃 그래프가 [ADR 0016](../ADR/0016-name-the-package-slopadeditor-and-reserve-slopad-for-the-app.md)의 `SlopadEditor*` 계열을 쓴다. `scripts/verify-naming.sh`가 리네임 이전 표기를 회귀로 취급한다. SwiftUI 표면 파일은 `SlopadEditorView.swift`, `SlopadEditorViewModel.swift`, `SlopadEditorDocument.swift` |
| 인스턴스별 호스트 접근성 identifier/label이 없다 | `AppKitEditorViewController.configureEditorAccessibility(identifier:label:)`(`AppKitEditorViewController.swift:399-406`)와 `SlopadEditorView.editorAccessibility(identifier:label:)`(`SlopadEditorView.swift:83-90`)가 public이다. identity는 scroll surface에 적용되고, 값 동기화와 `.valueChanged` 게시까지 있다(`:696-699`, `:872-885`) |
| 접근성 계약이 전혀 없다 | 남은 것은 블록 단위 의미 투영과 cycle-safe 크로스프로세스 자동화 계약이며 [#94](https://github.com/hot666666/SlopadEditor/issues/94)가 소유한다. 현재 downstream MVP blocker에서 제외돼 있고 실험 PR #95는 폐기됐다 |
| 블록 chrome이 프레젠테이션 확장점이다 | clip된 `CGContext`에 그리기 전용이며(`AppKitBlockChromeRenderer.swift:10-36`), [Lessons Learned](LESSONS_LEARNED.md)의 *Treating an Appearance Hook as a Whole Text Renderer Seam*이 확장을 금지한다 |
| (누락) | built-in 플로팅 서식 툴바와 블록별 todo 체크박스는 이미 출하됐다(`AppKitFloatingFormattingToolbar.swift`, `AppKitTodoCheckboxControl.swift`). hover rail은 첫 chrome이 아니라 그 위의 추가다 |
| (누락) | `divider`가 출하된 유일한 비텍스트 atomic leaf다. 커스텀 블록의 selection·Enter·Backspace·클립보드·틴트 동작은 새로 발명하지 말고 여기서 파생시킨다 |

## 결정 대기 항목

각 항목은 어렵게 만드는 제약, 실제 선택지, 권고안을 적는다. D1–D3은 ADR 승인을 막고,
D4–D6·D10–D12는 구현을 막고, D7–D9는 프레젠테이션·자동화 트랙을 막는다.

### D1 — 커스텀 블록 sizer는 어떤 격리와 입력을 받나

측정 메커니즘은 이미 있고, seam은 이 경우를 이미 예약해 두었다. `SlopadEditorBlockLayout`은
`any BlockMeasuring`을 들고 있다. 이것은 "높이와 baseline" 하나만 답하는 좁고 `Sendable`이며
동기적인 capability이고, geometry·navigation·deletion과 따로 선언된 이유가 바로
"소비자에게 쓰는 것만 건넨다 — `BlockLayout`은 높이만 필요하다"이다
(`BlockTextLayoutProtocol.swift:1-10`). 같은 파일의 주석이 capability를 쪼갠 이유 중 하나로
**"a future non-text block type"을 이미 명시**한다(`:69-74`). `TextLayoutCache`는
`blockID + text + kind + marks + availableWidth + depth`로 키를 만들어 "같은 입력이면 같은
측정"이 구조적으로 보장되고, `invalidate(blockID:)`도 이미 있다
(`TextLayoutCache.swift:29-45, 105-107`).

따라서 질문은 "높이를 누가 소유하나"가 아니다. 실제 결정은 다음 두 가지다.

1. **payload는 키가 읽는 canonical `Block` 값 안에 있어야 한다.** 다른 곳에 두면 payload 편집
   후 캐시가 낡은 높이를 돌려준다. ADR 0017 P1이 이미 그렇게 정한 진짜 이유가 이것이며, 이
   조항은 협상 대상이 아니다.
2. **`BlockMeasuring`은 `Sendable`이고 동기다.** 출하된 TextKit 백엔드는 이를 뷰가 아니라 락으로
   보호된 `TextKitLayoutContext`로 만족시킨다(`TextKitLayoutContext.swift:8-10`). 그러므로
   provider는 이 seam을 통해 살아 있는 `NSView`에게 크기를 물을 수 없다.

| 선택지 | 형태 | 비용 |
| --- | --- | --- |
| **A. payload와 너비에 대한 순수 sizing 함수** | provider가 `Sendable`한 `(payload, version, width, depth) -> height`를 제공, 뷰 미개입 | 기존 seam을 그대로 쓴다. 진짜 intrinsic sizing이 필요한 호스트는 그 계산을 뷰 밖에서 재현해야 한다 |
| **B. 런타임 뷰 측정 + 무효화** | 어댑터가 마운트된 본문을 측정해 높이 변경을 알리고, 레이아웃이 해당 블록을 무효화·재측정 | 동기적으로 크기를 알 수 없는 콘텐츠를 처리한다. seam에 없는 격리 story와, 자기 높이에 반응해 다시 크기가 변하는 본문이 루프를 만들지 않도록 수렴 규칙이 필요하다 |
| **C. canonical 선언 높이** | payload 봉투에 높이를 저장해 상수처럼 읽음 | 프레젠테이션 값을 canonical 문서 상태로 만들어 소유권 표와 모순되고, 너비·폰트 변경에서 깨진다 |

권고: **A를 계약으로, B는 비동기 크기 콘텐츠에 한한 탈출구**로 두고 레이아웃 패스당 재측정
횟수 상한을 명시한다. C는 제외한다. 첫 후보 소비자(앱 소유 Todo 표시)는 payload만으로 크기가
나오므로 1차에는 A로 충분할 가능성이 높다.

### D2 — provider는 어떻게 캔버스 안에 픽셀을 넣나

| 선택지 | 형태 | 비용 |
| --- | --- | --- |
| **A. 보이는 커스텀 블록마다 호스트 `NSView` 서브뷰** | 어댑터가 레이아웃 좌표로 호스트 뷰를 마운트·재활용 | 네이티브 컨트롤·포커스·접근성이 공짜로 동작한다. 단일 scroll owner, damage/redraw 모델, 빠른 스크롤 중 뷰 재활용과 충돌한다 |
| **B. 두 번째 페인트 훅** | chrome처럼 clip된 컨텍스트에 provider가 그린다 | Lessons Learned가 명시적으로 금지한 실패 패턴이고, 컨트롤을 담을 수도 없다 |
| **C. 캔버스 위 오버레이 레이어** | 호스트 뷰가 스크롤에 동기화되는 형제 레이어에 존재 | 캔버스 드로잉을 건드리지 않는다. 스크롤·damage를 정확히 추적해야 하는 두 번째 표면이 생기고, 실패가 눈에 보이는 어긋남으로 나타난다 |

권고: **A**, 단 어댑터가 소유하는 재활용 마운트 포인트와 명시적 lifecycle 콜백으로 제한한다.
B는 Lessons Learned가 배제한다. C는 어려운 동기화 문제를 더 눈에 띄는 문제로 바꿀 뿐이다.

### D3 — 커스텀 본문의 포커스와 포인터 정책

**두 축을 분리해야 한다.** 이전 판은 "display-only"라는 표현으로 키보드 포커스와 포인터
상호작용을 뭉뚱그렸는데, 이 둘은 다른 결정이다. 캔버스가 `NSTextInputClient`이므로 호스트 뷰가
first responder가 되면 IME·캐럿·선택 모델이 입력 표면을 잃는다. 반면 클릭을 받는 것은 first
responder가 되는 것과 무관하다 — 출하된 todo 체크박스가 이미 그 증거다.

| 축 | 선택지 | 권고 |
| --- | --- | --- |
| 키보드 first responder | (a) 절대 안 받음 (b) Session 액션을 통한 명시적 대여·반납 | **(a)**. (b)는 IME·undo·선택마다 두 번째 포커스 소유자를 만든다 |
| 포인터 상호작용 | (a) 히트가 블록 선택으로만 해석 (b) provider가 클릭·드래그를 소비하되 rail·구조 드래그 우선순위는 에디터가 유지 | **(b)**. 앱 소유 Todo를 토글하려면 클릭이 필요하고, 이는 키보드 포커스를 요구하지 않는다 |

즉 1차 권고는 "**키보드는 절대 안 넘기고 포인터는 넘긴다**"이다. 이 조합에서 우선순위 규칙이
필요하다: rail·드래그 핸들 히트가 본문 히트를 이긴다.

### D4 — custom case는 `BlockKind`에 어떻게 들어가고, 각 switch는 무엇을 답하나

오늘 9개 프로덕션 파일이 exhaustive하게 분기한다. case 추가는 기계적 수정이 아니다. 각 지점이
경계에 대한 답이다(Markdown 진단, archive 와이어 모양, chrome 지표, 마커 종류, 레이아웃 분기,
클립보드 평문 fallback, 선택 틴트). `BlockKind.custom(typeID:version:)` + `BlockContent`에 payload를
둘지, 한 case가 봉투 전체를 들지 정한다. selection·Enter·Backspace·틴트는 `divider`에서 파생시킨다.

### D5 — archive 호환 정책은 무엇인가

봉투는 `formatVersion:1`로 고정돼 있고 다른 값에는 fail-closed다. 커스텀 블록은 V2를 요구한다.
결정할 것: V1 리더가 V2 문서를 통째로 거부하는가(현재 fail-closed 동작이자 정직한 선택),
그리고 커스텀 블록이 없는 문서는 인코더가 V1을 계속 내보내 기존 파일이 읽히게 할 것인가.
payload 바이트 예산도 기존 admission 예산 안에 정한다 — 불투명 `Data`는 그러지 않으면 무한이다.

### D6 — patch 보존 불변식은 정확히 무엇을 검사하나

ADR 0017 P5는 보존을 생산자의 예의가 아니라 canonical replacement 불변식으로 만든다. 비교 키
(identity + `typeID` + `version` + payload 바이트), capability 없이 unknown 블록의 순서 변경을
허용할지, 호스트 capability를 patch에 어떻게 표현할지 정한다. capability가 일반적인 "검증 건너뛰기"
플래그가 되어서는 안 된다.

**경로별 비대칭을 명문화해야 한다.** P4는 사용자가 unknown 블록을 직접 이동·삭제하는 것을
허용하고, P5는 patch가 같은 일을 하는 것을 capability 없이는 거부한다. 같은 연산이 도달 경로에
따라 답이 다르다. 이는 의도된 것이다 — 직접 조작은 사람이 그 순간 보고 한 행위이고, patch는
일괄 교체라 조용한 소실이 위험이다. 하지만 문서에 이유를 적지 않으면 구현자가 둘 중 하나를
버그로 오해한다.

### D7 — hover 상태는 어느 레이어가 소유하고, `BlockHitRegion`은 넓어지나

`BlockHitRegion`은 `body`, `dragHandle`, `gutter` 셋이다. Notion식 rail은 삽입 어포던스와 블록
메뉴를 더하고, 커스텀 본문이 네 번째 목적지를 더한다. 소유권 표는 오버레이 위젯을 플랫폼
런타임에 두므로 hover는 AppKit, 히트 분류는 Session이라는 분할이 자연스럽다. 양쪽 코드를 쓰기
전에 이 분할을 확정한다.

### D8 — 프레젠테이션 토큰은 무엇이고, 무엇을 무효화하나

목표 화면은 상시 gutter 구분선 없음, hover된 블록 옆에만 나타나는 rail 어포던스, 블록 콘텐츠와
인라인인 체크박스, 조용한 텍스트 블록 경계, 자체 배경을 가진 callout·code, 서로 다른 블록
표현에도 유지되는 텍스트 컬럼 정렬이다. 원본 스크린샷은 OS 임시 디렉터리에 있었으므로 이미
없다고 가정하고, 토큰을 구현 전에 저장소 안에 고정한다.

**이 목표는 이미 출하된 기본 chrome과 두 곳에서 정면으로 충돌한다.**

1. `AppKitDefaultBlockChromeRenderer`는 gutter 구분선을 **항상** 그린다
   (`AppKitBlockChromeRenderer.swift:113-119`). 목표는 상시 구분선 없음이다.
2. `AppKitTodoCheckboxControl.hitRect`는 체크박스를 **gutter 중앙**에 놓는다
   (`AppKitTodoCheckboxControl.swift:16-29`, `gutterRect.midX`). 목표는 콘텐츠와 인라인이다.

두 번째가 더 무겁다. 체크박스를 콘텐츠 lane으로 옮기면 ROADMAP P2가 확정한 히트 우선순위
규칙의 기하 전제가 무너진다. 그 규칙은 "체크박스 히트가 **gutter** 선택이나 블록 드래그를
시작하지 않으며, 컨트롤이 아닌 **gutter** 히트만 구조 선택/드래그 경로를 쓴다"고 말한다.
체크박스가 gutter를 떠나면 경쟁 상대가 gutter가 아니라 **텍스트 히트**가 된다.

즉 D8은 새 기능 추가가 아니라 **완료된 P2 결정의 재개**이며, 기존 호스트에게는 눈에 보이는 기본
외형 변경이다. 진행 여부는 소유자 판단이 필요하다.

정렬은 기하에 영향을 준다. `TextKitEditorStyle`(=`AppKitEditorStyle`)을 바꾸고, 이 값은 하나의
원자적 설정 단위로 적용되며 텍스트 캐시 identity에 참여한다. 따라서 레이아웃 캐시를 무효화하고
`SlopadEditorUIBenchmarkApp`의 100/1,000/10,000 블록 게이트 재실행을 요구한다.

### D9 — 접근성 투영을 무엇이 cycle-safe하게 만드나

[#94](https://github.com/hot666666/SlopadEditor/issues/94)는 cycle-safe 자동화 표면을 요구하고,
두 번째 상태 소유자·테스트 전용 입력 프록시·canvas와 scroll view의 이중 editable 노출을
배제한다. 블록 단위 의미 투영은 이를 더 어렵게 만들고, 호스트 뷰가 접근성 하위 트리를 소유하는
커스텀 블록이야말로 이전 XCUITest 스냅샷 순환이 나타난 지점이다. 투영의 지연성, 재귀 상한,
1차에서 커스텀 본문을 노출할지 여부를 실험 재개 전에 정한다. 실패 signature 변화 없이 같은
실험을 반복하는 것은 그 이슈의 수용 기준이 이미 배제한다.

**D2 선택이 이 일정에 커플링된다.** D2-A(호스트 `NSView` 서브뷰)를 고르면 그 뷰들이 접근성
트리에 자동으로 올라간다. 그러면 #94는 병행 항목이 아니라 선행 조건이 된다.

### D10 — provider는 어디로 주입되나

ADR 0012는 호스트 표면을 "동기화된 액션 또는 값 관찰"로만 admit한다. provider 집합은 둘 다
아니다 — 초기화 파라미터이거나 뷰 모디파이어다. `SlopadEditorAppKit`과 `SlopadEditorSwiftUI`를
넓히지 않고 어떻게 넣을지 정해야 한다. 컨트롤러 초기화는 이미 호스트 계약("controller
initialization, `resetDocument`")이므로 가장 가까운 자리이지만, `resetDocument`로 문서를 교체할 때
provider 집합이 어떻게 되는지도 같은 결정에 포함된다.

### D11 — payload 예산은 하나인가 셋인가

archive에는 바이트·깊이·멤버 admission 예산이 있지만 클립보드(`EditorClipboardPayload`)와 patch
검증에는 없다. 한 숫자를 셋이 공유하지 않으면 저장은 되는데 복사는 안 되는 문서, 또는 patch로는
들어오는데 저장은 실패하는 문서가 생긴다.

### D12 — Markdown 왕복 비대칭을 어떻게 표현하나

encode는 호스트가 미리 표준 블록으로 변환하면 통과시킬 수 있다. 그러나 decode는 커스텀 블록을
**생산할 수 없다**. 따라서 export → import 왕복은 호스트가 변환하더라도 커스텀 블록을 영구히
잃는다. 커스텀 블록을 가진 문서의 export를 아예 막을지, 변환 후 통과를 허용하고 손실을 UX에서
알릴지 정한다.

## 이슈 분해 제안

D1–D6과 D10–D12가 닫힌 뒤에만 생성하고, Epic #67이 닫힌 뒤에만 착수한다.

| ID | 제목 | owner 레이어 | 의존 | 완료 의미 |
| --- | --- | --- | --- | --- |
| C0 | ADR 0017 승인과 ADR 0012/0013/0015·ROADMAP·ARCHITECTURE 개정 | docs/architecture | D1–D3 | intent 문서와 소스가 일치하고, 계약과 제안을 섞은 문서가 없다 |
| C1 | canonical 커스텀 블록 어휘와 불변식 | `SlopadEditorCoreModel`, `SlopadEditorDocumentModel` | C0, D4 | 9개 switch 지점이 답을 갖고, leaf·텍스트 능력·예산 불변식에 테스트가 있다 |
| C2 | 커스텀 payload 예산을 포함한 Archive V2 | `SlopadEditorArchive` | C1, D5, D11 | 왕복이 identity와 payload를 보존하고, V1/V2 호환 정책이 예산 경계에서 검증된다 |
| C3 | Markdown 미지원 커스텀 진단 | `SlopadEditorMarkdown` | C1, D12 | encode·decode가 `typeID`를 지목하며 fail-closed하고 downstream Markdown fixture가 증명한다 |
| C4 | patch 보존 불변식과 호스트 capability | `SlopadEditorDocumentModel` | C1, D6 | unknown 커스텀 블록이 assistant 왕복에서 살아남고 capability 경로가 양방향으로 커버된다 |
| C5 | 기존 측정 capability를 통한 커스텀 블록 sizing | `SlopadEditorBlockLayout`, 백엔드 | C1, D1 | payload 편집이 기존 캐시 키로 새 높이를 만들고, canonical 프레젠테이션 상태가 없으며, 탈출 경로가 재측정 횟수를 제한한다 |
| C6 | provider 마운트·재활용·히트 라우팅 | `SlopadEditorAppKitUI` | C5, D2, D3, D7, D10 | 커스텀 본문이 보이는 상태에서 스크롤·damage·드래그·선택이 정확하다 |
| C7 | 미지원 placeholder와 보존 fixture | fixtures | C2, C4, C6 | downstream 호스트가 미등록 타입의 편집·이동·복사·저장·재적재 생존을 증명한다 |
| C8 | hover rail과 프레젠테이션 토큰 | `SlopadEditorAppKitUI`, style | D7, D8 | rail 동작이 `SlopadEditorDebugApp`에서 검증되고 벤치마크 게이트가 재실행·기록된다 |
| C9 | 블록 의미 투영과 cycle-safe 자동화 | `SlopadEditorAppKitUI` | C6, D9, #94 | focused AppKit 회귀와 public 호스트 lookup 경로가 있고 스냅샷 순환이 없다 |

## 이 트랙이 무효화하는 검증 게이트

[Testing](TESTING.md)에서 습관이 아니라 변경 표면으로 선택한다.

```sh
swift test --quiet
git diff --check
bash scripts/verify-host-surface.sh
bash scripts/verify-archive-surface.sh
swift package dump-package
```

owner별로 추가: rail·히트 라우팅·포커스·커스텀 본문 상호작용은 `SlopadEditorDebugApp`,
style·측정·마운트 변경은 100/1,000/10,000 블록의 `SlopadEditorUIBenchmarkApp`, 포맷 경계는
각각의 downstream Markdown·archive fixture. 컴파일 증명은 동작 증명이 아니며, 이 중 어느 것도
#94가 요구하는 접근성 증거를 대체하지 않는다.

## 범위 밖

AI 응답 블록 종류, 데이터베이스 행 블록, 날짜/상태 피커 블록, 자식 에디터 블록을 갖는 커스텀
컨테이너, 전역 또는 동적 provider 레지스트리, 포맷 플러그인 레지스트리, 호스트 소유 텍스트
렌더링. 이미지와 테이블은 [#50](https://github.com/hot666666/SlopadEditor/issues/50) 아래
built-in canonical 작업으로 남으며 커스텀 블록 payload가 아니다.
