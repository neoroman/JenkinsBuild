# JenkinsBuild — 소스 구조와 논리적 모듈

이 문서는 **현재 파일 배치와 무관하게** JenkinsBuild가 하는 일을 기능 단위로 정리하고, **공통 코드**와 **사이트·벤더 특화 코드**의 경계를 명확히 한다.

## 1. 실행 흐름(한 줄 요악)

1. `build.sh`가 `config/defaultconfig`(마지막에 선택적으로 `config/defaultconfig.local`을 `source`) → `argsparser` → `jsonconfig` → `sshfunctions` → `utilconfig`를 `source`한다.
2. (비난독화·조건 충족 시) 배포 사이트 동기화로 `installOrUpdate.sh`를 실행한 뒤 `config/fcmconfig`를 `source`한다.
3. Android는 `util/makePath` → `plugins/allatori_android.sh`(Allatori 훅) → `platform/android.sh`(내부에서 `plugins/obfuscation_android.sh` 로드)의 `doExecuteAndroid`, iOS는 `util/versions`를 불러 온 뒤 `platform/ios.sh`(내부에서 `plugins/ixshield_ios.sh` 로드)의 `doExecuteIOS`가 빌드·산출물 배치를 담당한다.
4. 공통으로 `util/makejson` → `util/makehtml` 후, 출력 JSON이 있으면 `config/buildenvironment`를 거쳐 `util/sendslack`·`util/sendteams`·`util/sendemail` 순으로 알린다.
5. 로컬 릴리스 헬퍼는 `dist.sh`(+`util/dist_shlib`, `util/versions`)가 Git 버전·태그·(옵션) Jenkins 트리거를 맡는다. (`util/versions`는 iOS 빌드 경로에서도 `build.sh`가 별도로 `source`한다.)

## 2. 논리 모듈 맵(파일 참조)

- **오케스트레이션**: `build.sh` — 분기, include 순서, 빌드 후 산출 파이프라인 고정.
- **인자·전역 초기화**: `config/argsparser`, `config/defaultconfig`, `config/utilconfig` — CLI, 기본값, `WORKSPACE`/`DEBUGGING`/도구 경로.
- **설정 로드·변조**: `config/jsonconfig` — `config.json`에서 production/development 블록 추출, **topPath·jenkinsWorkspace 등을 jq로 파일에 다시 씀**.
- **FCM/설정 파일 복사**: `config/fcmconfig` — 플랫폼·릴리스 여부에 따라 `google-services.json` 등 복사(상대/절대 경로 해석 포함).
- **SSH/SCP 업로드**: `config/sshfunctions` — `jsonconfig`의 `.ssh.*` 기반 원격 디렉터리·파일 조작. OpenSSH `BatchMode`/타임아웃/known_hosts 는 스크립트에 하드코딩되어 있지 않으며, CI·에이전트 SSH 설정 정책은 `docs/CONFIG_AND_SECRETS.md` §8.
- **배포 HTML/언어 메타**: `config/buildenvironment` — 언어 JSON, 테마 색, 클라이언트명·계정 표시용 값 로드. (**실행 위치**: `makejson`/`makehtml` 이후, `$OUTPUT_FOLDER/$OUTPUT_FILENAME_JSON`이 있을 때만 `build.sh`가 `source`)
- **Android 빌드 본체**: `platform/android.sh` — 버전 해석, 스토어(Play/원스토어/라이브/테스트), Gradle 태스크. **난독화 증적 PNG**(`check.sh` 등)는 `plugins/obfuscation_android.sh` (`makeObfuscationScreenshot` → `jb_android_make_obfuscation_screenshot`). **Allatori Gradle 훅**은 `plugins/allatori_android.sh` (`build.sh`에서만 include).
- **iOS 빌드 본체**: `platform/ios.sh` — 스킴/타깃, xcodebuild, Export. **IxShield 난독화 증적(PNG)** 은 `plugins/ixshield_ios.sh` (`platform/ios.sh`에서 `makeObfuscationScreenshot` → `jb_ixshield_make_obfuscation_screenshot`).
- **경로/산출 접두**: `util/makePath` 등.
- **JSON/HTML 산출**: `util/makejson`, `util/makehtml` — 배포 사이트용 아티팩트 목록·히스토리·git 로그 가공.
- **알림**: `util/sendslack`, `util/sendteams`, `util/sendemail` — 후자는 **`config/jsonconfig`가 세팅한 `$MAIL_ENDPOINT`**(`notifications.mailEndpoint`; 미설정 시 `${FRONTEND_POINT}/${TOP_PATH}/phpmodules/sendmail_domestic.php`)로 `curl` POST.
- **릴리스 자동화**: `dist.sh`, `util/dist_shlib`, `util/versions` — 비교·설명은 `docs/dist_comparison.md`.

