#!/bin/bash
#
# Written by EungShik Kim on 2022.04.04
# Normalized by Henry Kim on 2023.11.29
# Refactored: dist_with_tag.sh features + -y option
# Mandatory: git should be installed
#
set -eo pipefail

SCRIPT_PATH=$(dirname "$0")
SCRIPT_NAME=$(basename "$0")

###############################################################################
# shellcheck disable=SC1091
. "${SCRIPT_PATH}/util/versions"
###############################################################################
# shellcheck disable=SC1091
. "${SCRIPT_PATH}/util/dist_shlib"
###############################################################################

### Default variables
UPDATE_VERSION=0
UPDATE_VERSION_FORCE=0
DRY_RUN=0
USING_CONFIG=0
TAG_PREFIX=""
NON_INTERACTIVE=0
JENKINS_URL=""
JENKINS_JOB_NAME=""
JENKINS_USER=""
JENKINS_TOKEN=""
JENKINS_TRIGGER_TOKEN=""
JENKINS_JAR="/tmp/jenkins-cli.jar"
JENKINS_TRIGGERED=0
CONFIG_FILE=""

### Argument parsing
while [[ $# -gt 0 ]]; do
  key="$1"
  case "$key" in
    --make-config)
      makeConfig
      exit 0
      ;;
    -p|--platform)
      INPUT_OS="$2"
      shift 2
      ;;
    -t|--tag)
      GIT_TAG_FULL="$2"
      shift 2
      ;;
    -c|--config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    -r|--release-type)
      RELEASE_TYPE="$2"
      shift 2
      ;;
    -a|--auto-update)
      UPDATE_VERSION=1
      shift
      ;;
    -uf|--force-update)
      UPDATE_VERSION=1
      UPDATE_VERSION_FORCE=1
      shift
      ;;
    -y|--yes)
      NON_INTERACTIVE=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --jenkins-url)
      JENKINS_URL="$2"
      shift 2
      ;;
    --jenkins-job)
      JENKINS_JOB_NAME="$2"
      shift 2
      ;;
    --jenkins-user)
      JENKINS_USER="$2"
      shift 2
      ;;
    --jenkins-token)
      JENKINS_TOKEN="$2"
      shift 2
      ;;
    --jenkins-trigger-token)
      JENKINS_TRIGGER_TOKEN="$2"
      shift 2
      ;;
    -h|--help)
      help
      exit 0
      ;;
    *)
      echo "  [$SCRIPT_NAME] Error: unknown option $key"
      help
      exit 1
      ;;
  esac
done

### Check input arguments and cope
checkArgumentsAndCope

### Load Jenkins config from dist.config if not set via CLI
[ -z "$CONFIG_FILE" ] && CONFIG_FILE="dist.config"
if [ -z "$JENKINS_URL" ] || [ -z "$JENKINS_JOB_NAME" ]; then
  loadJenkinsConfig "$CONFIG_FILE"
fi
REMOTE_REPO=$(dist_resolve_push_remote "$CONFIG_FILE")

### Auto-detect version update when project files exist
if [ "$UPDATE_VERSION" -eq 0 ] && shouldUpdateVersion; then
  UPDATE_VERSION=1
  if [ -z "${INPUT_OS}" ] || [ "$INPUT_OS" = "unknown" ]; then
    INPUT_OS="both"
  fi
  echo "  [$SCRIPT_NAME] 프로젝트 파일이 감지되어 자동으로 버전 업데이트를 활성화합니다. (플랫폼: $INPUT_OS)"
fi

###############################################################################
### Main Process START
###############################################################################

getInputTag
printInputTag

### Detect existing tag (삭제는 최종 확인 이후에 수행한다 - 취소해도 기존 태그가 보존되도록)
FINAL_TAG_CLEAN=$(echo "${FINAL_TAG}" | tr -d "'" | tr -d '"')
TAG_EXISTS_LOCAL=0
TAG_EXISTS_REMOTE=0
git rev-parse -q --verify "refs/tags/${FINAL_TAG_CLEAN}" >/dev/null 2>&1 && TAG_EXISTS_LOCAL=1
git ls-remote --exit-code --tags "$REMOTE_REPO" "refs/tags/${FINAL_TAG_CLEAN}" >/dev/null 2>&1 && TAG_EXISTS_REMOTE=1
echo "  [$SCRIPT_NAME] push remote: ${REMOTE_REPO}, HEAD: $(git rev-parse --short HEAD)"
if [ "$TAG_EXISTS_LOCAL" -eq 1 ] || [ "$TAG_EXISTS_REMOTE" -eq 1 ]; then
  OLD_TAG_COMMIT=$(git rev-parse -q --verify "refs/tags/${FINAL_TAG_CLEAN}^{commit}" 2>/dev/null | cut -c1-7)
  echo "  [$SCRIPT_NAME] Tag ${FINAL_TAG_CLEAN} already exists (local=${TAG_EXISTS_LOCAL}, remote=${TAG_EXISTS_REMOTE}${OLD_TAG_COMMIT:+, points to ${OLD_TAG_COMMIT}}); it will be recreated on HEAD."
