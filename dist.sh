#!/bin/sh
#
# Written by EungShik Kim on 2022.04.04
# Normalized by Henry Kim on 2023.11.29
#
SCRIPT_PATH=$(dirname $0)
SCRIPT_NAME=$(basename $0)
function getLastTag() {
  LAST_TAG_FULL=$(git describe --tags)
  VERSIONS=( ${LAST_TAG_FULL//-/ })
  num=0
  LAST_BUILD_TYPE=${VERSIONS[num]}
  if [[ "${LAST_BUILD_TYPE}" == [Rr]* ]]; then
    LAST_BUILD_TYPE="$(echo ${LAST_BUILD_TYPE} | tr '[:lower:]' '[:upper:]')-"
    num=$((num + 1))
  elif [[ "${LAST_BUILD_TYPE}" == [Dd]* ]]; then
    LAST_BUILD_TYPE="$(echo ${LAST_BUILD_TYPE} | tr '[:lower:]' '[:upper:]')-"
    num=$((num + 1))
  else
    LAST_BUILD_TYPE=""
  fi
  LAST_TAG=${VERSIONS[num]}
  # LAST_COMMIT_HASH=${VERSIONS[2]} # It's not commit hash... WhatThe!?!
}
function getInputTag() {
  VERSION_STRING=( ${GIT_TAG_FULL//-/ })
  num=0
  BUILD_TYPE=${VERSION_STRING[num]}
  if [[ "${BUILD_TYPE}" == [Rr]* ]]; then
    BUILD_TYPE="$(echo ${BUILD_TYPE} | tr '[:lower:]' '[:upper:]')-"
    num=$((num + 1))
  elif [[ "${BUILD_TYPE}" == [Dd]* ]]; then
    BUILD_TYPE="$(echo ${BUILD_TYPE} | tr '[:lower:]' '[:upper:]')-"
    num=$((num + 1))
  else
    # thanks to https://stackoverflow.com/a/10218528
    BUILD_TYPE="$(echo ${RELEASE_TYPE:0:1} | tr '[:lower:]' '[:upper:]')-"
  fi
  FULL_VERSION=${VERSION_STRING[num]}
  VERSION_STRING=( ${FULL_VERSION//./ })
  MARKET_VERSION="${VERSION_STRING[0]}.${VERSION_STRING[1]}.${VERSION_STRING[2]}"
  BUILD_NUMBER="${VERSION_STRING[3]}"
  if test -z $BUILD_NUMBER; then
    BUILD_NUMBER="1"
  fi
}
function printLastTag() {
  getLastTag
  echo "  ┍━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┑"
  echo "           FYI - The last tag is '$LAST_BUILD_TYPE$LAST_TAG'"
  echo "  ┕━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┙"
}
ProceedOrNot=0
function printInputTag() {
  echo " ┍━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┑"
  echo "     Input tag is '${FINAL_TAG}'"
  echo "     Input platform is '${INPUT_OS}'"
  echo "     Input release type is '${RELEASE_TYPE}'"
  if [ $ProceedOrNot -eq 1 ]; then
    echo "     Commit this version change, Push, and Proceed build on Jenkins, Are you sure? (Y/n)"
  fi
  if [ $DRY_RUN -eq 1 ]; then
    echo "     Is dry-run? ..........[YES]"
  fi
  echo " ┕━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┙"
}
function printResult() {
  getLastTag
  echo " ┍━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┑"
  echo "     Result - Jenkins build as tag '$FINAL_TAG' started..."
  echo " ┕━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┙"
}
function printUntrackError() {
  echo " ┍━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┑"
  echo "     There are some issues, maybe untracked files remained..."
  echo "     You can `git stash` untracked files for push!"
  echo " ┕━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┙"
}
function printNotMainError() {
  echo " ┍━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┑"
  echo "     Branch is not `main`, you should checkout main branch"
  echo " ┕━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┙"
}
function printUncommitError() {
  echo " ┍━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┑"
  echo "     WARNING!!! There are some issues, maybe uncommited files remained..."
  echo "     run git commit first..."
  echo " ┕━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┙"
}
function matchPlatformOrNot() {
  # thanks to https://stackoverflow.com/a/50808490
  trap "$(shopt -p nocasematch)" RETURN
  # thanks to https://stackoverflow.com/a/1728814
  shopt -s nocasematch
  case "${INPUT_OS}" in
    "android" ) INPUT_OS="android";;
    "ios" ) INPUT_OS="ios";;
    "both" ) INPUT_OS="both";;
    * ) 
      $SCRIPT_PATH/$SCRIPT_NAME -h
      echo "error: unknown platform was specified => ${INPUT_OS}."
      echo ""
      exit
      ;;
  esac
}
function matchReleaseTypeOrNot() {
  # thanks to https://stackoverflow.com/a/50808490
  trap "$(shopt -p nocasematch)" RETURN
  # thanks to https://stackoverflow.com/a/1728814
  shopt -s nocasematch
  case "${RELEASE_TYPE}" in
    "release" ) RELEASE_TYPE="release";;
    "develop" ) RELEASE_TYPE="develop";;
    * ) 
      $SCRIPT_PATH/$SCRIPT_NAME -h
      echo "error: unknown release type was specified => ${RELEASE_TYPE}."
      echo ""
      exit
      ;;
  esac
}
## Default variables
UPDATE_VERSION=0
DRY_RUN=0
## Parsing arguments, https://stackoverflow.com/a/14203146
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
  -p | --platform)
    INPUT_OS="$2"
    shift # past argument
    shift # past value
    ;;
  -t | --tag)
    GIT_TAG_FULL="$2"
    shift # past argument
    shift # past value
    ;;
  -c | --config)
    CONFIG_FILE="$2"
    shift # past argument
    shift # past value
    ;;
  -r | --release-type)
    RELEASE_TYPE="$2"
    shift # past argument
    shift # past value
    ;;
  -a | --auto-update)
    UPDATE_VERSION=1
    shift # past argument
    shift # past value
    ;;
  --dry-run)
    DRY_RUN=1
    shift # past argument
    ;;
  * | -h | --help) # unknown option
    shift          # past argument
    echo "usage: $SCRIPT_NAME [ -p | --platform {ios|android|both}] [ -t | --tag <tag name>] "
    echo "          [ -c | --config <config_file>] [ -r | --release-type {release|develop}] "
    echo "          [ -a | --auto-update]"
    echo ""
    echo "examples:"
    echo "       $SCRIPT_NAME -p both -t '1.0.0' -r develop"
    echo "       $SCRIPT_NAME -p ios -t '1.0.0' -a -r release"
    echo "       $SCRIPT_NAME -p ios -t '1.0.0' -c dist.config"
    echo ""
    echo "mandatory arguments:"
    echo "   -p, --platform     {ios|android|both}"
    echo "                      assign platform as iOS or Android or both to processing"
    echo "   -t, --tag          git tag to be added with <tag name> such as '1.0.0', 'D-1.0.0.43', 'RA-1.0.0.44', 'RI-1.0.0.45'"
    echo "                      eg. tag prefix 'D-' means test build for both iOS and Android platform"
    echo "                      eg. tag prefix 'RA-' means release build for Android platform"
    echo "                      eg. tag prefix 'RI-' means release build for iOS platform"
    echo ""
    echo "optional arguments:"
    echo "   -h, --help         show this help message and exit:"
    echo "   -c, --config       <config_file>"
    echo "                      can copy file from $SCRIPT_PATH/dist.config.default"
    echo "   -r, --release-type {Release|Develop}, default is Develop"
    echo "   -a, --auto-update  update project version string(code) and commit & push automatically"
    echo "   --dry-run          dry run only instead of real processing with git command"
    printLastTag
    exit
    ;;
  esac
