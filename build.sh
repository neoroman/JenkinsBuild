#!/bin/sh
##
# Script for iOS and Android Release Build on Jenkins
# Written by Henry Kim on 5/22/2018
# Modified by Henry Kim on 2019.06.19 referenced from jenkins-shell-AOS-preRelease.sh
# Modified by Henry Kim on 2021.07.29 for GApp4 and integrations of Android and iOS
# Modifeid by Henry Kim on 2021.09.30 for normalized for most Applicaiton project
#
# Prerequisites for executing this script
#  0. Install Xcode command line tools from "https://developer.apple.com/download/more/" for only iOS
#  1. Install slack from "https://github.com/rockymadden/slack-cli"
#     (also use "brew install rockymadden/rockymadden/slack-cli"),
#     run "slack init", and Enter Slack API token from https://api.slack.com/custom-integrations/legacy-tokens
#  2. Install jq path with "/usr/local/bin/jq" in "/usr/local/bin/slac"
#  3. Install a2ps via HomeBrew, brew install a2ps
#  4. Install gs via HomeBrew, brew install gs
#  5. Install convert(ImageMagick) via HomeBrew, brew install imagemagick
#  6. Install bundletool for Android AAB output since 2021 Aug, brew install bundletool
#
################################################################################
GIT=$(which git)
########
SCRIPT_NAME=$(basename $0)
DEBUGGING=0
PRODUCE_OUTPUT_USE=1 # Exit if output not using for distribution, maybe it's for SonarQube
USING_MAIL=0
WITH_TAG_PUSH=1
GIT_USER="AppDevTeam"
GIT_EMAIL="app.support@company.com"
## Parsing arguments, https://stackoverflow.com/a/14203146
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
  -p | --platform)
    INPUT_OS="$2"
    shift # past argument
    shift # past value
    ;;
  -x | --xcode)
    XCODE_DEVELOPER="$2"
    shift # past argument
    shift # past value
    ;;
  -tp | --toppath)
    TOP_PATH="$2"
    shift # past argument
    shift # past value
    ;;
  -dr | --docroot)
    APP_ROOT_PREFIX="$2"
    shift # past argument
    shift # past value
    ;;
  -ff | --flutterflag)
    FLUTTER_FLAG="$2"
    shift # past argument
    shift # past value
    ;;
  -r | --release)
    IS_RELEASE=1
    RELEASE_TYPE="release"
    shift # past argument
    ;;
  -d | --debug)
    DEBUGGING=1
    shift # past argument
    ;;
  no-output)
    PRODUCE_OUTPUT_USE=0
    shift # past argument
    ;;
  output-exit)
    PRODUCE_OUTPUT_USE=0
    OUTPUT_AND_EXIT_USE=1
    shift # past argument
    ;;
  -ctb | --current-tag-branch)
    LAST_TAG=$($GIT describe --tags)
    if [ -z $LAST_TAG ]; then
      LAST_TAG="master"
    fi
    $GIT fetch --prune
    $GIT branch -r | grep -v '\->' | grep -v 'external/' | while read remote; do $GIT branch --track "${remote#origin/}" "$remote" --force >/dev/null; done
    $GIT fetch --all
    SYNC_TO_BE=$($GIT branch --contains tags/${LAST_TAG} | grep -vi 'head' | tail -1 | tr -d ' *')
    $GIT checkout ${SYNC_TO_BE}
    exit
    ;;
  --without-tag-push)
    WITH_TAG_PUSH=0
    shift # past argument
    ;;
  -pu | --push-to-upstream)
    upstreamUrl="$2"
    if [[ "${upstreamUrl#https://}" != "${upstreamUrl}" ]]; then
      upstreamProtocol="https://"
      tempUrl="${upstreamUrl#https://}"
    elif [[ "${upstreamUrl#http://}" != "${upstreamUrl}" ]]; then
      upstreamProtocol="http://"
      tempUrl="${upstreamUrl#http://}"
    fi
    if [[ "${tempUrl#*:*@}" != "${tempUrl}" ]]; then
      tempAccount="${tempUrl#*:*@}"
      upstreamAccount="${tempUrl#@${tempAccount}}"
      tempUrl="${tempUrl#*:*@}"
    else
      exit 1
    fi
    if [[ "${tempUrl%%/*}" != "${tempUrl}" ]]; then
      upstreamDomain="${tempUrl%%/*}"
    fi
    if [ $($GIT remote -v | grep "${upstreamDomain}" >/dev/null && [ $? -eq 0 ] && echo 1 || echo 0) -eq 0 ]; then
      $GIT remote add external $upstreamUrl
    fi
    $GIT config user.name $GIT_USER
    $GIT config user.email $GIT_EMAIL
    $GIT config core.autocrlf false
    $GIT fetch --prune
    CURRENT_BRANCH=$($GIT rev-parse --abbrev-ref HEAD)
    $GIT branch -r | grep -v '\->' | grep -v 'external/' | grep -v ${CURRENT_BRANCH} | while read remote; do $GIT branch --track "${remote#origin/}" "$remote" --force >/dev/null; done
    $GIT fetch --all
    LAST_TAG=$($GIT describe --tags)
    if [ -z $LAST_TAG ]; then
      LAST_TAG="master"
      SYNC_TO_BE=${LAST_TAG}
    else
      SYNC_TO_BE=$($GIT branch --contains tags/${LAST_TAG} | grep -v 'head' | tail -1 | tr -d ' *')
    fi
    if [[ ! -z "$SYNC_TO_BE" ]]; then
      $GIT checkout ${SYNC_TO_BE}
      $GIT push -u external ${SYNC_TO_BE}
    fi
    if [ $WITH_TAG_PUSH -eq 1 ]; then
      $GIT push -u external --tags -f
    fi
    exit
    ;;
  * | -h | --help) # unknown option
    shift          # past argument
    echo "Usage: $SCRIPT_NAME -p {ios|android} -d"
    echo ""
    echo "optional arguments:"
    echo "   -h, --help        show this help message and exit:"
    echo "   -p {ios,android}, --platform {ios,android}"
    echo "                     assign platform as iOS or Android to processing"
    echo "   -tp {TOP_PATH}, --toppath {TOP_PATH}"
    echo "                     assign TOP_PATH to installing output of iOS or Android"
    echo "   -d, --debug       debugging mode"
    exit
    ;;
  esac
done
################################################################################
if test -z $TOP_PATH; then
  TOP_PATH="Company/Projects"
fi
if [ $DEBUGGING -eq 1 ]; then
  FRONTEND_POINT="http://127.0.0.1"
  USING_SLACK=0
  ### Using Teams or Not, 0=Not Using, 1=Using Teams
  USING_TEAMS_WEBHOOK=0
  TEAMS_WEBHOOK="https://webhook.office.com/webhookb1/57dae0bf-abb2-43df-b7c1-73121c5a75a4@13a84ba8-5a74-4cdf-a639-57395cf71a8f/IncomingWebhook/abb12c1b7cb74044b535c2dfa5031729/a9b785d5-fbf6-4857-add7-dc64d1dd64c1"
  DEBUG_ANDROID_HOME="/usr/local/share/android-sdk"
  if test -z $APP_ROOT_PREFIX; then
    APP_ROOT_PREFIX="/Users/Company/Projects/sites"
  fi
  sudoPassword="qwer1234"
  jenkinsUser="jenkinsUser"
else
  FRONTEND_POINT="https://macmini.company.com"
  USING_SLACK=0
  ### Using Teams or Not, 0=Not Using, 1=Using Teams
  USING_TEAMS_WEBHOOK=0
  TEAMS_WEBHOOK="https://webhook.office.com/webhookb2/57dae0bf-abb2-43df-b7c1-73121c5a75a4@13a84ba8-5a74-4cdf-a639-57395cf71a8f/IncomingWebhook/abb12c1b7cb74044b535c2dfa5031729/a9b785d5-fbf6-4857-add7-dc64d1dd64c1"
  if test -z $APP_ROOT_PREFIX; then
    APP_ROOT_PREFIX="/Library/WebServer/Documents"
  fi
  sudoPassword="qwer1234"
  jenkinsUser="jenkinsUser"
fi
DEBUG_WORKSPACE_IOS="/Users/Company/Projects/app-ios"
DEBUG_WORKSPACE_ANDROID="/Users/Company/Projects/app-android"
SLACK="/usr/local/bin/slack"
SLACK_CHANNEL="#app-distribution"
export ANDROID_HOME="/Users/foo/Library/Android/sdk"
APP_BUNDLE_IDENTIFIER_ANDROID="com.company.mobile"
OUTPUT_PREFIX="AppProject_"
Obfuscation_INPUT_FILE="Obfuscation_File.png"
outputGoogleStoreSuffix="-GoogleStore-release.apk"
outputOneStoreSuffix="-OneStore-release.apk"
INFO_PLIST="Projects/Info.plist"
USING_SCP=0
if [ ! -d ${APP_ROOT_PREFIX}/${TOP_PATH} ]; then
  CURRENT_PATH=$PWD
  mkdir -p ${APP_ROOT_PREFIX}/${TOP_PATH}
  if [ -d ${APP_ROOT_PREFIX}/${TOP_PATH} ]; then
    cd ${APP_ROOT_PREFIX}/${TOP_PATH}
    TOP_PATH_NAME=$(basename $PWD)
    cd ..
    rm -rf $TOP_PATH_NAME
    $GIT clone https://github.com/neoroman/JenkinsAppDistTemplate.git $TOP_PATH_NAME
    chmod 777 ${APP_ROOT_PREFIX}/${TOP_PATH}
  fi
  cd $CURRENT_PATH
fi
################################################################################
if [ ! -d ${APP_ROOT_PREFIX}/${TOP_PATH} ]; then
  echo ""
  echo "Error: please make distribution site, like following:"
  echo "       mkdir -p ${APP_ROOT_PREFIX}/${TOP_PATH}"
  echo ""
  exit 2
fi
################################################################################
# JQ=$(which jq)
if [[ "$JQ" == "" ]]; then
  if [ -f "/usr/local/bin/jq" ]; then
    JQ="/usr/local/bin/jq"
  elif [ -f "/usr/bin/jq" ]; then
    JQ="/usr/bin/jq"
  else
    JQ="/bin/jq"
  fi
fi
jsonConfig="${APP_ROOT_PREFIX}/${TOP_PATH}/config/config.json"
installedOrNot="${APP_ROOT_PREFIX}/${TOP_PATH}/config/.install_not_finished"
if [ -f $jsonConfig ]; then
  if [ $DEBUGGING -eq 1 ]; then
    config=$(cat $jsonConfig | $JQ '.development')
    DEBUG_WORKSPACE_IOS=$(cat $jsonConfig | $JQ '.ios.jenkinsWorkspace' | tr -d '"')
    DEBUG_WORKSPACE_ANDROID=$(cat $jsonConfig | $JQ '.android.jenkinsWorkspace' | tr -d '"')
  else
    config=$(cat $jsonConfig | $JQ '.production')
  fi
  if [ ${TOP_PATH%"$TOP_PATH_NAME"} == ${TOP_PATH} ]; then
    TOP_PATH=$(echo $config | $JQ '.topPath' | tr -d '"')
  fi
  OUTPUT_PREFIX=$(echo $config | $JQ '.outputPrefix' | tr -d '"')
  ANDROID_HOME=$(cat $jsonConfig | $JQ '.android.androidHome' | tr -d '"')
  USING_SLACK=$(test $(cat $jsonConfig | $JQ '.slack.enabled') = true && echo 1 || echo 0)
  SLACK_CHANNEL=$(cat $jsonConfig | $JQ '.slack.channel' | tr -d '"')
  USING_TEAMS_WEBHOOK=$(test $(cat $jsonConfig | $JQ '.teams.enabled') = true && echo 1 || echo 0)
  TEAMS_WEBHOOK=$(cat $jsonConfig | $JQ '.teams.webhook' | tr -d '"')
  APP_BUNDLE_IDENTIFIER_ANDROID=$(cat $jsonConfig | $JQ '.android.packageId' | tr -d '"')
  Obfuscation_INPUT_FILE=$(cat $jsonConfig | $JQ '.android.obfuscationInputFile' | tr -d '"')
  outputGoogleStoreSuffix=$(cat $jsonConfig | $JQ '.android.outputGoogleStoreSuffix' | tr -d '"')
  outputOneStoreSuffix=$(cat $jsonConfig | $JQ '.android.outputOneStoreSuffix' | tr -d '"')
  INFO_PLIST=$(cat $jsonConfig | $JQ '.ios.InfoPlist' | tr -d '"')
  USING_SCP=$(test $(cat $jsonConfig | $JQ '.ssh.enabled') = true && echo 1 || echo 0)
  frontEndPoint=$(echo $config | $JQ '.frontEndPoint' | tr -d '"')
  frontEndProtocol=$(echo $config | $JQ '.frontEndProtocol' | tr -d '"')
  FRONTEND_POINT="$frontEndProtocol://$frontEndPoint"
  ConfigJavaHome=$(cat $jsonConfig | $JQ '.android.javaHome' | tr -d '"')
  USING_MAIL=$(test $(cat $jsonConfig | $JQ '.mail.domesticEnabled') = true && echo 1 || echo 0)
  PROJECT_NAME=$(cat $jsonConfig | $JQ '.ios.projectName' | tr -d '"')
  POD_FILE=$(cat $jsonConfig | $JQ '.ios.podFile' | tr -d '"')
  sudoPassword=$(cat $jsonConfig | $JQ '.ios.sudoPassword' | tr -d '"')
  jenkinsUser=$(cat $jsonConfig | $JQ '.ios.jenkinsUser' | tr -d '"')
  isFlutterEnabled=$(test $(cat $jsonConfig | $JQ '.Flutter.enabled') = true && echo 1 || echo 0)
  FlutterBin=$(cat $jsonConfig | $JQ '.Flutter.path' | tr -d '"')
  ANDROID_APP_PATH=$(cat $jsonConfig | $JQ '.android.appPath' | tr -d '"')
  isReactNativeEnabled=$(test $(cat $jsonConfig | $JQ '.ReactNative.enabled') = true && echo 1 || echo 0)
  if [ $isReactNativeEnabled -eq 1 ]; then
    NodePath=$(cat $jsonConfig | $JQ '.ReactNative.path' | tr -d '"')
    ReactNativeBin="${NodePath}/npm"
    export PATH=${NodePath}:$PATH
  else
    NodePath=""
    ReactNativeBin=""
  fi
fi
################################################################################
if [ -f $installedOrNot ]; then
  echo ""
  echo "Error: please finish setup distribution site, see following url:"
  echo "       ${FRONTEND_POINT}/${TOP_PATH}/setup.php"
  echo ""
  # exit 1
fi
################################################################################
if [ $USING_SCP -eq 1 ]; then
  SSH=$(which ssh)
  SCP=$(which scp)
  SFTP_PORT=$(cat $jsonConfig | $JQ '.ssh.port' | tr -d '"')
  SFTP_ENDPOINT=$(cat $jsonConfig | $JQ '.ssh.endpoint' | tr -d '"')
  SFTP_TARGET=$(cat $jsonConfig | $JQ '.ssh.target' | tr -d '"')
  function checkDirExist() {
    DIR="$1"
    $SSH -p ${SFTP_PORT} ${SFTP_ENDPOINT} test -d ${SFTP_TARGET}/${DIR} && echo 1 || echo 0
    ## Example
    # if [ $(checkDirExist ios_distributions) -eq 1 ]; then
    #   echo "Dir exist: ios_distributions"
    # else
    #   echo "Dir **NOT** exist: ios_distributions"
    # fi
  }
  function checkFileExist() {
    FILE="$1"
    $SSH -p ${SFTP_PORT} ${SFTP_ENDPOINT} test -f ${SFTP_TARGET}/${FILE} && echo 1 || echo 0
    ## Example
    # if [ $(checkFileExist ios_distributions/ExportOptions.plist) -eq 1 ]; then
    #   echo "File exist: ios_distributions/ExportOptions.plist"
    # else
    #   echo "File **NOT** exist: ios_distributions/ExportOptions.plist"
    # fi
  }
  function sendFile() {
    FILE="$1"
    DEST="$2"
    $SCP -pq -P ${SFTP_PORT} ${FILE} ${SFTP_ENDPOINT}:${SFTP_TARGET}/${DEST}/ && echo 1 || echo 0
    ## Example
    # if [ $(sendFile $0 ios_distributions) -eq 1 ]; then
    #   echo "Successfully send file $0 to ios_distributions"
    # else
    #   echo "Failed to send file"
    # fi
  }
  function removeFile() {
    FILE="$1"
    if [ $(checkFileExist ${FILE}) -eq 1 ]; then
      $SSH -p ${SFTP_PORT} ${SFTP_ENDPOINT} rm ${SFTP_TARGET}/${FILE} && echo 1 || echo 0
    else
      echo 0
    fi
    ## Example
    # if [ $(removeFile ios_distributions/$0) -eq 1 ]; then
    #   echo "Successfully remove $0"
    # else
    #   echo "Fail to remove $0"
    # fi
  }
  function makeDir() {
    DIR="$1"
    if [ $(checkDirExist ${DIR}) -eq 0 ]; then
      $SSH -p ${SFTP_PORT} ${SFTP_ENDPOINT} mkdir ${SFTP_TARGET}/${DIR} && echo 1 || echo 0
    else
      echo 1
    fi
    ## Example
    # if [ $(makeDir ios_distributions/abc) -eq 1 ]; then
    #   echo "Successfully make dir ios_distributions/abc"
    # else
    #   echo "Fail to make dir ios_distributions/abc"
    # fi
  }
fi
################################################################################
if test -z "${INPUT_OS}"; then
    ./$SCRIPT_NAME -h
    exit
fi
if [ $DEBUGGING -eq 1 ]; then
  if test -z $WORKSPACE; then
    if [[ "$INPUT_OS" == "ios" ]]; then
      WORKSPACE=$DEBUG_WORKSPACE_IOS
    else
      WORKSPACE=$DEBUG_WORKSPACE_ANDROID
    fi
  fi
elif test -z $WORKSPACE; then
  WORKSPACE="."
fi
###################
if test -z $IS_RELEASE; then
  if [ -d ".git" ]; then
    GIT_LAST_TAG=$(cd $WORKSPACE && $GIT describe --tags)
    if [[ $GIT_LAST_TAG == R* ]]; then
      IS_RELEASE=1
      RELEASE_TYPE="release"
    else
      IS_RELEASE=0
      RELEASE_TYPE="develop"
    fi
  fi
