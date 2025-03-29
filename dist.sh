#!/bin/sh
#
# Written by EungShik Kim on 2022.04.04
# Normalized by Henry Kim on 2023.11.29
# Madatory:
#     git      should be installed...
#
###
SCRIPT_PATH=$(dirname "$0")
SCRIPT_NAME=$(basename $0)
#
###############################################################################
# shellcheck disable=SC1091
. "${SCRIPT_PATH}/util/versions"        ### Import version compare func #######
###############################################################################
#
###############################################################################
# shellcheck disable=SC1091
. "${SCRIPT_PATH}/util/dist_shlib"      ### Import overall func ###############
###############################################################################
#
### Default variables
UPDATE_VERSION=0
DRY_RUN=0
USING_CONFIG=0
TAG_PREFIX=""
### Parsing arguments, https://stackoverflow.com/a/14203146
# shellcheck disable=SC3010
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
    ;;
  --dry-run)
    DRY_RUN=1
    shift # past argument
    ;;
  * | -h | --help) # unknown option
    shift          # past argument
    help
    exit
    ;;
  esac
done
### Check input arguments and cope
checkArgumentsAndCope
#
###############################################################################
### Main Process START ########################################################
###############################################################################
if [ -z "$(git status --untracked-files=no --porcelain --ignore-submodules)" ]; then
  # Working directory clean excluding untracked files

  getInputTag
  printInputTag

  if test ! -z "$(git tag | grep '${FINAL_TAG}')"; then
    echo " ┍━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┑"
    echo "     Input tag '$BUILD_TYPE$MARKET_VERSION.$BUILD_NUMBER' is exist, delete it? (Y/n)"
    echo " ┕━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┙"
    read -n1 Answer
    if [[ "$Answer" == "Y" || "$Answer" == "y" ]]; then
      git tag -d '${FINAL_TAG}'
    else
      exit
    fi
  fi

  if [ $UPDATE_VERSION -eq 1 ]; then
    if [[ "$INPUT_OS" == "ios" || "$INPUT_OS" == "both" ]]; then
      show_spinner

      IOS_FILE="$(find . -name 'project.pbxproj' | grep -v 'Pods' | grep -v 'node_modules')"
      
      hide_spinner

      if [ -f "$IOS_FILE" ]; then
        oldMarketingVersion="$(grep 'MARKETING_VERSION =' $IOS_FILE | sort | uniq | xargs)"
        oldCurrentProjectVersion="$(grep 'CURRENT_PROJECT_VERSION =' $IOS_FILE | sort | uniq | xargs)"
        cat "$IOS_FILE" | \
        sed -e "s/CURRENT_PROJECT_VERSION = \(.*\);/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/g" | \
        sed -e "s/MARKETING_VERSION = \(.*\);/MARKETING_VERSION = $MARKET_VERSION;/g" \
        > $IOS_FILE.new
        
        if [ $DRY_RUN -eq 1 ]; then
          echo " ┍━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┑"
          echo "    (DEBUG)"
          echo "    iOS: mv $IOS_FILE.new $IOS_FILE"
          echo "       ${oldMarketingVersion}  <== ${MARKET_VERSION}"
          echo "       ${oldCurrentProjectVersion}  <== ${BUILD_NUMBER}"
          echo " ┕━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┙"
          rm $IOS_FILE.new
        else
          mv $IOS_FILE.new $IOS_FILE
          echo " ┍━━ iOS project.pbxproj ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┑"
          echo "    update ${oldMarketingVersion} into ${MARKET_VERSION} ....... [DONE]"
          echo "    update ${oldCurrentProjectVersion} into ${BUILD_NUMBER} ........ [DONE]"
          echo " ┕━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┙"
        fi
      fi
    fi

    if [[ "$INPUT_OS" == "android" || "$INPUT_OS" == "both" ]]; then
      show_spinner

      # thanks to https://stackoverflow.com/a/70940482
      AOS_FILE="$(find . -name 'build.gradle' -exec grep -lirZ 'com.android.application' {} \; | xargs grep -li 'applicationId' | grep -v 'node_modules')"
      
      hide_spinner

      if [ -f "$AOS_FILE" ]; then
        oldVersionName="$(grep 'versionName' $AOS_FILE | sort | uniq | xargs | tr -d '[A-Za-z]-_() ')"
        oldVersionCode="$(grep 'versionCode ' $AOS_FILE | sort | uniq | xargs | tr -d '[A-Za-z]-_() ')"

        getLastTag
        currentTagVersion=$(getParsedVersion "${LAST_TAG}")
        resultcomp=$(vercomp ${currentTagVersion} ${oldVersionName}) # return 0 mean same, 1 mean $currentTagVersion > $oldVersionName, 2 mean $currentTagVersion < $oldVersionName
        if [ $resultcomp -ge 0 ]; then
          cat $AOS_FILE | \
          sed -e "/versionCode =/!s/versionCode .*/versionCode $BUILD_NUMBER/g" | \
          sed -e "s/versionName \".*\"/versionName \"$MARKET_VERSION\"/g" \
          > $AOS_FILE.new
        else
          printGradleVersionNameError
          exit
        fi

        if [ $DRY_RUN -eq 1 ]; then
          echo " ┍━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┑"
          echo "    (DEBUG)"
          echo "    Android: mv $AOS_FILE.new $AOS_FILE"
          echo "         versionName = ${oldVersionName}  <== ${MARKET_VERSION}"
          echo "         versionCode = ${oldVersionCode}  <== ${BUILD_NUMBER}"
          rm $AOS_FILE.new
          echo " ┕━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┙"
        else
          mv $AOS_FILE.new $AOS_FILE
          echo " ┍━━ Android app > build.gradle ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┑"
          echo "    update versionName ${oldVersionName} into ${MARKET_VERSION} ...... [DONE]"
          echo "    update versionCode ${oldVersionCode} into ${BUILD_NUMBER} .......... [DONE]"
          echo " ┕━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┙"
        fi
      fi
    fi
  fi

  Type="${RELEASE_TYPE}"
  OS="${INPUT_OS}"
  REMOTE_REPO="$(git remote -v  | grep 'github.com' | grep '(push)' | awk '{print $1}' | tr -d ' ')"
  if [ $UPDATE_VERSION -eq 1 ]; then
    echo "Commit this version changing, Push tag '${FINAL_TAG}', and Proceed build on Jenkins"
  else
    echo "Push tag '${FINAL_TAG}', and Proceed build on Jenkins"
  fi
  # thanks to https://stackoverflow.com/a/226724
  while true; do
      read -n1 -p "Are you sure? (y/n) " yn
      case $yn in
          [Yy]* )
              echo ""
              CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
              if [ $UPDATE_VERSION -eq 1 -a $DRY_RUN -eq 0 ]; then
                  # Check for untracked files that need to be added
                  UNTRACKED_FILES=$(git ls-files --others --exclude-standard)
                  if [ ! -z "$UNTRACKED_FILES" ]; then
                      git add $UNTRACKED_FILES
                      echo " ┍━━━ adding new files ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┑"
                      echo "    git add new files ..... [DONE]"
                      echo "    Added: $UNTRACKED_FILES"
                      echo " ┕━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┙"
                  fi
                  
                  git commit -am "Update version $Type v${MARKET_VERSION} build($BUILD_NUMBER) for $OS"
                  git push $REMOTE_REPO $CURRENT_BRANCH
                  echo " ┍━━━ commit & push version changed ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┑"
                  echo "    git commit -am \"Update version $Type v${MARKET_VERSION} build($BUILD_NUMBER) for $OS\" ..... [DONE]"
                  echo "    git push $REMOTE_REPO $CURRENT_BRANCH ..... [DONE]"
                  echo " ┕━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┙"
              else
                  # Check for untracked files to display in debug mode
                  UNTRACKED_FILES=$(git ls-files --others --exclude-standard)
                  if [ ! -z "$UNTRACKED_FILES" ]; then
                      echo "(DEBUG) command: git add $UNTRACKED_FILES"
                  fi
                  
                  echo "(DEBUG) command: git commit -am \"Update version $Type v${MARKET_VERSION} build($BUILD_NUMBER) for $OS\""
                  echo "(DEBUG) command: git push ${REMOTE_REPO} ${CURRENT_BRANCH}"
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
  if [ $DRY_RUN -eq 1 ]; then
    echo "(DEBUG) command: git tag -a \"${FINAL_TAG}\""
    echo "(DEBUG) command: git push --tags ${REMOTE_REPO}"
  else
    git tag -a "${FINAL_TAG}" -m "${Type} build for ${OS}"
    git push --tags ${REMOTE_REPO}
    echo " ┍━━━ add tag & push to remote ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┑"
    echo "    git tag -a \"${FINAL_TAG}\" -m \"${Type} build for ${OS}\" ..... [DONE]"
    echo "    git push --tags ${REMOTE_REPO} ..... [DONE]"
    echo " ┕━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┙"
  fi
else 
  # Uncommitted changes error
  printUncommitError
  exit
fi

printResult
###############################################################################
### Main Process E N D ########################################################
###############################################################################
