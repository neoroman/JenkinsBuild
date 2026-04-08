# JenkinsBuild — `ralph.sh`용 리팩터링 TODO (PRD)

워크스페이스의 `scripts/ralph.sh`는 `PRD_PATH` 환경변수로 **임의 마크다운 PRD**를 지정할 수 있다. 이 파일을 그 PRD로 지정하면 체크박스 진행도를 `ralph.sh check`로 볼 수 있다.

```bash
export PRD_PATH="$HOME/.openclaw/workspace/working-copy/JenkinsBuild/docs/RALPH_REFACTOR_TODO.md"
# (선택) export PROGRESS_PATH=.../progress_jenkinsbuild.txt
"$HOME/.openclaw/workspace/scripts/ralph.sh" check
"$HOME/.openclaw/workspace/scripts/ralph.sh" run 30 120
```

**규칙**: 한 번에 **가장 위쪽의 미완료 체크박스 한 항목**만 처리하고 커밋하는 것이 Ralph 루프와 잘 맞는다. 워크스페이스 `scripts/ralph.sh`는 **마크다운 코드 펜스 밖**에서 **줄 시작**(선행 공백만 허용)의 GFM 태스크 목록 항목만 집계한다(미완료: 하이픈·공백·`[`·공백·`]` 패턴, 완료: 대괄호 안이 `x`/`X`). `check`와 주입 프롬프트의 미완료 목록은 위 조건으로만 채운다. 표·진행 메모·설명 문장에 체크박스 모양을 넣을 때는 **해당 줄이 하이픈 목록으로 시작하지 않게** 쓰면 오탐이 없고, 실행 예시는 코드 펜스 안에 두는 것을 권장한다.

---

## Phase 0 — 문서·기준선

- [x] `docs/ARCHITECTURE.md`, `docs/CONFIG_AND_SECRETS.md`와 실제 코드 경로를 교차 검증(파일 이동 시 문서 동기화 규칙을 README에 한 줄 추가).
- [x] `test/config.json`을 “샘플만”임을 머리말 주석 또는 `test/README.md`에 명시.
- [x] (선택) 워크스페이스 `working-copy/AngelNet-DistSite/config/config.json`과 `test/config.json`의 **최상위 키 델타**를 분기마다 점검(예: `discord`, `custom`, 사이트 전용 블록). **`mail-gmail`은 백업용·미사용이므로 델타·과제에서 제외.** 문서만 갱신해도 됨; 비밀 값은 금지.

## Phase 1 — 비밀·설정 안전장치(고통 적음, 효과 큼)

- [x] `config/defaultconfig`에서 실서비스 비밀·URL을 제거하고 placeholder만 남기거나, `defaultconfig.local.example` + gitignore 분리.
- [x] `config/jsonconfig`: `config.json` in-place 수정이 꼭 필요한지 문서화; 가능하면 환경변수 오버레이 또는 `config.runtime.json`(gitignore)로 대체 설계안 작성.
- [x] `util/sendemail`: Jenkins 로그에 남을 수 있는 필드 목록 정리 및 마스킹 후보보고.

## Phase 2 — 쉘 공통화·품질

- [x] `build.sh` vs `dist.sh` shebang/strict mode(`set -u` 등) 정책 통일안 — 무엇을 깨지 않을지 리스트업.
- [x] `platform/android.sh` / `platform/ios.sh` 공통: 반복되는 `jq cat $jsonConfig` 패턴을 함수(`jb_jq_bool`, `jb_jq_str`)로 추출할지 결정 후 일부만 이동(작은 PR).
- [x] `shellcheck` 대상 디렉터리와 예외 파일 목록을 정함(`.shellcheckrc` 또는 CI 한 줄).

## Phase 3 — 플러그인 분리 1차 (Allatori / IxShield)