fi
###################
HOSTNAME=$(hostname)
A2PS="/usr/local/bin/a2ps"
GS="/usr/local/bin/gs"
CONVERT="/usr/local/bin/convert"
CURL="/usr/bin/curl"
USING_JSON=1
###################
FILE_TODAY=$(/bin/date "+%y%m%d")
###################
##
################################################################################
################################################################################
## for Android
################################################################################
if [[ "$INPUT_OS" == "android" ]]; then

    if test -z $ConfigJavaHome; then
      export JAVA_HOME="/usr/local/opt/openjdk@8"
    else
      export JAVA_HOME="${ConfigJavaHome}"
    fi
    export ANDROID_SDK_ROOT="${ANDROID_HOME}"
    export ANDROID_HOME="${ANDROID_HOME}"
    #export CLASSPATH="${JAVA_HOME}/libexec/openjdk.jdk/Contents/Home/lib"
    ##### Using Allatori or Not, 0=Not Using, 1=Using Allatori (1차 난독화)
    USING_ALLATORI=$(test $(cat $jsonConfig | $JQ '.android.usingAllatori') = true && echo 1 || echo 0)
    APP_PATH="${TOP_PATH}/android"
    APP_ROOT_SUFFIX="android_distributions"
    APP_ROOT="${APP_ROOT_PREFIX}/${TOP_PATH}/${APP_ROOT_SUFFIX}"
    APP_HTML="${APP_ROOT_PREFIX}/${APP_PATH}"
    ###################
    if test -z $ANDROID_APP_PATH; then
      ANDROID_APP_PATH="app"
    fi
    if [ -f ${WORKSPACE}/${ANDROID_APP_PATH}/version.properties ]; then
      MAJOR=$(grep '^major' ${WORKSPACE}/${ANDROID_APP_PATH}/version.properties | sed -e 's/.*=\([0-9]\)/\1/')
      MINOR=$(grep '^minor' ${WORKSPACE}/${ANDROID_APP_PATH}/version.properties | sed -e 's/.*=\([0-9]\)/\1/')
      POINT=$(grep '^point' ${WORKSPACE}/${ANDROID_APP_PATH}/version.properties | sed -e 's/.*=\([0-9]\)/\1/')
      DEBUG_MAJOR=$(grep '^debug_major' ${WORKSPACE}/${ANDROID_APP_PATH}/version.properties | sed -e 's/.*=\([0-9]\)/\1/')
      DEBUG_MINOR=$(grep '^debug_minor' ${WORKSPACE}/${ANDROID_APP_PATH}/version.properties | sed -e 's/.*=\([0-9]\)/\1/')
      DEBUG_POINT=$(grep '^debug_point' ${WORKSPACE}/${ANDROID_APP_PATH}/version.properties | sed -e 's/.*=\([0-9]\)/\1/')
      DEBUG_LOCAL=$(grep '^debug_local' ${WORKSPACE}/${ANDROID_APP_PATH}/version.properties | sed -e 's/.*=\([0-9]\)/\1/')
    fi
    BUILD_GRADLE_CONFIG="${WORKSPACE}/${ANDROID_APP_PATH}/build.gradle"
    if [ $IS_RELEASE -eq 1 ]; then
      APP_VERSION="${MAJOR}.${MINOR}.${POINT}"
      BUILD_VERSION=$(grep ${APP_BUNDLE_IDENTIFIER_ANDROID} -5 ${BUILD_GRADLE_CONFIG} | grep 'versionCode' | awk 'BEGIN{FS=" "} {print $2}')
    else
      APP_VERSION="${DEBUG_MAJOR}.${DEBUG_MINOR}.${DEBUG_POINT}"
      BUILD_VERSION="${DEBUG_LOCAL}"
    fi
    if [[ "${APP_VERSION}" == ".." ]]; then
      if [ $isFlutterEnabled -eq 1 ]; then
        LOCAL_PROPERTIES="${WORKSPACE}/android/local.properties"
        if [ -f ${LOCAL_PROPERTIES} ]; then
          APP_VERSION=$(grep 'flutter.versionName' ${LOCAL_PROPERTIES} | sed -e "s/flutter.versionName=\([0-9]*.[0-9]*.[0-9]*.*\)/\1/")
          BUILD_VERSION=$(grep 'flutter.versionCode' ${LOCAL_PROPERTIES} | sed -e "s/flutter.versionCode=\(.*\)/\1/")
        else
          APP_VERSION=$(grep 'flutterVersionName' ${BUILD_GRADLE_CONFIG} | grep "flutterVersionName = '"| sed -e "s/flutterVersionName = '\([0-9]*.[0-9]*.[0-9]*.*\)'/\1/" | tr -d "' ")
          BUILD_VERSION=$(grep 'flutterVersionCode' ${BUILD_GRADLE_CONFIG} | grep "flutterVersionCode = '"| sed -e "s/flutterVersionCode = '\(.*\)'/\1/" | tr -d "' ")
        fi
      else
        APP_VERSION=$(grep 'versionName' ${BUILD_GRADLE_CONFIG} | sed -e 's/versionName "\(.*\)"/\1/' | tr -d ' ')
        if [ $isReactNativeEnabled -eq 1 ]; then
          BUILD_VERSION=$(grep 'versionCode' ${BUILD_GRADLE_CONFIG} | head -1 | sed -e 's/versionCode \(.*\)$/\1/' | tr -d ' ')
        else
          BUILD_VERSION=$(grep 'versionCode' ${BUILD_GRADLE_CONFIG} | sed -e 's/versionCode \(.*\)$/\1/' | tr -d ' ')
        fi
      fi
      if [[ "${APP_VERSION}" == ".." ]]; then
          APP_VERSION="1.0.0"
      fi
      if [[ "${BUILD_VERSION}" == "" ]]; then
          BUILD_VERSION="1"
      fi
    fi
    OUTPUT_FOLDER="${APP_ROOT}/${APP_VERSION}"
    HTTPS_PREFIX="${FRONTEND_POINT}/${TOP_PATH}/${APP_ROOT_SUFFIX}/${APP_VERSION}/"
    ###################
    USING_GOOGLESTORE=$(test $(cat $jsonConfig | $JQ '.android.GoogleStore.enabled') = true && echo 1 || echo 0)
    GRADLE_TASK_GOOGLESTORE=$(cat $jsonConfig | $JQ '.android.GoogleStore.taskName' | tr -d '"')
    USING_BUNDLE_GOOGLESTORE=$(test $(cat $jsonConfig | $JQ '.android.GoogleStore.usingBundleAAB') = true && echo 1 || echo 0)
    ###
    USING_ONESTORE=$(test $(cat $jsonConfig | $JQ '.android.OneStore.enabled') = true && echo 1 || echo 0)
    GRADLE_TASK_ONESTORE=$(cat $jsonConfig | $JQ '.android.OneStore.taskName' | tr -d '"')
    USING_BUNDLE_ONESTORE=$(test $(cat $jsonConfig | $JQ '.android.OneStore.usingBundleAAB') = true && echo 1 || echo 0)
    ###
    USING_LIVESERVER=$(test $(cat $jsonConfig | $JQ '.android.LiveServer.enabled') = true && echo 1 || echo 0)
    GRADLE_TASK_LIVESERVER=$(cat $jsonConfig | $JQ '.android.LiveServer.taskName' | tr -d '"')
    USING_BUNDLE_LIVESERVER=$(test $(cat $jsonConfig | $JQ '.android.LiveServer.usingBundleAAB') = true && echo 1 || echo 0)
    ###
    USING_TESTSERVER=$(test $(cat $jsonConfig | $JQ '.android.TestServer.enabled') = true && echo 1 || echo 0)
    GRADLE_TASK_TESTSERVER=$(cat $jsonConfig | $JQ '.android.TestServer.taskName' | tr -d '"')
    USING_BUNDLE_TESTSERVER=$(test $(cat $jsonConfig | $JQ '.android.TestServer.usingBundleAAB') = true && echo 1 || echo 0)
    ###################
    if [ $isFlutterEnabled -eq 1 ]; then
      APK_OUTPUT_PATH="build/app/outputs"
    else
      APK_OUTPUT_PATH="${ANDROID_APP_PATH}/build/outputs"
    fi
    if [ $IS_RELEASE -eq 1 ]; then
      APK_FILE_TITLE="${OUTPUT_PREFIX}${APP_VERSION}(${BUILD_VERSION})_${FILE_TODAY}"

      if [ $isReactNativeEnabled -eq 1 ]; then
        if [ $USING_BUNDLE_GOOGLESTORE -eq 1 ]; then
          FILE_EXTENSION="aab"
          OUTPUT_FOLDER_GOOGLESTORE="${WORKSPACE}/${APK_OUTPUT_PATH}/bundle/release"
        else
          FILE_EXTENSION="apk"
          OUTPUT_FOLDER_GOOGLESTORE="${WORKSPACE}/${APK_OUTPUT_PATH}/apk/release"
        fi
        APK_GOOGLESTORE="${APK_FILE_TITLE}${outputGoogleStoreSuffix%.*}.${FILE_EXTENSION}"

        if [ $USING_BUNDLE_ONESTORE -eq 1 ]; then
          FILE_EXTENSION="aab"
          OUTPUT_FOLDER_ONESTORE="${WORKSPACE}/${APK_OUTPUT_PATH}/bundle/release"
        else
          FILE_EXTENSION="apk"
          OUTPUT_FOLDER_ONESTORE="${WORKSPACE}/${APK_OUTPUT_PATH}/apk/release"
        fi
        APK_ONESTORE="${APK_FILE_TITLE}${outputOneStoreSuffix%.*}.${FILE_EXTENSION}"
      else
        if [ $USING_BUNDLE_GOOGLESTORE -eq 1 ]; then
          FILE_EXTENSION="aab"
          OUTPUT_FOLDER_GOOGLESTORE="${WORKSPACE}/${APK_OUTPUT_PATH}/bundle/${GRADLE_TASK_GOOGLESTORE}Release"
        else
          FILE_EXTENSION="apk"
          OUTPUT_FOLDER_GOOGLESTORE="${WORKSPACE}/${APK_OUTPUT_PATH}/apk/${GRADLE_TASK_GOOGLESTORE}/release"
        fi
        APK_GOOGLESTORE="${APK_FILE_TITLE}${outputGoogleStoreSuffix%.*}.${FILE_EXTENSION}"

        if [ $USING_BUNDLE_ONESTORE -eq 1 ]; then
          FILE_EXTENSION="aab"
          OUTPUT_FOLDER_ONESTORE="${WORKSPACE}/${APK_OUTPUT_PATH}/bundle/${GRADLE_TASK_ONESTORE}Release"
        else
          FILE_EXTENSION="apk"
          OUTPUT_FOLDER_ONESTORE="${WORKSPACE}/${APK_OUTPUT_PATH}/apk/${GRADLE_TASK_ONESTORE}/release"
        fi
        APK_ONESTORE="${APK_FILE_TITLE}${outputOneStoreSuffix%.*}.${FILE_EXTENSION}"
      fi

      Obfuscation_SCREENSHOT="${OUTPUT_PREFIX}${APP_VERSION}(${BUILD_VERSION})_${FILE_TODAY}_Obfuscation.png"
      Obfuscation_OUTPUT_FILE="${OUTPUT_PREFIX}${APP_VERSION}(${BUILD_VERSION})_${FILE_TODAY}_file.png"
    else
      if [ $isReactNativeEnabled -eq 1 ]; then
        if [ $USING_BUNDLE_LIVESERVER -eq 1 ]; then
          FILE_EXTENSION="aab"
          OUTPUT_FOLDER_LIVESERVER="${WORKSPACE}/${APK_OUTPUT_PATH}/bundle/release"
        else
          FILE_EXTENSION="apk"
          OUTPUT_FOLDER_LIVESERVER="${WORKSPACE}/${APK_OUTPUT_PATH}/apk/release"
        fi
        OUTPUT_APK_LIVESERVER="${OUTPUT_PREFIX}${APP_VERSION}.${BUILD_VERSION}_${FILE_TODAY}-${GRADLE_TASK_LIVESERVER}-release.${FILE_EXTENSION}"

        if [ $USING_BUNDLE_TESTSERVER -eq 1 ]; then
          FILE_EXTENSION="aab"
          OUTPUT_FOLDER_TESTSERVER="${WORKSPACE}/${APK_OUTPUT_PATH}/bundle/debug"
        else
          FILE_EXTENSION="apk"
          OUTPUT_FOLDER_TESTSERVER="${WORKSPACE}/${APK_OUTPUT_PATH}/apk/debug"
        fi
        OUTPUT_APK_TESTSERVER="${OUTPUT_PREFIX}${APP_VERSION}.${BUILD_VERSION}_${FILE_TODAY}-${GRADLE_TASK_TESTSERVER}-debug.${FILE_EXTENSION}"
      else
        if [ $USING_BUNDLE_LIVESERVER -eq 1 ]; then
          FILE_EXTENSION="aab"
          OUTPUT_FOLDER_LIVESERVER="${WORKSPACE}/${APK_OUTPUT_PATH}/bundle/${GRADLE_TASK_LIVESERVER}Debug"
        else
          FILE_EXTENSION="apk"
          OUTPUT_FOLDER_LIVESERVER="${WORKSPACE}/${APK_OUTPUT_PATH}/apk/${GRADLE_TASK_LIVESERVER}/debug"
        fi
        OUTPUT_APK_LIVESERVER="${OUTPUT_PREFIX}${APP_VERSION}.${BUILD_VERSION}_${FILE_TODAY}-${GRADLE_TASK_LIVESERVER}-debug.${FILE_EXTENSION}"

        if [ $USING_BUNDLE_TESTSERVER -eq 1 ]; then
          FILE_EXTENSION="aab"
          OUTPUT_FOLDER_TESTSERVER="${WORKSPACE}/${APK_OUTPUT_PATH}/bundle/${GRADLE_TASK_TESTSERVER}/debug"
        else
          FILE_EXTENSION="apk"
          OUTPUT_FOLDER_TESTSERVER="${WORKSPACE}/${APK_OUTPUT_PATH}/apk/${GRADLE_TASK_TESTSERVER}/debug"
        fi
        OUTPUT_APK_TESTSERVER="${OUTPUT_PREFIX}${APP_VERSION}.${BUILD_VERSION}_${FILE_TODAY}-${GRADLE_TASK_TESTSERVER}-debug.${FILE_EXTENSION}"
      fi
    fi
    SLACK_TEXT=""
    MAIL_TEXT=""
    FCM_CONFIG_JSON_PATH="${WORKSPACE}/${ANDROID_APP_PATH}/google-services.json"
    ###################
    if [ ! -d $APP_ROOT ]; then
      mkdir -p $APP_ROOT
      chmod 777 $APP_ROOT
    fi
    if [ ! -d $OUTPUT_FOLDER ]; then
      mkdir -p $OUTPUT_FOLDER
      chmod 777 $OUTPUT_FOLDER
    fi
    if [ $USING_SCP -eq 1 ]; then
      if [ $DEBUGGING -eq 0 ]; then
        NEO2UA_OUTPUT_FOLDER="${TOP_PATH}/${APP_ROOT_SUFFIX}/${APP_VERSION}"
        if [ $(checkDirExist ${NEO2UA_OUTPUT_FOLDER}) -eq 0 ]; then
          # echo "Dir **NOT** exist: ${TOP_PATH}/${APP_ROOT_SUFFIX}/${APP_VERSION}"
          makeDir ${NEO2UA_OUTPUT_FOLDER}
        fi
      fi
    fi
    cd ${WORKSPACE}
    if [ -f ${WORKSPACE}/gradlew ]; then
      chmod +x ${WORKSPACE}/gradlew
    fi
    if [ $isReactNativeEnabled -eq 1 ]; then
      cd ${WORKSPACE}
      $ReactNativeBin install --legacy-peer-deps
      $ReactNativeBin run build
    fi
    ###################
    # Step 1.1: Check 'allatori' 난독화 실행 여부
    if [ $IS_RELEASE -eq 1 -a $USING_ALLATORI -eq 1 ]; then
      ALLATORI_EXEC_PATH="${BUILD_GRADLE_CONFIG}"
      ALLATORI_EXEC_TEMP="${WORKSPACE}/${ANDROID_APP_PATH}/build.gradle.new"
      ALLATORI_EXEC=$(grep 'runAllatori(variant)' ${ALLATORI_EXEC_PATH} | grep -v 'def runAllatori(variant)' | awk 'BEGIN{FS=" "; OFS=""} {print $1$2}')
      if [[ "$ALLATORI_EXEC" = "//"* ]]; then
        sed 's/^\/\/.*runAllatori(variant)/            runAllatori(variant)/' $ALLATORI_EXEC_PATH >$ALLATORI_EXEC_TEMP

        ALLATORI_EXEC=$(grep 'runAllatori(variant)' ${ALLATORI_EXEC_TEMP} | grep -v 'def runAllatori(variant)' | awk 'BEGIN{FS=" "; OFS=""} {print $1$2}')
        if [[ "$ALLATORI_EXEC" = "//"* ]]; then
          sed 's/^.*\/\/runAllatori(variant)/            runAllatori(variant)/' $ALLATORI_EXEC_PATH >$ALLATORI_EXEC_TEMP

          ALLATORI_EXEC=$(grep 'runAllatori(variant)' ${ALLATORI_EXEC_TEMP} | grep -v 'def runAllatori(variant)' | awk 'BEGIN{FS=" "; OFS=""} {print $1$2}')
          if [[ "$ALLATORI_EXEC" != "//"* ]]; then
            mv -f $ALLATORI_EXEC_TEMP $ALLATORI_EXEC_PATH
          fi
        else
          mv -f $ALLATORI_EXEC_TEMP $ALLATORI_EXEC_PATH
        fi
      fi
    fi
    if [ $DEBUGGING -eq 1 ]; then
      if [ $IS_RELEASE -eq 1 ]; then
        if [ ! -f $OUTPUT_FOLDER/$APK_GOOGLESTORE ]; then
          touch $OUTPUT_FOLDER/$APK_GOOGLESTORE
        fi
        if [ ! -f $OUTPUT_FOLDER/$APK_ONESTORE ]; then
          touch $OUTPUT_FOLDER/$APK_ONESTORE
        fi
      else
        if [ ! -f $OUTPUT_FOLDER/$OUTPUT_APK_LIVESERVER ]; then
          touch $OUTPUT_FOLDER/$OUTPUT_APK_LIVESERVER
        fi
        if [ ! -f $OUTPUT_FOLDER/$OUTPUT_APK_TESTSERVER ]; then
          touch $OUTPUT_FOLDER/$OUTPUT_APK_TESTSERVER
        fi
      fi
    else
      gradleBuildKey="assemble"
      flutterBuildKey="apk"
      FILE_EXTENSION="apk"
      if [ $IS_RELEASE -eq 1 ]; then
        ###################
        if [ $USING_GOOGLESTORE -eq 1 ]; then
          # Step 2.1: Build target for GoogleStore
          if [ $USING_BUNDLE_GOOGLESTORE -eq 1 ]; then
            gradleBuildKey="bundle"
            flutterBuildKey="appbundle"
            FILE_EXTENSION="aab"
          fi
          if [ $isFlutterEnabled -eq 1 ]; then
            $FlutterBin pub get

            if test -z $FLUTTER_FLAG; then
              $FlutterBin build ${flutterBuildKey} --flavor ${GRADLE_TASK_GOOGLESTORE}
            else
              $FlutterBin build ${flutterBuildKey} --flavor ${GRADLE_TASK_GOOGLESTORE} ${FLUTTER_FLAG}
            fi
          elif [ $isReactNativeEnabled -eq 1 ]; then
            if [ $USING_BUNDLE_GOOGLESTORE -eq 1 ]; then
              $ReactNativeBin run android_prod_bundle
            else
              $ReactNativeBin run android_prod_apk
            fi
          else
            ./gradlew "${gradleBuildKey}${GRADLE_TASK_GOOGLESTORE}"
          fi
          if [ -d $OUTPUT_FOLDER_GOOGLESTORE -a -f $OUTPUT_FOLDER_GOOGLESTORE/output.json ]; then
            BUILD_APK_GOOGLESTORE=$(cat $OUTPUT_FOLDER_GOOGLESTORE/output.json | $JQ '.[0].apkData.outputFile' | tr -d '"')
          fi
          if test -z "$BUILD_APK_GOOGLESTORE"; then
            if [ -d $OUTPUT_FOLDER_GOOGLESTORE -a -f $OUTPUT_FOLDER_GOOGLESTORE/output-metadata.json ]; then
              BUILD_APK_GOOGLESTORE=$(cat $OUTPUT_FOLDER_GOOGLESTORE/output-metadata.json | $JQ '.elements[0].outputFile' | tr -d '"')
            fi
          fi
          if test -z "$BUILD_APK_GOOGLESTORE"; then
            BUILD_APK_GOOGLESTORE=$(find ${OUTPUT_FOLDER_GOOGLESTORE} -name "*.${FILE_EXTENSION}" -exec basename {} \;)
          fi
          if [ -f $OUTPUT_FOLDER_GOOGLESTORE/$BUILD_APK_GOOGLESTORE ]; then
            mv $OUTPUT_FOLDER_GOOGLESTORE/$BUILD_APK_GOOGLESTORE $OUTPUT_FOLDER/$APK_GOOGLESTORE
            SIZE_GOOGLE_APP_FILE=$(du -sh ${OUTPUT_FOLDER}/${APK_GOOGLESTORE} | awk '{print $1}')
            SLACK_TEXT="${SLACK_TEXT}${HOSTNAME} > ${GRADLE_TASK_GOOGLESTORE} 배포용 다운로드(${SIZE_GOOGLE_APP_FILE}B): ${HTTPS_PREFIX}${APK_GOOGLESTORE}\n"
            MAIL_TEXT="${MAIL_TEXT}${GRADLE_TASK_GOOGLESTORE} 배포용 다운로드(${SIZE_GOOGLE_APP_FILE}B): <a href=${HTTPS_PREFIX}${APK_GOOGLESTORE}>${HTTPS_PREFIX}${APK_GOOGLESTORE}</a><br />"
            if [ $USING_BUNDLE_GOOGLESTORE -eq 1 ]; then
              BUNDLE_TOOL=$(which bundletool)
              if test -z $BUNDLE_TOOL; then
                BUNDLE_TOOL="/opt/homebrew/bin/bundletool"
              fi
              BUNDLE_APK_FILE="$OUTPUT_FOLDER/${APK_GOOGLESTORE%.aab}.apk"
              $BUNDLE_TOOL build-apks --bundle="$OUTPUT_FOLDER/$APK_GOOGLESTORE" --output="$BUNDLE_APK_FILE" --mode=universal
              SIZE_GOOGLE_APP_FILE=$(du -sh ${BUNDLE_APK_FILE} | awk '{print $1}')
            fi
          fi
        fi
        ###################
        if [ $USING_ONESTORE -eq 1 ]; then
          # Step 2.2: Build target for OneStore
          if [ $USING_BUNDLE_ONESTORE -eq 1 ]; then
            gradleBuildKey="bundle"
            flutterBuildKey="appbundle"
            FILE_EXTENSION="aab"
          fi
          if [ $isFlutterEnabled -eq 1 ]; then
            $FlutterBin pub get

            if test -z $FLUTTER_FLAG; then
              $FlutterBin build ${flutterBuildKey} --flavor ${GRADLE_TASK_ONESTORE}
            else
              $FlutterBin build ${flutterBuildKey} --flavor ${GRADLE_TASK_ONESTORE} ${FLUTTER_FLAG}
            fi
          elif [ $isReactNativeEnabled -eq 1 ]; then
            if [ $USING_BUNDLE_ONESTORE -eq 1 ]; then
              $ReactNativeBin run android_prod_bundle
            else
              $ReactNativeBin run android_prod_apk
            fi
          else
            ./gradlew "${gradleBuildKey}${GRADLE_TASK_ONESTORE}"
          fi
          if [ -d $OUTPUT_FOLDER_ONESTORE -a -f $OUTPUT_FOLDER_ONESTORE/output.json ]; then
            BUILD_APK_ONESTORE=$(cat $OUTPUT_FOLDER_ONESTORE/output.json | $JQ '.[0].apkData.outputFile' | tr -d '"')
          fi
          if test -z "$BUILD_APK_ONESTORE"; then
            if [ -d $OUTPUT_FOLDER_ONESTORE -a -f $OUTPUT_FOLDER_ONESTORE/output-metadata.json ]; then
              BUILD_APK_ONESTORE=$(cat $OUTPUT_FOLDER_ONESTORE/output-metadata.json | $JQ '.elements[0].outputFile' | tr -d '"')
            fi
          fi
          if test -z "$BUILD_APK_ONESTORE"; then
            BUILD_APK_ONESTORE=$(find ${OUTPUT_FOLDER_ONESTORE} -name "*.${FILE_EXTENSION}" -exec basename {} \;)
          fi
          if [ -f $OUTPUT_FOLDER_ONESTORE/$BUILD_APK_ONESTORE ]; then
            mv $OUTPUT_FOLDER_ONESTORE/$BUILD_APK_ONESTORE $OUTPUT_FOLDER/$APK_ONESTORE
            SIZE_ONE_APP_FILE=$(du -sh ${OUTPUT_FOLDER}/${APK_ONESTORE} | awk '{print $1}')
            SLACK_TEXT="${SLACK_TEXT}${HOSTNAME} > ${GRADLE_TASK_ONESTORE} 배포용 다운로드(${SIZE_ONE_APP_FILE}B): ${HTTPS_PREFIX}${APK_ONESTORE}\n"
            MAIL_TEXT="${MAIL_TEXT}${GRADLE_TASK_ONESTORE} 배포용 다운로드(${SIZE_ONE_APP_FILE}B): <a href=${HTTPS_PREFIX}${APK_ONESTORE}>${HTTPS_PREFIX}${APK_ONESTORE}</a><br />"
            if [ $USING_BUNDLE_ONESTORE -eq 1 ]; then
              BUNDLE_TOOL=$(which bundletool)
              if test -z $BUNDLE_TOOL; then
                BUNDLE_TOOL="/opt/homebrew/bin/bundletool"
              fi
              BUNDLE_APK_FILE="$OUTPUT_FOLDER/${APK_ONESTORE%.aab}.apk"
              $BUNDLE_TOOL build-apks --bundle="$OUTPUT_FOLDER/$APK_ONESTORE" --output="$BUNDLE_APK_FILE" --mode=universal
              SIZE_ONE_APP_FILE=$(du -sh ${BUNDLE_APK_FILE} | awk '{print $1}')
            fi
          fi
        fi
      else
        ##########
        if [ $USING_LIVESERVER -eq 1 ]; then
          # Step 1.1: Build target for LiveServer
          if [ $USING_BUNDLE_LIVESERVER -eq 1 ]; then
            gradleBuildKey="bundle"
            flutterBuildKey="appbundle"
            FILE_EXTENSION="aab"
          fi
          if [ $isFlutterEnabled -eq 1 ]; then
            $FlutterBin pub get

            if test -z $FLUTTER_FLAG; then
              $FlutterBin build ${flutterBuildKey} --flavor ${GRADLE_TASK_LIVESERVER}
            else
              $FlutterBin build ${flutterBuildKey} --flavor ${GRADLE_TASK_LIVESERVER} ${FLUTTER_FLAG}
            fi
          elif [ $isReactNativeEnabled -eq 1 ]; then
            if [ $USING_BUNDLE_LIVESERVER -eq 1 ]; then
              $ReactNativeBin run android_prod_bundle
            else
              $ReactNativeBin run android_prod_apk
            fi
          else
            ./gradlew "${gradleBuildKey}${GRADLE_TASK_LIVESERVER}"
          fi
          if [ -d $OUTPUT_FOLDER_LIVESERVER -a -f $OUTPUT_FOLDER_LIVESERVER/output.json ]; then
            APK_LIVESERVER=$(cat $OUTPUT_FOLDER_LIVESERVER/output.json | $JQ '.[0].apkData.outputFile' | tr -d '"')
          fi
          if [[ $APK_LIVESERVER == "" ]]; then
            APK_LIVESERVER=$(find ${OUTPUT_FOLDER_LIVESERVER} -name "*.${FILE_EXTENSION}" -exec basename {} \;)
          fi
          if [ -f $OUTPUT_FOLDER_LIVESERVER/$APK_LIVESERVER ]; then
            mv $OUTPUT_FOLDER_LIVESERVER/$APK_LIVESERVER $OUTPUT_FOLDER/$OUTPUT_APK_LIVESERVER
            SIZE_LIVE_APP_FILE=$(du -sh ${OUTPUT_FOLDER}/${OUTPUT_APK_LIVESERVER} | awk '{print $1}')
            SLACK_TEXT="${SLACK_TEXT}${HOSTNAME} > ${GRADLE_TASK_LIVESERVER}(debug)(${SIZE_LIVE_APP_FILE}B): ${HTTPS_PREFIX}${OUTPUT_APK_LIVESERVER}\n"
            MAIL_TEXT="${MAIL_TEXT}${GRADLE_TASK_LIVESERVER}(debug)(${SIZE_LIVE_APP_FILE}B): <a href=${HTTPS_PREFIX}${OUTPUT_APK_LIVESERVER}>${HTTPS_PREFIX}${OUTPUT_APK_LIVESERVER}</a><br />"
            if [ $USING_BUNDLE_LIVESERVER -eq 1 ]; then
              BUNDLE_TOOL=$(which bundletool)
              if test -z $BUNDLE_TOOL; then
                BUNDLE_TOOL="/opt/homebrew/bin/bundletool"
              fi
              BUNDLE_APK_FILE="$OUTPUT_FOLDER/${OUTPUT_APK_LIVESERVER%.aab}.apk"
              $BUNDLE_TOOL build-apks --bundle="$OUTPUT_FOLDER/$OUTPUT_APK_LIVESERVER" --output="$BUNDLE_APK_FILE" --mode=universal
              SIZE_LIVE_APP_FILE=$(du -sh ${BUNDLE_APK_FILE} | awk '{print $1}')
            fi
          fi
        fi
        ##########
        if [ $USING_TESTSERVER -eq 1 ]; then
          USING_GMMSTB_MODE=$(test $(cat $jsonConfig | $JQ '.android.TestServer.usingGMMSTB') = true && echo 1 || echo 0)
          if [ $USING_GMMSTB_MODE -eq 1 ]; then
            # Step 1.2: GMMS TB모드 켜기
            MAIN_ACTIVITY=$(find . -name 'MainActivity.java')
            if [ -f $MAIN_ACTIVITY ]; then
              grep 'Config.IS_TB_GMMS_SERVER =' $MAIN_ACTIVITY
              if [ -n $? ]; then
                sed '/Config.IS_TB_GMMS_SERVER = .*/ a\
                          Config.IS_TB_GMMS_SERVER = true;' $MAIN_ACTIVITY >$MAIN_ACTIVITY.new
                mv -f $MAIN_ACTIVITY.new $MAIN_ACTIVITY
              fi
            fi
          fi
          if [ $USING_BUNDLE_TESTSERVER -eq 1 ]; then
            gradleBuildKey="bundle"
            flutterBuildKey="appbundle"
            FILE_EXTENSION="aab"
          fi
          if [ $isFlutterEnabled -eq 1 ]; then
            $FlutterBin pub get

            if test -z $FLUTTER_FLAG; then
              $FlutterBin build ${flutterBuildKey} --flavor ${GRADLE_TASK_TESTSERVER}
            else
              $FlutterBin build ${flutterBuildKey} --flavor ${GRADLE_TASK_TESTSERVER} ${FLUTTER_FLAG}
            fi
          elif [ $isReactNativeEnabled -eq 1 ]; then
            if [ $USING_BUNDLE_TESTSERVER -eq 1 ]; then
              $ReactNativeBin run android_tb_bundle
            else
              $ReactNativeBin run android_tb_apk
            fi
          else
            ./gradlew "${gradleBuildKey}${GRADLE_TASK_TESTSERVER}"
          fi
          if [ -d $OUTPUT_FOLDER_TESTSERVER -a -f $OUTPUT_FOLDER_TESTSERVER/output.json ]; then
            APK_TESTSERVER=$(cat $OUTPUT_FOLDER_TESTSERVER/output.json | $JQ '.[0].apkData.outputFile' | tr -d '"')
          fi
          if [[ $APK_TESTSERVER == "" ]]; then
            APK_TESTSERVER=$(find ${OUTPUT_FOLDER_TESTSERVER} -name "*.${FILE_EXTENSION}" -exec basename {} \;)
          fi
          if [ -f $OUTPUT_FOLDER_TESTSERVER/$APK_TESTSERVER ]; then
            mv $OUTPUT_FOLDER_TESTSERVER/$APK_TESTSERVER $OUTPUT_FOLDER/$OUTPUT_APK_TESTSERVER
            SIZE_TEST_APP_FILE=$(du -sh ${OUTPUT_FOLDER}/${OUTPUT_APK_TESTSERVER} | awk '{print $1}')
            SLACK_TEXT="${SLACK_TEXT}${HOSTNAME} > ${GRADLE_TASK_TESTSERVER}(debug)(${SIZE_TEST_APP_FILE}B): ${HTTPS_PREFIX}${OUTPUT_APK_TESTSERVER}\n"
            MAIL_TEXT="${MAIL_TEXT}${GRADLE_TASK_TESTSERVER}(debug)(${SIZE_TEST_APP_FILE}B): <a href=${HTTPS_PREFIX}${OUTPUT_APK_TESTSERVER}>${HTTPS_PREFIX}${OUTPUT_APK_TESTSERVER}</a><br />"
            if [ $USING_BUNDLE_TESTSERVER -eq 1 ]; then
              BUNDLE_TOOL=$(which bundletool)
              if test -z $BUNDLE_TOOL; then
                BUNDLE_TOOL="/opt/homebrew/bin/bundletool"
              fi
              BUNDLE_APK_FILE="$OUTPUT_FOLDER/${OUTPUT_APK_TESTSERVER%.aab}.apk"
              $BUNDLE_TOOL build-apks --bundle="$OUTPUT_FOLDER/$OUTPUT_APK_TESTSERVER" --output="$BUNDLE_APK_FILE" --mode=universal
              SIZE_TEST_APP_FILE=$(du -sh ${BUNDLE_APK_FILE} | awk '{print $1}')
            fi
          fi
        fi
      fi
    fi
    ###################
    # Step 2.9: Exit if output not using for distribution, maybe it's for SonarQube
    if [ $PRODUCE_OUTPUT_USE -eq 0 ]; then
      if [ $OUTPUT_AND_EXIT_USE -ne 1 ]; then
        # Exit here with remove all binary outputs
        if [ -f $OUTPUT_FOLDER/$APK_GOOGLESTORE ]; then
          rm -f $OUTPUT_FOLDER/$APK_GOOGLESTORE
        fi
        if [ -f $OUTPUT_FOLDER/$APK_ONESTORE ]; then
          rm -f $OUTPUT_FOLDER/$APK_ONESTORE
        fi
        if [ -f $OUTPUT_FOLDER/$OUTPUT_APK_LIVESERVER ]; then
          rm -f $OUTPUT_FOLDER/$OUTPUT_APK_LIVESERVER
        fi
        if [ -f $OUTPUT_FOLDER/$APK_TESTSERVER ]; then
          rm -f $OUTPUT_FOLDER/$OUTPUT_APK_TESTSERVER
        fi
      fi
      exit
    elif [ $DEBUGGING -eq 0 ]; then
      if [ $USING_SCP -eq 1 ]; then
        ###################
        # Step 2.99: Send file to NAS (app.company.com)
        if [ -f ${OUTPUT_FOLDER}/${APK_GOOGLESTORE} ]; then
          if [ $(sendFile ${OUTPUT_FOLDER}/${APK_GOOGLESTORE} ${NEO2UA_OUTPUT_FOLDER}) -eq 0 ]; then
            #   echo "Failed to send file"
            echo "TODO: **NEED** to resend this file => ${OUTPUT_FOLDER}/${APK_GOOGLESTORE} to ${NEO2UA_OUTPUT_FOLDER}"
          fi
        fi
        if [ -f ${OUTPUT_FOLDER}/${APK_ONESTORE} ]; then
          if [ $(sendFile ${OUTPUT_FOLDER}/${APK_ONESTORE} ${NEO2UA_OUTPUT_FOLDER}) -eq 0 ]; then
            #   echo "Failed to send file"
            echo "TODO: **NEED** to resend this file => ${OUTPUT_FOLDER}/${APK_ONESTORE} to ${NEO2UA_OUTPUT_FOLDER}"
          fi
        fi
        if [ -f ${OUTPUT_FOLDER}/${OUTPUT_APK_LIVESERVER} ]; then
          if [ $(sendFile ${OUTPUT_FOLDER}/${OUTPUT_APK_LIVESERVER} ${NEO2UA_OUTPUT_FOLDER}) -eq 0 ]; then
            #   echo "Failed to send file"
            echo "TODO: **NEED** to resend this file => ${OUTPUT_FOLDER}/${OUTPUT_APK_LIVESERVER} to ${NEO2UA_OUTPUT_FOLDER}"
          fi
        fi
        if [ -f ${OUTPUT_FOLDER}/${OUTPUT_APK_TESTSERVER} ]; then
          if [ $(sendFile ${OUTPUT_FOLDER}/${OUTPUT_APK_TESTSERVER} ${NEO2UA_OUTPUT_FOLDER}) -eq 0 ]; then
            #   echo "Failed to send file"
            echo "TODO: **NEED** to resend this file => ${OUTPUT_FOLDER}/${OUTPUT_APK_TESTSERVER} to ${NEO2UA_OUTPUT_FOLDER}"
          fi
        fi
      fi
    fi
    ###################
    # Step 3: 난독화 증적 자료 생성
    if [ $DEBUGGING -eq 0 ]; then
      USING_OBFUSCATION=$(test $(cat $jsonConfig | $JQ '.android.usingObfuscation') = true && echo 1 || echo 0)
      if [ $USING_OBFUSCATION -eq 1 ]; then
        if [ -f ${OUTPUT_FOLDER}/${APK_GOOGLESTORE} -a -f ${OUTPUT_FOLDER}/${APK_ONESTORE} ]; then
          if [ -f $WORKSPACE/${ANDROID_APP_PATH}/check.sh -a $IS_RELEASE -eq 1 ]; then
            chmod +x $WORKSPACE/${ANDROID_APP_PATH}/check.sh
            cd $WORKSPACE/${ANDROID_APP_PATH} && echo "appdevteam@DESKTOP-ONE NIMGW32 ${WORKSPACE} (${GIT_BRANCH})" >merong.txt
            cd $WORKSPACE/${ANDROID_APP_PATH} && echo "$ ./check.sh -a src" >>merong.txt
            cd $WORKSPACE/${ANDROID_APP_PATH} && ./check.sh -a src >>merong.txt
            cd $WORKSPACE/${ANDROID_APP_PATH} && cat merong.txt | $A2PS -=book -B -q --medium=A4dj --borders=no -o out1.ps && $GS -sDEVICE=png256 -dNOPAUSE -dBATCH -dSAFER -dTextAlphaBits=4 -q -r300x300 -sOutputFile=out2.png out1.ps &&
            cd $WORKSPACE/${ANDROID_APP_PATH} && $CONVERT -trim out2.png $OUTPUT_FOLDER/$Obfuscation_SCREENSHOT
            cd $WORKSPACE/${ANDROID_APP_PATH} && rm -f out[12].png out[12].ps merong.txt

            if [ -f $APP_HTML/$Obfuscation_INPUT_FILE ]; then
              cp -f $APP_HTML/$Obfuscation_INPUT_FILE $OUTPUT_FOLDER/$Obfuscation_OUTPUT_FILE
            fi

            if [ $USING_SCP -eq 1 ]; then
              if [ $(sendFile ${OUTPUT_FOLDER}/${Obfuscation_SCREENSHOT} ${NEO2UA_OUTPUT_FOLDER}) -eq 0 ]; then
                #   echo "Failed to send file"
                echo "TODO: **NEED** to resend this file => ${OUTPUT_FOLDER}/${Obfuscation_SCREENSHOT} to ${NEO2UA_OUTPUT_FOLDER}"
              fi
              if [ $(sendFile ${OUTPUT_FOLDER}/${Obfuscation_OUTPUT_FILE} ${NEO2UA_OUTPUT_FOLDER}) -eq 0 ]; then
                #   echo "Failed to send file"
                echo "TODO: **NEED** to resend this file => ${OUTPUT_FOLDER}/${Obfuscation_OUTPUT_FILE} to ${NEO2UA_OUTPUT_FOLDER}"
              fi
            fi
          fi
        fi
      fi
    fi