## 3. 플랫폼별 책임

### 3.1 Android

- `jsonconfig`의 `.android.*`: 패키지 ID, 앱 경로, 스토어별 task/releaseType, AAB 여부, **usingAllatori**, **usingObfuscation**, keystore 필드, FCM 블록 등.
- 버전은 `version.properties` 우선, 없으면 `build.gradle`/`pubspec` 등에서 파싱.
- 산출물은 `APP_ROOT_PREFIX/TOP_PATH/android_distributions/<version>/` 하위 URL prefix와 연동.

### 3.2 iOS

- `.ios.*`: AppStore/Adhoc/Enterprise/Enterprise4WebDebug, 스킴·번들·**obfuscationSource**, **usingObfuscation**, `podFile`, `rubyGemPath`, FCM(스토어별) 등.
- Info.plist / `project.pbxproj` / Flutter xcconfig에서 버전 문자열 수집.
- 산출은 `ios_distributions` 트리 및 ITMS plist 링크 생성 등(설정에 따름).

### 3.3 공통·교차

- Flutter/React Native: `jsonconfig` 플래그에 따라 PATH·빌드 명령 분기(`utilconfig`, `makejson`, `buildenvironment`).
- 배포 사이트 동기화: `build.sh` 초입의 `installOrUpdate.sh`(및 `.htaccess` 존재 시) — **사이트 템플릿 레포 특화**.

## 4. “일반화 기능” vs “사이트·벤더 특화”(플러그인 후보)

아래는 **코어에서 빼내 플러그인 인터페이스**(훅 스크립트 또는 `plugins/<name>.sh` + `config.json`의 `plugins[]`)로 두기 좋은 부분이다.

| 구분 | 내용 | 현재 위치(대표) |
|------|------|-----------------|
| **벤더: Allatori** | Release 빌드 시 `build.gradle`에서 `runAllatori(variant)` 주석 해제·백업 | `plugins/allatori_android.sh` (`build.sh` → `doExecuteAndroid` 직전에 로드) |
| **벤더: IxShield 계열** | `ix_set_debug` 치환, `IxShieldCheck.sh`/`check.sh` 실행, ImageMagick/gs PNG | **iOS:** `plugins/ixshield_ios.sh`; **Android:** `plugins/obfuscation_android.sh`; 스모크: `test/obfuscation_*.sh`가 각각 위 플러그인을 직접 source |
| **사이트: PHP 메일 게이트** | `curl`로 **`$MAIL_ENDPOINT`**(JSON `notifications.mailEndpoint`)에 subject/body/첨부 전달 | `util/sendemail` + `config/jsonconfig` |
| **사이트: Slack/Teams 웹훅 형식** | 메시지 페이로드 조합 | `util/sendslack`, `util/sendteams` |
| **사이트: SSH 배포 경로 규약** | 원격 디렉터리 트리·권한 가정 | `config/sshfunctions`, 플랫폼 스크립트 내 `NEO2UA_OUTPUT_FOLDER` 등 |
| **사이트: 언어·HTML 테마** | `lang_*.json`, 테마 색, 클라이언트 문구 | `config/buildenvironment`, `util/makehtml` |

### 4.1 Slack / Teams 페이로드 — `notifications/formatters/` 분리 검토 (2026-04-07)

