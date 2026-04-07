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

## 6) 후속 TODO (강화 포인트)

- dry-run 단계별 사전 조건 검증(필수 파일/디렉터리 존재 체크) 자동화
- `ios.output.plist`/`android.output.move`에서 출력 경로 계산값을 더 상세히 표기
- CI에 `--dry-run-step` 스모크 잡을 추가해 리팩터링 시 회귀를 빠르게 감지
