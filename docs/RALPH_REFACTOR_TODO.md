# JenkinsBuild — `ralph.sh`용 리팩터링 TODO (PRD)

워크스페이스의 `scripts/ralph.sh`는 `PRD_PATH` 환경변수로 **임의 마크다운 PRD**를 지정할 수 있다. 이 파일을 그 PRD로 지정하면 체크박스 진행도를 `ralph.sh check`로 볼 수 있다.

```bash
export PRD_PATH="$HOME/.openclaw/workspace/working-copy/JenkinsBuild/docs/RALPH_REFACTOR_TODO.md"
# (선택) export PROGRESS_PATH=.../progress_jenkinsbuild.txt
"$HOME/.openclaw/workspace/scripts/ralph.sh" check
"$HOME/.openclaw/workspace/scripts/ralph.sh" run 30 120
```

**규칙**: 한 번에 **가장 위쪽의 미완료(`- [ ]`) 한 항목**만 처리하고 커밋하는 것이 Ralph 루프와 잘 맞는다.

---

## Phase 0 — 문서·기준선

- [x] `docs/ARCHITECTURE.md`, `docs/CONFIG_AND_SECRETS.md`와 실제 코드 경로를 교차 검증(파일 이동 시 문서 동기화 규칙을 README에 한 줄 추가).
- [x] `test/config.json`을 “샘플만”임을 머리말 주석 또는 `test/README.md`에 명시.
- [x] (선택) 워크스페이스 `working-copy/AngelNet-DistSite/config/config.json`과 `test/config.json`의 **최상위 키 델타**를 분기마다 점검(예: `discord`, `custom`, 사이트 전용 블록). **`mail-gmail`은 백업용·미사용이므로 델타·과제에서 제외.** 문서만 갱신해도 됨; 비밀 값은 금지.

## Phase 1 — 비밀·설정 안전장치(고통 적음, 효과 큼)

- [ ] `config/defaultconfig`에서 실서비스 비밀·URL을 제거하고 placeholder만 남기거나, `defaultconfig.local.example` + gitignore 분리.
- [ ] `config/jsonconfig`: `config.json` in-place 수정이 꼭 필요한지 문서화; 가능하면 환경변수 오버레이 또는 `config.runtime.json`(gitignore)로 대체 설계안 작성.
- [ ] `util/sendemail`: Jenkins 로그에 남을 수 있는 필드 목록 정리 및 마스킹 후보보고.

## Phase 2 — 쉘 공통화·품질

- [ ] `build.sh` vs `dist.sh` shebang/strict mode(`set -u` 등) 정책 통일안 — 무엇을 깨지 않을지 리스트업.
- [ ] `platform/android.sh` / `platform/ios.sh` 공통: 반복되는 `jq cat $jsonConfig` 패턴을 함수(`jb_jq_bool`, `jb_jq_str`)로 추출할지 결정 후 일부만 이동(작은 PR).
- [ ] `shellcheck` 대상 디렉터리와 예외 파일 목록을 정함(`.shellcheckrc` 또는 CI 한 줄).

## Phase 3 — 플러그인 분리 1차 (Allatori / IxShield)

- [ ] `platform/android.sh`의 Allatori 블록을 `plugins/allatori_android.sh`(또는 `hooks/post-config-android.sh`)로 이동하고 `build.sh`에서만 source.
- [ ] `platform/ios.sh`의 IxShield 관련(sed, `IxShieldCheck.sh`, PNG)을 `plugins/ixshield_ios.sh`로 이동; 비활성 시 noop.
- [ ] `test/obfuscation_android.sh`, `test/obfuscation_ios.sh`를 새 플러그인 경로에서 호출하도록 정리.

## Phase 4 — 알림·사이트 특화 분리

- [ ] `util/sendemail`의 PHP URL 조립을 `jsonconfig` 키(예: `notifications.mailEndpoint`)로 빼기 — 하드코딩 `phpmodules/sendmail_domestic.php` 제거.
- [ ] `util/sendslack`, `util/sendteams`: 페이로드 빌더를 `notifications/formatters/` 같은 하위로 분리할지 검토.

## Phase 5 — FCM·SSH

- [ ] `config/fcmconfig`: 드라이런 모드(복사 대상만 echo) 옵션 추가.
- [ ] `config/sshfunctions`: `BatchMode`/타임아웃/known_hosts 정책 문서화; 실패 시 재시도 정책은 별 이슈로 분리.

## Phase 6 — dist 워크플로

- [ ] `dist.sh`가 `grep 'github.com'`으로 remote 고르는 부분 — Forgejo/기타 호스트 선택을 `dist.config` 옵션으로 일반화할지 결정.
- [ ] `docs/dist_comparison.md`에 “Forgejo 원격 사용 시” 절 추가.

## Phase 7 — 장기 구조(선택)

- [ ] JSON Schema for public config + 검증 CLI(`scripts/validate-config.sh`).
- [ ] 단위 테스트 대체: 핵심 순수 함수만 `bash` + bats 또는 Python으로 추출.

---

## 진행 메모(릴리스 노트용)

| 날짜 | 메모 |
|------|------|
| 2026-04-06 | 초안 작성 — 아키텍처/비밀 문서와 연동 |
| 2026-04-07 | Phase 0: DistSite vs `test/config.json` 최상위 키 델타 절차·기준선을 `test/README.md`에 기록 (`mail-gmail` 제외 시 동일 집합) |
