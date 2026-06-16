# FCM 설정 복사 자동화 개선 분석 보고서

[fcmconfig](file:///Users/henry/tc/JenkinsBuild/config/fcmconfig) 스크립트에서 하드코딩된 `release`, `debug`, `ini` 분기를 제거하고, `*_src` -> `*_dst` 패턴의 모든 변수 쌍을 동적으로 감지하여 처리하도록 개선하는 방안에 대한 분석 결과입니다.

---

## 1. 현재 구현의 한계점

현재 [fcmconfig](file:///Users/henry/tc/JenkinsBuild/config/fcmconfig)는 복사 대상 변수를 명시적인 하드코딩 방식으로 처리하고 있습니다.

### `fcm_try_copy_pair` 함수 내의 하드코딩
```shell
fcm_try_copy_pair() {
  ...
  case "$_variant" in
  release)
    # release_src / release_dst 검사 및 할당
    ;;
  debug)
    # debug_src / debug_dst 검사 및 할당
    ;;
  ini)
    # ini_src / ini_dst 검사 및 할당
    ;;
  *)
    return 0
    ;;
  esac
  ...
}
```

### `fcm_copy_block` 함수 내의 명시적 호출
```shell
fcm_copy_block() {
  ...
  fcm_try_copy_pair "$_jqpath" "$_tag" release
  fcm_try_copy_pair "$_jqpath" "$_tag" debug
  fcm_try_copy_pair "$_jqpath" "$_tag" ini
}
```

### 문제점
- `staging`, `qa`, `beta` 등 새로운 빌드 환경(Variant)이 추가될 때마다 쉘 스크립트 코드(`fcmconfig`)를 직접 수정하여 새로운 case와 호출 코드를 삽입해야 합니다.
- 스크립트와 JSON 설정 스키마의 결합도가 높아 유지보수 효율이 저하됩니다.

---

## 2. 제안하는 개선 방안

이 문제를 해결하기 위해 **1) `jq`를 이용해 JSON 객체 내에서 `*_src` 및 `*_dst` 쌍을 가진 접두사(Prefix)들을 동적으로 추출**하고, **2) 추출된 목록을 순회하며 복사**하도록 개선합니다.

### A. `fcm_try_copy_pair` 함수 일반화
`case` 문을 이용해 각 variant 이름을 하드코딩하는 대신, 전달받은 접두사(`$_variant`)를 이용하여 동적으로 JSON 키를 검사하고 값을 읽어옵니다.

```shell
fcm_try_copy_pair() {
  _jqpath="$1"
  _tag="$2"
  _variant="$3"

  # variant_src 및 variant_dst가 문자열이고 비어 있지 않은지 동적으로 검증
  if ! $JQ -e "${_jqpath} | type == \"object\" and (.${_variant}_src | type == \"string\") and (.${_variant}_dst | type == \"string\") and (.${_variant}_src != \"\") and (.${_variant}_dst != \"\")" "$jsonConfig" >/dev/null 2>&1; then
    return 0
  fi

  _src=$($JQ -r "${_jqpath}.${_variant}_src" "$jsonConfig")
  _dst=$($JQ -r "${_jqpath}.${_variant}_dst" "$jsonConfig")

  _abs_src=$(fcm_resolve_src "$_src")
  _abs_dst=$(fcm_resolve_dst "$_dst")

  if [ ! -f "$_abs_src" ]; then
    echo "       [FCM] skip (${_tag} ${_variant}): source missing: $_abs_src" >&2
    return 0
  fi

  if [ "${FCM_DRY_RUN:-0}" -eq 1 ]; then
    echo "       [FCM] dry-run (${_tag} ${_variant}): $_abs_src -> $_abs_dst"
    return 0
  fi

  _dst_dir=$(dirname "$_abs_dst")
  if [ ! -d "$_dst_dir" ]; then
    mkdir -p "$_dst_dir" || {
      echo "       [FCM] skip (${_tag} ${_variant}): could not create directory: $_dst_dir" >&2
      return 0
    }
  fi

  cp "$_abs_src" "$_abs_dst" || {
    echo "       [FCM] skip (${_tag} ${_variant}): copy failed: $_abs_src -> $_abs_dst" >&2
    return 0
  }
  echo "       [FCM] ${_tag} (${_variant}): $(basename "$_abs_src") -> $_dst"
}
```

### B. `fcm_copy_block` 함수 내 동적 접두사 감지 및 순회
`jq`를 통해 대상 경로에 선언된 `*_src` 키들을 찾고, 짝이 맞는 `*_dst` 키가 존재하는 접두사들만 추출하여 루프를 돕니다.

```shell
fcm_copy_block() {
  _jqpath="$1"
  _tag="$2"

  if ! $JQ -e "${_jqpath} | type == \"object\"" "$jsonConfig" >/dev/null 2>&1; then
    return 0
  fi

  # [동적 접두사 감지]
  # 1. 객체의 모든 키-값 쌍을 배열로 전환 (to_entries)
  # 2. 키 이름이 "_src"로 끝나는 항목 필터링
  # 3. "_src"를 잘라내어 접두사(prefix) 추출 (예: "release")
  # 4. 동일 객체 내에 접두사 + "_dst" 키가 존재하며, 값이 비어 있지 않은 문자열인지 검증
  # 5. 유효한 접두사만 줄바꿈 단위로 출력
  _variants=$($JQ -r "${_jqpath} | to_entries | . as \$entries | .[] | select(.key | endswith(\"_src\")) | .key as \$key | (\$key | sub(\"_src$\"; \"\")) as \$prefix | (\$prefix + \"_dst\") as \$dst_key | (\$entries | map(select(.key == \$dst_key and (.value | type == \"string\") and .value != \"\")) | .[0].value) as \$dst_val | select(\$dst_val != null) | select(.value | type == \"string\" and .value != \"\") | \$prefix" "$jsonConfig" 2>/dev/null)

  if [ -n "$_variants" ]; then
    echo "$_variants" | while read -r _variant; do
      [ -z "$_variant" ] && continue
      fcm_try_copy_pair "$_jqpath" "$_tag" "$_variant"
    done
  fi
}
```

---

## 3. 개선 시 장점 및 기대 효과

1. **높은 유연성과 확장성**
   - 향후 `config.json`에 `staging_src`/`staging_dst` 또는 `beta_src`/`beta_dst` 등 새로운 설정 쌍을 자유롭게 추가하더라도 **쉘 스크립트 수정이 전혀 필요하지 않습니다.**
2. **코드 유지보수성 및 가독성 개선**
   - 하드코딩된 분기 코드(case 조건문)와 중복 호출이 사라져 코드가 한결 간결해집니다.
3. **호환성 유지**
   - 기존의 `release_src/release_dst`, `debug_src/debug_dst`, `ini_src/ini_dst` 구조는 아무런 설정 변경 없이 **그대로 동일하게 작동**합니다.
4. **POSIX 쉘 호환성**
   - `#!/bin/sh` 환경에서 완벽히 호환되도록 표준적인 `while read -r` 루프 구조를 사용하여 리눅스 및 macOS 환경 모두에서 안정적으로 작동합니다.
