# config.json — 외부 주입 설정과 민감 정보 취급

## 1. 이 레포에서 말하는 `config.json`

- 배포 사이트(웹 문서 루트 아래 앱 프로젝트)의 `config/config.json`이 **단일 진실 공급원** 역할을 한다.
- Jenkins에서 `build.sh --config /path/to/site.json` 형태로 줄 경우, `config/jsonconfig`가 그 파일을 **기본 경로로 복사**한 뒤 동일 파일을 읽고 일부 필드를 **다시 기록**한다.

**실배포 예시(워크스페이스 기준)**

- `working-copy/AngelNet-DistSite/config/config.json` — Forgejo `AngelNet/AngelNet-DistSite`를 `working-copy/`에 두었을 때의 **실제 스키마 샘플**로 쓸 수 있다.  
  이 문서에는 **값을 적지 않고** 키 구조·주의점만 정리한다.

### 1.1 실예시 기준 최상위 키(이름만)

다음 키가 **한 파일에 동시에** 존재하는 형태다(운영 빌드 + 배포 PHP + 알림이 같은 JSON을 공유).

- **`development` / `production`** — URL·`topPath`·기능 플래그(`usingLogin`, `usingMySQL`, …).
- **`android` / `ios`** — 패키지/스킴, 스토어 타입, **키스토어·난독화 플래그**, Jenkins 워크스페이스 등.
- **`users`** — 역할별(`app`, `qc`, `git` …) **로컬 웹 로그인용** 계정 블록(비밀번호 평문).
- **`mail`** — PHPMailer 스타일 SMTP 블록 + `domesticEnabled` 등(Jenkins의 `USING_MAIL`은 여기 `mail`만 본다).
- **`mail-gmail`** — 일부 배포 `config.json`에 **백업용으로만** 남아 있는 SMTP 모양 블록이 있을 수 있다. **런타임·JenkinsBuild 파이프라인에서는 사용하지 않는다**고 가정하고, **본 문서의 개선 방향(§4)·체크리스트(§5)·스키마 과제에서는 제외**한다.
- **`slack` / `teams` / `discord`** — 채널·`webhook` 등(웹훅 URL 전체가 비밀에 가깝다).
- **`ssh`** — 배포용 SCP 엔드포인트.
- **`jira`** — 프로젝트 키·베이스 URL.
- **`Flutter` / `ReactNative`** — `enabled`, `path`.
- **`custom`** — `enabled`, `executable`(사이트 특화 훅 경로로 추정; 파일 시스템 권한과 함께 민감).
- **`icon`** — `home` 등 에셋 경로.

### 1.2 `test/config.json`과의 차이

양쪽 모두 `mail`, `slack`, `teams`, `discord`, `users` 등 **대부분의 최상위 키는 동일**하다. 실배포 예시에는 `test`에 없는 **사이트·백업 전용 키**가 더 붙을 수 있다(예: 아래 `mail-gmail`).

- **`mail-gmail`**: 파일에만 두는 **백업용 블록**(현재 **미사용**). JenkinsBuild `jsonconfig`는 `.mail`만 다룬다. **프로젝트 개선·리팩터링 문서에서는 이 키를 과제로 다루지 않는다.**

| 구분 | `test/config.json` | AngelNet-DistSite 실예시 |
|------|---------------------|---------------------------|
| 용도 | 레포 내부 스모크·교육용 값 | 실서비스·Jenkins·PHP가 **동일 파일** 공유 |
| 활성 SMTP | `mail` | `mail`(동일). `mail-gmail`은 **백업 보관만** — 개선 범위 제외 |

→ 통합 테스트·실서버 JSON을 오갈 때 **활성 메일 경로는 `mail`만** 보면 된다.

## 2. 민감도가 높은 키(실제 값은 문서에 적지 말 것)

| 영역 | 키(대표) | 위험 |
|------|-----------|------|
| 배포 사이트 로그인 | `users.*.password`, `.email` | 크리덴셜 노출, 로그에 남을 수 있음 |
| 메일 | `mail.*` | 활성 SMTP 자격 증명. (`mail-gmail` 등 **백업용·미사용** 블록은 팀 보관 정책으로만 관리하고, 본 문서 §4 개선 과제에서는 제외) |
| Slack/Teams/Discord | `slack|teams|discord.*webhook` | 웹훅 스팸·데이터 유출 |
| iOS 업로드 | `ios.AppStore.uploadApp.agentAppSpecificPassword` 등 | Apple ID 보조 앱 비밀 |
| iOS 빌드 서버 | `ios.sudoPassword`, `ios.jenkinsUser` | 서버 권한 상승 |
| Android 서명 | `android.keyStorePassword`, `keyStoreAlias`, keystore 파일 경로 | APK 서명 키 유출 |
| SSH 배포 | `ssh.endpoint`, `target`, 포트 | 인프라 내부 경로 노출 + 접속 정보 |
| Git/Jira URL | `gitBrowseUrl`, `jira.url` | 상대적으로 낮으나 내망 정보 |
| 사이트 훅 | `custom.executable` | 임의 명령 경로 노출·변조 |