################################################################################
################################################################################
## for iOS
################################################################################
elif [[ "$INPUT_OS" == "ios" ]]; then

    XCODE="/usr/bin/xcodebuild"
    if [ ! -f $XCODE ]; then
      echo ""
      echo "Error: cannot find xcodebuild in $XCODE"
      echo ""
      exit
    fi
    # Step 1.01: Change default Xcode version
    if test -z $XCODE_DEVELOPER; then
      XCODE_DEVELOPER="/Applications/Xcode.app/Contents/Developer"
    elif [ ${XCODE_DEVELOPER#"Xcode"} != ${XCODE_DEVELOPER} ]; then
      XCODE_DEVELOPER="/Applications/${XCODE_DEVELOPER}/Contents/Developer"
    fi
    XCODE_DEVELOPER_LAST=${XCODE_DEVELOPER}
    sudo -S xcode-select -s $XCODE_DEVELOPER_LAST <<<"${sudoPassword}"
    ###################
    ZIP="/usr/bin/zip"
    POD="/usr/local/bin/pod"
    ###################
    APP_PATH="${TOP_PATH}/ios"
    APP_ROOT_SUFFIX="ios_distributions"
    if test -z $PROJECT_NAME; then
      echo ""
      echo "Error: please finish setup distribution site, see following url:"
      echo "       ${FRONTEND_POINT}/${TOP_PATH}/setup.php"
      exit
    fi
    ###################
    if [ $isFlutterEnabled -eq 1 ]; then
      export LANG=en_US.UTF-8
      export GEM_PATH="/System/Library/Frameworks/Ruby.framework/Versions/2.6/usr/lib/ruby/gems/2.6.0"
      # $POD repo update
      # POD_LOCK_FILE="${WORKSPACE}/${POD_FILE}.lock"
      # cd $(dirname ${WORKSPACE}/${POD_FILE})
      # rm $POD_LOCK_FILE
      # $POD install
      # cd ${WORKSPACE}
      POD_EXEC_DIR=$(dirname ${POD})
      export PATH=${POD_EXEC_DIR}:$PATH
      $FlutterBin pub get
      $FlutterBin build ios
    elif [ $isReactNativeEnabled -eq 1 ]; then
      cd ${WORKSPACE}
      $ReactNativeBin install --legacy-peer-deps
      $ReactNativeBin run build
    fi
    if test ! -z $(grep 'CFBundleShortVersionString' "${WORKSPACE}/${INFO_PLIST}"); then
      if [ -f "${WORKSPACE}/${INFO_PLIST}" ]; then
        APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${WORKSPACE}/${INFO_PLIST}")
        BUILD_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${WORKSPACE}/${INFO_PLIST}")
      fi
    else
      APP_VERSION="MARKETING_VERSION"
    fi
    if [[ "$APP_VERSION" == *"MARKETING_VERSION"* ]]; then
      XCODE_PBXFILE="${WORKSPACE}/${PROJECT_NAME}.xcodeproj/project.pbxproj"
      APP_VERSION=$(grep 'MARKETING_VERSION' $XCODE_PBXFILE | head -1 | sed -e 's/MARKETING_VERSION = \(.*\);/\1/g' | tr -d ' \t')
      BUILD_VERSION=$(grep 'CURRENT_PROJECT_VERSION = ' $XCODE_PBXFILE | head -1 | sed -e 's/CURRENT_PROJECT_VERSION = \(.*\);/\1/g' | tr -d ' \t')
      if [[ "$APP_VERSION" == *"FLUTTER_BUILD_NAME"* ]]; then
        APP_VERSION=$(grep 'FLUTTER_BUILD_NAME=' ios/Flutter/Generated.xcconfig | head -1 | sed -e 's/FLUTTER_BUILD_NAME=\(.*\)/\1/g' | tr -d ' ')
      fi
      if [[ "$BUILD_VERSION" == *"FLUTTER_BUILD_NUMBER"* ]]; then
        BUILD_VERSION=$(grep 'FLUTTER_BUILD_NUMBER=' ios/Flutter/Generated.xcconfig | head -1 | sed -e 's/FLUTTER_BUILD_NUMBER=\(.*\)/\1/g' | tr -d ' ')
      fi
    fi
    if test -z $BUILD_VERSION; then
      BUILD_VERSION="1"
    fi
    APP_ROOT="${APP_ROOT_PREFIX}/${TOP_PATH}/${APP_ROOT_SUFFIX}"
    APP_HTML="${APP_ROOT_PREFIX}/${APP_PATH}"
    if test -z ${GIT_BRANCH}; then
        GIT_BRANCH=$($GIT rev-parse --abbrev-ref HEAD)
    fi
    LOCAL_BRANCH=$(echo ${GIT_BRANCH} | sed -e 's/.*\/\(.*\)$/\1/')
    DST_ROOT="/tmp/${PROJECT_NAME}/${LOCAL_BRANCH}"
    OUTPUT_FOLDER="${APP_ROOT}/${APP_VERSION}"
    HTTPS_PREFIX="${FRONTEND_POINT}/${TOP_PATH}/${APP_ROOT_SUFFIX}/${APP_VERSION}/"
    ###################
    XCODE_WORKSPACE="${WORKSPACE}/${PROJECT_NAME}.xcworkspace"
    if [ ! -d $XCODE_WORKSPACE ]; then
      echo ""
      echo "Error: cannot find the target workspace, $XCODE_WORKSPACE"
      echo ""
      exit
    fi
    USING_APPSTORE=$(test $(cat $jsonConfig | $JQ '.ios.AppStore.enabled') = true && echo 1 || echo 0)
    if [ $USING_APPSTORE -eq 1 ]; then
      SCHEME_APPSTORE=$(cat $jsonConfig | $JQ '.ios.AppStore.schemeName' | tr -d '"')
      TARGET_APPSTORE=$(cat $jsonConfig | $JQ '.ios.AppStore.targetName' | tr -d '"')
      BUNDLE_ID_APPSTORE=$(cat $jsonConfig | $JQ '.ios.AppStore.bundleId' | tr -d '"')
      BUNDLE_NAME_APPSTORE=$(cat $jsonConfig | $JQ '.ios.AppStore.bundleName' | tr -d '"')
    fi
    USING_ADHOC=$(test $(cat $jsonConfig | $JQ '.ios.Adhoc.enabled') = true && echo 1 || echo 0)
    if [ $USING_ADHOC -eq 1 ]; then
      SCHEME_ADHOC=$(cat $jsonConfig | $JQ '.ios.Adhoc.schemeName' | tr -d '"')
      TARGET_ADHOC=$(cat $jsonConfig | $JQ '.ios.Adhoc.targetName' | tr -d '"')
      BUNDLE_ID_ADHOC=$(cat $jsonConfig | $JQ '.ios.Adhoc.bundleId' | tr -d '"')
      BUNDLE_NAME_ADHOC=$(cat $jsonConfig | $JQ '.ios.Adhoc.bundleName' | tr -d '"')
    fi
    USING_ENTERPRISE=$(test $(cat $jsonConfig | $JQ '.ios.Enterprise.enabled') = true && echo 1 || echo 0)
    if [ $USING_ENTERPRISE -eq 1 ]; then
      SCHEME_ENTER=$(cat $jsonConfig | $JQ '.ios.Enterprise.schemeName' | tr -d '"')
      TARGET_ENTER=$(cat $jsonConfig | $JQ '.ios.Enterprise.targetName' | tr -d '"')
      BUNDLE_ID_ENTER=$(cat $jsonConfig | $JQ '.ios.Enterprise.bundleId' | tr -d '"')
      BUNDLE_NAME_ENTER=$(cat $jsonConfig | $JQ '.ios.Enterprise.bundleName' | tr -d '"')
    fi
    USING_ENTER4WEB=$(test $(cat $jsonConfig | $JQ '.ios.Enterprise4WebDebug.enabled') = true && echo 1 || echo 0)
    if [ $USING_ENTER4WEB -eq 1 ]; then
      SCHEME_ENTER4WEB=$(cat $jsonConfig | $JQ '.ios.Enterprise4WebDebug.schemeName' | tr -d '"')
      TARGET_ENTER4WEB=$(cat $jsonConfig | $JQ '.ios.Enterprise4WebDebug.targetName' | tr -d '"')
      BUNDLE_ID_ENTER4WEB=$(cat $jsonConfig | $JQ '.ios.Enterprise4WebDebug.bundleId' | tr -d '"')
      BUNDLE_NAME_ENTER4WEB=$(cat $jsonConfig | $JQ '.ios.Enterprise4WebDebug.bundleName' | tr -d '"')
    fi
    ###################
    if [ ! -d $DST_ROOT ]; then
      mkdir -p $DST_ROOT
      chmod 777 $DST_ROOT
    fi
    if [ -d $DST_ROOT/Applications ]; then
      rm -rf ${DST_ROOT}/Applications
    fi
    if [ ! -d $APP_ROOT ]; then
      mkdir -p $APP_ROOT
      chmod 777 $APP_ROOT
    fi
    if [ ! -d $OUTPUT_FOLDER ]; then
      mkdir -p $OUTPUT_FOLDER
      chmod 777 $OUTPUT_FOLDER
    fi
    if [ $USING_SCP -eq 1 ]; then
      if [ $DEBUGGING -eq 0 ]; then
        NEO2UA_OUTPUT_FOLDER="${TOP_PATH}/${APP_ROOT_SUFFIX}/${APP_VERSION}"
        if [ $(checkDirExist ${NEO2UA_OUTPUT_FOLDER}) -eq 0 ]; then
          # echo "Dir **NOT** exist: ${TOP_PATH}/${APP_ROOT_SUFFIX}/${APP_VERSION}"
          makeDir ${NEO2UA_OUTPUT_FOLDER}
        fi
      fi
    fi
    ###################
    if [ $isFlutterEnabled -ne 1 -a -f ${WORKSPACE}/${POD_FILE} ]; then
      POD_LOCK_FILE="${WORKSPACE}/${POD_FILE}.lock"
      cd $(dirname ${WORKSPACE}/${POD_FILE})
      export LANG=en_US.UTF-8
      export GEM_PATH="/System/Library/Frameworks/Ruby.framework/Versions/2.6/usr/lib/ruby/gems/2.6.0"
      if [ ! -f $POD_LOCK_FILE ]; then
        if [ $(uname -p) == "arm" ]; then
          arch -x86_64 $POD install
        else
          $POD install
        fi
      else
        if [ $(uname -p) == "arm" ]; then
          arch -x86_64 $POD update
        else
          $POD update
        fi
      fi
    fi
    ###################
    if [ $DEBUGGING -eq 0 ]; then
      # unlock the keychain to make code signing work
      sudo -S su ${jenkinsUser} -c "security unlock-keychain -p "${sudoPassword}" ${HOME}/Library/Keychains/login.keychain" <<<"${sudoPassword}"
    fi
    ###################
    # Step 1.1: Build target for AppStore (We don't need AppStore version for preRelease)
    if [ $DEBUGGING -eq 0 ]; then
      if [ $IS_RELEASE -eq 1 -a $USING_APPSTORE -eq 1 ]; then
        if [ $APP_VERSION != "" ]; then
          VERSION_STRING="${APP_VERSION}(${BUILD_VERSION})"
        else
          VERSION_STRING=""
        fi
        ARCHIVE_FILE="${OUTPUT_PREFIX}${VERSION_STRING}_${FILE_TODAY}.xcarchive"
        ARCHIVE_PATH="${OUTPUT_FOLDER}/${ARCHIVE_FILE}"
        plistConfig="${APP_ROOT_PREFIX}/${TOP_PATH}/config/ExportOptions_AppStore.plist"
        EXPORT_PLIST="${APP_ROOT}/ExportOptions.plist"
        if [ -f $plistConfig ]; then
          cp $plistConfig $EXPORT_PLIST
          chmod 777 $EXPORT_PLIST
          echo ""
          echo "Warning: should modify ``ExportOptions.plist`` for binary(IPK) of App Store"
          echo ""
        fi
        if [ ! -f $EXPORT_PLIST ]; then
          APPSTORE_BUNDLE_IDENTIFIER=$(cat $jsonConfig | $JQ '.ios.AppStore.bundleId' | tr -d '"')
          APPSTORE_TEAM_ID=$(cat $jsonConfig | $JQ '.ios.AppStore.teamId' | tr -d '"')
          APPSTORE_KEY_STRING=$(cat $jsonConfig | $JQ '.ios.AppStore.appKeyString' | tr -d '"')
          APPSTORE_NOTIFICATION_KEY_STRING=$(cat $jsonConfig | $JQ '.ios.AppStore.notificationKeyString' | tr -d '"')
          printf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<"'!'"DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n\t<key>method</key>\n\t<string>app-store</string>\n\t<key>provisioningProfiles</key>\n\t<dict>\n\t\t<key>${APPSTORE_BUNDLE_IDENTIFIER}</key>\n\t\t<string>${APPSTORE_KEY_STRING}</string>\n\t\t<key>${APPSTORE_BUNDLE_IDENTIFIER}.NotificationServiceExtension</key>\n\t\t<string>${APPSTORE_NOTIFICATION_KEY_STRING}</string>\n\t</dict>\n\t<key>signingCertificate</key>\n\t<string>iPhone Distribution</string>\n\t<key>signingStyle</key>\n\t<string>manual</string>\n\t<key>stripSwiftSymbols</key>\n\t<true/>\n\t<key>teamID</key>\n\t<string>${APPSTORE_TEAM_ID}</string>\n\t<key>uploadBitcode</key>\n\t<false/>\n\t<key>uploadSymbols</key>\n\t<true/>\n</dict>\n</plist>\n" \
            >$EXPORT_PLIST
        fi
        $XCODE -workspace "${XCODE_WORKSPACE}" -scheme "${SCHEME_APPSTORE}" -sdk iphoneos -configuration AppStoreDistribution archive -archivePath ${ARCHIVE_PATH}
        $XCODE -exportArchive -archivePath ${ARCHIVE_PATH} -exportOptionsPlist ${EXPORT_PLIST} -exportPath ${OUTPUT_FOLDER}
      fi
      if [ $USING_ADHOC -eq 1 ]; then
        # Step 1.2: Build target for AdHoc
        $XCODE -workspace "${XCODE_WORKSPACE}" -scheme "${SCHEME_ADHOC}" DSTROOT="${DST_ROOT}" -destination "generic/platform=iOS" archive
      fi
      if [ $USING_ENTERPRISE -eq 1 ]; then
        # Step 1.1: Build target for Enterprise
        $XCODE -workspace "${XCODE_WORKSPACE}" -scheme "${SCHEME_ENTER}" DSTROOT="${DST_ROOT}" -destination "generic/platform=iOS" archive
      fi
      if [ $USING_ENTER4WEB -eq 1 ]; then
        # Step 1.1: Build target for Enterprise
        $XCODE -workspace "${XCODE_WORKSPACE}" -scheme "${SCHEME_ENTER4WEB}" DSTROOT="${DST_ROOT}" -destination "generic/platform=iOS" archive
      fi
    fi
    ###################
    # Step 2.0: Prepare
    if [ $APP_VERSION != "" ]; then
      VERSION_STRING="${APP_VERSION}(${BUILD_VERSION})"
    else
      VERSION_STRING=""
    fi
    PAYLOAD_FOLDER="${DST_ROOT}/Applications/Payload"
    if [ $USING_APPSTORE -eq 1 -a $IS_RELEASE -eq 1 ]; then
      ###################
      # Step 2.1: Copy ``App Store'' target from Applications to OUTPUT_FOLDER
      OUTPUT_FILENAME_APPSTORE_SUFFIX=$(cat $jsonConfig | $JQ '.ios.AppStore.fileSuffix' | tr -d '"')
      OUTPUT_FILENAME_APPSTORE="${OUTPUT_PREFIX}${VERSION_STRING}_${FILE_TODAY}${OUTPUT_FILENAME_APPSTORE_SUFFIX}"
      OUTPUT_FILENAME_APPSTORE_IPA="${OUTPUT_FILENAME_APPSTORE}.ipa"
      OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK="${OUTPUT_PREFIX}${VERSION_STRING}_${FILE_TODAY}_IxShieldCheck.png"
      TEMP_APPSTORE_APP_FOLDER="${OUTPUT_FILENAME_APPSTORE}.app"
      OUTPUT_FILE="${OUTPUT_FOLDER}/${TARGET_APPSTORE}"
      if [ -f "${OUTPUT_FILE}" ]; then
        mv $OUTPUT_FILE "${OUTPUT_FOLDER}/${OUTPUT_FILENAME_APPSTORE_IPA}"
        SIZE_STORE_APP_FILE=$(du -sh "${OUTPUT_FOLDER}/${OUTPUT_FILENAME_APPSTORE_IPA}" | awk '{print $1}')

        if [ ! -d $OUTPUT_FOLDER/$TEMP_APPSTORE_APP_FOLDER ]; then
          mkdir $OUTPUT_FOLDER/$TEMP_APPSTORE_APP_FOLDER
        fi
        if [ -f $OUTPUT_FOLDER/DistributionSummary.plist ]; then
          mv -f $OUTPUT_FOLDER/DistributionSummary.plist $OUTPUT_FOLDER/$TEMP_APPSTORE_APP_FOLDER/
        fi
        if [ -f $OUTPUT_FOLDER/ExportOptions.plist ]; then
          mv -f $OUTPUT_FOLDER/ExportOptions.plist $OUTPUT_FOLDER/$TEMP_APPSTORE_APP_FOLDER/
        fi
        if [ -f $OUTPUT_FOLDER/Packaging.log ]; then
          mv -f $OUTPUT_FOLDER/Packaging.log $OUTPUT_FOLDER/$TEMP_APPSTORE_APP_FOLDER/
        fi
        if [ -d $ARCHIVE_PATH ]; then
          if [ -d $OUTPUT_FOLDER/$TEMP_APPSTORE_APP_FOLDER/$ARCHIVE_FILE ]; then
            rm -rf $OUTPUT_FOLDER/$TEMP_APPSTORE_APP_FOLDER/$ARCHIVE_FILE
          fi
          mv -f $ARCHIVE_PATH $OUTPUT_FOLDER/$TEMP_APPSTORE_APP_FOLDER/
        fi
        ###################
        # Step 2.1.1: Run IxShiedCheck script and take screenshot, nees 'a2ps' and 'gs' here...!!!
        if [ $DEBUGGING -eq 0 -a -f $A2PS ]; then
          SPLASH_VIEW="${WORKSPACE}/${PROJECT_NAME}/ObjC/SplashViewController.m"
          SPLASH_TEMP="${WORKSPACE}/${PROJECT_NAME}/ObjC/zzz.m"
          if [ -f $A2PS -a -f $SPLASH_VIEW ]; then
            if [ -f $SPLASH_VIEW ]; then
              sed -e 's/ix_set_debug/IX_SET_DEBUG/g' $SPLASH_VIEW >$SPLASH_TEMP
              mv -f $SPLASH_TEMP $SPLASH_VIEW

              cd $WORKSPACE && echo "MacBook-Pro:ios appDevTeam$ ./IxShieldCheck.sh -i ./${PROJECT_NAME}" >merong.txt
              cd $WORKSPACE && ./IxShieldCheck.sh -i . >>merong.txt
              cd $WORKSPACE && cat merong.txt | $A2PS -=book -B -q --medium=A4dj --borders=no -o out1.ps && $GS -sDEVICE=png256 -dNOPAUSE -dBATCH -dSAFER -dTextAlphaBits=4 -q -r300x300 -sOutputFile=out2.png out1.ps &&
              cd $WORKSPACE && $CONVERT -trim out2.png $OUTPUT_FOLDER/$OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK
              cd $WORKSPACE && rm -f out[12].png out[12].ps merong.txt
            fi
          fi
        fi
      fi
      ###################
      # Step 2.1.2: Remove archive folder
      if [ -d $OUTPUT_FOLDER/$TEMP_APPSTORE_APP_FOLDER ]; then
        rm -rf $OUTPUT_FOLDER/$TEMP_APPSTORE_APP_FOLDER
      fi
    fi
    ###################
    # Step 2.2: Copy ``Ad-Hoc'' target from Applications to OUTPUT_FOLDER
    if [ $USING_ADHOC -eq 1 ]; then
      OUTPUT_FILENAME_ADHOC_SUFFIX=$(cat $jsonConfig | $JQ '.ios.Adhoc.fileSuffix' | tr -d '"')
      OUTPUT_FILENAME_ADHOC="${OUTPUT_PREFIX}${VERSION_STRING}_${FILE_TODAY}${OUTPUT_FILENAME_ADHOC_SUFFIX}"
      OUTPUT_FILENAME_ADHOC_IPA="${OUTPUT_FILENAME_ADHOC}.ipa"
      OUTPUT_FILENAME_ADHOC_PLIST="${OUTPUT_FILENAME_ADHOC}.plist"
      OUTPUT_FILE="${DST_ROOT}/Applications/${OUTPUT_FILENAME_ADHOC_IPA}"
      if [ -d "${DST_ROOT}/Applications/${TARGET_ADHOC}" ]; then
        if [ -d $PAYLOAD_FOLDER ]; then
          rm -rf $PAYLOAD_FOLDER
        fi
        mkdir -p $PAYLOAD_FOLDER
        mv "${DST_ROOT}/Applications/${TARGET_ADHOC}" "${DST_ROOT}/Applications/Payload"
        cd "${DST_ROOT}/Applications"
        $ZIP -r "${OUTPUT_FILE}" Payload
        mv $OUTPUT_FILE "${OUTPUT_FOLDER}/"
        SIZE_ADHOC_APP_FILE=$(du -sh ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ADHOC_IPA} | awk '{print $1}')
      fi
    fi
    ###################
    # Step 2.3: Copy ``Enterprise'' target from Applications to OUTPUT_FOLDER
    if [ $USING_ENTERPRISE -eq 1 ]; then
      OUTPUT_FILENAME_ENTER_SUFFIX=$(cat $jsonConfig | $JQ '.ios.Enterprise.fileSuffix' | tr -d '"')
      OUTPUT_FILENAME_ENTER="${OUTPUT_PREFIX}${VERSION_STRING}_${FILE_TODAY}${OUTPUT_FILENAME_ENTER_SUFFIX}"
      OUTPUT_FILENAME_ENTER_IPA="${OUTPUT_FILENAME_ENTER}.ipa"
      OUTPUT_FILENAME_ENTER_PLIST="${OUTPUT_FILENAME_ENTER}.plist"
      OUTPUT_FILE="${DST_ROOT}/Applications/${OUTPUT_FILENAME_ENTER_IPA}"
      if [ -d "${DST_ROOT}/Applications/${TARGET_ENTER}" ]; then
        if [ -d $PAYLOAD_FOLDER ]; then
          rm -rf $PAYLOAD_FOLDER
        fi
        mkdir -p $PAYLOAD_FOLDER
        mv "${DST_ROOT}/Applications/${TARGET_ENTER}" "${DST_ROOT}/Applications/Payload"
        cd "${DST_ROOT}/Applications"
        $ZIP -r "${OUTPUT_FILE}" Payload
        mv $OUTPUT_FILE "${OUTPUT_FOLDER}/"
        SIZE_ENTER_APP_FILE=$(du -sh ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER_IPA} | awk '{print $1}')
      fi
    fi
    ###################
    # Step 2.3.1: Copy ``Enterprise4WebDebugging'' target from Applications to OUTPUT_FOLDER
    if [ $USING_ENTER4WEB -eq 1 ]; then
      OUTPUT_FILENAME_ENTER4WEB_SUFFIX=$(cat $jsonConfig | $JQ '.ios.Enterprise4WebDebug.fileSuffix' | tr -d '"')
      OUTPUT_FILENAME_ENTER4WEB="${OUTPUT_PREFIX}${VERSION_STRING}_${FILE_TODAY}${OUTPUT_FILENAME_ENTER4WEB_SUFFIX}"
      OUTPUT_FILENAME_ENTER4WEB_IPA="${OUTPUT_FILENAME_ENTER4WEB}.ipa"
      OUTPUT_FILENAME_ENTER4WEB_PLIST="${OUTPUT_FILENAME_ENTER4WEB}.plist"
      OUTPUT_FILE="${DST_ROOT}/Applications/${OUTPUT_FILENAME_ENTER4WEB_IPA}"
      if [ -d "${DST_ROOT}/Applications/${TARGET_ENTER4WEB}" ]; then
        if [ -d $PAYLOAD_FOLDER ]; then
          rm -rf $PAYLOAD_FOLDER
        fi
        mkdir -p $PAYLOAD_FOLDER
        mv "${DST_ROOT}/Applications/${TARGET_ENTER4WEB}" "${DST_ROOT}/Applications/Payload"
        cd "${DST_ROOT}/Applications"
        $ZIP -r "${OUTPUT_FILE}" Payload
        mv $OUTPUT_FILE "${OUTPUT_FOLDER}/"
        SIZE_ENTER4WEB_APP_FILE=$(du -sh ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER4WEB_IPA} | awk '{print $1}')
      fi
    fi
    ###################
    # Step 2.4-1: Exit if output not using for distribution, maybe it's for Jenkins PR Checker
    if [ $PRODUCE_OUTPUT_USE -eq 0 ]; then
      if [ $OUTPUT_AND_EXIT_USE -ne 1 ]; then
        # Exit here with remove all binary outputs
        if [ -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER_IPA} ]; then
          rm -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER_IPA}
        fi
        if [ -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER4WEB_IPA} ]; then
          rm -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER4WEB_IPA}
        fi
        if [ -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ADHOC_IPA} ]; then
          rm -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ADHOC_IPA}
        fi
        if [ -f $OUTPUT_FOLDER/$OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK ]; then
          rm -f $OUTPUT_FOLDER/$OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK
        fi
        if [ -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_APPSTORE_IPA} ]; then
          rm -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_APPSTORE_IPA}
        fi
      fi
      exit
    elif [ $DEBUGGING -eq 1 ]; then
      if [ $USING_ENTERPRISE -eq 1 ]; then
        if [ ! -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER_IPA} ]; then
          touch ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER_IPA}
        fi
      fi
      if [ $USING_ENTER4WEB -eq 1 ]; then
        if [ ! -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER4WEB_IPA} ]; then
          touch ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER4WEB_IPA}
        fi
      fi
      if [ $USING_ADHOC -eq 1 ]; then
        if [ ! -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ADHOC_IPA} ]; then
          touch ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ADHOC_IPA}
        fi
      fi
      if [ $IS_RELEASE -eq 1 -a $USING_APPSTORE -eq 1 ]; then
        if [ ! -f $OUTPUT_FOLDER/$OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK ]; then
          touch $OUTPUT_FOLDER/$OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK
        fi
        if [ ! -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_APPSTORE_IPA} ]; then
          touch ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_APPSTORE_IPA}
        fi
      fi
    elif [ $USING_SCP -eq 1 ]; then
      ###################
      # Step 2.99: Send file to NAS (app.company.com)
      if [ -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_APPSTORE_IPA} ]; then
        if [ $(sendFile ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_APPSTORE_IPA} ${NEO2UA_OUTPUT_FOLDER}) -eq 0 ]; then
          #   echo "Failed to send file"
          echo "TODO: **NEED** to resend this file => ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_APPSTORE_IPA} to ${NEO2UA_OUTPUT_FOLDER}"
        fi
        if [ -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK} ]; then
          if [ $(sendFile ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK} ${NEO2UA_OUTPUT_FOLDER}) -eq 0 ]; then
            #   echo "Failed to send file"
            echo "TODO: **NEED** to resend this file => ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK} to ${NEO2UA_OUTPUT_FOLDER}"
          fi
        fi
      fi
      if [ -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ADHOC_IPA} ]; then
        if [ $(sendFile ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ADHOC_IPA} ${NEO2UA_OUTPUT_FOLDER}) -eq 0 ]; then
          #   echo "Failed to send file"
          echo "TODO: **NEED** to resend this file => ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ADHOC_IPA} to ${NEO2UA_OUTPUT_FOLDER}"
        fi
      fi
      if [ -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER_IPA} ]; then
        if [ $(sendFile ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER_IPA} ${NEO2UA_OUTPUT_FOLDER}) -eq 0 ]; then
          #   echo "Failed to send file"
          echo "TODO: **NEED** to resend this file => ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER_IPA} to ${NEO2UA_OUTPUT_FOLDER}"
        fi
      fi
      if [ -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER4WEB_IPA} ]; then
        if [ $(sendFile ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER4WEB_IPA} ${NEO2UA_OUTPUT_FOLDER}) -eq 0 ]; then
          #   echo "Failed to send file"
          echo "TODO: **NEED** to resend this file => ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER4WEB_IPA} to ${NEO2UA_OUTPUT_FOLDER}"
        fi
      fi
    fi

    ###################
    # Step 2.4: Make plist for mobile downloads to OUTPUT_FOLDER
    if [ $IS_RELEASE -eq 1 ]; then
      VERSION_STRING="v${APP_VERSION}(${BUILD_VERSION})(검증용)"
    elif [ "$APP_VERSION" != "" ]; then
      VERSION_STRING="v${APP_VERSION}.${BUILD_VERSION}"
    else
      VERSION_STRING=""
    fi

    if [ $USING_ADHOC -eq 1 ]; then
      ADHOC_IPA_DOWNLOAD_URL=${HTTPS_PREFIX}${OUTPUT_FILENAME_ADHOC_IPA}
      echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?><"'!'"DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\"><plist version=\"1.0\"><dict><key>items</key><array><dict><key>assets</key><array><dict><key>kind</key><string>software-package</string><key>url</key><string>${ADHOC_IPA_DOWNLOAD_URL}</string></dict></array><key>metadata</key><dict><key>bundle-identifier</key><string>${BUNDLE_ID_ADHOC}</string><key>bundle-version</key><string>${APP_VERSION}</string><key>kind</key><string>software</string><key>title</key><string>${BUNDLE_NAME_ADHOC} ${VERSION_STRING}</string></dict></dict></array></dict></plist>" \
        >$OUTPUT_FOLDER/$OUTPUT_FILENAME_ADHOC_PLIST
      ADHOC_PLIST_ITMS_URL=${HTTPS_PREFIX}${OUTPUT_FILENAME_ADHOC_PLIST}
      if [ $USING_SCP -eq 1 ]; then
        if [ -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ADHOC_PLIST} ]; then
          if [ $(sendFile ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ADHOC_PLIST} ${NEO2UA_OUTPUT_FOLDER}) -eq 0 ]; then
            #   echo "Failed to send file"
            echo "TODO: **NEED** to resend this file => ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ADHOC_PLIST} to ${NEO2UA_OUTPUT_FOLDER}"
          fi
        fi
      fi
    fi
    if [ $USING_ENTERPRISE -eq 1 ]; then
      ENTER_IPA_DOWNLOAD_URL=${HTTPS_PREFIX}${OUTPUT_FILENAME_ENTER_IPA}
      echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?><"'!'"DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\"><plist version=\"1.0\"><dict><key>items</key><array><dict><key>assets</key><array><dict><key>kind</key><string>software-package</string><key>url</key><string>${ENTER_IPA_DOWNLOAD_URL}</string></dict></array><key>metadata</key><dict><key>bundle-identifier</key><string>${BUNDLE_ID_ENTER}</string><key>bundle-version</key><string>${APP_VERSION}</string><key>kind</key><string>software</string><key>title</key><string>${BUNDLE_NAME_ENTER} ${VERSION_STRING}</string></dict></dict></array></dict></plist>" \
        >$OUTPUT_FOLDER/$OUTPUT_FILENAME_ENTER_PLIST
      ENTER_PLIST_ITMS_URL=${HTTPS_PREFIX}${OUTPUT_FILENAME_ENTER_PLIST}
      if [ $USING_SCP -eq 1 ]; then
        if [ -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER_PLIST} ]; then
          if [ $(sendFile ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER_PLIST} ${NEO2UA_OUTPUT_FOLDER}) -eq 0 ]; then
            #   echo "Failed to send file"
            echo "TODO: **NEED** to resend this file => ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER_PLIST} to ${NEO2UA_OUTPUT_FOLDER}"
          fi
        fi
      fi
    fi
    if [ $USING_ENTER4WEB -eq 1 ]; then
      ENTER4WEB_IPA_DOWNLOAD_URL=${HTTPS_PREFIX}${OUTPUT_FILENAME_ENTER4WEB_IPA}
      echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?><"'!'"DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\"><plist version=\"1.0\"><dict><key>items</key><array><dict><key>assets</key><array><dict><key>kind</key><string>software-package</string><key>url</key><string>${ENTER4WEB_IPA_DOWNLOAD_URL}</string></dict></array><key>metadata</key><dict><key>bundle-identifier</key><string>${BUNDLE_ID_ENTER4WEB}</string><key>bundle-version</key><string>${APP_VERSION}</string><key>kind</key><string>software</string><key>title</key><string>${BUNDLE_NAME_ENTER4WEB} ${VERSION_STRING}</string></dict></dict></array></dict></plist>" \
        >$OUTPUT_FOLDER/$OUTPUT_FILENAME_ENTER4WEB_PLIST
      ENTER4WEB_PLIST_ITMS_URL=${HTTPS_PREFIX}${OUTPUT_FILENAME_ENTER4WEB_PLIST}
      if [ $USING_SCP -eq 1 ]; then
        if [ -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER4WEB_PLIST} ]; then
          if [ $(sendFile ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER4WEB_PLIST} ${NEO2UA_OUTPUT_FOLDER}) -eq 0 ]; then
            #   echo "Failed to send file"
            echo "TODO: **NEED** to resend this file => ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER4WEB_PLIST} to ${NEO2UA_OUTPUT_FOLDER}"
          fi
        fi
      fi
    fi
    APPSTORE_TITLE=$(cat $jsonConfig | $JQ '.ios.AppStore.title' | tr -d '"')
    ADHOC_TITLE=$(cat $jsonConfig | $JQ '.ios.Adhoc.title' | tr -d '"')
    ENTER_TITLE=$(cat $jsonConfig | $JQ '.ios.Enterprise.title' | tr -d '"')
    ENTER4WEB_TITLE=$(cat $jsonConfig | $JQ '.ios.Enterprise4WebDebug.title' | tr -d '"')