fi

### Update version in project files
if [ "$UPDATE_VERSION" -eq 1 ]; then
  set +e  # hide_spinner and some commands can return non-zero
  if [[ "$INPUT_OS" == "ios" || "$INPUT_OS" == "both" ]]; then
    show_spinner
    IOS_FILE=$(dist_find_ios_pbxproj)
    hide_spinner
    if [ -f "$IOS_FILE" ]; then
      oldMarketingVersion=$(grep 'MARKETING_VERSION =' "$IOS_FILE" | sort | uniq | xargs)
      oldCurrentProjectVersion=$(grep 'CURRENT_PROJECT_VERSION =' "$IOS_FILE" | sort | uniq | xargs)
      parsedTagVersion=$(getParsedVersion "${VERSIONS}")
      iosCurrentVersion=$(iosHighestMarketingVersion "$IOS_FILE")
      if ! checkVersionUpdate "$parsedTagVersion" "$iosCurrentVersion" "iOS" "$IOS_FILE"; then
        UPDATE_VERSION=0
      else
        if [ "$DRY_RUN" -eq 1 ]; then
          echo "  (DEBUG) iOS: ${oldMarketingVersion} <== ${MARKET_VERSION}, ${oldCurrentProjectVersion} <== ${BUILD_NUMBER}"
        else
          sed -e "s/CURRENT_PROJECT_VERSION = .*;/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/g" \
              -e "s/MARKETING_VERSION = .*;/MARKETING_VERSION = $MARKET_VERSION;/g" \
              "$IOS_FILE" > "${IOS_FILE}.new"
          mv "${IOS_FILE}.new" "$IOS_FILE"
          echo "  ┍━━ iOS project.pbxproj ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┑"
          echo "    update ${oldMarketingVersion} into ${MARKET_VERSION} ....... [DONE]"
          echo "    update ${oldCurrentProjectVersion} into ${BUILD_NUMBER} ........ [DONE]"
          echo "  ┕━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┙"
        fi
      fi
    fi
  fi

  if [[ "$INPUT_OS" == "android" || "$INPUT_OS" == "both" ]]; then
    show_spinner
    AOS_FILE=$(dist_find_android_gradle)
    hide_spinner
    if [ -f "$AOS_FILE" ]; then
      oldVersionName=$(dist_extract_android_version_name "$AOS_FILE")
      oldVersionCode=$(dist_extract_android_version_code "$AOS_FILE")
      parsedTagVersion=$(getParsedVersion "${VERSIONS}")
      set +e
      checkVersionUpdate "$parsedTagVersion" "$oldVersionName" "Android" "$AOS_FILE"
      _cv_rv=$?
      set -e
      if [ "$_cv_rv" -ne 0 ]; then
        if [ "$_cv_rv" -eq 1 ]; then
          printGradleVersionNameError
        fi
        exit 1
      fi
      if [ "$DRY_RUN" -eq 1 ]; then
        echo "  (DEBUG) Android: versionName ${oldVersionName} <== ${MARKET_VERSION}, versionCode ${oldVersionCode} <== ${BUILD_NUMBER}"
      else
        sed -e "s/versionCode = [0-9][0-9]*/versionCode = $BUILD_NUMBER/g" \
            -e "/versionCode =/!s/versionCode .*/versionCode $BUILD_NUMBER/g" \
            -e "s/versionName = \".*\"/versionName = \"$MARKET_VERSION\"/g" \
            -e "s/versionName \".*\"/versionName \"$MARKET_VERSION\"/g" \
            "$AOS_FILE" > "${AOS_FILE}.new"
        mv "${AOS_FILE}.new" "$AOS_FILE"
        echo "  ┍━━ Android app > build.gradle ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┑"
        echo "    update versionName ${oldVersionName} into ${MARKET_VERSION} ...... [DONE]"
        echo "    update versionCode ${oldVersionCode} into ${BUILD_NUMBER} .......... [DONE]"
        echo "  ┕━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┙"
      fi
    fi
  fi
  set -e
