# TermPet — 작업 규칙 요약

전체 명세는 `SPEC.md` 참고. 이 파일은 매 작업 시 지켜야 할 규칙만 요약한다.

## 진행 방식
- **Phase 단위로 진행.** Phase 시작 전 세부 작업 목록을 먼저 보여주고, 끝나면 빌드 통과 확인 → 사용자 확인용 체크리스트 제시 → **멈추고 피드백 대기.**
- Phase 완료 시 git commit: `phase-N: 요약`

## 빌드
- `.xcodeproj`는 직접 편집 금지. **`project.yml`(XcodeGen)** 만 수정하고, 파일 추가/삭제 시 `xcodegen generate` 재실행.
- 매 Phase 끝에 빌드 통과 필수 (경고 최소화):
  ```
  xcodebuild -project TermPet.xcodeproj -scheme TermPet -configuration Debug build
  ```
- 개발 실행: `Scripts/run.sh` (로그 보기: `--logs`, 프로젝트 재생성: `--gen`)
- 설치/업데이트: `Scripts/install.sh` (Release 빌드 → /Applications)
- 아이콘 재생성: `swift Scripts/make-icons.swift`
- 배포(Homebrew): `Scripts/release.sh <버전>` → GitHub Release + `Casks/termpet.rb` 갱신
- 테스트: `xcodebuild -project TermPet.xcodeproj -scheme TermPet test`

## 코드 원칙
- 로직(상태 머신, 이벤트 파싱, 트랜스크립트 파싱, 설정 병합)은 UI와 분리하고 **XCTest 단위 테스트** 작성.
- 사용자는 React+TS 개발자, Swift 초보 → 새 Swift/AppKit 개념은 **React/TS 비유로 1~2줄 주석**.
  (예: `@State` ≈ `useState`, `@Observable` 클래스 ≈ Zustand 스토어)
- Swift 언어 모드: 5 (Swift 6 strict concurrency 경고 과다 회피)
- 메뉴바 앱(`LSUIElement`), App Sandbox OFF, Hardened Runtime ON, macOS 14+

## 외부 연동
- Claude Code 훅 / Codex notify 형식은 **현재 공식 문서 확인 후** 구현. 불확실하면 방어적 파싱(필드 누락 허용) + TODO.
- 사용자 설정 파일(`~/.claude/settings.json`, `~/.zshrc`, `~/.codex/config.toml`) 수정 시 **백업 후 병합**, 절대 덮어쓰지 않음. 자동 수정은 설정 화면 버튼 클릭 시에만.
- 훅 스크립트는 앱이 꺼져 있어도 CLI/쉘을 절대 느리게 하거나 에러 내지 않음 (`curl --max-time 1`, 백그라운드, `jq` 비의존).
