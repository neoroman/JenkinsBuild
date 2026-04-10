# JenkinsBuild

Practical build automation scripts for Jenkins-based iOS/Android pipelines.

Korean guide: [README.ko.md](README.ko.md)

## Requirements (macOS Jenkins host)

- `jq` (required): `brew install jq`
- `bundletool` for Android AAB (required for Android): `brew install bundletool`
- Xcode command line tools (required for iOS only)
- Optional:
  - `slack-cli`: `brew install rockymadden/rockymadden/slack-cli`
  - `gs`: `brew install gs`
  - ImageMagick (`convert`): `brew install imagemagick`

## Real usage: keep `jenkins/` submodule up to date

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

## Real usage: run Android build in Jenkins

```bash
bash -ex "${WORKSPACE}/jenkins/jenkins-build.sh" -p android --toppath "NeoRoman/AppProject"
```

- `--toppath` should be your app root relative path under `${WORKSPACE}`.
- Example value: `"NeoRoman/AppProject"`.

## Optional distribution-site config

```bash
bash -ex "${WORKSPACE}/jenkins/build.sh" -p android --toppath "NeoRoman/AppProject" \
  --config "${WORKSPACE}/jenkins_config/config.json" \
  --language "${WORKSPACE}/jenkins_config/lang_ko.json"
```

- `--config`: site/distribution configuration JSON.
- `--language`: localized message JSON.

## Jenkins example

![help](images/JenkinsConfigHelp.png)

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/CONFIG_AND_SECRETS.md](docs/CONFIG_AND_SECRETS.md)
- [docs/DRY_RUN_CHECKLIST.md](docs/DRY_RUN_CHECKLIST.md)
- [docs/dist_comparison.md](docs/dist_comparison.md)

## Author

ALTERANT / neoroman@gmail.com

## License

See [LICENSE](LICENSE).
