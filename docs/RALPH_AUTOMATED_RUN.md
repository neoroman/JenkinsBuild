# JenkinsBuild — Ralph 자동 루프 (리팩터 PRD)

워크스페이스의 `scripts/ralph.sh`를 `PRD_PATH`=`docs/RALPH_REFACTOR_TODO.md`로 묶어 **장시간 반복 실행**하기 위한 설정이다.

## 무엇을 하느냐

- **PRD**: `docs/RALPH_REFACTOR_TODO.md` (체크박스 TODO; `ARCHITECTURE.md` / `CONFIG_AND_SECRETS.md`와 정합)
- **한 iteration**: 로컬 Cursor/OpenAI 호환 API(`scripts/ralph.sh` 기본: cursor_bridge)에 PRD 요약 + 미완료 `- [ ]` 목록을 넣어 **“가장 위 미완료 한 항목”** 수준의 가이드를 한 번 받는다.
- **코드/문서 자동 적용은 없음** — 응답을 보고 사람이나 다른 에이전트가 저장소에 반영한다. (`ralph.sh` 주석과 동일)
- **진행 로그**: `docs/ralph_refactor_progress.log` (각 줄: 시각, iteration, 응답 첫 줄 요약). 저장소의 `*.log`는 `.gitignore`이므로 **커밋되지 않는다**.

## 래퍼 스크립트

경로(독립 실행):

```bash
"$HOME/.openclaw/workspace/scripts/ralph-jenkinsbuild-refactor.sh" [MAX] [SLEEP_SEC]
```

- 기본값: **MAX=100**, **SLEEP_SEC=300** (5분 간격).
- 환경 변수로 경로 덮어쓰기 가능: `OPENCLAW_WS`, `PRD_PATH`, `PROGRESS_PATH`, `TASKS_JSON_PATH`.
- API 키: `CURSOR_API_KEY` 또는 `OPENAI_API_KEY` — 미설정 시 `~/.openclaw/models/cursor_bridge/.env/cursor_bridge.env` 로드 (`ralph.sh`와 동일).

### 백그라운드 예시 (약 8.3시간)

```bash
nohup env OPENCLAW_WS="$HOME/.openclaw/workspace" \
  bash "$HOME/.openclaw/workspace/scripts/ralph-jenkinsbuild-refactor.sh" 100 300 \
  >> /tmp/jenkinsbuild-ralph-runner.log 2>&1 &
```

- 러너 표준 출력/에러: `/tmp/jenkinsbuild-ralph-runner.log`
- PRD 진행 한 줄 요약: `tail -f working-copy/JenkinsBuild/docs/ralph_refactor_progress.log` (워크스페이스 기준 상대 경로)

### 수동 진행도 확인

```bash
export PRD_PATH="$HOME/.openclaw/workspace/working-copy/JenkinsBuild/docs/RALPH_REFACTOR_TODO.md"
export PROGRESS_PATH="$HOME/.openclaw/workspace/working-copy/JenkinsBuild/docs/ralph_refactor_progress.log"
"$HOME/.openclaw/workspace/scripts/ralph.sh" check
```

## Git·문서 정책 (본 자동화에 대한 사용자 지시 요약)

- **커밋/푸시**: 이 루프가 돌아가는 동안 **리팩터링 관련 변경은 `working-copy/JenkinsBuild` 저장소에서만** `git add` / `commit` / `push` 한다.
- **메타 문서**: 운영·정책 설명은 본 파일처럼 **`JenkinsBuild/docs/`** 에 둔다.
- **장기 MEMORY.md**: 사용자 요청에 따라 이 작업을 **`MEMORY.md`에 남기지 않는다** (워크스페이스 에이전트 규칙과 별개로, 본 루프 메타는 이 문서와 로그로만 추적).

## 선택: 에이전트에 추가 지시

`scripts/ralph.sh`는 `RALPH_EXTRA_INSTRUCTION` 환경변수를 iteration 프롬프트에 합친다. 예:

```bash
export RALPH_EXTRA_INSTRUCTION='Always cite ARCHITECTURE.md § numbers when proposing file moves.'
bash "$HOME/.openclaw/workspace/scripts/ralph-jenkinsbuild-refactor.sh" 10 60
```

## 관련 문서

- `docs/RALPH_REFACTOR_TODO.md` — PRD 본문
- `docs/ARCHITECTURE.md`, `docs/CONFIG_AND_SECRETS.md` — 분석 기준
- 워크스페이스: `docs/openclaw_settings/ralph-loop-and-token-reduction.md` — Ralph 루프 개념
