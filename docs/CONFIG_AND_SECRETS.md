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
- **`mail-gmail`** — 동일 모양의 **보조 SMTP 프로필**(실예시에만 있음; JenkinsBuild 쉘은 참조하지 않을 수 있음 → PHP/사이트 전용 가능성).
- **`slack` / `teams` / `discord`** — 채널·`webhook` 등(웹훅 URL 전체가 비밀에 가깝다).
- **`ssh`** — 배포용 SCP 엔드포인트.
- **`jira`** — 프로젝트 키·베이스 URL.
- **`Flutter` / `ReactNative`** — `enabled`, `path`.
- **`custom`** — `enabled`, `executable`(사이트 특화 훅 경로로 추정; 파일 시스템 권한과 함께 민감).
- **`icon`** — `home` 등 에셋 경로.

### 1.2 `test/config.json`과의 차이

양쪽 모두 `mail`, `slack`, `teams`, `discord`, `users` 등 **대부분의 최상위 키는 동일**하다. 실배포 예시에서 눈에 띄는 점은 다음뿐이다.

- **`mail-gmail`**: `test/config.json`에는 없고, AngelNet-DistSite 실예시에만 있는 **두 번째 SMTP 블록**(구조는 `mail`과 동형). JenkinsBuild `jsonconfig`는 `.mail`만 읽으므로, 이 키는 **PHP/사이트 쪽 전용**일 가능성이 크다 — 그럼에도 **같은 파일에 평문 자격 증명이 두 벌** 있는 상태라 분리·Credential 이전 대상으로 본다.

| 구분 | `test/config.json` | AngelNet-DistSite 실예시 |
|------|---------------------|---------------------------|
| 용도 | 레포 내부 스모크·교육용 값 | 실서비스·Jenkins·PHP가 **동일 파일** 공유 |
| SMTP | `mail` 단일 | `mail` + **`mail-gmail`** |

→ 통합 테스트용 JSON을 실서버에서 그대로 쓰거나 반대로 복사할 때 **`mail-gmail` 유무**로 동작이 달라지지 않는지(메일 발송 경로) 확인한다. 장기적으로는 Phase 7의 **스키마·허용 키 검증**에 `mail-gmail` 포함 여부를 명시하는 것이 좋다.

## 2. 민감도가 높은 키(실제 값은 문서에 적지 말 것)

| 영역 | 키(대표) | 위험 |
|------|-----------|------|
| 배포 사이트 로그인 | `users.*.password`, `.email` | 크리덴셜 노출, 로그에 남을 수 있음 |
| 메일 | `mail.*`, **`mail-gmail.*`**(실예시) | SMTP 자격 증명 이중 보관 → 회전·폐기 시 한쪽만 바꾸는 실수 |
| Slack/Teams/Discord | `slack|teams|discord.*webhook` | 웹훅 스팸·데이터 유출 |
| iOS 업로드 | `ios.AppStore.uploadApp.agentAppSpecificPassword` 등 | Apple ID 보조 앱 비밀 |
| iOS 빌드 서버 | `ios.sudoPassword`, `ios.jenkinsUser` | 서버 권한 상승 |
| Android 서명 | `android.keyStorePassword`, `keyStoreAlias`, keystore 파일 경로 | APK 서명 키 유출 |
| SSH 배포 | `ssh.endpoint`, `target`, 포트 | 인프라 내부 경로 노출 + 접속 정보 |
| Git/Jira URL | `gitBrowseUrl`, `jira.url` | 상대적으로 낮으나 내망 정보 |
| 사이트 훅 | `custom.executable` | 임의 명령 경로 노출·변조 |

또한 `config/defaultconfig`에는 **placeholder 수준을 넘는 기본값**(예: `sudoPassword`, Teams URL)이 들어 있을 수 있어, **레포에 실비밀이 섞이지 않도록** 운영 절차가 필요하다.

## 3. 현재 구현에서 민감 정보가 새는 지점

