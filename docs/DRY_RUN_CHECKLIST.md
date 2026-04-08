# JenkinsBuild Dry-Run Checklist

`platform/android.sh`, `platform/ios.sh`의 실제 빌드/파일쓰기 구간을 안전하게 점검하기 위한 체크리스트다.

## 1) 개발 상태 스냅샷

- 핵심 실행 경로: `build.sh` -> `platform/android.sh` / `platform/ios.sh`
- 새 dry-run 플래그:
  - `--dry-run`: 플랫폼 단계 시뮬레이션만 수행하고 종료
  - `--dry-run-step <step-id>`: 특정 단계만 실행 표시 (나머지는 SKIP)
- 공통 헬퍼: `platform/jb_dryrun.sh`

## 2) Android 단계 체크

- `android.pre.reactnative` — RN 의존성/사전 빌드 준비
- `android.pre.allatori` — Allatori hook 주입
- `android.build.primary` — GoogleStore/핵심 타깃 build
- `android.build.secondary` — OneStore/Live/Test 타깃 build
- `android.output.move` — 산출물 이동/파일명 규칙
- `android.output.bundletool` — AAB to universal APK
- `android.output.cleanup` — 출력 정리
- `android.scp.upload` — 원격 업로드(sendFile)
- `android.obfuscation.proof` — 난독화 증적 생성

## 3) iOS 단계 체크

- `ios.pre.flutter_or_react` — Flutter/RN 사전 빌드
- `ios.pre.init_config` — 버전/출력 경로 초기화
- `ios.pre.pods` — pod install/update
- `ios.pre.unlock_keychain` — keychain unlock
- `ios.build.archive` — xcode archive/export
- `ios.output.package` — IPA 패키징(zip/mv)
- `ios.output.cleanup` — 산출물 제거
- `ios.output.plist` — OTA plist 생성
- `ios.scp.upload` — 원격 업로드(sendFile)
- `ios.obfuscation.proof` — IxShield 증적 생성

## 4) 실행 커맨드 (실제 검증)

```bash
mkdir -p /tmp/jb-dryrun-root/JenkinsBuildDryRun/{config,lang}

./build.sh -p android -c ./test/config.json -dr /tmp/jb-dryrun-root -tp JenkinsBuildDryRun --dry-run
./build.sh -p android -c ./test/config.json -dr /tmp/jb-dryrun-root -tp JenkinsBuildDryRun --dry-run-step android.build.primary

./build.sh -p ios -c ./test/config.json -dr /tmp/jb-dryrun-root -tp JenkinsBuildDryRun --dry-run
./build.sh -p ios -c ./test/config.json -dr /tmp/jb-dryrun-root -tp JenkinsBuildDryRun --dry-run-step ios.output.plist
```

## 5) 검증 결과

- 쉘 문법 검사(`bash -n`) 통과: `build.sh`, `platform/android.sh`, `platform/ios.sh`, `platform/jb_dryrun.sh`, `config/argsparser`
- `--dry-run` 전체 실행 시 각 단계가 `RUN`으로 출력됨
- `--dry-run-step` 실행 시 지정 단계만 `RUN`, 나머지는 `SKIP`
- iOS dry-run에서 `xcode-select`/`sudo` 실행은 차단됨 (`[DRY-RUN] skip xcode-select switch`)
- dry-run 모드에서는 플랫폼 시뮬레이션 후 즉시 종료(`makejson/makehtml/notification` 스킵)

## 6) Android/iOS 함수 단위 테스트 케이스 (성공/실패/skip)

### Android (`jb_android_make_obfuscation_screenshot`)

- 성공: `bash test/obfuscation_android.sh`
- 실패: 필수 환경변수 누락 상태에서 함수 직접 호출 (`OUTPUT_FOLDER` 미설정)
- skip: `DEBUGGING=1` 상태에서 함수 직접 호출

실행 결과(2026-04-07):

- 재실행 확인: `bash test/obfuscation_android.sh` + 실패/skip 함수 직접 호출 3케이스 모두 재현
- 성공 케이스: `exit 0`
  - 핵심 로그: `Created obfuscation screenshot with ImageMagick`, `Copied obfuscation file: .../test/android/output/obfuscation_output.png`
  - 참고: ImageMagick `convert` deprecation/font warning 출력은 있었지만 테스트 자체는 통과
- 실패 케이스: `exit 1`
  - 오류: `plugins/obfuscation_android.sh: line 16: OUTPUT_FOLDER: unbound variable`
- skip 케이스: `exit 0`
  - 로그: `ANDROID_SKIP_OK` (DEBUGGING 분기로 함수 본문 실행 생략 확인)

### iOS (`jb_ixshield_make_obfuscation_screenshot`)

- 성공: `bash test/obfuscation_ios.sh`
- 실패: 필수 환경변수 누락 상태에서 함수 직접 호출 (`OBFUSCATION_SOURCE` 미설정)
- skip: `DEBUGGING=1` 상태에서 함수 직접 호출

실행 결과(2026-04-07):

- 재실행 확인: `bash test/obfuscation_ios.sh` + 실패/skip 함수 직접 호출 3케이스 모두 재현
- 성공 케이스: `exit 0`
  - 핵심 로그: `Created obfuscation screenshot with ImageMagick`, `iOS obfuscation screenshot smoke test OK`
  - 참고: ImageMagick `convert` deprecation/font warning 출력은 있었지만 테스트 자체는 통과
- 실패 케이스: `exit 1`
  - 오류: `plugins/ixshield_ios.sh: line 19: OBFUSCATION_SOURCE: unbound variable`
- skip 케이스: `exit 0`
  - 로그: `IOS_SKIP_OK` (DEBUGGING 분기로 함수 본문 실행 생략 확인)

## 7) 후속 TODO (강화 포인트)

- dry-run 단계별 사전 조건 검증(필수 파일/디렉터리 존재 체크) 자동화
- `ios.output.plist`/`android.output.move`에서 출력 경로 계산값을 더 상세히 표기
- CI에 `--dry-run-step` 스모크 잡을 추가해 리팩터링 시 회귀를 빠르게 감지