fi # iOS
###################


###################
# Step 5: Change HTML(index.html) file
if [ $APP_VERSION != "" ]; then
  if [ $IS_RELEASE -eq 1 ]; then
    VERSION_STRING="${APP_VERSION}(${BUILD_VERSION})"
  else
    VERSION_STRING="${APP_VERSION}.${BUILD_VERSION}"
  fi
else
  VERSION_STRING=""
fi  
OUTPUT_FILENAME_ONLY="${OUTPUT_PREFIX}${VERSION_STRING}_${FILE_TODAY}"
OUTPUT_FILENAME_HTML="${OUTPUT_FILENAME_ONLY}.html"
TODAY=$(/bin/date "+%Y.%m.%d")
HTML_INDEX_FILE=${APP_HTML}/index.html
if [[ "$INPUT_OS" == "ios" ]]; then
  HTML_DIST_FILE=${APP_HTML}/dist_ios.html
else
  HTML_DIST_FILE=${APP_HTML}/dist_android.html
fi
if [ $IS_RELEASE -eq 1 ]; then
  VERSION_FOR_HTML="<font color=red>(검증버전)</font>"
  HTML_TITLE="$(/bin/date "+%m")월 검증 버전"
else
  VERSION_FOR_HTML="<font color=red>(테스트버전)</font>"
  HTML_TITLE="테스트 버전"