1. **`config.json`을 빌드 중 수정** (`config/jsonconfig`의 `jq` + `mv`)  
   - Git으로 관리되는 설정이라면 의도치 않은 diff·커밋·백엔드 노출 시 전체 파일 유출 위험이 커진다.

2. **평문 JSON 한 파일에 모든 계층 혼재**  
   - 배포 웹 서버가 읽는 파일과 Jenkins가 읽는 파일이 같으면, 웹 앱 취약점 시 동시에 털리기 쉽다.

3. **`curl`로 PHP에 폼 인코딩** (`util/sendemail`)  
   - Jenkins 콘솔 로그에 URL·일부 필드가 남을 수 있다(마스킹·secrets 플러그인 필요).

4. **기본값 레이어** (`config/defaultconfig`)  
   - “동작 예시”와 “실제 팀 기본값”이 구분되지 않으면 git 히스토리에 비밀이 박힘.

## 4. 개선 방향(권장 순서)

### 4.1 설정 분리(가장 효과 큼)

- **`config.public.json`**: topPath, 스킴 이름, feature flag, **비밀이 없는** URL 골격만.
- **`secrets`**: Jenkins Credentials / macOS Keychain / `source` 가능한 `.env`(gitignore) / SOPS·git-crypt 등.
- 스크립트는 시작 시 `merge(public, secrets)` 결과를 메모리/임시 파일에만 두고, **원본 JSON을 덮어쓰지 않기**.

### 4.2 `jsonconfig` 동작 정책

- `topPath`, `jenkinsWorkspace` 반영이 필요하면:
  - **A)** 읽기 전용 오버레이(`config.runtime.json` 한 번 쓰기 + gitignore), 또는  
  - **B)** 환경변수(`JB_TOP_PATH`, `JB_WORKSPACE`)로만 전달.  
- “소스 트리의 config.json을 빌드할 때마다 mutate”는 점진적으로 제거하는 것이 안전하다.

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
- **이중 SMTP**: `mail`과 `mail-gmail`이 모두 있으면, 코드 경로별로 어느 쪽을 쓰는지(국내/해외, 발신 정책) 문서화하지 않으면 **잘못된 박스로 메일이 나가거나** 비밀 로테이션 시 한쪽만 갱신하는 사고가 나기 쉽다.
- **Jenkins가 건드리는 필드**: `topPath`, `android.jenkinsWorkspace`, `ios.jenkinsWorkspace` 등은 빌드 중 **in-place `jq` 갱신** 대상이다. Git으로 관리되는 동일 파일이면 **의도치 않은 diff**가 생긴다.
- **`users`**: `app` / `qc` / `git` 등 하위 블록이 웹 Basic 인증·로컬 로그인 등에 쓰이면, 이 JSON이 **DocumentRoot 아래에 그대로 있을 때** 서빙/백업 유출 경로를 점검한다.
- **`discord` / `slack` / `teams`**: JenkinsBuild `jsonconfig`는 현재 **Slack·Teams만** 읽는다. `discord`는 **배포 PHP·다른 스크립트 전용**일 수 있으므로, “쉘이 안 읽는다 = 없다”로 착각하지 않는다.
- **iOS `AppStore.uploadApp.*` + `sudoPassword`**: 빌드 에이전트 서버 권한과 Apple 업로드 자격이 한 파일에 있음 → 분리·Credential Store 이전 우선순위가 높다.
- **Android `usingAllatori` / `usingObfuscation`**: 난독화 파이프라인 옵션이 설정 파일에 있으므로, 실수로 `true`가 `development` 빌드에 섞이지 않는지 빌드 매트릭스와 대조한다.

동일 저장소의 `lang/*.json`에는 고객 표기용 문자열만 두고, 비밀을 넣지 않는다.

## 6. 참고 파일

- 스키마 느낌의 샘플: `test/config.json`
- **실배포 형태(키만 교차 검증)**: `working-copy/AngelNet-DistSite/config/config.json`(워크스페이스 클론 가정)
- 로더·변조 로직: `config/jsonconfig`
- 표시용으로 config에서 ID/PW 읽는 부분: `config/buildenvironment`
