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
JENKINS_JAR="/tmp/jenkins-cli.jar"
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

### Process uncommitted changes (dist_with_tag.sh: allow commit)
processGitChanges() {
  if [ -z "$(git status --untracked-files=no --porcelain --ignore-submodules 2>/dev/null)" ]; then
    echo "  [$SCRIPT_NAME] No changes to commit."
    return 0
  fi
  echo "  [$SCRIPT_NAME] Processing Git changes..."
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  [$SCRIPT_NAME] DRY-RUN: Would stage, commit and push changes."
    return 0
  fi
  if ! confirm "There's uncommitted changes. Do you want to commit and push?"; then
    echo "  [$SCRIPT_NAME] Commit & push cancelled by user."
    exit 0
  fi
  UNTRACKED_FILES=$(git ls-files --others --exclude-standard 2>/dev/null || true)
  if [ -n "$UNTRACKED_FILES" ]; then
    git add $UNTRACKED_FILES
    echo "  ┍━━━ adding new files ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┑"
    echo "    git add new files ..... [DONE]"
    echo "  ┕━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┙"
  fi
  git add -u
  git commit -m "Update version ${RELEASE_TYPE} v${MARKET_VERSION} build(${BUILD_NUMBER}) for ${INPUT_OS}" || exit 1
  REMOTE_REPO=$(git remote -v | grep 'github.com' | grep '(push)' | awk '{print $1}' | tr -d ' ' | head -n1)
  REMOTE_REPO=${REMOTE_REPO:-origin}
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  git push "$REMOTE_REPO" "$CURRENT_BRANCH"
  echo "  ┍━━━ commit & push version changed ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┑"
  echo "    git commit & push ..... [DONE]"
  echo "  ┕━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┙"
}

processGitChanges

### Process existing tag (fix ${FINAL_TAG} bug, add remote delete)
processTagging() {
  set +e  # pipeline in conditional can trigger exit in some bash versions
  FINAL_TAG_CLEAN=$(echo "${FINAL_TAG}" | tr -d "'" | tr -d '"')
  tag_exists=0
  git tag 2>/dev/null | grep -q "^${FINAL_TAG_CLEAN}$" && tag_exists=1 || true
  if [ "$tag_exists" -eq 1 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "  [$SCRIPT_NAME] DRY-RUN: Tag ${FINAL_TAG_CLEAN} exists. Would delete locally and from remote."
      return 0
    fi
    if ! confirm "Tag ${FINAL_TAG_CLEAN} already exists. Do you want to delete and recreate it?"; then
      echo "  [$SCRIPT_NAME] Tag operation cancelled by user."
      exit 0
    fi
    git tag -d "${FINAL_TAG_CLEAN}" || true
    git push --delete origin "${FINAL_TAG_CLEAN}" 2>/dev/null || true
    echo "  [$SCRIPT_NAME] Tag ${FINAL_TAG_CLEAN} deleted locally and from remote."
  fi
  set -e
}

processTagging

### Update version in project files
if [ "$UPDATE_VERSION" -eq 1 ]; then
  set +e  # hide_spinner and some commands can return non-zero
  if [[ "$INPUT_OS" == "ios" || "$INPUT_OS" == "both" ]]; then
    show_spinner
    IOS_FILE=$(find . -name 'project.pbxproj' | grep -v 'Pods' | grep -v 'node_modules' | head -n1)
    hide_spinner
    if [ -f "$IOS_FILE" ]; then
      oldMarketingVersion=$(grep 'MARKETING_VERSION =' "$IOS_FILE" | sort | uniq | xargs)
      oldCurrentProjectVersion=$(grep 'CURRENT_PROJECT_VERSION =' "$IOS_FILE" | sort | uniq | xargs)
      parsedTagVersion=$(getParsedVersion "${VERSIONS}")
      if ! checkVersionUpdate "$parsedTagVersion" "$(echo "$oldMarketingVersion" | awk -F= '{print $2}' | tr -d ' ;')" "iOS"; then
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
    AOS_FILE=$(find . -name 'build.gradle' -exec grep -lir 'com.android.application' {} \; 2>/dev/null | grep -v 'node_modules' | head -n1)
    hide_spinner
    if [ -f "$AOS_FILE" ]; then
      oldVersionName=$(grep 'versionName' "$AOS_FILE" | sort | uniq | xargs | tr -d '[A-Za-z]-_() ')
      oldVersionCode=$(grep 'versionCode ' "$AOS_FILE" | sort | uniq | xargs | tr -d '[A-Za-z]-_() ')
      parsedTagVersion=$(getParsedVersion "${VERSIONS}")
      if ! checkVersionUpdate "$parsedTagVersion" "$oldVersionName" "Android"; then
        printGradleVersionNameError
        exit 1
      fi
      if [ "$DRY_RUN" -eq 1 ]; then
        echo "  (DEBUG) Android: versionName ${oldVersionName} <== ${MARKET_VERSION}, versionCode ${oldVersionCode} <== ${BUILD_NUMBER}"
      else
        sed -e "/versionCode =/!s/versionCode .*/versionCode $BUILD_NUMBER/g" \
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
REMOTE_REPO=$(git remote -v | grep 'github.com' | grep '(push)' | awk '{print $1}' | tr -d ' ' | head -n1)
REMOTE_REPO=${REMOTE_REPO:-origin}
FINAL_TAG_CLEAN=$(echo "${FINAL_TAG}" | tr -d "'" | tr -d '"')

if [ "$UPDATE_VERSION" -eq 1 ]; then
  echo "  Commit this version changing, Push tag '${FINAL_TAG_CLEAN}', and Proceed build on Jenkins"
else
  echo "  Push tag '${FINAL_TAG_CLEAN}', and Proceed build on Jenkins"
fi

if [ "$DRY_RUN" -eq 0 ] && ! confirm "Are you sure?"; then
  echo "  bye"
  exit 0
fi

### Commit if we updated version and have changes
if [ "$UPDATE_VERSION" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    git add -u
    UNTRACKED_FILES=$(git ls-files --others --exclude-standard 2>/dev/null || true)
    [ -n "$UNTRACKED_FILES" ] && git add $UNTRACKED_FILES
    git commit -am "Update version $Type v${MARKET_VERSION} build(${BUILD_NUMBER}) for $OS"
    git push "$REMOTE_REPO" "$(git rev-parse --abbrev-ref HEAD)"
    echo "  ┍━━━ commit & push version changed ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┑"
    echo "    git commit & push ..... [DONE]"
    echo "  ┕━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┙"
  fi
fi

### Create and push tag
if [ "$DRY_RUN" -eq 1 ]; then
  echo "  (DEBUG) command: git tag -a \"${FINAL_TAG_CLEAN}\""
  echo "  (DEBUG) command: git push ${REMOTE_REPO} ${FINAL_TAG_CLEAN}"
else
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
    triggerJenkinsBuild "$JENKINS_URL" "$JENKINS_JOB_NAME" "$JENKINS_JAR"
  fi
fi

printResult
###############################################################################
### Main Process E N D
###############################################################################