`config/defaultconfig`는 **저장소에 커밋되는 셸 기본값**이며, 비밀번호·실 Teams 웹훅·내부 배포 URL 등은 넣지 않는다(placeholder 또는 빈 값).  
**실제 값**은 `config/defaultconfig.local`(**gitignore**)에 두고, `config/defaultconfig.local.example`를 복사해 채운다. `build.sh`는 `TOP_DIR`이 잡힌 뒤 `defaultconfig` 안에서 `defaultconfig.local`이 있으면 추가로 `source`한다.

## 3. 현재 구현에서 민감 정보가 새는 지점

1. **`config.json`을 빌드 중 수정** (`config/jsonconfig`의 `jq` + `mv`)  
   - Git으로 관리되는 설정이라면 의도치 않은 diff·커밋·백엔드 노출 시 전체 파일 유출 위험이 커진다.

2. **평문 JSON 한 파일에 모든 계층 혼재**  
   - 배포 웹 서버가 읽는 파일과 Jenkins가 읽는 파일이 같으면, 웹 앱 취약점 시 동시에 털리기 쉽다.

3. **`curl`로 PHP에 폼 인코딩** (`util/sendemail`)  
   - Jenkins 콘솔 로그에 URL·일부 필드가 남을 수 있다(마스킹·secrets 플러그인 필요).

4. **기본값 레이어** (`config/defaultconfig` + 선택 `config/defaultconfig.local`)  
   - 레포의 `defaultconfig`는 비밀 없이 유지하고, 팀·빌더 전용 값은 **gitignore된** `defaultconfig.local`로 분리한다(예시: `defaultconfig.local.example`).

## 4. 개선 방향(권장 순서)

### 4.1 설정 분리(가장 효과 큼)

- **`config.public.json`**: topPath, 스킴 이름, feature flag, **비밀이 없는** URL 골격만.
- **`secrets`**: Jenkins Credentials / macOS Keychain / `source` 가능한 `.env`(gitignore) / SOPS·git-crypt 등.
- 스크립트는 시작 시 `merge(public, secrets)` 결과를 메모리/임시 파일에만 두고, **원본 JSON을 덮어쓰지 않기**.

### 4.2 `jsonconfig` 동작 정책(요약)

- **`config.json` in-place 수정은 기능적으로 필수가 아니다.** Jenkins가 이미 `TOP_PATH`·`WORKSPACE` 등을 환경변수로 넣을 수 있다면, 쉘 변수·오버레이만으로도 동일 빌드를 구성할 수 있다. 현재의 `jq` + `mv`는 **디스크 상의 단일 파일을 Jenkins 값과 맞춰 두려는 편의**에 가깝다(같은 경로의 JSON을 PHP·후속 스크립트·다음 빌드가 읽는다는 전제).
- 대안은 **7절**에 정리한다: **A)** 사이트 옆 `config.runtime.json`(gitignore) + 병합 읽기, **B)** 표준화된 환경변수 오버레이.
- *점진적 목표:* tracked `config.json`을 빌드마다 덮어쓰지 않는 방향으로 옮긴다.

### 4.3 스키마·검증

- JSON Schema 또는 `jq` 기반 체크 스크립트로 **필수 키·타입·enum** 검증.
- CI에서 `test/config.json`을 **금지 키 목록**(실비밀 패턴)으로 스캔.

### 4.4 로그·알림

- 메일/슬랙 전송 전 본문에서 패스워드·웹훅 URL 마스킹.
- Jenkins Pipeline이면 `withCredentials` + `maskPasswords` 사용.

### 4.5 FCM·키스토어 경로

- `fcmconfig`의 `*_src`는 가능하면 **CI 아티팩트 또는 잠긴 볼륨**에서만 읽기.
- Android keystore는 저장소에 넣지 않고 경로만 참조(파일은 Credentials).

## 5. AngelNet-DistSite 실예시를 볼 때 체크할 항목

`working-copy/AngelNet-DistSite/config/config.json` 기준으로 다음을 순서대로 보면 좋다.

