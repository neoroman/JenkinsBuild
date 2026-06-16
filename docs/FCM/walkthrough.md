# FCM 설정 복사 자동화 개선 완료 보고서

[fcmconfig](file:///Users/henry/tc/JenkinsBuild/config/fcmconfig) 스크립트에서 하드코딩된 `release`, `debug`, `ini` 변수 감지 구조를 제거하고, `*_src` -> `*_dst` 패턴을 가지는 모든 변수 쌍을 동적으로 감지하여 일괄 처리하도록 개선 및 검증을 완료하였습니다.

## 주요 변경 사항

### 1. [fcmconfig](file:///Users/henry/tc/JenkinsBuild/config/fcmconfig) 스크립트 일반화
- **`fcm_try_copy_pair` 함수 일반화**: `case "$_variant"` 하드코딩 분기 처리를 제거하고, 접두사 매개변수(`$_variant`)에 기반하여 `.${_variant}_src` 및 `.${_variant}_dst` 설정을 동적으로 가져오도록 수정했습니다.
- **`fcm_copy_block` 함수 동적 처리**: `jq` 쿼리를 사용해 대상 JSON 블록에서 `*_src` 패턴으로 선언된 키들을 탐색한 뒤, 매칭되는 `*_dst` 키가 존재하는 유효한 접두사들을 추출합니다. 추출된 접두사 리스트를 `while read -r` 루프로 돌며 복사를 호출합니다.

## 검증 결과

### 1. 테스트용 dummy 설정 추가 (`test/config.json`)
동적 감지 기능이 정상 작동하는지 확인하기 위해 `test/config.json`에 `custom_src` / `custom_dst`를 포함한 테스트 FCM 설정을 임시 추가했습니다.
```json
            "FCM": {
                "release_src": "GoogleService/release/google-services.json",
                "release_dst": "app/google-services.json",
                "debug_src": "GoogleService/debug/google-services.json",
                "debug_dst": "app/src/debug/google-services.json",
                "custom_src": "GoogleService/custom/google-services.json",
                "custom_dst": "app/src/custom/google-services.json"
            }
```

### 2. 드라이런 테스트 (`FCM_DRY_RUN=1`) 실행
```bash
WORKSPACE="/Users/henry/tc/JenkinsBuild/test" \
jsonConfig="/Users/henry/tc/JenkinsBuild/test/config.json" \
JQ="jq" \
IS_RELEASE=1 \
INPUT_OS="android" \
FCM_DRY_RUN=1 \
APP_ROOT_PREFIX="/Users/henry/tc/JenkinsBuild" \
TOP_PATH="test" \
. /Users/henry/tc/JenkinsBuild/config/fcmconfig
```

**출력 결과:**
```
       [FCM] dry-run (Android GoogleStore FCM release): /Users/henry/tc/JenkinsBuild/test/GoogleService/release/google-services.json -> /Users/henry/tc/JenkinsBuild/test/app/google-services.json
       [FCM] dry-run (Android GoogleStore FCM debug): /Users/henry/tc/JenkinsBuild/test/GoogleService/debug/google-services.json -> /Users/henry/tc/JenkinsBuild/test/app/src/debug/google-services.json
       [FCM] dry-run (Android GoogleStore FCM custom): /Users/henry/tc/JenkinsBuild/test/GoogleService/custom/google-services.json -> /Users/henry/tc/JenkinsBuild/test/app/src/custom/google-services.json
       [FCM] dry-run (Android GoogleStore FCM release → app): /Users/henry/tc/JenkinsBuild/test/GoogleService/release/google-services.json -> /Users/henry/tc/JenkinsBuild/test/app/google-services.json
```

- 기존의 `release`, `debug`뿐만 아니라 새로 추가한 `custom` 변수 쌍이 스크립트 수정 없이 **동적으로 감지되어 성공적으로 dry-run 복사 파이프라인에 포함**된 것을 확인했습니다.
- 검증 완료 후, 검증에 사용했던 임시 테스트 파일 및 `test/config.json` 변경 내용은 모두 안전하게 복구(Clean)하였습니다.