- [x] `platform/android.sh`의 Allatori 블록을 `plugins/allatori_android.sh`(또는 `hooks/post-config-android.sh`)로 이동하고 `build.sh`에서만 source.
- [x] `platform/ios.sh`의 IxShield 관련(sed, `IxShieldCheck.sh`, PNG)을 `plugins/ixshield_ios.sh`로 이동; 비활성 시 noop.
- [x] `test/obfuscation_android.sh`, `test/obfuscation_ios.sh`를 새 플러그인 경로에서 호출하도록 정리.

## Phase 4 — 알림·사이트 특화 분리

- [x] `util/sendemail`의 PHP URL 조립을 `jsonconfig` 키(예: `notifications.mailEndpoint`)로 빼기 — 하드코딩 `phpmodules/sendmail_domestic.php` 제거.
- [x] `util/sendslack`, `util/sendteams`: 페이로드 빌더를 `notifications/formatters/` 같은 하위로 분리할지 검토.

## Phase 5 — FCM·SSH

- [x] `config/fcmconfig`: 드라이런 모드(복사 대상만 echo) 옵션 추가.
- [x] `config/sshfunctions`: `BatchMode`/타임아웃/known_hosts 정책 문서화; 실패 시 재시도 정책은 별 이슈로 분리.

## Phase 6 — dist 워크플로

- [x] `dist.sh`가 `grep 'github.com'`으로 remote 고르는 부분 — Forgejo/기타 호스트 선택을 `dist.config` 옵션으로 일반화할지 결정.
- [x] `docs/dist_comparison.md`에 “Forgejo 원격 사용 시” 절 추가.

## Phase 7 — 장기 구조(선택)

- [x] JSON Schema for public config + 검증 CLI(`scripts/validate-config.sh`).
- [x] 단위 테스트 대체: 핵심 순수 함수만 `bash` + bats 또는 Python으로 추출.

## Phase 8 — 플랫폼 단계 dry-run 검증

- [x] `config/argsparser`에 `--dry-run`, `--dry-run-step` 옵션 추가.
- [x] `platform/{ios,android}.sh`에서 빌드/파일쓰기 핵심 단계를 체크포인트로 분리해 dry-run 출력 제공.
- [x] `build.sh`에서 dry-run 시 플랫폼 점검만 수행하고 `makejson`/알림 루틴은 스킵.
- [x] `docs/DRY_RUN_CHECKLIST.md`에 단위 체크리스트·실행 예시·검증 결과 기록.

---

## 진행 메모(릴리스 노트용)