fi
##############
lastJsonFile=$(find ${APP_ROOT} -name "*.json" -and -not -name "${OUTPUT_FILENAME_ONLY}.json" -exec grep -l '"releaseType": "'${RELEASE_TYPE}'"' {} \; | sort -r | uniq | head -1)
if [ -z $lastBuildDate ]; then
  lastBuildDate="10.day"
fi
if [[ "$lastJsonFile" != "" ]]; then
  if [ -f $lastJsonFile ]; then
    #####################
    appVersion=$(cat $lastJsonFile | $JQ '.appVersion ' | tr -d '"')
    buildVersion=$(cat $lastJsonFile | $JQ '.buildVersion ' | tr -d '"')
    buildTime=$(cat $lastJsonFile | $JQ '.buildTime' | tr -d '"')
    lastBuildDate=$(cat $lastJsonFile | $JQ '.buildTime' | tr -d '"' | sed -e 's/\(.*\) .*/\1/g')
    jenkinsBuildNumber=$(cat $lastJsonFile | $JQ '.buildNumber' | tr -d '"')
    if [[ "$INPUT_OS" == "ios" ]]; then
      gitBrowseUrl=$(cat $jsonConfig | $JQ '.ios.gitBrowseUrl' | tr -d '"')
    else
      gitBrowseUrl=$(cat $jsonConfig | $JQ '.android.gitBrowseUrl' | tr -d '"')
    fi
    if [ ${gitBrowseUrl%"/"} == ${gitBrowseUrl} ]; then
      gitBrowseUrl="${gitBrowseUrl}/"
    fi
    gitUrl=$(echo ${gitBrowseUrl} | sed -e 's/\//\\\//g' | sed -e 's/\./\\./g')
    jiraBrowseUrl=$(cat $jsonConfig | $JQ '.jira.url' | tr -d '"')
    if [ ${jiraBrowseUrl%"/"} == ${jiraBrowseUrl} ]; then
      jiraBrowseUrl="${jiraBrowseUrl}/"
    fi
    jiraUrl=$(echo ${jiraBrowseUrl} | sed -e 's/\//\\\//g' | sed -e 's/\./\\./g')
    jiraProjectKey=$(cat $jsonConfig | $JQ '.jira.projectKey' | tr -d '"')
    #####################
    if [ $IS_RELEASE -eq 1 ]; then
      GIT_LAST_LOG_ORG=$(cd ${WORKSPACE} && $GIT log --date=format:"%Y%m%d" --pretty=format:"<li><span class=\"tit\">%ad</span><p class=\"txt\">%s</p></li>" --no-merges ${GIT_BRANCH} --since="${lastBuildDate}" | sort -r | uniq)
      GIT_LAST_LOG=$(echo ${GIT_LAST_LOG_ORG} | sed -e "s/\(${jiraProjectKey}-[0-9]*\)/<a href=${jiraUrl}\1>\1<\/a>/g")
    else
      if [[ "$INPUT_OS" == "ios" ]]; then
        GIT_LAST_LOG_ORG=$(cd ${WORKSPACE} && $GIT log --pretty=format:"<li><span class=\"tit\">%h▶︎</span><p class=\"txt\">%s by %cn</p></li>" --no-merges ${GIT_BRANCH} --since="${lastBuildDate}")
        GIT_LAST_LOG=$(echo ${GIT_LAST_LOG_ORG} | sed -e "s/\([0-9A-Za-z]*\)▶︎/<a href=${gitUrl}\1>\1<\/a>/g")
        GIT_LAST_LOG=$(echo ${GIT_LAST_LOG} | sed -e "s/\(${jiraProjectKey}-[0-9]*\)/<a href=${jiraUrl}\1>\1<\/a>/g")
      else
        GIT_LAST_LOG_ORG=$(cd ${WORKSPACE} && $GIT log --pretty=format:"<li><span class=\"tit\">%h▶︎</span><p class=\"txt\">%s by %cn</p></li>" --no-merges ${GIT_BRANCH} --since="${lastBuildDate}")
        GIT_LAST_LOG=$(echo ${GIT_LAST_LOG_ORG} | sed -e "s/\([0-9A-Za-z]*\)▶︎/<a href=${gitUrl}\1>\1<\/a>/g")
        GIT_LAST_LOG=$(echo ${GIT_LAST_LOG} | sed -e "s/\(${jiraProjectKey}-[0-9]*\)/<a href=${jiraUrl}\1>\1<\/a>/g")
      fi
    fi
  fi
fi
if test -z $GIT_LAST_LOG ; then
  if test -z $lastBuildDate; then
    lastBuildDate="10.day"
  fi
  GIT_LAST_LOG=$(cd ${WORKSPACE} && $GIT log -3 --pretty=%s --no-merges ${GIT_BRANCH} --since="${lastBuildDate}" | sort | uniq | sed -e 's/\[feature development\]//g' | awk '{printf("&nbsp;&nbsp;&nbsp; %s<br \/>\n", $0)}')