- **`DEBUGGING`과 블록 선택**: Jenkins는 `jsonconfig`에서 `.development` vs `.production`만 고른다. PHP·프론트는 동일 파일의 다른 키를 읽을 수 있으므로 **환경 불일치**가 없는지 본다.
- **백업용 `mail-gmail`**: 파일에만 있을 수 있으며 **미사용**이면 개선 문서·스키마 검증 **범위에서 제외**. 활성 SMTP는 `mail`만 점검한다.
- **Jenkins가 건드리는 필드**: `topPath`, `android.jenkinsWorkspace`, `ios.jenkinsWorkspace` 등은 빌드 중 **in-place `jq` 갱신** 대상이다. Git으로 관리되는 동일 파일이면 **의도치 않은 diff**가 생긴다.
- **`users`**: `app` / `qc` / `git` 등 하위 블록이 웹 Basic 인증·로컬 로그인 등에 쓰이면, 이 JSON이 **DocumentRoot 아래에 그대로 있을 때** 서빙/백업 유출 경로를 점검한다.
- **`discord` / `slack` / `teams`**: JenkinsBuild `jsonconfig`는 현재 **Slack·Teams만** 읽는다. `discord`는 **배포 PHP·다른 스크립트 전용**일 수 있으므로, “쉘이 안 읽는다 = 없다”로 착각하지 않는다.
- **iOS `AppStore.uploadApp.*` + `sudoPassword`**: 빌드 에이전트 서버 권한과 Apple 업로드 자격이 한 파일에 있음 → 분리·Credential Store 이전 우선순위가 높다.
- **Android `usingAllatori` / `usingObfuscation`**: 난독화 파이프라인 옵션이 설정 파일에 있으므로, 실수로 `true`가 `development` 빌드에 섞이지 않는지 빌드 매트릭스와 대조한다.

배포 사이트의 `lang/lang_*.json`(또는 `--language`로 지정한 JSON을 `buildenvironment`가 복사·해석)에는 고객 표기용 문자열만 두고, 비밀을 넣지 않는다. JenkinsBuild 레포 루트에 고정 `lang/` 트리가 있는 것은 아니다.

## 6. 참고 파일

- 스키마 느낌의 샘플: `test/config.json`
- **실배포 형태(키만 교차 검증)**: `working-copy/AngelNet-DistSite/config/config.json`(워크스페이스에 해당 클론이 있을 때; 없으면 문서의 키 목록만 기준으로 삼는다)
- 로더·변조 로직: `config/jsonconfig`
- 표시용으로 config에서 ID/PW 읽는 부분: `config/buildenvironment`

## 7. `config/jsonconfig` — in-place `config.json` 수정이 꼭 필요한가?

### 7.1 지금 코드가 디스크에 쓰는 필드

`config/jsonconfig`는 `$jsonConfig`(기본값은 `${APP_ROOT_PREFIX}/${TOP_PATH}/config/config.json`)가 존재할 때, 다음 조건에서만 **원본 파일을 임시 JSON에 쓴 뒤 `mv`로 치환**한다.

| 조건 | 갱신 경로(JSON) |
|------|-----------------|
| `DEBUGGING=1`이고, 파일의 `.development.topPath`가 쉘의 `$TOP_PATH`와 다름 | `.development.topPath` |
| `DEBUGGING≠1`이고, `.production.topPath`가 `$TOP_PATH`와 다름 | `.production.topPath` |
| `$WORKSPACE`가 비어 있지 않고 `INPUT_OS=android`이며 `.android.jenkinsWorkspace`와 다름 | `.android.jenkinsWorkspace` |
| 위와 같고 `INPUT_OS=ios`이며 `.ios.jenkinsWorkspace`와 다름 | `.ios.jenkinsWorkspace` |

`CUSTOM_CONFIG=1`이고 `CUSTOM_CONFIG_PATH`가 지정된 경우, 먼저 해당 파일을 `DEFAULT_CONFIG_JSON`으로 복사한 뒤 같은 파일을 읽는다.

### 7.2 “필수”인가? — **아니다**

- **빌드 논리만 보면** `TOP_PATH`·`WORKSPACE`는 이미 쉘/CI에서 주입 가능하므로, JSON에 다시 써 넣지 않아도 **경로 계산·아티팩트 출력** 자체는 환경변수·내부 변수로 대체할 수 있다.
- **현재 in-place 갱신의 실질 이유**는 (1) 웹·PHP·배포 스크립트가 **같은 `config.json`만** 보고 경로를 맞추길 기대하는 관행, (2) 이후 단계에서 `cat $jsonConfig | jq …`로 **파일을 다시 읽을 때** Jenkins와 파일 내용이 어긋나지 않게 하려는 목적에 가깝다.
- 구현 상 주의: `jsonconfig`는 파일을 고친 뒤 **`config=$(cat $jsonConfig | $JQ '.development' …)`를 다시 실행하지 않는다.** 즉 같은 `source` 구간 안에서 이미 뽑아 둔 `$config`는 **갱신 전 스냅샷**이며, 갱신은 “디스크 동기화” 성격이 강하다.