- **현재**: `util/sendslack`은 웹훅일 때 Slack Block Kit JSON(블록·버튼)·아닐 때 `slack chat send` 텍스트 등 **경로가 둘**이고, `util/sendteams`는 Office 365 Connector **MessageCard**(`sections`, `facts`, `heroImage`)로 **스키마가 완전히 다름**. iOS/Android·릴리스/개발 분기와 Jenkins 전역 변수에 강하게 묶여 있다.
- **결정**: 페이로드 문자열 조립을 **`notifications/formatters/`로 당장 쪼개 이전하지 않는다.** 이유: (1) 공통으로 빼기 좋은 “단일 JSON 모델”이 없고, 두 채널은 직렬화 형식이 달라 **파일만 나눠도 중복 분기가 그대로** 따라간다. (2) `source` 순서·ShellCheck 범위·회귀 테스트 부담 대비 이득이 작다. (3) 실질 중복은 “어떤 산출물 링크를 넣을지” **의미** 층이며, 형식이 달라 한 번에 추출하기 어렵다.
- **후속(선택)**: 중복이 문제가 되면 (a) **정규화된 사실만** 세팅하는 얇은 레이어(예: 공통 변수·함수 한 파일, 또는 `jq`로 채울 JSON 템플릿) 후 채널별로만 감싸기, (b) 또는 **소형 헬퍼(예: Python)** 로 JSON 생성 — 이 단계에서 디렉터리명을 `notifications/` 아래로 두는 편이 자연스럽다.

**권장 방향(개념)**

- 코어는 “버전 확정 → 빌드 명령 실행 → 산출물 경로 확정 → (옵션) 업로드 → 메타 JSON/HTML”만 유지.
- `preBuild`, `postBuild`, `obfuscationReport`, `notify` 류 **훅 이름을 고정**하고, Allatori/IxShield/사내 PHP는 훅 구현체로 이동.
- `jsonconfig`에는 `plugins: [{ "id": "allatori", "enabled": true, "config": { ... } }]`처럼 **선언적 활성화**만 남긴다.

## 5. `config.json`과 배포 사이트의 관계

- 기본 경로: `${APP_ROOT_PREFIX}/${TOP_PATH}/config/config.json` (또는 `--config`로 준 커스텀 파일을 **그 경로로 복사**).
- `development` / `production` 블록으로 프론트·아웃바운드 URL, `topPath`, `outputPrefix` 등이 갈린다.
- 더 자세한 *비밀·분리* 논의는 `docs/CONFIG_AND_SECRETS.md` 참고.

**실배포 스키마 참고**: 워크스페이스에 `working-copy/AngelNet-DistSite`(Forgejo `AngelNet/AngelNet-DistSite`)를 두면, 그 안의 `config/config.json`이 **`discord`·`custom` 등 현실적인 키 집합** 예시가 된다. (`mail-gmail`은 **백업용·미사용**으로 둘 수 있어 **개선 문서 범위에서는 제외** — `CONFIG_AND_SECRETS.md` 참고.) 값은 문서나 커밋에 넣지 말고, 키 이름·계층만 교차 검증한다.

## 6. 테스트·샘플

- `test/config.json`: 스키마 샘플·더미 비밀(교육용) — **실운영 값과 혼동 금지**. 실예시에만 있는 **백업용·미사용** 키와의 차이는 `docs/CONFIG_AND_SECRETS.md` §1.2.
- `test/obfuscation_*.sh`(플러그인 직접 호출), `test/android/`, `test/ios/`, `test/ios/fixtures/`: 난독화 경로 스모크용.

## 7. 관련 문서

- `docs/CONFIG_AND_SECRETS.md` — 민감 정보·외부 주입 개선.
- `docs/SHELL_STRICT_AND_SHEBANG.md` — `build.sh` vs `dist.sh` shebang·strict mode 정책(무엇을 바로 바꾸지 않을지 포함).
- `docs/dist_comparison.md` — `dist.sh` vs 과거 단일 스크립트 비교.