done
if test -z "$GIT_TAG_FULL"; then
    $SCRIPT_PATH/$SCRIPT_NAME -h
    echo ""
    echo "error: no tag name specified."
    echo ""
    exit
fi
if test -z "$INPUT_OS"; then
    $SCRIPT_PATH/$SCRIPT_NAME -h
    echo ""
    echo "error: no platform type specified."
    echo ""
    exit
else
  matchPlatformOrNot
fi
if test ! -z "$RELEASE_TYPE"; then
    matchReleaseTypeOrNot
else
    # Set default release type as develop
    RELEASE_TYPE="develop"
fi
if test ! -z "$CONFIG_FILE"; then
    if test ! -f "$CONFIG_FILE"; then
      $SCRIPT_PATH/$SCRIPT_NAME -h
      echo ""
      echo "error: no config file in $CONFIG_FILE"
      echo ""
      exit
    fi
fi
###
###
if [ -z "$(git status --untracked-files=no --porcelain --ignore-submodules)" ]; then
  # Working directory clean excluding untracked files

  getInputTag
  if test -z "${BUILD_TYPE}"; then
    FINAL_TAG="${MARKET_VERSION}.${BUILD_NUMBER}"
  else
    FINAL_TAG="${BUILD_TYPE}${MARKET_VERSION}.${BUILD_NUMBER}"
  fi

  if [ ! -z "$(git tag | grep '${FINAL_TAG}')" ]; then
    echo " ┍━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┑"
    echo "     Input tag '$BUILD_TYPE$MARKET_VERSION.$BUILD_NUMBER' is exist, delete it? (Y/n)"
    echo " ┕━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┙"
    read -n1 Answer
    if [ "$Answer" == "Y" -o "$Answer" == "y" ]; then
      git tag -d '${FINAL_TAG}'
    else
      exit
    fi
  fi

  if [ $UPDATE_VERSION -eq 1 ]; then
    if [[ "$INPUT_OS" == "ios" || "$INPUT_OS" == "both" ]]; then
      IOS_FILE="$(find . -name 'project.pbxproj' | grep -v 'Pods' | grep -v 'node_modules')"
      if [ -f "$IOS_FILE" ]; then
        cat $IOS_FILE | \
        sed -e "s/CURRENT_PROJECT_VERSION = \(.*\);/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/g" | \
        sed -e "s/MARKETING_VERSION = \(.*\);/MARKETING_VERSION = $MARKET_VERSION;/g" \
        > $IOS_FILE.new
        if [ $DRY_RUN -eq 0 ]; then
          mv $IOS_FILE.new $IOS_FILE
        else
          echo "iOS: mv $IOS_FILE.new $IOS_FILE"
          grep 'MARKETING_VERSION =' $AOS_FILE
          grep 'CURRENT_PROJECT_VERSION =' $AOS_FILE
          rm $IOS_FILE.new
        fi
      fi
    fi

    if [[ "$INPUT_OS" == "android" || "$INPUT_OS" == "both" ]]; then
      # thanks to https://stackoverflow.com/a/70940482
      AOS_FILE="$(find . -name 'build.gradle' -exec grep -lirZ '^apply plugin' {} \; | xargs grep -li 'com.android.application' | xargs grep -li 'applicationId' | grep -v 'node_modules')"
      if [ -f "$AOS_FILE" ]; then
        cat $AOS_FILE | \
        sed -e "/versionCode =/!s/versionCode .*/versionCode $BUILD_NUMBER/g" | \
        sed -e "s/versionName \".*\"/versionName \"$MARKET_VERSION\"/g" \
        > $AOS_FILE.new
        if [ $DRY_RUN -eq 0 ]; then
          mv $AOS_FILE.new $AOS_FILE
        else
          echo "Android: mv $AOS_FILE.new $AOS_FILE"
          grep 'versionName' $AOS_FILE
          grep 'versionCode ' $AOS_FILE
          rm $AOS_FILE.new
        fi
      fi
    fi
  fi

  Type="${RELEASE_TYPE}"
  OS="${INPUT_OS}"
  REMOTE_REPO="$(git remote -v  | grep 'github.com' | grep '(push)' | awk '{print $1}' | tr -d ' ')"
  printInputTag
  if [ $UPDATE_VERSION -eq 1 ]; then
    echo "Commit this version changing, Push tag(${FINAL_TAG}), and Proceed build on Jenkins"
  else
    echo "Push tag(${FINAL_TAG}), and Proceed build on Jenkins"
  fi
  # thanks to https://stackoverflow.com/a/226724
  while true; do
      read -n1 -p "Are you sure? (y/n) " yn
      case $yn in
          [Yy]* )
              echo ""
              CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
              if [ $UPDATE_VERSION -eq 1 -a $DRY_RUN -eq 0 ]; then
                git commit -a -m "Update version $Type v${MARKET_VERSION} build($BUILD_NUMBER) for $OS"
                git push $REMOTE_REPO $CURRENT_BRANCH
              else
                echo "processing push command: git push ${REMOTE_REPO} ${CURRENT_BRANCH}"
              fi
            break;;
          [Nn]* ) 
              echo ""
              echo "bye"
              exit;;
          * ) 
              echo ""
              echo "Please answer yes or no.";;
      esac
  done
  FINAL_TAG=$(echo ${FINAL_TAG} | tr -d "'" | tr -d '"')
  if [ $DRY_RUN -eq 0 ]; then
    git tag -a ${FINAL_TAG} -m "${Type} build for ${OS}"
    git push --tags $REMOTE_REPO
  else
    echo "processing add tag command : git tag -a ${FINAL_TAG}"
    echo "processing push command: git push --tags ${REMOTE_REPO}"
  fi
else 
  # Uncommitted changes error
  printUncommitError
  exit
fi

printResult