fi
BUILD_TIME=$(/bin/date "+%Y.%m.%d %H:%M")
##################################
# Step 6
##### JSON Generation START ######
if [ -f $JQ -a $USING_JSON -eq 1 ]; then
  OUTPUT_FILENAME_JSON="${OUTPUT_FILENAME_ONLY}.json"

  if [[ "$INPUT_OS" == "ios" ]]; then
    if [ $IS_RELEASE -eq 1 ]; then
      if [ $USING_APPSTORE -eq 1 ]; then
        file1Title="${APPSTORE_TITLE}"
        file1Size="${SIZE_STORE_APP_FILE}B"
        file1Binary="${OUTPUT_FILENAME_APPSTORE_IPA}"
        file1Plist=""
      else
        file1Title=""
        file1Size=""
        file1Binary=""
        file1Plist=""
      fi
      if [ $USING_ADHOC -eq 1 ]; then
        file2Title="${ADHOC_TITLE}"
        file2Size="${SIZE_ADHOC_APP_FILE}B"
        file2Binary="${OUTPUT_FILENAME_ADHOC_IPA}"
        file2Plist="${ADHOC_PLIST_ITMS_URL}"
      else
        file2Title=""
        file2Size=""
        file2Binary=""
        file2Plist=""
      fi
      if [ $USING_ENTERPRISE -eq 1 ]; then
        file3Title="${ENTER_TITLE}"
        file3Size="${SIZE_ENTER_APP_FILE}B"
        file3Binary="${OUTPUT_FILENAME_ENTER_IPA}"
        file3Plist="${ENTER_PLIST_ITMS_URL}"
      else
        file3Title=""
        file3Size=""
        file3Binary=""
        file3Plist=""
      fi
      if [ -f $OUTPUT_FOLDER/$OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK ]; then
        file4Title="IxShieldCheck 화면캡처"
        file4Size="PNG"
        file4Binary="${OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK}"
      else
        file4Title=""
        file4Size=""
        file4Binary=""
      fi
      file4Plist=""
      file5Title=""
      file5Size=""
      file5Binary=""
      file5Plist=""
    else
      if [ $USING_ADHOC -eq 1 ]; then
        file1Title="${ADHOC_TITLE}"
        file1Size="${SIZE_ADHOC_APP_FILE}B"
        file1Binary="${OUTPUT_FILENAME_ADHOC_IPA}"
        file1Plist="${ADHOC_PLIST_ITMS_URL}"
      else
        file1Title=""
        file1Size=""
        file1Binary=""
        file1Plist=""
      fi
      if [ $USING_ENTERPRISE -eq 1 ]; then
        file2Title="${ENTER_TITLE}"
        file2Size="${SIZE_ENTER_APP_FILE}B"
        file2Binary="${OUTPUT_FILENAME_ENTER_IPA}"
        file2Plist="${ENTER_PLIST_ITMS_URL}"
      else
        file2Title=""
        file2Size=""
        file2Binary=""
        file2Plist=""
      fi
      if [ $USING_ENTER4WEB -eq 1 ]; then
        file3Title="${ENTER4WEB_TITLE}"
        file3Size="${SIZE_ENTER4WEB_APP_FILE}B"
        file3Binary="${OUTPUT_FILENAME_ENTER4WEB_IPA}"
        file3Plist="${ENTER4WEB_PLIST_ITMS_URL}"
      else
        file3Title=""
        file3Size=""
        file3Binary=""
        file3Plist=""
      fi
      file4Title=""
      file4Size=""
      file4Binary=""
      file4Plist=""
      file5Title=""
      file5Size=""
      file5Binary=""
      file5Plist=""
    fi
  else
    if [ $IS_RELEASE -eq 1 ]; then
      GOOGLE_TITLE=$(cat $jsonConfig | $JQ '.android.GoogleStore.title' | tr -d '"')
      ONE_TITLE=$(cat $jsonConfig | $JQ '.android.OneStore.title' | tr -d '"')

      if [ $USING_GOOGLESTORE -eq 1 ]; then
        file1Title="${GOOGLE_TITLE}"
        file1Size="${SIZE_GOOGLE_APP_FILE}B"
        file1Binary="${APK_GOOGLESTORE}"
        file1Plist=""
      else
        file1Title=""
        file1Size=""
        file1Binary=""
        file1Plist=""
      fi
      if [ $USING_ONESTORE -eq 1 ]; then
        file2Title="${ONE_TITLE}"
        file2Size="${SIZE_ONE_APP_FILE}B"
        file2Binary="${APK_ONESTORE}"
        file2Plist=""
      else
        file2Title=""
        file2Size=""
        file2Binary=""
        file2Plist=""
      fi
      if [ $USING_OBFUSCATION -eq 1 ]; then
        file3Title="난독화파일_스크린샷"
        file3Size="PNG"
        file3Binary="${Obfuscation_OUTPUT_FILE}"
        file3Plist=""
        file4Title="난독화스크립트_증적자료"
        file4Size="PNG"
        file4Binary="${Obfuscation_SCREENSHOT}"
        file4Plist=""
        file5Title="2차 난독화 APK Signing"
        file5Size="unsigned 버전 업로드 필요"
        file5Binary="android_signing.php?title=${APK_FILE_TITLE}"
        file5Plist=""
      else
        file3Title=""
        file3Size=""
        file3Binary=""
        file3Plist=""
        file4Title=""
        file4Size=""
        file4Binary=""
        file4Plist=""
        file5Title=""
        file5Size=""
        file5Binary=""
        file5Plist=""
      fi
    else
      LIVE_TITLE=$(cat $jsonConfig | $JQ '.android.LiveServer.title' | tr -d '"')
      TEST_TITLE=$(cat $jsonConfig | $JQ '.android.TestServer.title' | tr -d '"')

      file1Title="${LIVE_TITLE}"
      file1Size="${SIZE_LIVE_APP_FILE}B"
      file1Binary="${OUTPUT_APK_LIVESERVER}"
      file1Plist=""
      file2Title="${TEST_TITLE}"
      file2Size="${SIZE_TEST_APP_FILE}B"
      file2Binary="${OUTPUT_APK_TESTSERVER}"
      file2Plist=""
      file3Title=""
      file3Size=""
      file3Binary=""
      file3Plist=""
      file4Title=""
      file4Size=""
      file4Binary=""
      file4Plist=""
      file5Title=""
      file5Size=""
      file5Binary=""
      file5Plist=""
    fi
  fi

  JSON_STRING=$($JQ -n \
    --arg title "${HTML_TITLE}" \
    --arg av "${APP_VERSION}" \
    --arg bv "${BUILD_VERSION}" \
    --arg bn "${BUILD_NUMBER}" \
    --arg bt "${BUILD_TIME}" \
    --arg vk "${VERSION_KEY}" \
    --arg rt "${RELEASE_TYPE}" \
    --arg url_prefix "${HTTPS_PREFIX}" \
    --arg file1_title "${file1Title}" \
    --arg file1_size "${file1Size}" \
    --arg file1_binary "${file1Binary}" \
    --arg file1_plist "${file1Plist}" \
    --arg file2_title "${file2Title}" \
    --arg file2_size "${file2Size}" \
    --arg file2_binary "${file2Binary}" \
    --arg file2_plist "${file2Plist}" \
    --arg file3_title "${file3Title}" \
    --arg file3_size "${file3Size}" \
    --arg file3_binary "${file3Binary}" \
    --arg file3_plist "${file3Plist}" \
    --arg file4_title "${file4Title}" \
    --arg file4_size "${file4Size}" \
    --arg file4_binary "${file4Binary}" \
    --arg file4_plist "${file4Plist}" \
    --arg file5_title "${file5Title}" \
    --arg file5_size "${file5Size}" \
    --arg file5_binary "${file5Binary}" \
    --arg file5_plist "${file5Plist}" \
    --arg git_last_log "${GIT_LAST_LOG}" \
'{"title": $title, "appVersion": $av, "buildVersion": $bv, "versionKey": $vk, '\
'"buildNumber": $bn, "buildTime": $bt, "urlPrefix": $url_prefix, "releaseType": $rt, '\
'"files": [ '\
'{ "title": $file1_title, "size": $file1_size, "file": $file1_binary, "plist": $file1_plist }, '\
'{ "title": $file2_title, "size": $file2_size, "file": $file2_binary, "plist": $file2_plist }, '\
'{ "title": $file3_title, "size": $file3_size, "file": $file3_binary, "plist": $file3_plist }, '\
'{ "title": $file4_title, "size": $file4_size, "file": $file4_binary, "plist": $file4_plist }, '\
'{ "title": $file5_title, "size": $file5_size, "file": $file5_binary, "plist": $file5_plist } ], '\
'"gitLastLog": $git_last_log}')

  echo "${JSON_STRING}" >$OUTPUT_FOLDER/$OUTPUT_FILENAME_JSON
  chmod 777 $OUTPUT_FOLDER/$OUTPUT_FILENAME_JSON

fi
##### JSON Generation END ########
##################################

##################################
if [ $USING_SCP -eq 1 ]; then
  # Step 7: Send JSON file to NAS(app.company.com)
  if [ $DEBUGGING -eq 0 ]; then
    if [ -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_JSON} ]; then
      if [ $(sendFile ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_JSON} ${NEO2UA_OUTPUT_FOLDER}) -eq 0 ]; then
        #   echo "Failed to send file"
        echo "TODO: **NEED** to resend this file => ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_JSON} to ${NEO2UA_OUTPUT_FOLDER}"
      fi
    fi
  fi
fi

USING_HTML=$(test $(echo $config | $JQ '.usingHTML') = true && echo 1 || echo 0)
if [ -d $APP_HTML -a $USING_HTML -eq 1 ]; then
  HTML_OUTPUT="


    <"'!'"-- ${APP_VERSION}(${BUILD_VERSION}) jenkins(${BUILD_NUMBER}) START -->
    <div class=\"large-4 columns\"><a href=\"../remove_html_snippet.php?os=ios&title=${APP_VERSION}($BUILD_VERSION)%20${VERSION_FOR_HTML}%20jenkins(${BUILD_NUMBER})\"><img src=\"../../../download-res/img/mainBtnClose.png\" style=\"position: relative;margin-top: -15px;margin-right: 10px;right: 0px;float: right;\"></a>
    <ul class=\"pricing-table\">
    <li class=\"price\" style=\"background-color:lightblue!important\"><div class=\"rTable\">
      <div class=\"rTableRow\" style=\"display: table-row;margin:0px;\">
      <div class=\"rTableCell\" style=\"display: table-cell;margin-top:0px;text-align: center;vertical-align:center;\"><font color=\"#3083FB\">GApp <b>iOS</b></font> v${APP_VERSION}(${BUILD_VERSION})<br />(<font color=red>검증버전</font>)<br /><font size=1>(${BUILD_TIME})</font></div>
      <div class=\"rTableCell\" style=\"display: table-cell;margin-top:0px;text-align: center;vertical-align:center;\">
        <"'!'"-- RELEASE:::${file1Title} (${file1Size}B): ${HTTPS_PREFIX}${file1Binary} -->
        <span style=\"position: relative;margin: 0px;right: 0px;float: center;font-size:0.5em;\"><a class=\"button secondary radius\" style=\"white-space:nowrap; height:25px; padding-left:10px; padding-right:10px;\" 
        href=\"${HTTPS_PREFIX}${file1Binary}\">$file1Title (${file1Size}B)<img src=\"../../../download-res/img/icons8-downloading_updates.png\" style=\"position: relative;margin-top: -6px;margin-left: 18px;right: 0px;float: right;width:auto;height:1.5em\"></a></span>
        <"'!'"-- RELEASE:::${file2Title} (${file2Size}B): ${HTTPS_PREFIX}${file2Binary} -->
        <span style=\"position: relative;margin: 0px;right: 0px;float: center;font-size:0.5em;\"><a class=\"button secondary radius\" style=\"white-space:nowrap; height:25px; padding-left:10px; padding-right:10px;\" 
        href=\"javascript:appDownloader('${ITMS_PREFIX}${file2Plist}');\">${VERSION_FOR_HTML} $file2Title (${file2Size}B)<img src=\"../../../download-res/img/icons8-downloading_updates.png\" style=\"position: relative;margin-top: -6px;margin-left: 18px;right: 0px;float: right;width:auto;height:1.5em\"></a></span>
        <"'!'"-- RELEASE:::${file3Title} (${file3Size}B): ${HTTPS_PREFIX}${file3Binary} -->
        <span style=\"position: relative;margin: 0px;right: 0px;float: center;font-size:0.5em;\"><a class=\"button secondary radius\" style=\"white-space:nowrap; height:25px; padding-left:20px; padding-right:20px;\" 
        href=\"javascript:appDownloader('${ITMS_PREFIX}${file3Plist}');\">${VERSION_FOR_HTML} Enterprise (${file3Size}B)<img src=\"../../../download-res/img/icons8-downloading_updates.png\" style=\"position: relative;margin-top: -6px;margin-left: 18px;right: 0px;float: right;width:auto;height:1.5em\"></a></span>
        <"'!'"-- RELEASE:::${file4Title} (PNG): ${HTTPS_PREFIX}${file4Binary} -->
        <span style=\"position: relative;margin: 0px;right: 0px;float: center;font-size:0.5em;\"><a class=\"button secondary radius\" style=\"white-space:nowrap; height:25px; padding-left:10px; padding-right:10px;\"
        href=\"${HTTPS_PREFIX}${file4Binary}\" download=\"${file4Binary}\">${file4Title} (PNG)<img src=\"../../../download-res/img/icons8-downloading_updates.png\" style=\"position: relative;margin-top: -6px;margin-left: 18px;right: 0px;float: right;width:auto;height:1.5em\"></a></span>
        <"'!'"-- PRERELEASE_${APP_VERSION}.${BUILD_VERSION}_$(/bin/date "+%y%m%d")_FOR_SAM_LOG -->
      </div>
      </div>
      </div>
    </li>
    <a class=\"price-table-toggle\">+ Show History</a>
    <ul class=\"price-table-features\">
      <li class=\"none\"><div align=left>
      <div align=center><font color=\"#34bebe\"><b>iOS</b></font>&nbsp;&nbsp;v${APP_VERSION}(${BUILD_VERSION}): ${HTML_TITLE}<br />(${BUILD_TIME})</div>
        <hr />
        <br />${GIT_LAST_LOG}
        </div>
      </li>
    </ul>
    </ul>
    </div>
    <"'!'"-- ${APP_VERSION}(${BUILD_VERSION}) jenkins(${BUILD_NUMBER}) END -->


  "

  if [ $IS_RELEASE -eq 1 ]; then
    TEMP_FILE_BASENAME="temp_release"
  else
    TEMP_FILE_BASENAME="temp"
  fi
  echo "$HTML_OUTPUT" >$APP_HTML/$TEMP_FILE_BASENAME.html
  if [ -f $HTML_INDEX_FILE ]; then
    cp -f $HTML_INDEX_FILE $HTML_INDEX_FILE.bak
    cat $HTML_INDEX_FILE.bak | sed $'s/^M/\\\n/g' >$HTML_INDEX_FILE
    cp -f $HTML_DIST_FILE $HTML_DIST_FILE.bak
    cat $HTML_DIST_FILE.bak | sed $'s/^M/\\\n/g' >$HTML_DIST_FILE

    cd $APP_HTML
    if [[ "$INPUT_OS" == "ios" ]]; then
      if [ $IS_RELEASE -eq 1 ]; then
        sed '/NEW_UPLOAD_COLUMN_HERE/r temp_release.html' dist_ios.html >dist_ios2.html
      else
        sed '/NEW_UPLOAD_COLUMN_HERE/r temp.html' dist_ios.html >dist_ios2.html
      fi
      mv -f dist_ios2.html dist_ios.html
      chmod 777 index.html
      chmod 777 dist_ios.html
      if [ $USING_SCP -eq 1 ]; then
        if [ $DEBUGGING -eq 0 ]; then
          if [ $(sendFile ${APP_HTML}/dist_ios.html ${APP_PATH}) -eq 0 ]; then
            #   echo "Failed to send file"
            echo "TODO: **NEED** to resend this file => ${APP_HTML}/dist_ios.html to ${APP_PATH}"
          fi
        fi
      fi
    else
      if [ $IS_RELEASE -eq 1 ]; then
        sed '/NEW_UPLOAD_COLUMN_HERE/r temp_release.html' dist_android.html >dist_android2.html
      else
        sed '/NEW_UPLOAD_COLUMN_HERE/r temp.html' dist_android.html >dist_android2.html
      fi
      mv -f dist_android2.html dist_android.html
      chmod 777 index.html
      chmod 777 dist_android.html
      if [ $USING_SCP -eq 1 ]; then
        if [ $DEBUGGING -eq 0 ]; then
          if [ $(sendFile ${APP_HTML}/dist_android.html ${APP_PATH}) -eq 0 ]; then
            #   echo "Failed to send file"
            echo "TODO: **NEED** to resend this file => ${APP_HTML}/dist_android.html to ${APP_PATH}"
          fi
        fi
      fi
    fi
    ##################################
    if [ $USING_SCP -eq 1 ]; then
      if [ $DEBUGGING -eq 0 ]; then
        if [ $(sendFile ${APP_HTML}/index.html ${APP_PATH}) -eq 0 ]; then
          #   echo "Failed to send file"
          echo "TODO: **NEED** to resend this file => ${APP_HTML}/index.html to ${APP_PATH}"
        fi
      fi
    fi
    if [ -f $TEMP_FILE_BASENAME.html ]; then
      cp -f $TEMP_FILE_BASENAME.html $OUTPUT_FOLDER/zzz_$OUTPUT_FILENAME_HTML
      ##################################
      if [ $USING_SCP -eq 1 ]; then
        if [ $DEBUGGING -eq 0 ]; then
          if [ $(sendFile ${OUTPUT_FOLDER}/zzz_${OUTPUT_FILENAME_HTML} ${NEO2UA_OUTPUT_FOLDER}) -eq 0 ]; then
            #   echo "Failed to send file"
            echo "TODO: **NEED** to resend this file => ${OUTPUT_FOLDER}/zzz_${OUTPUT_FILENAME_HTML} to ${NEO2UA_OUTPUT_FOLDER}"
          fi
        fi
      fi
    fi
  fi
else
  if [[ "$INPUT_OS" == "ios" ]]; then
    touch $APP_HTML/dist_ios.html
    chmod 777 $APP_HTML/dist_ios.html
  else
    touch $APP_HTML/dist_android.html
    chmod 777 $APP_HTML/dist_android.html
  fi
  chmod 777 $APP_HTML/index.html
  touch $OUTPUT_FOLDER/zzz_$OUTPUT_FILENAME_HTML
  ##################################
  if [ $USING_SCP -eq 1 ]; then
    if [ $DEBUGGING -eq 0 ]; then
      if [ $(sendFile ${OUTPUT_FOLDER}/zzz_${OUTPUT_FILENAME_HTML} ${NEO2UA_OUTPUT_FOLDER}) -eq 0 ]; then
        #   echo "Failed to send file"
        echo "TODO: **NEED** to resend this file => ${OUTPUT_FOLDER}/zzz_${OUTPUT_FILENAME_HTML} to ${NEO2UA_OUTPUT_FOLDER}"
      fi
    fi
  fi
fi

