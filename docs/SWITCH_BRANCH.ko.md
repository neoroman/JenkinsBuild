# Develop / release 브랜치 전환 도구

**Languages:** [English (SWITCH_BRANCH.md)](SWITCH_BRANCH.md)

엔트리 포인트는 이 서브모듈 저장소 루트의 `switch.sh`입니다. 예전에는 별도 모듈이던 Python 보조 로직을 heredoc과 `mktemp`로 내장해 **단일 스크립트**로 동작하며, 외부 Python 파일에 의존하지 않습니다.

도구는 **릴리스 대비 디벨롭** 소스 차이를 **규칙 파일**로 관리한 뒤, **같은 저장소의 현재 브랜치 작업 트리**에 패치 적용 또는 되돌립니다. 디벨롭 전용 변경은 로컬에만 두고 원격에는 커밋하지 않는 것을 전제로 합니다.

## 빠른 시작 예제

상위 앱 저장소를 **REPO_ROOT**라 할 때, 서브모듈이 `jenkins/`에 연결되어 있다고 가정합니다. **JenkinsBuild 저장소만 단독으로 클론한 경우**에는 해당 디렉터리가 곧 루트이므로 `./jenkins/` 접두어 없이 `./update.sh`, `./switch.sh`를 실행하면 됩니다.

1. 본인 PC의 working copy에서 **REPO_ROOT**로 이동한 뒤 `./jenkins/update.sh`를 실행합니다. (서브모듈을 갱신해 최신 `./jenkins/switch.sh`를 사용합니다.)
2. 현재 checkout된 앱 브랜치와 무관하게 동작하므로, **Release / Develop** 기준 브랜치 이름을 미리 정해 둡니다.
3. `./jenkins/switch.sh --mode generate-config --release-branch master --develop-branch develop/main --dry-run` 로 설정 생성을 **드라이런**하고, 오류가 없는지 확인합니다.
4. `./jenkins/switch.sh --mode generate-config --release-branch master --develop-branch develop/main` 를 실행합니다.
5. `dev_switch.config`가 생성되었는지 확인합니다. (실행한 디렉터리 기준; 일반적으로 `jenkins/` 루트 또는 작업 루트)
6. 현재 브랜치에 **develop 모드** 적용: `./jenkins/switch.sh --mode develop` (`dev_switch.config`에 따른 변경이 현재 브랜치 작업 트리에 반영됩니다.)
7. GitHub에 커밋하기 **전** 테스트용 코드를 제거하려면 **release 모드** 적용: `./jenkins/switch.sh --mode release`
8. `dev_switch.config.zip` 파일이 생성되고, develop 모드에서 적용했던 코드 변경은 제거됩니다.
9. `dev_switch.config.zip`과 `.gitignore` 등을 포함하여 `git add` / `commit` / `push` 합니다.

## 동작 흐름

1. **한 번** `--mode generate-config`: 기본적으로 `switch.sh` 옆의 `dev_switch.config.default`에서 `[repo]`를 읽고(`push_url`, `release_branch` / `production_branch`, `develop_branch`), 각 브랜치를 `.generate-config/<branch-path>/` 아래에 클론한 뒤 트리를 비교해 저장소 루트에 `dev_switch.config`를 씁니다. 로컬 디렉터리 두 개만 쓰려면 `--release-dir`와 `--develop-dir`를 넘깁니다. 생성 시 필요하면 `.gitignore`에 `/dev_switch.config`, `/dev_switch.config.zip`, `.generate-config/`를 추가합니다.
2. 아무 브랜치에서나 `--mode develop`은 release→develop 치환을 적용하고, `--mode release`는 develop→release로 되돌립니다.
3. **`--mode release` 이후** 루트의 `dev_switch.config`는 **암호가 걸린 zip**(`dev_switch.config.zip`; 비밀번호는 `switch.sh`의 `ZIP_PASSWORD`)으로 묶이고, 평문 `dev_switch.config`는 삭제됩니다.
4. **`--mode develop`**은 `dev_switch.config.zip`이 있으면 풀어 쓴 뒤 규칙을 적용합니다.

## 빠른 사용 예 (명령 모음)

```bash
# 요약 diff (저장소 루트에 dev_switch.config 필요, 또는 --config)
./switch.sh --mode compare

# develop 패치만 미리보기
./switch.sh --mode develop --dry-run

# develop 적용 + 왕복 검증
./switch.sh --mode verify-develop --release-branch master --develop-branch develop/main

# release로 복원 (+ 설정을 zip으로 보관 후 평문 삭제)
./switch.sh --mode release

# 설정 생성 한 번 (기본: dev_switch.config.default → dev_switch.config)
./switch.sh --mode generate-config

# 샘플 기본값 파일로 비교
./switch.sh --mode compare --config ./dev_switch.config.default
```

(`jenkins/` 서브모듈 안에서 실행할 때는 위 경로를 `./jenkins/switch.sh` 형태로 맞춥니다.)

## 설정 파일

- 템플릿: `./dev_switch.config.default` (앱에 맞게 `[repo]` URL·브랜치 조정; iOS/Android 경로가 `generate-config`에 의미 있게 맞아야 함)
- 생성·활성 설정: `./dev_switch.config` (민감 정보 — 커밋하지 말 것, `.gitignore` 참고)
- release 이후: `./dev_switch.config.zip` (스크립트가 유지)

INI 형식: `rule.*` 섹션에 `file`, `release`, `develop` 키(`prod` / `dev` 별칭 지원).

## Python 직접 호출 (선택)

일반 사용은 `switch.sh`로 합니다. 추출한 헬퍼에 대해 `python3`를 직접 쓰는 것은 디버깅용입니다.
