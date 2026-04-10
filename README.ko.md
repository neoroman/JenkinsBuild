# JenkinsBuild

Jenkins 기반 iOS/Android 파이프라인을 위한 실전 빌드 자동화 스크립트 모음입니다.

English guide: [README.md](README.md)

## 요구 사항 (macOS Jenkins 호스트 기준)

- `jq` (필수): `brew install jq`
- Android AAB용 `bundletool` (Android 빌드 시 필수): `brew install bundletool`
- iOS 빌드 시 Xcode Command Line Tools 필요
- 선택:
  - `slack-cli`: `brew install rockymadden/rockymadden/slack-cli`
  - `gs`: `brew install gs`
  - ImageMagick (`convert`): `brew install imagemagick`

## 실사용: `jenkins/` 서브모듈 최신화

```bash
SUBMODULE_PATH="jenkins"
SUBMODULE_URL="https://github.com/neoroman/JenkinsBuild.git"

[ -d "$SUBMODULE_PATH/.git" ] || git config -f .gitmodules --get "submodule.${SUBMODULE_PATH}.path" >/dev/null 2>&1 \
  || git submodule add "$SUBMODULE_URL" "$SUBMODULE_PATH"

git submodule sync -- "$SUBMODULE_PATH"
git submodule update --init --remote "$SUBMODULE_PATH"
# git -C "$SUBMODULE_PATH" pull origin main
git submodule foreach git pull origin main
```

## 실사용: Jenkins에서 Android 빌드 실행

```bash
bash -ex "${WORKSPACE}/jenkins/jenkins-build.sh" -p android --toppath "NeoRoman/AppProject"
```

- `--toppath`는 `${WORKSPACE}` 기준 앱 루트 상대 경로입니다.
- 예시 값: `"NeoRoman/AppProject"`.

## 배포 사이트 설정(선택)

```bash
bash -ex "${WORKSPACE}/jenkins/build.sh" -p android --toppath "NeoRoman/AppProject" \
  --config "${WORKSPACE}/jenkins_config/config.json" \
  --language "${WORKSPACE}/jenkins_config/lang_ko.json"
```

- `--config`: 사이트/배포 설정 JSON
- `--language`: 현지화 메시지 JSON

## Jenkins 설정 예시

![help](images/JenkinsConfigHelp.png)

## 문서 링크

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/CONFIG_AND_SECRETS.md](docs/CONFIG_AND_SECRETS.md)
- [docs/RALPH_REFACTOR_TODO.md](docs/RALPH_REFACTOR_TODO.md)
- [docs/RALPH_AUTOMATED_RUN.md](docs/RALPH_AUTOMATED_RUN.md)
- [docs/DRY_RUN_CHECKLIST.md](docs/DRY_RUN_CHECKLIST.md)
- [docs/dist_comparison.md](docs/dist_comparison.md)

## 작성자

ALTERANT / neoroman@gmail.com

## 라이선스

[LICENSE](LICENSE) 참고.