if [ -f $OUTPUT_FOLDER/$OUTPUT_FILENAME_JSON ]; then
  cd $APP_ROOT
  SHORT_GIT_LOG="${HTML_TITLE}"
  ###########
  if [ $IS_RELEASE -eq 1 ]; then
    THEME_COLOR="619FFA"
    VERSION_STRING="v${APP_VERSION}(${BUILD_VERSION}) "
  else
    THEME_COLOR="5DF0D1"
    VERSION_STRING="v${APP_VERSION}.${BUILD_VERSION} "
  fi
  ###########
  if [ -f "${APP_ROOT_PREFIX}/${TOP_PATH}/lang/default.json" ]; then
    language=$(cat "${APP_ROOT_PREFIX}/${TOP_PATH}/lang/default.json" | $JQ '.LANGUAGE' | tr -d '"')
    lang_file="${APP_ROOT_PREFIX}/${TOP_PATH}/lang/lang_${language}.json"
    CLIENT_NAME=$(cat $lang_file | $JQ '.client.title' | tr -d '"')
    APP_NAME=$(cat $lang_file | $JQ '.app.name' | tr -d '"')
    CLIENT_TITLE=$(cat $lang_file | $JQ '.title.h2_client' | tr -d '"')
    SITE_URL=$(cat $lang_file | $JQ '.client.short_url' | tr -d '"')
    SITE_ID=$(cat $jsonConfig | $JQ '.users.app.userId' | tr -d '"')
    SITE_PW=$(cat $jsonConfig | $JQ '.users.app.password' | tr -d '"')
    SITE_ID_PW="${SITE_ID}/${SITE_PW}"
    QC_ID=$(cat $jsonConfig | $JQ '.users.qc.userId' | tr -d '"')
    QC_PW=$(cat $jsonConfig | $JQ '.users.qc.password' | tr -d '"')
    QC_ID_PW="${QC_ID}/${QC_PW}"
  else
    CLIENT_NAME="Company Projects"
    APP_NAME="SomeApp"
    CLIENT_TITLE="{고객사} 앱 배포"
    SITE_URL="https://bit.ly/client_site"
    SITE_ID_PW="app/qwer1234"
    QC_ID_PW="qc/insu1234"
  fi
  OTHER_BUILE_ENV=""
  if [ $isFlutterEnabled -eq 1 ]; then
    BUILD_COMMAND=$FlutterBin
  elif [ $isReactNativeEnabled -eq 1 ]; then
    BUILD_COMMAND="./android/gradlew"
    OTHER_BUILE_ENV="node "$(node --version)
    OTHER_BUILE_ENV="${OTHER_BUILE_ENV}\nnpm v"$(npm --version)
    OTHER_BUILE_ENV="${OTHER_BUILE_ENV}\n"
  else
    BUILD_COMMAND="./gradlew"
  fi
  ###########
  ###################
  # Step 4: Send build result to Slack
  if [ $USING_SLACK -eq 1 ]; then
    jsonDefaultLang="${APP_ROOT_PREFIX}/${TOP_PATH}/lang/default.json"
    if [ -f "${jsonDefaultLang}" ]; then
      language=$(cat "${jsonDefaultLang}" | $JQ '.LANGUAGE' | tr -d '"')
      lang_file="${APP_ROOT_PREFIX}/${TOP_PATH}/lang/lang_${language}.json"
      SITE_URL=$(cat $lang_file | $JQ '.client.short_url' | tr -d '"')
      SITE_ID=$(cat $jsonConfig | $JQ '.users.app.userId' | tr -d '"')
      SITE_PW=$(cat $jsonConfig | $JQ '.users.app.password' | tr -d '"')
      SITE_ID_PW="${SITE_ID}/${SITE_PW}"
      SLACK_WEBHOOK=$(cat $jsonConfig | $JQ '.slack.webhook' | tr -d '"')
    fi
    if [[ "$INPUT_OS" == "ios" ]]; then
      ITMS_PREFIX="itms-services://?action=download-manifest&url="
      SLACK_INSTALL_STR=""
      SLACK_APPSTORE_DOWN_STR=""
      SLACK_APPSTORE_ATTACH_STR=""
      if [ $USING_APPSTORE -eq 1 ]; then
        SLACK_INSTALL_STR="${ENTER_TITLE} 및 ${ADHOC_TITLE} 설치: ${SITE_URL}\n(사이트 접근 ID/PW는 ${SITE_ID_PW})\n\n"
        SLACK_APPSTORE_DOWN_STR="${APPSTORE_TITLE} IPA 다운로드(${SIZE_STORE_APP_FILE}B): ${HTTPS_PREFIX}${OUTPUT_FILENAME_APPSTORE_IPA}\n"
        SLACK_APPSTORE_ATTACH_STR="첨부파일: ${HTTPS_PREFIX}${OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK}\n"
      fi
      SLACK_ADHOC_DOWN_STR=""
      SLACK_ADHOC_ITMS_STR=""
      if [ $USING_ADHOC -eq 1 ]; then
        SLACK_ADHOC_DOWN_STR="${ADHOC_TITLE}(${SIZE_ADHOC_APP_FILE}B): ${HTTPS_PREFIX}${OUTPUT_FILENAME_ADHOC_IPA}\n"
        SLACK_ADHOC_ITMS_STR="${ADHOC_TITLE}(${SIZE_ADHOC_APP_FILE}B): ${ITMS_PREFIX}${ADHOC_PLIST_ITMS_URL}]n"
      fi
      SLACK_ENTER_DOWN_STR=""
      SLACK_ENTER_ITMS_STR=""
      if [ $USING_ENTERPRISE -eq 1 ]; then
        SLACK_ENTER_DOWN_STR="${ENTER_TITLE}(${SIZE_ENTER_APP_FILE}B): ${HTTPS_PREFIX}${OUTPUT_FILENAME_ENTER_IPA}\n"
        SLACK_ENTER_ITMS_STR="${ENTER_TITLE}(${SIZE_ENTER_APP_FILE}B): ${ITMS_PREFIX}${ENTER_PLIST_ITMS_URL}\n"
      fi
      if [[ "$SLACK_WEBHOOK" == "null" ]]; then
        if [ $IS_RELEASE -eq 0 ]; then
          $SLACK chat send --text "${HOSTNAME} > ${SLACK_ADHOC_DOWN_STR}${HOSTNAME} > ${SLACK_ENTER_DOWN_STR}" --channel ${SLACK_CHANNEL} --pretext "${HOSTNAME} > iOS Build output files for ${GIT_BRANCH} - ${CHANGE_TITLE}(commit: ${GIT_COMMIT}) => ${BUILD_URL}" --color good
          $SLACK chat send --text "${HOSTNAME} > ${SLACK_ADHOC_ITMS_STR}${HOSTNAME} > ${SLACK_ENTER_ITMS_STR}" --channel ${SLACK_CHANNEL} --pretext "${HOSTNAME} > iOS Uploaded IPA/Plist files for ${GIT_BRANCH} - ${CHANGE_TITLE}(commit: ${GIT_COMMIT}) => ${BUILD_URL}" --color good
        else
          $SLACK chat send --text "${HOSTNAME} > ${SLACK_INSTALL_STR}${HOSTNAME} > ${SLACK_APPSTORE_DOWN_STR}${HOSTNAME} > ${SLACK_ADHOC_DOWN_STR}${HOSTNAME} > ${SLACK_ENTER_DOWN_STR}\n${HOSTNAME} > ${SLACK_APPSTORE_ATTACH_STR}" --channel ${SLACK_CHANNEL} --pretext "${HOSTNAME} > iOS Build output files for ${GIT_BRANCH} - ${CHANGE_TITLE}(commit: ${GIT_COMMIT}) => ${BUILD_URL}" --color good
          $SLACK chat send --text "${HOSTNAME} > ${SLACK_ADHOC_ITMS_STR}${HOSTNAME} > ${SLACK_ENTER_ITMS_STR}" --channel ${SLACK_CHANNEL} --pretext "${HOSTNAME} > iOS Uploaded IPA/Plist files for ${GIT_BRANCH} - ${CHANGE_TITLE}(commit: ${GIT_COMMIT}) => ${BUILD_URL}" --color good
        fi
        $SLACK chat send --text "${HOSTNAME} > ${FRONTEND_POINT}/${TOP_PATH}/dist_uaqa.php > Go iOS" --channel ${SLACK_CHANNEL} --pretext "${HOSTNAME} > iOS Download Web Page for ${SHORT_GIT_LOG}" --color good
      else
        GIT_BROWSER_URL=$(cat $jsonConfig | $JQ '.ios.gitBrowseUrl' | tr -d '"')
        BLOCK_TITLE="iOS 테스트"
        if [ $IS_RELEASE -eq 1 -a $USING_APPSTORE -eq 1 ]; then
          BLOCK_TITLE="iOS 검증용"
          BLOCK_SECTION="${BLOCK_SECTION}                {
                  \"type\": \"section\",
                  \"text\": {
                      \"type\": \"mrkdwn\",
                      \"text\": \"${VERSION_STRING} ${SLACK_APPSTORE_DOWN_STR}\"
                  }
              },"
          BLOCK_SECTION="${BLOCK_SECTION}                {
                  \"type\": \"section\",
                  \"text\": {
                      \"type\": \"mrkdwn\",
                      \"text\": \"${VERSION_STRING} ${SLACK_APPSTORE_ATTACH_STR}\"
                  }
              },"
        fi
        if [ $USING_ADHOC -eq 1 ]; then
          BLOCK_SECTION="${BLOCK_SECTION}                {
              \"type\": \"section\",
              \"text\": {
                  \"type\": \"mrkdwn\",
                  \"text\": \"${VERSION_STRING} ${SLACK_ADHOC_DOWN_STR}\"
              }
          },"
        fi
        if [ $USING_ENTERPRISE -eq 1 ]; then
          BLOCK_SECTION="${BLOCK_SECTION}                {
              \"type\": \"section\",
              \"text\": {
                  \"type\": \"mrkdwn\",
                  \"text\": \"${VERSION_STRING} ${SLACK_ENTER_DOWN_STR}\"
              }
          },"
        fi
        SLACK_JSON_ALL="{
            \"channel\": \"${SLACK_CHANNEL}\", 
            \"username\": \"Jenkins(자동배포)\", 
            \"icon_emoji\": \":bowtie:\",
            \"blocks\": [
                {
                    \"type\": \"header\",
                    \"text\": {
                        \"type\": \"plain_text\",
                        \"text\": \"${HOSTNAME} > ${BLOCK_TITLE} ${APP_NAME}.App\",
                        \"emoji\": true
                    }
                },
                {
                    \"type\": \"section\",
                    \"text\": {
                        \"type\": \"mrkdwn\",
                        \"text\": \"${CLIENT_NAME} ${APP_NAME} 앱: Jenkins(${BUILD_NUMBER}) - ${GIT_BRANCH} (commit: ${GIT_COMMIT})\"
                    },
                    \"accessory\": {
                        \"type\": \"button\",
                        \"text\": {
                            \"type\": \"plain_text\",
                            \"text\": \"사이트 링크\",
                            \"emoji\": true
                        },
                        \"value\": \"click_me_123\",
                        \"url\": \"${GIT_BROWSER_URL}/${GIT_COMMIT}\",
                        \"action_id\": \"button-action\"
                    }
                },
                ${BLOCK_SECTION}
                {
                    \"type\": \"section\",
                    \"text\": {
                        \"type\": \"mrkdwn\",
                        \"text\": \"설치 및 다운로드 사이트: ${CLIENT_TITLE} ${SITE_URL} (ID/PW: ${SITE_ID_PW})\"
                    },
                    \"accessory\": {
                        \"type\": \"button\",
                        \"text\": {
                            \"type\": \"plain_text\",
                            \"text\": \"사이트 링크\",
                            \"emoji\": true
                        },
                        \"value\": \"click_me_123\",
                        \"url\": \"${SITE_URL}\",
                        \"action_id\": \"button-action\"
                    }
                }, 
                {
                    \"type\": \"section\",
                    \"text\": {
                        \"type\": \"mrkdwn\",
                        \"text\": \"배포 웹사이트 (내부 QA용): 내부 QA 사이트 (ID/PW: ${QC_ID_PW})\"
                    },
                    \"accessory\": {
                        \"type\": \"button\",
                        \"text\": {
                            \"type\": \"plain_text\",
                            \"text\": \"사이트 링크\",
                            \"emoji\": true
                        },
                        \"value\": \"click_me_123\",
                        \"url\": \"${FRONTEND_POINT}/${TOP_PATH}/ios/dist_ios.php\",
                        \"action_id\": \"button-action\"
                    }
                }, 
                {
                    \"type\": \"section\",
                    \"text\": {
                        \"type\": \"mrkdwn\",
                        \"text\": \"빌드 환경: ${OTHER_BUILE_ENV}$($XCODE -version | tr -d '\n'), CocoaPod $($POD --version)\"
                    }
                }, 
                {
                    \"type\": \"section\",
                    \"text\": {
                        \"type\": \"mrkdwn\",
                        \"text\": \"Jenkin 작업 결과: Jenkin 사이트\"
                    },
                    \"accessory\": {
                        \"type\": \"button\",
                        \"text\": {
                            \"type\": \"plain_text\",
                            \"text\": \"바로가기\",
                            \"emoji\": true
                        },
                        \"value\": \"click_me_123\",
                        \"url\": \"${BUILD_URL}\",
                        \"action_id\": \"button-action\"
                    }
                }
            ]
        }"
        $CURL -H "Content-Type: application/json" -d "${SLACK_JSON_ALL}" $SLACK_WEBHOOK
      fi
    elif [[ "$INPUT_OS" == "android" ]]; then
      if [[ "$SLACK_WEBHOOK" == "null" ]]; then
        if [ $IS_RELEASE -eq 1 ]; then
          if [ $USING_OBFUSCATION -eq 1 ]; then
            $SLACK chat send --text "${HOSTNAME} > 안드로이드 1차 난독화 버전 전달합니다.\n\n\nAPK 설치: ${SITE_URL} (ID/PW ${SITE_ID_PW})\n\n${SLACK_TEXT}\n\n첨부파일: \n난독화파일_ES1 - ${HTTPS_PREFIX}${Obfuscation_OUTPUT_FILE}\n난독화스크립트_ES1 - ${HTTPS_PREFIX}${Obfuscation_SCREENSHOT}\n\n" --channel ${SLACK_CHANNEL} --pretext "Android Build output files for ${GIT_BRANCH} - ${CHANGE_TITLE}(commit: ${GIT_COMMIT}) => ${BUILD_URL}" --color good
          else
            $SLACK chat send --text "${HOSTNAME} > 안드로이드 1차 난독화 버전 전달합니다.\n\n\nAPK 설치: ${SITE_URL} (ID/PW ${SITE_ID_PW})\n\n${SLACK_TEXT}\n\n" --channel ${SLACK_CHANNEL} --pretext "Android Build output files for ${GIT_BRANCH} - ${CHANGE_TITLE}(commit: ${GIT_COMMIT}) => ${BUILD_URL}" --color good
          fi
        else
          $SLACK chat send --text "${SLACK_TEXT}" --channel ${SLACK_CHANNEL} --pretext "${HOSTNAME} > Android Build output files for ${GIT_BRANCH} - ${CHANGE_TITLE}(commit: ${GIT_COMMIT}) => ${BUILD_URL}" --color good
        fi
        $SLACK chat send --text "${HOSTNAME} > ${FRONTEND_POINT}/${TOP_PATH}/dist_uaqa.php > Go Android" --channel ${SLACK_CHANNEL} --pretext "${HOSTNAME} > Android Download Web Page for ${SHORT_GIT_LOG}" --color good
      else
        GIT_BROWSER_URL=$(cat $jsonConfig | $JQ '.android.gitBrowseUrl' | tr -d '"')
        BLOCK_TITLE="Android 테스트"
        BLOCK_SECTION="${BLOCK_SECTION}                {
                  \"type\": \"section\",
                  \"text\": {
                      \"type\": \"mrkdwn\",
                      \"text\": \"${VERSION_STRING} ${SLACK_TEXT}\"
                  }
              },"
        if [ $IS_RELEASE -eq 1 ]; then
          BLOCK_TITLE="Android 검증용"
          if [ $USING_OBFUSCATION -eq 1 ]; then
            BLOCK_SECTION="${BLOCK_SECTION}                {
                    \"type\": \"section\",
                    \"text\": {
                        \"type\": \"mrkdwn\",
                        \"text\": \"${VERSION_STRING} 난독화파일_ES1\"
                    },
                    \"accessory\": {
                        \"type\": \"button\",
                        \"text\": {
                            \"type\": \"plain_text\",
                            \"text\": \"파일 다운로드\",
                            \"emoji\": true
                        },
                        \"value\": \"click_me_123\",
                        \"url\": \"${HTTPS_PREFIX}${Obfuscation_OUTPUT_FILE}\",
                        \"action_id\": \"button-action\"
                    }
                },"
            BLOCK_SECTION="${BLOCK_SECTION}                {
                    \"type\": \"section\",
                    \"text\": {
                        \"type\": \"mrkdwn\",
                        \"text\": \"${VERSION_STRING} 난독화파일_ES1\"
                    },
                    \"accessory\": {
                        \"type\": \"button\",
                        \"text\": {
                            \"type\": \"plain_text\",
                            \"text\": \"파일 다운로드\",
                            \"emoji\": true
                        },
                        \"value\": \"click_me_123\",
                        \"url\": \"${HTTPS_PREFIX}${Obfuscation_OUTPUT_FILE}\",
                        \"action_id\": \"button-action\"
                    }
                },"                
          fi
        fi
        SLACK_JSON_ALL="{
            \"channel\": \"${SLACK_CHANNEL}\", 
            \"username\": \"Jenkins(자동배포)\", 
            \"icon_emoji\": \":bowtie:\",
            \"blocks\": [
                {
                    \"type\": \"header\",
                    \"text\": {
                        \"type\": \"plain_text\",
                        \"text\": \"${HOSTNAME} > ${BLOCK_TITLE} ${APP_NAME}.App\",
                        \"emoji\": true
                    }
                },
                {
                    \"type\": \"section\",
                    \"text\": {
                        \"type\": \"mrkdwn\",
                        \"text\": \"${CLIENT_NAME} ${APP_NAME} 앱: Jenkins(${BUILD_NUMBER}) - ${GIT_BRANCH} (commit: ${GIT_COMMIT})\"
                    },
                    \"accessory\": {
                        \"type\": \"button\",
                        \"text\": {
                            \"type\": \"plain_text\",
                            \"text\": \"사이트 링크\",
                            \"emoji\": true
                        },
                        \"value\": \"click_me_123\",
                        \"url\": \"${GIT_BROWSER_URL}/${GIT_COMMIT}\",
                        \"action_id\": \"button-action\"
                    }
                },
                ${BLOCK_SECTION}
                {
                    \"type\": \"section\",
                    \"text\": {
                        \"type\": \"mrkdwn\",
                        \"text\": \"설치 및 다운로드 사이트: ${CLIENT_TITLE} ${SITE_URL} (ID/PW: ${SITE_ID_PW})\"
                    },
                    \"accessory\": {
                        \"type\": \"button\",
                        \"text\": {
                            \"type\": \"plain_text\",
                            \"text\": \"사이트 링크\",
                            \"emoji\": true
                        },
                        \"value\": \"click_me_123\",
                        \"url\": \"${SITE_URL}\",
                        \"action_id\": \"button-action\"
                    }
                }, 
                {
                    \"type\": \"section\",
                    \"text\": {
                        \"type\": \"mrkdwn\",
                        \"text\": \"배포 웹사이트 (내부 QA용): 내부 QA 사이트 (ID/PW: ${QC_ID_PW})\"
                    },
                    \"accessory\": {
                        \"type\": \"button\",
                        \"text\": {
                            \"type\": \"plain_text\",
                            \"text\": \"사이트 링크\",
                            \"emoji\": true
                        },
                        \"value\": \"click_me_123\",
                        \"url\": \"${FRONTEND_POINT}/${TOP_PATH}/android/dist_android.php\",
                        \"action_id\": \"button-action\"
                    }
                }, 
                {
                    \"type\": \"section\",
                    \"text\": {
                        \"type\": \"mrkdwn\",
                        \"text\": \"빌드 환경: ${OTHER_BUILE_ENV}$(cd ${WORKSPACE} && $BUILD_COMMAND --version | sed -e 's/$/\\n/g' | tr -d '\n')\"
                    }
                }, 
                {
                    \"type\": \"section\",
                    \"text\": {
                        \"type\": \"mrkdwn\",
                        \"text\": \"Jenkin 작업 결과: Jenkin 사이트\"
                    },
                    \"accessory\": {
                        \"type\": \"button\",
                        \"text\": {
                            \"type\": \"plain_text\",
                            \"text\": \"바로가기\",
                            \"emoji\": true
                        },
                        \"value\": \"click_me_123\",
                        \"url\": \"${BUILD_URL}\",
                        \"action_id\": \"button-action\"
                    }
                }
            ]
        }"
        $CURL -H "Content-Type: application/json" -d "${SLACK_JSON_ALL}" $SLACK_WEBHOOK
      fi
    fi
  fi

  BINARY_FACTS=""
  if [[ "$INPUT_OS" == "ios" ]]; then
    ###########
    if [ $USING_TEAMS_WEBHOOK -eq 1 ]; then
      GIT_BROWSER_URL=$(cat $jsonConfig | $JQ '.ios.gitBrowseUrl' | tr -d '"')
      ########
      if [ $IS_RELEASE -eq 1 ]; then
        BINARY_TITLE="iOS 검증용"
        if [ $USING_APPSTORE -eq 1 ]; then
          BINARY_FACTS="${BINARY_FACTS}{
                            \"name\": \"${APPSTORE_TITLE}\",
                            \"value\": \"${VERSION_STRING}[${APPSTORE_TITLE}.ipa 다운로드](${HTTPS_PREFIX}${OUTPUT_FILENAME_APPSTORE_IPA}) (${SIZE_STORE_APP_FILE}B)\"
                    }"
        fi
        if [ $USING_ADHOC -eq 1 ]; then
          if [[ "$BINARY_FACTS" != "" ]]; then
            BINARY_FACTS="${BINARY_FACTS}, "
          fi
          BINARY_FACTS="${BINARY_FACTS}{
                            \"name\": \"${ADHOC_TITLE}\",
                            \"value\": \"${VERSION_STRING}[${ADHOC_TITLE}.ipa 다운로드](${HTTPS_PREFIX}${OUTPUT_FILENAME_ADHOC_IPA}) (${SIZE_ADHOC_APP_FILE}B)\"
                    }"
        fi
        if [ $USING_ENTERPRISE -eq 1 ]; then
          if [[ "$BINARY_FACTS" != "" ]]; then
            BINARY_FACTS="${BINARY_FACTS}, "
          fi
          BINARY_FACTS="${BINARY_FACTS}{
                            \"name\": \"${ENTER_TITLE}\",
                            \"value\": \"${VERSION_STRING}[${ENTER_TITLE}.ipa 다운로드](${HTTPS_PREFIX}${OUTPUT_FILENAME_ENTER_IPA}) (${SIZE_ENTER_APP_FILE}B)\"
                    }"
        fi
        if [ $USING_APPSTORE -eq 1 ]; then
          if [[ "$BINARY_FACTS" != "" ]]; then
            BINARY_FACTS="${BINARY_FACTS}, "
          fi
          BINARY_FACTS="${BINARY_FACTS}{
                            \"name\": \"IxShieldCheck (PNG)\",
                            \"value\": \"${VERSION_STRING}[IxShield.png 다운로드](${HTTPS_PREFIX}${OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK})\"
                    }"
        fi
      else
        BINARY_TITLE="iOS 테스트"
        if [ $USING_ADHOC -eq 1 ]; then
          if [[ "$BINARY_FACTS" != "" ]]; then
            BINARY_FACTS="${BINARY_FACTS}, "
          fi
          BINARY_FACTS="${BINARY_FACTS}{
                            \"name\": \"${ADHOC_TITLE}\",
                            \"value\": \"${VERSION_STRING}[${ADHOC_TITLE}.ipa 다운로드](${HTTPS_PREFIX}${OUTPUT_FILENAME_ADHOC_IPA}) (${SIZE_ADHOC_APP_FILE}B)\"
                    }"
        fi
        if [ $USING_ENTERPRISE -eq 1 ]; then
          if [[ "$BINARY_FACTS" != "" ]]; then
            BINARY_FACTS="${BINARY_FACTS}, "
          fi
          BINARY_FACTS="${BINARY_FACTS}{
                          \"name\": \"${ENTER_TITLE}\",
                          \"value\": \"${VERSION_STRING}[${ENTER_TITLE}.ipa 다운로드](${HTTPS_PREFIX}${OUTPUT_FILENAME_ENTER_IPA}) (${SIZE_ENTER_APP_FILE}B)\"
                    }"
        fi
      fi
      ########
      JSON_ALL="{
          \"@type\": \"MessageCard\",
          \"@context\": \"${FRONTEND_POINT}/${TOP_PATH}/dist_uaqa.php\",
          \"themeColor\": \"${THEME_COLOR}\",
          \"summary\": \"Jenkins build completed\",
          \"sections\": [
              {
                  \"heroImage\": {
                      \"image\": \"${FRONTEND_POINT}/${TOP_PATH}/${ICON}\"
                  }
              },
              {
                  \"activityTitle\": \"${HOSTNAME} > ${BINARY_TITLE} ${APP_NAME}.App\",
                  \"activitySubtitle\": \"$(/bin/date '+%Y.%m.%d %H:%M') by ${BUILD_TAG}\",
                  \"activityImage\": \"${FRONTEND_POINT}/${TOP_PATH}/${ICON}\",
                  \"text\": \"${CLIENT_NAME} ${APP_NAME} 앱: Jenkins(${BUILD_NUMBER}) - ${GIT_BRANCH} (commit: [${GIT_COMMIT}](${GIT_BROWSER_URL}/${GIT_COMMIT}))\",
                  \"facts\": [${BINARY_FACTS}, {
                          \"name\": \"설치 및 다운로드 사이트\",
                          \"value\": \"${CLIENT_TITLE} [${SITE_URL}](${SITE_URL}) (ID/PW: ${SITE_ID_PW})\"
                  }, {
                          \"name\": \"배포 웹사이트 (내부 QA용)\",
                          \"value\": \"내부 QA 사이트 [바로가기](${FRONTEND_POINT}/${TOP_PATH}/ios/dist_ios.php) (ID/PW: ${QC_ID_PW})\"
                  }, {
                          \"name\": \"빌드 환경\",
                          \"value\": \"<pre>${OTHER_BUILE_ENV}$($XCODE -version)\nCocoaPod $($POD --version)</pre>\"
                  }, {
                          \"name\": \"Jenkin 작업 결과\",
                          \"value\": \"Jenkin 사이트 [바로가기](${BUILD_URL})\"
                  }],
                  \"markdown\": true
          }]
        }"
      $CURL -H "Content-Type: application/json" -d "${JSON_ALL}" $TEAMS_WEBHOOK
    fi
    if [ $USING_MAIL -eq 1 ]; then
      MAIL_APPSTORE_DOWN_STR=""
      MAIL_APPSTORE_ATTACH_STR=""
      if [ $USING_APPSTORE -eq 1 ]; then
        MAIL_APPSTORE_DOWN_STR="${APPSTORE_TITLE} IPA 다운로드(${SIZE_STORE_APP_FILE}B): <a href=${HTTPS_PREFIX}${OUTPUT_FILENAME_APPSTORE_IPA}>${HTTPS_PREFIX}${OUTPUT_FILENAME_APPSTORE_IPA}</a><br />"
        MAIL_APPSTORE_ATTACH_STR="첨부파일: <a href=${HTTPS_PREFIX}${OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK}>${HTTPS_PREFIX}${OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK}</a>"
      fi
      MAIL_ADHOC_DOWN_STR=""
      MAIL_ADHOC_ITMS_STR=""
      if [ $USING_ADHOC -eq 1 ]; then
        MAIL_ADHOC_DOWN_STR="${ADHOC_TITLE} IPA 다운로드(${SIZE_ADHOC_APP_FILE}B): <a href=${HTTPS_PREFIX}${OUTPUT_FILENAME_ADHOC_IPA}>${HTTPS_PREFIX}${OUTPUT_FILENAME_ADHOC_IPA}</a><br />"
        MAIL_ADHOC_ITMS_STR="${ADHOC_TITLE} Plist: ${ITMS_PREFIX}${ADHOC_PLIST_ITMS_URL}<br />"
      fi
      MAIL_ENTER_DOWN_STR=""
      MAIL_ENTER_ITMS_STR=""
      if [ $USING_ENTERPRISE -eq 1 ]; then
        MAIL_ENTER_DOWN_STR="${ENTER_TITLE} IPA 다운로드(${SIZE_ENTER_APP_FILE}B): <a href=${HTTPS_PREFIX}${OUTPUT_FILENAME_ENTER_IPA}>${HTTPS_PREFIX}${OUTPUT_FILENAME_ENTER_IPA}</a><br /><br />"
        MAIL_ENTER_ITMS_STR="${ENTER_TITLE} Plist: ${ITMS_PREFIX}${ENTER_PLIST_ITMS_URL}<br />"
      fi
      if [ -f $OUTPUT_FOLDER/$OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK -a $IS_RELEASE -eq 1 ]; then
        $CURL --data-urlencode "subject1=[iOS ${APP_NAME}.app > ${HOSTNAME}] Jenkins(${BUILD_NUMBER}) ${DEBUG_MSG} -" \
          --data-urlencode "subject2=iOS ${GIT_BRANCH} - ${CHANGE_TITLE}(commit: ${GIT_COMMIT})" \
          --data-urlencode "message_header=${MAIL_APPSTORE_DOWN_STR}${MAIL_ADHOC_DOWN_STR}${MAIL_ENTER_DOWN_STR}${MAIL_APPSTORE_ATTACH_STR}" \
          --data-urlencode "message_description=${SHORT_GIT_LOG}<br />${GIT_LAST_LOG}<br />${MAIL_ADHOC_ITMS_STR}${MAIL_ENTER_ITMS_STR}<br /><br /><br /><pre>${OTHER_BUILE_ENV}$($XCODE -version)</pre><br /><br /><a href=${BUILD_URL}>${BUILD_URL}</a>" \
          --data-urlencode "message_attachment=난독화스크립트 - ${OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK}" \
          --data-urlencode "attachment_path=$OUTPUT_FOLDER/$OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK" \
          ${FRONTEND_POINT}/${TOP_PATH}/sendmail_domestic.php
      elif [ $IS_RELEASE -eq 1 ]; then
        $CURL --data-urlencode "subject1=[iOS ${APP_NAME}.app > ${HOSTNAME}] Jenkins(${BUILD_NUMBER}) ${DEBUG_MSG} -" \
          --data-urlencode "subject2=iOS ${GIT_BRANCH} - ${CHANGE_TITLE}(commit: ${GIT_COMMIT})" \
          --data-urlencode "message_header=${MAIL_APPSTORE_DOWN_STR}${MAIL_ADHOC_DOWN_STR}${MAIL_ENTER_DOWN_STR}첨부파일: 없음" \
          --data-urlencode "message_description=${SHORT_GIT_LOG}<br />${GIT_LAST_LOG}<br />${MAIL_ADHOC_ITMS_STR}${MAIL_ENTER_ITMS_STR}<br /><br /><br /><pre>${OTHER_BUILE_ENV}$($XCODE -version)</pre><br /><br /><a href=${BUILD_URL}>${BUILD_URL}</a>" \
          ${FRONTEND_POINT}/${TOP_PATH}/sendmail_domestic.php
      else
        $CURL --data-urlencode "subject1=[iOS ${APP_NAME}.app > ${HOSTNAME}] Jenkins(${BUILD_NUMBER}) ${DEBUG_MSG} -" \
          --data-urlencode "subject2=iOS ${GIT_BRANCH} - ${CHANGE_TITLE}(commit: ${GIT_COMMIT})" \
          --data-urlencode "message_header=iOS 테스트 ${APP_NAME} 전달합니다.<br /><br />${MAIL_ADHOC_DOWN_STR}${MAIL_ENTER_DOWN_STR}" \
          --data-urlencode "message_description=${SHORT_GIT_LOG}<br />${GIT_LAST_LOG}<br />${MAIL_ADHOC_ITMS_STR}${MAIL_ENTER_ITMS_STR}<br /><br /><br /><pre>${OTHER_BUILE_ENV}$($XCODE -version)</pre><br /><br /><a href=${BUILD_URL}>${BUILD_URL}</a>" \
          ${FRONTEND_POINT}/${TOP_PATH}/sendmail_domestic.php
      fi
    fi
  else # iOS
    ###########
    if [ $USING_TEAMS_WEBHOOK -eq 1 ]; then
      GIT_BROWSER_URL=$(cat $jsonConfig | $JQ '.android.gitBrowseUrl' | tr -d '"')
      ########
      if [ $IS_RELEASE -eq 1 ]; then
        BINARY_TITLE="Android 검증용"
        if [ $USING_GOOGLESTORE -eq 1 ]; then
          if [[ "$BINARY_FACTS" != "" ]]; then
            BINARY_FACTS="${BINARY_FACTS}, "
          fi
          BINARY_FACTS="${BINARY_FACTS}{
                          \"name\": \"${GOOGLE_TITLE} 배포용\",
                          \"value\": \"${VERSION_STRING}[${GRADLE_TASK_GOOGLESTORE} 다운로드](${HTTPS_PREFIX}${APK_GOOGLESTORE}) (${SIZE_GOOGLE_APP_FILE}B)\"
                  }"
        fi
        if [ $USING_ONESTORE -eq 1 ]; then
          if [[ "$BINARY_FACTS" != "" ]]; then
            BINARY_FACTS="${BINARY_FACTS}, "
          fi
          BINARY_FACTS="${BINARY_FACTS}{
                          \"name\": \"${ONE_TITLE} 배포용\",
                          \"value\": \"${VERSION_STRING}[${GRADLE_TASK_ONESTORE} 다운로드](${HTTPS_PREFIX}${APK_ONESTORE}) (${SIZE_ONE_APP_FILE}B)\"
                  }"
        fi
        if [ $USING_OBFUSCATION -eq 1 ]; then
          if [[ "$BINARY_FACTS" != "" ]]; then
            BINARY_FACTS="${BINARY_FACTS}, "
          fi
          BINARY_FACTS="${BINARY_FACTS}{
                          \"name\": \"난독화증적파일 스크린샷 (PNG)\",
                          \"value\": \"${VERSION_STRING}[난독화증적파일 스크린샷 다운로드](${HTTPS_PREFIX}${Obfuscation_OUTPUT_FILE})\"
                  }, "
          BINARY_FACTS="${BINARY_FACTS}{
                          \"name\": \"난독화스크립트 캡쳐 (PNG)\",
                          \"value\": \"${VERSION_STRING}[난독화스크립트 캡쳐 다운로드](${HTTPS_PREFIX}${Obfuscation_SCREENSHOT})\"
                  }"
        fi
      else
        BINARY_TITLE="Android 테스트"
        if [ $USING_TESTSERVER -eq 1 ]; then
          if [[ "$BINARY_FACTS" != "" ]]; then
            BINARY_FACTS="${BINARY_FACTS}, "
          fi
          BINARY_FACTS="${BINARY_FACTS}{
                          \"name\": \"${GRADLE_TASK_TESTSERVER}(TB)\",
                          \"value\": \"${VERSION_STRING}[${GRADLE_TASK_TESTSERVER}.apk 다운로드](${HTTPS_PREFIX}${OUTPUT_APK_TESTSERVER}) (${SIZE_TEST_APP_FILE}B)\"
                  }"
        fi
        if [ $USING_LIVESERVER -eq 1 ]; then
          if [[ "$BINARY_FACTS" != "" ]]; then
            BINARY_FACTS="${BINARY_FACTS}, "
          fi
          BINARY_FACTS="${BINARY_FACTS}{
                          \"name\": \"${GRADLE_TASK_LIVESERVER}\",
                          \"value\": \"${VERSION_STRING}[${GRADLE_TASK_LIVESERVER}.apk 다운로드](${HTTPS_PREFIX}${OUTPUT_APK_LIVESERVER}) (${SIZE_LIVE_APP_FILE}B)\"
                  }"
        fi
      fi
      ########
      ICON=$(cat $jsonConfig | $JQ '.teams.iconImage' | tr -d '"')
      JSON_ALL="{
            \"@type\": \"MessageCard\",
            \"@context\": \"${FRONTEND_POINT}/${TOP_PATH}/dist_uaqa.php\",
            \"themeColor\": \"${THEME_COLOR}\",
            \"summary\": \"Jenkins build completed\",
            \"sections\": [
                {
                    \"heroImage\": {
                        \"image\": \"${FRONTEND_POINT}/${TOP_PATH}/${ICON}\"
                    }
                },
                {
                    \"activityTitle\": \"${HOSTNAME} > ${BINARY_TITLE} ${APP_NAME}.App\",
                    \"activitySubtitle\": \"$(/bin/date '+%Y.%m.%d %H:%M') by ${BUILD_TAG}\",
                    \"activityImage\": \"${FRONTEND_POINT}/${TOP_PATH}/${ICON}\",
                    \"text\": \"${CLIENT_NAME} ${APP_NAME} 앱: Jenkins(${BUILD_NUMBER}) - ${GIT_BRANCH} (commit: [${GIT_COMMIT}](${GIT_BROWSER_URL}/${GIT_COMMIT}))\",
                    \"facts\": [${BINARY_FACTS}, {
                            \"name\": \"설치 및 다운로드 사이트\",
                            \"value\": \"${CLIENT_NAME} [${SITE_URL}](${SITE_URL}) (ID/PW: ${SITE_ID_PW})\"
                    }, {
                            \"name\": \"배포 웹사이트 (내부 QA용)\",
                            \"value\": \"내부 QA 사이트 [바로가기](${FRONTEND_POINT}/${TOP_PATH}/android/dist_android.php) (ID/PW: ${QC_ID_PW})\"
                    }, {
                            \"name\": \"빌드 환경\",
                            \"value\": \"<pre>${OTHER_BUILE_ENV}$(cd ${WORKSPACE} && $BUILD_COMMAND --version)</pre>\"
                    }, {
                            \"name\": \"Jenkin 작업 결과\",
                            \"value\": \"Jenkin 사이트 [바로가기](${BUILD_URL})\"
                    }],
                    \"markdown\": true
            }]
          }"
      $CURL -H "Content-Type: application/json" -d "${JSON_ALL}" $TEAMS_WEBHOOK
    fi # Android
    
    if [ $USING_MAIL -eq 1 ]; then
      if [ -f $OUTPUT_FOLDER/$Obfuscation_OUTPUT_FILE -a $IS_RELEASE -eq 1 ]; then
        ATTACHMENT_DOWN=""
        ATTACHMENT_STR=""
        if [ $USING_OBFUSCATION -eq 1 ]; then
          ATTACHMENT_DOWN="첨부파일: <br />난독화파일 - <a href=${HTTPS_PREFIX}${Obfuscation_OUTPUT_FILE}>${HTTPS_PREFIX}${Obfuscation_OUTPUT_FILE}</a><br />난독화스크립트 - <a href=${HTTPS_PREFIX}${Obfuscation_SCREENSHOT}>${HTTPS_PREFIX}${Obfuscation_SCREENSHOT}</a><br /><br />"
          ATTACHMENT_STR="message_attachment=난독화파일 - ${Obfuscation_OUTPUT_FILE}<br />난독화스크립트 - ${Obfuscation_SCREENSHOT}"
        fi
        $CURL --data-urlencode "subject1=[AOS ${APP_NAME}.app > ${HOSTNAME}] Jenkins(${BUILD_NUMBER}) 자동빌드 -" \
          --data-urlencode "subject2=Android ${GIT_BRANCH} - ${CHANGE_TITLE}(commit: ${GIT_COMMIT})" \
          --data-urlencode "message_header=안드로이드 1차 난독화 버전 전달합니다.<br /><br /><br />${MAIL_TEXT}<br /><br />${ATTACHMENT_DOWN}" \
          --data-urlencode "message_description=${SHORT_GIT_LOG}<br />${GIT_LAST_LOG}<br /><br /><br /><pre>${OTHER_BUILE_ENV}$(cd ${WORKSPACE} && $BUILD_COMMAND --version)</pre><br /><br /><a href=${BUILD_URL}>${BUILD_URL}</a>" \
          --data-urlencode "${ATTACHMENT_STR}" \
          --data-urlencode "attachment_path=$OUTPUT_FOLDER/$Obfuscation_OUTPUT_FILE;$OUTPUT_FOLDER/$Obfuscation_SCREENSHOT" \
          ${FRONTEND_POINT}/${TOP_PATH}/sendmail_domestic.php
      else
        $CURL --data-urlencode "subject1=[AOS ${APP_NAME}.app > ${HOSTNAME}] Jenkins(${BUILD_NUMBER}) 자동빌드 -" \
          --data-urlencode "subject2=Android ${GIT_BRANCH} - ${CHANGE_TITLE}(commit: ${GIT_COMMIT})" \
          --data-urlencode "message_header=안드로이드 테스트 ${APP_NAME} 전달합니다.<br /><br /><br />${MAIL_TEXT}<br />" \
          --data-urlencode "message_description=$(echo ${GIT_LAST_LOG} | sed -e 's/\[uDev\]/<br \/>\&nbsp;\&nbsp;\&nbsp;/g' | sed -e 's/\\n/<br \/>\&nbsp;\&nbsp;\&nbsp;/g')<br /><br /><br /><br /><pre>${OTHER_BUILE_ENV}$(cd ${WORKSPACE} && $BUILD_COMMAND --version)</pre><br /><a href=${BUILD_URL}>${BUILD_URL}</a>" \
          ${FRONTEND_POINT}/${TOP_PATH}/sendmail_domestic.php
      fi
    fi
  fi # Android
fi