| 날짜 | 메모 |
|------|------|
| 2026-04-06 | 초안 작성 — 아키텍처/비밀 문서와 연동 |
| 2026-04-07 | Phase 0: DistSite vs `test/config.json` 최상위 키 델타 절차·기준선을 `test/README.md`에 기록 (`mail-gmail` 제외 시 동일 집합) |
| 2026-04-07 | Phase 1: `util/sendemail` 폼 필드·로그 유출 경로·마스킹 우선순위를 `docs/CONFIG_AND_SECRETS.md` §3.1에 정리 |
| 2026-04-07 | Phase 2: `docs/SHELL_STRICT_AND_SHEBANG.md` — `build.sh`/`dist.sh` shebang·`set -e`/`-u`/pipefail 기준선·안전/위험 변경 표 |
| 2026-04-07 | Phase 2: `platform/jb_json_helpers.sh` — `jb_jq_bool`/`jb_jq_str`; Android·iOS 스토어/타깃 설정 블록·난독화 플래그 일부 치환 |
| 2026-04-07 | Phase 2: `.shellcheckrc` + `scripts/run-shellcheck.sh` 명시적 대상·`util/exp` 예외 + `shellcheck.yml` CI(기본 심각도 error); SC2148/SC2070/SC2242 등 소규모 정리 |
| 2026-04-07 | Phase 3: `plugins/obfuscation_android.sh` — Android 난독화 스크린샷을 플러그인으로 이전; `test/obfuscation_*.sh`는 `ixshield_ios`/`obfuscation_android`를 직접 source |
| 2026-04-07 | Phase 4: `notifications.mailEndpoint` → `$MAIL_ENDPOINT`; `util/sendemail`은 하드코딩 경로 제거, `jsonconfig`에서 기본 조립 |
| 2026-04-07 | Phase 4: Slack vs Teams 페이로드 — `notifications/formatters/` 즉시 분리는 보류; 이유·후속은 `docs/ARCHITECTURE.md` §4.1 |
| 2026-04-07 | Phase 5: `config/fcmconfig` — `FCM_DRY_RUN=1` 시 복사 대상(src→dst)만 echo, mkdir/cp 생략 |
| 2026-04-07 | Phase 5: `config/sshfunctions` — 현재 코드는 ssh 옵션 미지정; `BatchMode`/타임아웃/known_hosts 는 CI·`~/.ssh/config` 정책으로 문서화(`CONFIG_AND_SECRETS.md` §8); 재시도는 별 이슈 |
| 2026-04-07 | Phase 6: `dist.config` `[remote]` — `remote.name` 우선, 없으면 `remote.pushUrlMatch`(기본 `github.com`)로 push URL에서 remote 선택; `dist_shlib`의 `dist_resolve_push_remote`; 태그 삭제 push도 동일 remote 사용 |
| 2026-04-07 | Phase 6: `docs/dist_comparison.md` §9 — Forgejo/비 GitHub 원격 시 `[remote]` (`name` vs `pushUrlMatch`), `dist_with_tag.sh`는 `origin` 고정 주의 |
| 2026-04-07 | Phase 7: `schema/public-config.schema.json` + `scripts/validate-config.sh` / `validate_config.py`; CI ShellCheck 워크플로에서 `test/config.json` 검증 |
| 2026-04-07 | Phase 7: `vercomp` → `scripts/pure/jb_vercomp.sh` 추출; `util/versions`는 source; `scripts/test_pure_vercomp.py` + CI 단계 |
| 2026-04-07 | Iter 21: PRD 본문에 미완료 체크박스 **문자열 그대로** 예시를 두면 (단순 grep 시) 오탐할 수 있어 규칙 문장을 정리; 워크스페이스 `scripts/ralph.sh`는 줄 시작 마크다운 체크박스만 집계 |
| 2026-04-07 | Iter 25: PRD 상단 규칙에 `ralph.sh` 집계 방식(코드 펜스 제외·줄 시작 GFM 태스크 목록만) 명시 |
| 2026-04-07 | Iter 30: 규칙·진행 메모에서 태스크 리터럴 제거(서브스트링 검색 오탐 방지); `PRD_PATH`→`ralph.sh check` Completed 20 / Remaining 0 재확인 |
| 2026-04-07 | Iter 31: `--dry-run`/`--dry-run-step` 추가, `platform/jb_dryrun.sh` 도입, iOS/Android 단계 체크포인트 및 `docs/DRY_RUN_CHECKLIST.md` 작성 |

## Phase 9 — 강력 리팩터링 2차 (실행부 분리/검증 강화)

- [x] `platform/android.sh` 실행부를 `android_exec_*` 함수(prepare/build/artifact/cleanup)로 분리하고 각 함수 단위 dry-run 체크포인트를 추가한다.
- [x] `platform/ios.sh` 실행부를 `ios_exec_*` 함수(prepare/xcodebuild/export/sign/cleanup)로 분리하고 각 함수 단위 dry-run 체크포인트를 추가한다.
- [x] 파일 쓰기/삭제 지점을 공통 래퍼(`jb_fs_write`, `jb_fs_copy`, `jb_fs_remove`)로 통일해 dry-run에서 실제 I/O를 차단한다.
- [x] 외부 명령 실행을 공통 래퍼(`jb_exec`)로 통일해 dry-run 시 실행 계획/인자만 출력하도록 한다.
- [x] `docs/DRY_RUN_CHECKLIST.md`에 Android/iOS 함수 단위 테스트 케이스(성공/실패/skip)를 추가하고 실제 실행 결과를 기록한다.
