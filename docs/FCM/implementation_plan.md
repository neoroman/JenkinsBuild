# FCM 설정 복사 자동화 개선 계획 (Dynamic FCM Config Processing)

[fcmconfig](file:///Users/henry/tc/JenkinsBuild/config/fcmconfig) 스크립트가 하드코딩된 `release`, `debug`, `ini` 변수 감지 방식을 탈피하고, `*_src` 및 `*_dst` 패턴을 갖는 모든 변수 쌍을 동적으로 감지하여 처리하도록 개선합니다.

## User Review Required

> [!NOTE]
> 본 변경은 하위 호환성을 완벽하게 유지합니다. 기존 `release`, `debug`, `ini` 접두사는 물론, 임의의 접두사(예: `staging`, `qa` 등)를 JSON에 선언하는 것만으로 쉘 스크립트 수정 없이 동작합니다.

## Open Questions

질문 사항이 없습니다. 분석 결과에 기반하여 설계를 확정하고 진행합니다.

## Proposed Changes

### Configuration

#### [MODIFY] [fcmconfig](file:///Users/henry/tc/JenkinsBuild/config/fcmconfig)
- [fcm_try_copy_pair](file:///Users/henry/tc/JenkinsBuild/config/fcmconfig#L10-L89) 함수에서 `case "$_variant" in` 하드코딩된 분기를 제거하고, 접두사 매개변수(`$_variant`)에 맞춰 동적으로 `_src`와 `_dst` 키 값을 읽어오도록 수정합니다.
- [fcm_copy_block](file:///Users/henry/tc/JenkinsBuild/config/fcmconfig#L91-L102) 함수에서 `jq` 쿼리를 활용해 대상 JSON 객체의 모든 키에서 `*_src` 패턴을 찾고, 그에 해당하는 `*_dst`를 가진 유효 접두사들을 동적으로 추출하여 루프를 돌며 `fcm_try_copy_pair`를 호출하도록 수정합니다.

#### [MODIFY] [config.json (test)](file:///Users/henry/tc/JenkinsBuild/test/config.json)
- 동적 감지 기능을 테스트할 수 있도록 `.android.GoogleStore.FCM` 또는 `.ios.AppStore.FCM`에 테스트용 `custom_src` 및 `custom_dst` 항목을 추가합니다.

---

## Verification Plan

### Automated/Manual Tests
- `test/config.json`에 `custom_src` 및 `custom_dst`를 추가한 뒤, `FCM_DRY_RUN=1`을 설정하고 `fcmconfig`를 로컬에서 소싱하여 감지된 복사 쌍이 올바르게 로그에 출력되는지 확인합니다.

```bash
# 테스트 명령어 예시
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
- 예상 결과: `GoogleStore FCM`에서 `release`, `debug`, `custom` 세 가지 variant에 대해 dry-run copy 메시지가 정상 출력되는지 확인합니다.
