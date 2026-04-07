# `build.sh` vs `dist.sh` — shebang·strict mode 정책 통일안

이 문서는 **코드를 한꺼번에 바꾸지 않고**, 두 진입 스크립트의 차이와 **안전하게 맞출 수 있는 것·맞추면 깨질 가능성이 큰 것**을 정리한다. (PRD Phase 2 첫 항목 산출물.)

## 1. 현재 상태(기준선)

| 항목 | `build.sh` | `dist.sh` |
|------|------------|-----------|
| Shebang | `#!/bin/sh` | `#!/bin/bash` |
| `set -e` | 없음 | 있음 (`set -eo pipefail`) |
| `set -u` | 없음 | 없음 |
| `pipefail` | 없음 | 있음 |
| 주요 특징 | 다수의 `config/*`·`platform/*`·`util/*`를 **순서대로 source**하는 오케스트레이터 | `function`, 배열, `[[` 등 **Bash 전제**가 명시됨 |

## 2. 이미 “통일”되어 있거나 문서만으로 맞출 수 있는 것(깨지지 않음)

- **역할 구분**: `build.sh` = CI/로컬 빌드 오케스트레이션, `dist.sh` = Git·태그·(옵션) Jenkins 릴리스 헬퍼 — **동일 strict 정책을 강제할 필요는 없음**. 정책은 “각 스크립트가 주장하는 인터프리터와 실제 문법을 일치시키는 방향”이 우선이다.
- **`dist.sh`의 `set -eo pipefail` 유지**: 단일 파일 중심, Bash 명시 — **현행 유지는 안전**하고 이미 파이프 실패를 잡는 이점이 있다.
- **`build.sh`에 즉시 `set -e`/`set -u`를 선언하지 않기**: 아래 3절 이유로 **현재 워킹 트리에서는 “정책상 보류”가 깨뜨리지 않는 선택**이다.
- **runbook·문서에 명시**: “`dist.sh`는 Bash 4+ 권장 / macOS 기본 Bash 3에서도 경량 분기만 쓰면 동작”, “`build.sh`는 상위에서 `TOP_DIR` 등이 비어 있으면 자체 계산” 같은 **실행 전제**만 적어도 운영·온보딩에 도움이 되며 동작을 바꾸지 않는다.

## 3. 맞추면 깨질 수 있는 것(선행 작업 없이 바꾸지 말 것)

### 3.1 `build.sh` 최상단에 `set -e`만 추가

- **위험**: `source`되는 모듈 어디서든 **0이 아닌 종료**가 나오면 전체 빌드가 즉시 중단된다. 의도적 비치명 오류(`grep` 미매치, 선택적 `ssh` 등)는 **명시적 `|| true` / 조건 분기**가 없으면 실패로 바뀐다.
- **선행 작업**: `config/*`, `platform/*`, `util/*` 전 구간에서 실패 허용 구문을 표준화한 뒤 단계적으로 도입.

### 3.2 `build.sh` 최상단에 `set -u` 추가

- **위험**: 옵션 처리·사이트별 블록에 따라 **정의되지 않은 변수**를 참조하는 경로가 있을 수 있다. `defaultconfig` 이전 구간이나 `jsonconfig` 병합 이후에만 의미가 생기는 키도 많다.
- **선행 작업**: `:-` 기본값, 조건부 참조, 필수 키 검증을 파일별로 정리.

### 3.3 `build.sh` shebang을 `#!/bin/sh`로 두고 Bash 전용 문법 유지

- **사실**: 본문에 **`[[ ... ]]`**, **`source`**(POSIX에서는 선택적) 등이 있어 **엄밀한 POSIX `sh`만으로는 보장되지 않는다**. macOS에서 `/bin/sh`가 Bash인 환경에서는 우연히 동작할 수 있으나, **Alpine `ash`/Debian `dash`** 등에서는 깨질 수 있다.
- **향후 정책 후보**: (1) 실제로 Bash에 고정하고 shebang을 `#!/usr/bin/env bash`로 바꾸거나, (2) `[[`/`source`를 `[` / `.`로 치환해 **진짜 POSIX sh**로 만든다. 둘 다 **별도 PR**에서 기계적 변환 + 스모크 테스트가 필요하다.

### 3.4 `dist.sh`에 `set -u` 추가

- **위험**: 옵션 조합에 따라 사용하지 않는 변수(`JENKINS_*`, `CONFIG_FILE` 등)를 일부 분기에서만 설정하는 패턴이면 **의도치 않은 종료**가 난다.
- **선행 작업**: `util/dist_shlib`·`dist.sh` 본체에서 **모든 읽는 변수에 기본값**을 두거나, `set -u` 적용 범위를 함수 내부로 한정.

## 4. 권장 통일안(실행 우선순위)

1. **단기(문서·리뷰만)**: 이 파일과 `docs/ARCHITECTURE.md` 상호 링크로 “두 진입점의 strict 차이는 의도적”을 명시한다. ✓ 현재 단계.
2. **중기**: PRD 후속 항목(`shellcheck` 범위)과 함께, **`dist.sh` 트리**부터 미사용 변수·따옴표를 정리한 뒤 `set -u` **후보**를 검토한다.
3. **중기~장기**: `build.sh`는 **shebang ↔ 실제 문법**을 맞추는 PR을 먼저 적용한 다음, 모듈 단위로 `set -e`에 안전한 구간(예: 순수 유틸 함수)부터 좁혀 나간다.

## 5. 요약 표 — “지금 해도 되는가?”

| 변경 | 지금 해도 안전한가 | 비고 |
|------|-------------------|------|
| `dist.sh` `set -eo pipefail` 유지 | 예 | 현행 유지 |
| `build.sh`에 `set -e`/`set -u` 즉시 추가 | **아니오** | source 그래프 전수 점검 후 |
| `build.sh` shebang만 `bash`로 변경 + 본문 유지 | 조건부 | **의존 환경이 Bash인 경우** 명확해짐; CI 이미지 확인 필요 |
| `build.sh`를 진짜 POSIX sh로 정돈 | 별도 프로젝트 | 대규모 치환 + 테스트 |
| 문서화(본 파일) | 예 | 동작 변경 없음 |

## 6. ShellCheck 범위(대상·예외·CI)

- **설정**: 루트 `.shellcheckrc` — `external-sources`, `source-path=SCRIPTDIR`(소스된 파일 경고 완화).
- **대상 파일**: `scripts/run-shellcheck.sh` 안의 `files=(...)` 배열이 단일 기준이다 — 루트 `build.sh`, `dist.sh`, `config/*` 스크립트(예: `jsonconfig`), `util/`의 슬랙·메일·경로 유틸·`versions`·`dist_shlib`, `platform/*.sh`, `test/**/*.sh`.
- **예외**: `util/exp`는 **Expect**라 ShellCheck 대상에서 제외한다.
- **심각도**: 기본 **`error`**만 CI에서 막는다(레거시 **warning** 수백 건은 후속 정리). 로컬에서 전부 보려면 `SHELLCHECK_SEVERITY=warning ./scripts/run-shellcheck.sh`.
- **CI**: `.github/workflows/shellcheck.yml` — `ubuntu-latest` + `apt install shellcheck` 후 위 스크립트 실행.

---

*관련: `docs/ARCHITECTURE.md`(실행 흐름), `docs/RALPH_REFACTOR_TODO.md`(Phase 2).*
