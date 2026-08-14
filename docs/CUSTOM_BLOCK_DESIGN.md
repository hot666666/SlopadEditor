# 호스트 정의 커스텀 블록 — 설계와 작업 계획

## 이 문서의 지위

구현 이전 계획이다. **이 문서의 어떤 절도 계약이 아니다.** 오늘의 동작은 현재 소스와 테스트가
정의하고, 경계는 [Architecture](ARCHITECTURE.md)와 승인된 [ADR](../ADR/README.md)이 정의한다.
여기서 이름 붙인 타입은 아직 존재하지 않는다.

계약 후보는 [ADR 0017](../ADR/0017-host-custom-block-boundary.md)이다. 이 문서는 그 ADR이
결정하지 않는 구현 선택과 작업 순서를 담는다.

## 일정과 [Epic #67](https://github.com/hot666666/SlopadEditor/issues/67)의 관계

**이 트랙은 Epic #67에 의존하지 않는다.** 그 Epic의 하위 작업도 아니다. 미완 항목을 하나씩
확인한 결과는 이렇다.

| #67 미완 항목 | P7이 필요로 하나 |
| --- | --- |
| #74 Markdown import/export UX | 아니다. C3은 코덱이 타입 있는 진단을 내면 되고 호스트 UX가 필요 없다 |
| #71 한국어 두벌식 delivery | 아니다. 커스텀 블록은 비텍스트 leaf라 composition이 진입하지 않는다 |
| #76 live cross-block composition | 아니다. 같은 이유 |
| #70 cross-block 시각 증거 | 아니다 |

게다가 #67의 임계 경로는 코드가 아니라 **사람이 만들어야 하는 증거**다. #71은 물리 키보드로
설치된 입력기를 실제로 돌린 기록을 요구하고(`docs/TESTING.md`가 합성 키 결과의 불충분함을
명시한다), #76은 #70/#71 없이 완료를 주장할 수 없다. P7을 그 뒤로 미루면 코드가 아닌 이유로
무기한 대기하게 된다.

따라서 P7을 먼저 진행하고 #67은 증거가 확보되는 대로 병행한다. 남는 제약은 `AGENTS.md`의 한 번에
한 writer 원칙뿐이며, 실제로 겹치는 지점은 하나다.

| 단위 | 충돌 | 판단 |
| --- | --- | --- |
| C0 문서·ADR | 없음 | 즉시 |
| #94 접근성 | Epic #67 밖의 독립 이슈 | 즉시. P11의 선행 조건이므로 먼저 |
| C1–C5 | #76이 model transaction과 history를 만지지만 커스텀 블록은 그 경로에 들어가지 않는다. 남는 것은 rebase 마찰 | 진행 |
| **C6 마운트·히트** | `AppKitEditorViewController` 입력 경로를 #71/#76과 공유한다. 1,600줄짜리 hot spot이다 | **둘 중 진행 중인 쪽과 순서를 잡는다** |

C6만 순서를 잡으면 나머지는 병행할 수 있다. 트랙 전체를 직렬화할 이유가 없다.

## 한 줄 요약

에디터는 **입력·블록 관리·자기 렌더링**까지 책임진다. 호스트는 **뷰와 그 의미**를 넘긴다.
에디터는 그 뷰를 캔버스 안 정해진 자리에 놓고 잘라내고 스크롤시키지만, 그 안을 절대 그리지
않고 그 payload를 절대 해석하지 않는다.

## 확정된 설계

