# config.json — 외부 주입 설정과 민감 정보 취급

## 1. 이 레포에서 말하는 `config.json`

- 배포 사이트(웹 문서 루트 아래 앱 프로젝트)의 `config/config.json`이 **단일 진실 공급원** 역할을 한다.
- Jenkins에서 `build.sh --config /path/to/site.json` 형태로 줄 경우, `config/jsonconfig`가 그 파일을 **기본 경로로 복사**한 뒤 동일 파일을 읽고 일부 필드를 **다시 기록**한다.

**참고 예시 경로(요청 시 언급됨)**

- `working-copy/AngelNet-DistSite/config/config.json` — 워크스페이스에 없을 수 있으나, 일반적으로 **이 레포의 `test/config.json`과 같은 키 계층**(users, mail, slack, teams, ssh, ios, android, development/production …)을 따른다.

## 2. 민감도가 높은 키(실제 값은 문서에 적지 말 것)

| 영역 | 키(대표) | 위험 |
|------|-----------|------|
| 배포 사이트 로그인 | `users.*.password`, `.email` | 크리덴셜 노출, 로그에 남을 수 있음 |
| 메일 | `mail.Host`, `Username`, `Password` | SMTP 탈취 |
| Slack/Teams/Discord | `*.webhook` | 웹훅 스팸·데이터 유출 |
| iOS 업로드 | `ios.AppStore.uploadApp.agentAppSpecificPassword` 등 | Apple ID 보조 앱 비밀 |
| iOS 빌드 서버 | `ios.sudoPassword`, `ios.jenkinsUser` | 서버 권한 상승 |
| Android 서명 | `android.keyStorePassword`, `keyStoreAlias`, keystore 파일 경로 | APK 서명 키 유출 |
| SSH 배포 | `ssh.endpoint`, `target`, 포트 | 인프라 내부 경로 노출 + 접속 정보 |
| Git/Jira URL | `gitBrowseUrl`, `jira.url` | 상대적으로 낮으나 내망 정보 |

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

## 5. AngelNet-DistSite 예시를 볼 때 체크할 항목

실제 `AngelNet-DistSite/config/config.json`을 열어볼 때 아래를 순서대로 확인하면 좋다.

- `production` / `development` 중 실제 Jenkins가 어느 쪽을 쓰는지(`DEBUGGING`/태그 규칙).
- `users`, `mail`, `slack`, `teams`, `ssh`, keystore, `uploadApp` 블록이 **웹에서 서빙되는지**(PHP가 노출하는지).
- 동일 저장소의 `lang/*.json`에 고객 표기용 문자열만 있는지, 비밀이 섞이지 않았는지.

## 6. 참고 파일

- 스키마 느낌의 샘플: `test/config.json`
- 로더·변조 로직: `config/jsonconfig`
- 표시용으로 config에서 ID/PW 읽는 부분: `config/buildenvironment`