fi

### Final confirmation before tag & push
Type="${RELEASE_TYPE}"
OS="${INPUT_OS}"

if [ "$UPDATE_VERSION" -eq 1 ]; then
  echo "  Commit this version changing, Push tag '${FINAL_TAG_CLEAN}', and Proceed build on Jenkins"
else
  echo "  Push tag '${FINAL_TAG_CLEAN}', and Proceed build on Jenkins"
fi
if [ "$TAG_EXISTS_LOCAL" -eq 1 ] || [ "$TAG_EXISTS_REMOTE" -eq 1 ]; then
  echo "  (existing tag '${FINAL_TAG_CLEAN}' will be deleted locally/remote and recreated)"
fi

if [ "$DRY_RUN" -eq 0 ] && ! confirm "Are you sure?"; then
  echo "  bye"
  exit 0
fi

### Commit tracked changes (version bump etc.). submodule 변경/untracked 파일은 커밋하지 않는다.
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if dist_has_commitable_changes; then
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  [$SCRIPT_NAME] DRY-RUN: Would commit tracked changes (excluding submodules) and push branch ${CURRENT_BRANCH}."
  else
    EXCLUDES=()
    while IFS= read -r ex; do [ -n "$ex" ] && EXCLUDES+=("$ex"); done < <(dist_submodule_excludes)
    git add -u -- . ${EXCLUDES[@]+"${EXCLUDES[@]}"}
    if git diff --cached --quiet; then
      echo "  [$SCRIPT_NAME] No staged changes to commit."
    else
      git commit -m "Update version $Type v${MARKET_VERSION} build(${BUILD_NUMBER}) for $OS"
      if [ "$CURRENT_BRANCH" = "HEAD" ]; then
        echo "  [$SCRIPT_NAME] WARN: detached HEAD - branch push skipped (tag will point to the new commit)."
      else
        git push "$REMOTE_REPO" "$CURRENT_BRANCH"
      fi
      echo "  ┍━━━ commit & push version changed ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┑"
      echo "    git commit & push ..... [DONE]"
      echo "  ┕━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┙"
    fi
  fi
fi

### Delete existing tag (local & remote), then create and push tag on HEAD
if [ "$DRY_RUN" -eq 1 ]; then
  [ "$TAG_EXISTS_LOCAL" -eq 1 ] || [ "$TAG_EXISTS_REMOTE" -eq 1 ] && echo "  (DEBUG) command: git tag -d ${FINAL_TAG_CLEAN}; git push ${REMOTE_REPO} --delete ${FINAL_TAG_CLEAN}"
  echo "  (DEBUG) command: git tag -a \"${FINAL_TAG_CLEAN}\""
  echo "  (DEBUG) command: git push ${REMOTE_REPO} ${FINAL_TAG_CLEAN}"
else
  [ "$TAG_EXISTS_LOCAL" -eq 1 ] && git tag -d "${FINAL_TAG_CLEAN}"
  if [ "$TAG_EXISTS_REMOTE" -eq 1 ]; then
    git push "$REMOTE_REPO" --delete "${FINAL_TAG_CLEAN}"
  fi
  git tag -a "${FINAL_TAG_CLEAN}" -m "${Type} build for ${OS}"
  git push "$REMOTE_REPO" "${FINAL_TAG_CLEAN}"
  echo "  ┍━━━ add tag & push to remote ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┑"
  echo "    git tag -a \"${FINAL_TAG_CLEAN}\" -m \"${Type} build for ${OS}\" ..... [DONE]"
  echo "    git push ${REMOTE_REPO} ${FINAL_TAG_CLEAN} ..... [DONE]"
  echo "  ┕━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┙"
fi

### Trigger Jenkins build if configured
if [ -n "$JENKINS_URL" ] && [ -n "$JENKINS_JOB_NAME" ]; then
  if downloadJenkinsCLI "$JENKINS_URL" "$JENKINS_JAR"; then
    triggerJenkinsBuild "$JENKINS_URL" "$JENKINS_JOB_NAME" "$JENKINS_JAR" && JENKINS_TRIGGERED=1
  fi
fi

printResult
###############################################################################
### Main Process E N D
###############################################################################