### 7.3 in-place를 줄이지 않으면 생기는 부담

- Git으로 관리되는 배포 `config.json`이면 **의도치 않은 diff·커밋**, 아티팩트에 올라간 파일 유출 시 **전체 블록 노출** 위험이 커진다(§3.1과 동일).
- DocumentRoot 아래 단일 JSON에 비밀·Jenkins가 덮어쓴 경로가 함께 있으면 공격 면이 넓어진다.

### 7.4 대체 설계안 A — `config.runtime.json`(gitignore) + 병합

**아이디어:** tracked 원본은 손대지 않고, Jenkins(또는 에이전트)만이 쓰는 **얇은 오버레이**에 `topPath`·`jenkinsWorkspace`만 둔다.

- **위치(권장):** 배포 사이트 트리 `config/config.runtime.json`(저장소마다 **gitignore**에 추가). JenkinsBuild 레포에서만 시험할 때는 `test/config.runtime.json` 등 로컬 경로를 쓰고 동 파일은 **이 레포 `.gitignore`에 포함**해 두는 것이 안전하다.
- **병합 규칙:** `jq`에서 객체 `*`는 중첩 객체까지 재귀 병합된다. 오버레이가 없으면 기존과 동일하게 단일 파일만 읽는다.

```bash
# 개념 예: 오버레이가 있을 때만 유효 JSON 하나로 고정
if [ -f "${jsonConfig%/*}/config.runtime.json" ]; then
  effective="$(mktemp ...)"
  jq -s '.[0] * .[1]' "$jsonConfig" "${jsonConfig%/*}/config.runtime.json" > "$effective"
else
  effective="$jsonConfig"
fi
# 이후 모든 jq는 $effective 대상으로 통일(원본 config.json은 불변)
```

- **Jenkins 쪽:** 빌드 시작 시 `config.runtime.json`을 한 번 생성(또는 Credentials/워크스페이스에서 복사)하고, 끝나면 삭제하거나 비워 둔다.
- **장점:** PHP가 여전히 “한 디렉터리의 JSON”만 보도록 맞출 때 **`config.runtime.json`만 배포 정책에서 제외**하기 쉽다.
- **단점:** 로더( `jsonconfig` )가 **모든 읽기 경로**를 병합 결과로 바꿔야 해서 리팩터 범위가 생긴다.

### 7.5 대체 설계안 B — 환경변수 오버레이

**아이디어:** 덮어쓸 값은 **전부 env**로 정하고, JSON은 템플릿/기본값만 유지한다.

| 제안 변수(예시 이름) | 용도 |
|---------------------|------|
| `JB_TOP_PATH` | `$TOP_PATH`와 불일치 시 JSON의 `.development`/`.production`. `topPath` 대신 **항상 이 값을 우선** |
| `JB_ANDROID_JENKINS_WORKSPACE` | `$WORKSPACE` + `android`일 때 `.android.jenkinsWorkspace` 대체 |
| `JB_IOS_JENKINS_WORKSPACE` | `$WORKSPACE` + `ios`일 때 `.ios.jenkinsWorkspace` 대체 |

- **적용 방식:** `jsonconfig` 초반에 `effectiveTopPath="${JB_TOP_PATH:-$TOP_PATH}"`처럼 두고, `jq`로 파일을 고치는 대신 **이후에 `config`에서 파생되는 값만 env를 덮어쓴다**거나, 아예 **`$config` 생성 시 `jq --arg`** 로 메모리 상 JSON만 패치한 뒤 파일은 건드리지 않는 방법도 있다.
- **장점:** Git/배포 JSON 불변, Jenkins **Credentials/EnvInject**와 모델이 맞다.
- **단점:** PHP 등 **다른 소비자가 여전히 디스크의 `topPath`만 본다면** env-only로는 맞지 않으므로, 사이트 쪽도 env 주입·템플릿 렌더로 맞추는 **추가 조율**이 필요할 수 있다.

### 7.6 권장 이행 순서(작은 단계)

1. **관측:** 현재 배포 파이프라인에서 `config.json`의 `topPath`·`jenkinsWorkspace`를 **PHP·cron이 읽는지** 여부를 확인한다. 안 읽는다면 **설계안 B**가 비용 대비 유리할 수 있다.
2. **병행:** `jsonconfig`에 “병합 소스(`effective`)” 변수를 도입해 읽기만 병합 파일로 전환하고, **쓰기(`mv`)는 플래그로 끈다**(예: `JB_JSONCONFIG_WRITE_DISK=0`).
3. **수렴:** 기본값을 “디스크 비갱신”으로 바꾸고, 필요 시에만 레거시 in-place를 허용한다.