| 항목 | 결정 | 이유 |
| --- | --- | --- |
| 높이 | 호스트가 `(payload, version, width, depth) -> height` **순수 함수**를 제공한다. 뷰가 높이를 정하지 않고, 에디터가 정한 높이에 뷰를 맞춘다 | `BlockMeasuring`은 `Sendable`·동기이고 출하된 백엔드는 락으로 보호된 컨텍스트로 이를 만족한다. 이 통로로는 살아 있는 `NSView`에 크기를 물을 수 없다 |
| 렌더 | 호스트가 뷰를 만들어 넘기고, **에디터가 캔버스(documentView) 안에 마운트**한다. 위치·클리핑·스크롤·순서는 에디터, 내용·수명은 호스트 | 캔버스가 곧 documentView이므로 스크롤과 클리핑이 공짜다. 호스트가 바깥에서 배치하면 관성 스크롤에서 본문이 텍스트와 어긋난다 |
| 키보드 | 호스트 본문은 first responder를 **절대** 받지 않는다 | 캔버스가 `NSTextInputClient`다. 넘기는 순간 IME·캐럿·선택에 두 번째 입력 주인이 생긴다 |
| 포인터 | 호스트 본문이 클릭을 **소비한다** | 출하된 todo 체크박스가 이미 증거다. 클릭은 first responder와 무관하다 |
| 히트 우선순위 | 훅 없이 **기하로** 해결한다. rail·드래그 핸들은 `x < gutterWidth`, 호스트 본문은 `x >= gutterWidth` | 히트 라우팅이 이미 순수 기하다(`Controller:1580-1583`). 서로 겹치지 않으면 정책 훅이 필요 없다 |
| 선택 표시 | 에디터가 배경과 테두리를 계속 그린다. 호스트에게는 `blockFrame`이 아니라 **안쪽 rect**를 준다 | 선택·드래그는 에디터 의미다. 호스트가 흉내 내면 두 번째 소유자가 생긴다. 현재 테두리는 1pt 안쪽에 그려진다(`AppKitBlockChromeRenderer.swift:88-98`) |
| 접근성 | 커스텀 본문의 접근성은 **호스트 소유**. 에디터는 건드리지 않는다. 단 [#94](https://github.com/hot666666/SlopadEditor/issues/94)가 **선행 조건**이다 | 뷰를 캔버스 하위에 넣으면 접근성 트리에 자동으로 올라간다. #91이 캔버스에서 걷어낸 모양이 다른 경로로 되살아날 수 있다 |

## 구현 선택 — 기본값

아래는 소유자 승인 없이 되돌릴 수 있는 수준의 선택이며, 구현자가 더 나은 근거를 찾으면 바꾸되
문서를 먼저 고친다.

**payload는 `BlockKind`가 든다.** `case custom(typeID: String, version: Int, payload: Data)`.
측정 캐시 키가 `blockID + text + kind + marks + width + depth`이므로, payload가 `kind` 안에 있으면
편집 시 무효화가 구조적으로 보장된다. 다른 곳에 두면 낡은 높이가 반환된다. `codeBlock(language:)`,
`orderedListItem(restartNumber:)`가 이미 같은 형태다.

**archive는 V2로 올린다.** 커스텀 블록이 없는 문서는 계속 V1로 인코딩해 기존 파일이 읽히게 한다.
V1 리더가 V2 문서를 거부하는 현행 fail-closed 동작은 유지한다.

**payload 예산은 하나의 상수를 공유한다.** archive·클립보드·patch 검증이 같은 블록당 상한을 쓴다.
셋이 다르면 저장은 되는데 복사가 안 되는 문서가 생긴다.

**patch 보존 비교 키는 `id + typeID + version + payload 바이트`다.** 이 넷이 patch 전후로 모두
살아 있어야 하며, capability 없이는 삭제·재타이핑·재버전·payload 재작성이 거부된다. capability는
커스텀 블록 변경 전용이며 일반 검증 우회 플래그가 아니다.

**위치와 부모는 비교하지 않는다.** 초안은 순서 변경까지 거부하려 했으나, 그러면 문단을
재배치하는 평범한 assistant patch가 거의 전부 거부된다. 호스트는 결국 capability를 상시 켜게 되고
불변식은 무력화된다. 막아야 할 것은 조용한 소실이지 이동이 아니다 — 이동한 블록은 `BlockID`로
다시 찾을 수 있지만 삭제된 블록은 돌아오지 않는다.

**provider는 컨트롤러 초기화 시 주입하고 `resetDocument`를 넘어 유지한다.** SwiftUI는 뷰 모디파이어로
같은 값을 전달한다. 전역 레지스트리는 없다.

**Markdown은 export를 막는다.** 커스텀 블록이 있으면 `typeID`를 지목하며 fail-closed. 호스트가
코덱 밖에서 미리 표준 블록으로 변환해야 한다. decode는 커스텀 블록을 생산할 수 없으므로 왕복은
비대칭이다.

**`BlockHitRegion.dragHandle`을 실제로 생성한다.** 현재 `handleMouseDown`은 `.gutter`와 `.body`만
만들고 `.dragHandle`은 switch에만 있고 도달하지 않는다. hover rail이 이 경로를 살린다.

## 테마 — 무엇이 이미 되고 무엇이 없나

호스트가 자기 뷰를 그리므로 그 뷰가 에디터와 어울리는지가 문제가 된다. 현재 상태는 이렇다.

**다크 모드는 이미 된다.** 에디터의 색은 `AppKitBlockChromeRenderer`가 시스템 시맨틱 컬러로
그린다(`.controlAccentColor`, `.selectedContentBackgroundColor`, `.separatorColor`,
`.secondaryLabelColor`). OS 외형을 따라간다. 호스트 뷰도 `NSView`이므로 `effectiveAppearance`를
그대로 받는다. 새로 할 일이 없다.

**폰트와 기하 테마는 있다.** `AppKitEditorStyle`이 폰트 이름·크기·행간·gutter 폭·좌우 여백·들여쓰기
폭을 담고, `updateEditorStyle(_:)`과 `editorStyle` 읽기가 모두 public이다. 호스트는 이 값을 읽어
자기 뷰의 폰트를 에디터 본문과 맞출 수 있다.

**스타일이 바뀌면 재측정은 자동이다.** `updateEditorStyle(_:)`은 텍스트 백엔드를 교체하고, 그
교체가 `advanceTextLayoutRevision()`을 거쳐 측정 캐시를 통째로 비운다. 호스트의 sizing 함수도 다시
불린다. 커스텀 블록을 위해 새로 만들 장치가 없다.

**색 테마는 없다.** `AppKitEditorStyle`에 색 필드가 하나도 없고, 색은 chrome 렌더러에 상수로 박혀
있다. 호스트가 브랜드 색을 지정할 계약이 없다는 뜻이다.

이 빈칸은 P7을 막지 않는다. 호스트 뷰는 자기 색을 자기가 정하고, 에디터가 그리는 선택 표시는
시스템 색이라 어느 외형에서도 읽힌다. 다만 **P8(Notion 프레젠테이션)의 전제조건이다** — "callout과
code block이 자체 배경을 갖는다" 같은 목표는 색 토큰 없이 표현할 수 없다. 색 토큰을 도입한다면
그것은 P8의 첫 단계이지 커스텀 블록 작업의 일부가 아니다.

## 앱이 자기 코드를 테스트하려면 에디터가 내놔야 하는 것

경계는 이렇다. 에디터는 **에디터 계약이 성립함**을 증명하고, 앱은 **자기가 그 계약을 옳게 씀**을
증명한다. 에디터는 앱의 payload가 무엇인지 설계상 모르므로 뒤쪽을 대신할 수 없다.

텍스트 영역은 이미 충분하다 — `documentSnapshot`, `perform(_:)`, `commitActiveComposition()`,
`onUpdate`/`onSnapshotChanged`, `configureEditorAccessibility`로 앱이 내부를 뒤지지 않고 단언할 수 있다.

커스텀 블록 때문에 새로 필요한 것은 다섯이다.

1. **`snapshot.blocks`에서 커스텀 블록을 식별하고 payload를 읽는 public 표현.** 앱이 "내 블록이
   문서에 들어갔고 payload가 이것"을 단언할 수 있어야 한다.
2. **provider의 명시적 생명주기 — 뷰 요청 / 재활용 / 해제.** 뷰 요청은 앱이 자기 factory에서 알 수
   있지만, 화면에서 벗어났을 때의 정리는 해제 콜백이 있어야 확인된다.
3. **provider 없이 payload만 주입하는 경로.** 미등록 타입 보존을 앱이 직접 저장→재적재로 검증한다.
4. **블록 단위 접근성 식별.** 앱의 XCUITest가 특정 커스텀 블록을 찾을 수 있어야 한다. #94의 범위다.
5. **마운트 완료의 결정적 신호.** 뷰 마운트가 스냅샷 발행과 같은 틱에 끝나야 앱 테스트가 flaky하지
   않다.

provider를 전역이 아니라 인스턴스마다 주입하기로 한 결정이 여기서 값을 한다. 앱 테스트가 스텁
provider를 꽂아 "에디터가 내 provider를 이 순서로 불렀나"를 단언할 수 있다.

## 검증 계층별로 무엇이 늘어나나

이 저장소에는 검증 계층이 여섯 개 있고 각각 증명하는 것이 다르다. 새 계층을 만드는 것이 아니라
기존 여섯에 한 칸씩 채운다.

| 계층 | 무엇 | 성격 |
| --- | --- | --- |
| L1 `swift test` | 커스텀 블록 불변식, patch 보존, 측정 캐시 무효화 | 기존 확장 |
| L2 네이티브 콜백 스모크 | 커스텀 본문 위에서 시작한 드래그가 에디터 드래그로 새지 않는지 | 기존 확장 |
| L3 `verify-host-surface.sh` | **호스트가 뷰를 넘기는 fixture.** 미등록 타입이 편집·이동·복사·저장·재적재를 살아남는지 | **새로 필요** |
| L4 `verify-archive-surface.sh` | Archive V2 왕복과 payload 예산 경계 | 기존 확장 |
| L5 DebugApp | 스크롤 중 본문이 텍스트와 어긋나지 않는지 | **육안 확인만 가능** |
| L6 벤치마크 앱 | 커스텀 블록 N개일 때 스크롤 프레임타임 | 기존 확장 |

XCUITest 계층은 이 저장소에 없다. #94의 크래시가 downstream 앱에서 발견된 이유이며, 커스텀 본문을
캔버스 안에 넣기로 한 이상 그 빈칸을 먼저 채워야 한다.

## 작업 순서

```
선행   #94  블록 단위 접근성과 cycle-safe 자동화 계약
        └─ P11이 캔버스 접근성 트리를 건드리므로 먼저 닫는다

C0  ADR 0017 승인 + ADR 0013/0015 개정, ADR 0012 재검토, ROADMAP·ARCHITECTURE 갱신
     │
     ├─ C1  canonical 어휘와 불변식        (CoreModel, DocumentModel)
     │       ├─ C2  Archive V2와 예산       (Archive)
     │       ├─ C3  Markdown 진단           (Markdown)
     │       ├─ C4  patch 보존 불변식       (DocumentModel)
     │       └─ C5  순수 sizing 함수 배선   (BlockLayout, 백엔드)
     │             └─ C6  마운트·재활용·히트 라우팅  (AppKitUI)
     │                   └─ C7  미등록 타입 보존 fixture  (Fixtures)
     │
     └─ C8  provider 주입 지점과 SwiftUI 경로  (AppKit, SwiftUI 파사드)

별도 트랙  P  hover rail과 Notion 프레젠테이션
            └─ 커스텀 블록과 독립. 출하된 기본 chrome을 바꾸고
               P2 히트 우선순위 결정을 재개하므로 따로 판단한다
```

프레젠테이션을 떼어낸 이유: 목표 화면은 상시 gutter 구분선 없음과 콘텐츠 인라인 체크박스인데,
출하된 기본 chrome은 구분선을 항상 그리고(`AppKitBlockChromeRenderer.swift:113-119`) 체크박스를
gutter 중앙에 놓는다(`AppKitTodoCheckboxControl.swift:16-29`). 체크박스를 콘텐츠 lane으로 옮기면
P2가 확정한 히트 우선순위 규칙의 기하 전제가 무너진다 — 경쟁 상대가 gutter가 아니라 텍스트가 된다.
이는 새 기능이 아니라 완료된 결정의 재개이므로 커스텀 블록을 막지 않게 분리한다.

## 검증 게이트

```sh
swift test --quiet
git diff --check
bash scripts/verify-host-surface.sh
bash scripts/verify-archive-surface.sh
swift package dump-package
```

owner별 추가: 마운트·히트·포커스는 `SlopadEditorDebugApp`, 측정·style·마운트 성능은 100/1,000/10,000
블록의 `SlopadEditorUIBenchmarkApp`, 포맷 경계는 각각의 downstream fixture. 컴파일 증명은 동작
증명이 아니며, 어느 것도 #94가 요구하는 접근성 증거를 대체하지 않는다.

## 범위 밖

AI 응답 블록 종류, 데이터베이스 행 블록, 날짜/상태 피커 블록, 자식 에디터 블록을 갖는 커스텀
컨테이너, 전역·동적 provider 레지스트리, 포맷 플러그인 레지스트리, 호스트 소유 텍스트 렌더링.
이미지와 테이블은 [#50](https://github.com/hot666666/SlopadEditor/issues/50) 아래 built-in canonical
작업으로 남으며 커스텀 블록 payload가 아니다.
