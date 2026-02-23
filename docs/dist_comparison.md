# jenkins/dist.sh vs dist_with_tag.sh 비교

두 스크립트는 서로 다른 repo에 있지만 같은 목적(버전 업데이트, Git 태깅, Jenkins 빌드 트리거)을 가진 유사한 스크립트입니다.
이 문서는 리팩터링 후 기준으로 두 스크립트를 비교합니다.

- **jenkins/dist.sh**: JenkinsBuild submodule 내 스크립트
- **dist_with_tag.sh**: angelnet-android 프로젝트 루트의 통합 스크립트

---

## 1. 구조 및 아키텍처

| 항목 | jenkins/dist.sh | dist_with_tag.sh |
|------|-----------------|------------------|
| **쉘** | `#!/bin/bash` | `#!/bin/bash` |
| **구조** | 모듈형 (dist.sh + util/versions + util/dist_shlib) | 단일 파일 (~594줄) |
| **에러 처리** | `set -eo pipefail` | `set -euo pipefail` |
| **의존성** | `util/versions`, `util/dist_shlib` | 없음 |

---

## 2. 공통 기능 (양쪽 모두 지원)

| 기능 | jenkins/dist.sh | dist_with_tag.sh |
|------|-----------------|------------------|
| Jenkins 통합 | ✅ | ✅ |
| `--make-config` | ✅ (dist.config) | ✅ (.distsConfig) |
| 강제 버전 업데이트 (-uf) | ✅ | ✅ |
| 자동 버전 감지 | ✅ | ✅ |
| Uncommitted 변경 처리 | ✅ | ✅ |
| 태그 재생성 (삭제 후 재생성) | ✅ | ✅ |
| `-y` (non-interactive) | ✅ | ❌ |
| `--dry-run` | ✅ | ✅ |
| 플랫폼 unknown 허용 | ✅ | ✅ |

---

## 3. 설정 파일 형식

| 항목 | jenkins/dist.sh | dist_with_tag.sh |
|------|-----------------|------------------|
| **기본 파일** | `dist.config` | `.distsConfig` |
| **형식** | git-config (INI) | KEY=value |
| **태그 prefix 검증** | ✅ D-, RI-, RA- 등 | ❌ |
| **플랫폼/릴리스 자동 추론** | ✅ 태그 prefix 기반 | ❌ |
| **Jenkins 설정** | `[jenkins]` 섹션 | KEY=value |

**jenkins/dist.config 예시:**
```ini
[ios "tagPrefix"]
    develop = D-
    release = RI-
[android "tagPrefix"]
    release = RA-
    develop = D-
[jenkins]
    url = ...
    job = ...
```

**dist_with_tag .distsConfig 예시:**
```ini
TAG=v1.0.0
PLATFORM=both
RELEASE_TYPE=release
JENKINS_URL=...
```

---

## 4. jenkins/dist.sh에만 있는 기능

| 기능 | 설명 |
|------|------|
| **태그 prefix 검증** | dist.config 기반 D-, RI-, RA- 등 형식 검증 |
| **플랫폼/릴리스 자동 추론** | 태그 prefix로 platform, release type 자동 결정 |
| **`-y` 옵션** | 모든 확인에 자동 yes (non-interactive) |
| **versionCode = 구분** | `versionCode =` vs `versionCode ` 구분 (멀티모듈 대응) |
| **마지막 태그 표시** | help 시 `printLastTag()`로 마지막 태그 출력 |
| **모듈화** | util/versions, util/dist_shlib로 분리 |

---

## 5. dist_with_tag.sh에만 있는 기능

| 기능 | 설명 |
|------|------|
| **`-y` 옵션** | ❌ (미구현) |
| **`set -u`** | 미정의 변수 사용 시 에러 |
| **Config 필수 아님** | config 없이 CLI만으로 실행 가능 |
| **버전 업데이트 옵션명** | `-u` / `-uf` (dist는 `-a` / `-uf`) |

---

## 6. 옵션/인자 차이

| 기능 | jenkins/dist.sh | dist_with_tag.sh |
|------|-----------------|------------------|
| 버전 업데이트 | `-a`, `--auto-update` | `-u`, `--update-version-string` |
| 강제 업데이트 | `-uf`, `--force-update` | `-uf`, `--update-version-string-forcefully` |
| Non-interactive | `-y`, `--yes` | ❌ |
| Config 필수 여부 | dist.config 없으면 경고 | .distsConfig 없으면 CLI 인자로 진행 |

---

## 7. Git 워크플로우

| 항목 | jenkins/dist.sh | dist_with_tag.sh |
|------|-----------------|------------------|
| **변경사항 감지** | `--untracked-files=no --ignore-submodules` | `--porcelain` |
| **커밋 범위** | `git add -u` + untracked | `git add .` |
| **태그 푸시** | `git push REMOTE TAG` (태그만) | `git push origin TAG` |
| **확인 시점** | 버전 업데이트 후 "Are you sure?" | 각 단계별 confirm |

---

## 8. 버전 업데이트 로직

| 항목 | jenkins/dist.sh | dist_with_tag.sh |
|------|-----------------|------------------|
| **iOS sed** | `sed -e "s/.../.../g" file > file.new; mv` | `sed -i "" "s/.../.../g" file` |
| **Android sed** | `versionCode =` 제외 후 치환 | `versionCode` 전체 치환 |
| **버전 파싱** | getParsedVersion(VERSIONS) | getParsedVersion(GIT_TAG_FULL) |
| **vercomp** | util/versions (단순) | 인라인 (더 상세) |

---

## 9. 결론 및 권장사항

### 기능 동등성

리팩터링 후 두 스크립트는 다음 기능을 공유합니다:

- Jenkins 통합
- makeConfig
- 강제 버전 업데이트
- 자동 버전 감지
- uncommitted 변경 처리
- 태그 재생성

### jenkins/dist.sh의 장점

1. **`-y` 옵션** – CI/자동화에 적합
2. **태그 prefix 검증** – D-, RI-, RA- 등 형식 검증
3. **모듈화** – util 분리로 유지보수 용이
4. **versionCode = 구분** – 멀티모듈 대응

### dist_with_tag.sh의 장점

1. **단일 파일** – 배포/이동이 간단
2. **Config 선택적** – CLI만으로 실행 가능
3. **`set -u`** – 미정의 변수 방지
4. **vercomp** – 비숫자·패딩 처리 등 보강된 버전 비교

### 사용 시나리오

- **jenkins/dist.sh**: dist.config 기반 D-, RI-, RA- 등 prefix를 쓰고, CI/자동화에서 `-y`가 필요한 경우
- **dist_with_tag.sh**: config 없이 `v1.2.3` 같은 단순 태그를 쓰고, 단일 스크립트로 배포가 필요한 경우

### dist_with_tag.sh에 추가하면 좋은 것

- `-y` 옵션 (non-interactive 모드)
