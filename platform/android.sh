#!/bin/sh
##
# Android Shell Script
#
# if test -z $ConfigJavaHome || test -z ${JAVA_NULL%null}; then
if test -z $ConfigJavaHome; then
    if type java >/dev/null 2>&1; then
        JAVA_EXEC=$(command -v java)
        ConfigJavaHome=$(dirname ${JAVA_EXEC%java})
    fi
fi
export JAVA_HOME="${ConfigJavaHome}"
export ANDROID_SDK_ROOT="${ANDROID_HOME}"
export ANDROID_HOME="${ANDROID_HOME}"
##### Using Allatori or Not, 0=Not Using, 1=Using Allatori (1차 난독화)
USING_ALLATORI=$(test $(cat $jsonConfig | $JQ '.android.usingAllatori') = true && echo 1 || echo 0)
APP_ROOT_SUFFIX="android_distributions"
APP_ROOT="${APP_ROOT_PREFIX}/${TOP_PATH}/${APP_ROOT_SUFFIX}"
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
    BUILD_VERSION=$(grep ${APP_BUNDLE_IDENTIFIER_ANDROID} -5 ${BUILD_GRADLE_CONFIG} | grep 'versionCode' | grep -v '^\/\/' | awk 'BEGIN{FS=" "} {print $2}')
else
    APP_VERSION="${DEBUG_MAJOR}.${DEBUG_MINOR}.${DEBUG_POINT}"
    BUILD_VERSION="${DEBUG_LOCAL}"
fi
if [[ "${APP_VERSION}" == ".." ]]; then
    if [ $isFlutterEnabled -eq 1 ]; then
        LOCAL_PROPERTIES="${WORKSPACE}/android/local.properties"
        PODSPEC="${WORKSPACE}/pubspec.yaml"
        if [ -f "${PODSPEC}" ]; then
            APP_VERSION=$(grep 'version:' ${PODSPEC} | grep -v '^#' | sed -e 's/version: \([0-9]*.[0-9]*.[0-9]*\)+.*/\1/')
            BUILD_VERSION=$(grep 'version:' ${PODSPEC} | grep -v '^#' |  sed -e 's/version: .*+\([0-9]*\).*/\1/')
        elif [ -f "${LOCAL_PROPERTIES}" ]; then
            APP_VERSION=$(grep 'flutter.versionName' ${LOCAL_PROPERTIES} | sed -e "s/flutter.versionName=\([0-9]*.[0-9]*.[0-9]*.*\)/\1/")
            BUILD_VERSION=$(grep 'flutter.versionCode' ${LOCAL_PROPERTIES} | sed -e "s/flutter.versionCode=\(.*\)/\1/")
        else
            APP_VERSION=$(grep 'flutterVersionName' ${BUILD_GRADLE_CONFIG} | grep "flutterVersionName = '"| sed -e "s/flutterVersionName = '\([0-9]*.[0-9]*.[0-9]*.*\)'/\1/" | tr -d "' ")
            BUILD_VERSION=$(grep 'flutterVersionCode' ${BUILD_GRADLE_CONFIG} | grep "flutterVersionCode = '"| sed -e "s/flutterVersionCode = '\(.*\)'/\1/" | tr -d "' ")
        fi
    else
        APP_VERSION=$(grep 'versionName[[:space:]]"' ${BUILD_GRADLE_CONFIG} | grep -v '^\/\/' | sed -e 's/versionName "\(.*\)"/\1/' | tr -d ' \r')
        if [[ $APP_VERSION == "versionName"* ]]; then
            APP_VERSION=$(grep 'versionName' ${BUILD_GRADLE_CONFIG} | grep -v '^\/\/' | sed -e "s/versionName '\(.*\)'/\1/" | tr -d ' \r')
        fi
        if [ $isReactNativeEnabled -eq 1 ]; then
            BUILD_VERSION=$(grep 'versionCode' ${BUILD_GRADLE_CONFIG} | grep -v '^\/\/' | head -1 | sed -e 's/versionCode \(.*\)$/\1/' | tr -d ' \r')
        else
            BUILD_VERSION=$(grep 'versionCode' ${BUILD_GRADLE_CONFIG} | grep -v '^\/\/' | sed -e 's/versionCode \(.*\)$/\1/' | tr -d ' \r')
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
RELEASE_TYPE_GOOGLESTORE=$(cat $jsonConfig | $JQ '.android.GoogleStore.releaseType' | tr -d '"')
###
USING_ONESTORE=$(test $(cat $jsonConfig | $JQ '.android.OneStore.enabled') = true && echo 1 || echo 0)
GRADLE_TASK_ONESTORE=$(cat $jsonConfig | $JQ '.android.OneStore.taskName' | tr -d '"')
USING_BUNDLE_ONESTORE=$(test $(cat $jsonConfig | $JQ '.android.OneStore.usingBundleAAB') = true && echo 1 || echo 0)
RELEASE_TYPE_ONESTORE=$(cat $jsonConfig | $JQ '.android.OneStore.releaseType' | tr -d '"')
###
USING_LIVESERVER=$(test $(cat $jsonConfig | $JQ '.android.LiveServer.enabled') = true && echo 1 || echo 0)
GRADLE_TASK_LIVESERVER=$(cat $jsonConfig | $JQ '.android.LiveServer.taskName' | tr -d '"')
USING_BUNDLE_LIVESERVER=$(test $(cat $jsonConfig | $JQ '.android.LiveServer.usingBundleAAB') = true && echo 1 || echo 0)
RELEASE_TYPE_LIVESERVER=$(cat $jsonConfig | $JQ '.android.LiveServer.releaseType' | tr -d '"')
###
USING_TESTSERVER=$(test $(cat $jsonConfig | $JQ '.android.TestServer.enabled') = true && echo 1 || echo 0)
GRADLE_TASK_TESTSERVER=$(cat $jsonConfig | $JQ '.android.TestServer.taskName' | tr -d '"')
USING_BUNDLE_TESTSERVER=$(test $(cat $jsonConfig | $JQ '.android.TestServer.usingBundleAAB') = true && echo 1 || echo 0)
RELEASE_TYPE_TESTSERVER=$(cat $jsonConfig | $JQ '.android.TestServer.releaseType' | tr -d '"')
###################
if [ $isFlutterEnabled -eq 1 ]; then
    APK_OUTPUT_PATH="build/app/outputs"
else
    APK_OUTPUT_PATH="${ANDROID_APP_PATH}/build/outputs"
fi
if [ $IS_RELEASE -eq 1 ]; then
    APK_FILE_TITLE="${OUTPUT_PREFIX}${APP_VERSION}(${BUILD_VERSION})_${FILE_TODAY}"

    if [ $USING_BUNDLE_GOOGLESTORE -eq 1 ]; then
        FILE_EXTENSION="aab"
    else
        FILE_EXTENSION="apk"
    fi
    if [[ "$RELEASE_TYPE_GOOGLESTORE" == "null" ]]; then
        RELEASE_TYPE_GOOGLESTORE="release"
    fi
    APK_GOOGLESTORE="${APK_FILE_TITLE}${outputGoogleStoreSuffix%.*}.${FILE_EXTENSION}"

    if [ $USING_BUNDLE_ONESTORE -eq 1 ]; then
        FILE_EXTENSION="aab"
    else
        FILE_EXTENSION="apk"
    fi
    if [[ "$RELEASE_TYPE_ONESTORE" == "null" ]]; then
        RELEASE_TYPE_ONESTORE="release"
    fi
    APK_ONESTORE="${APK_FILE_TITLE}${outputOneStoreSuffix%.*}.${FILE_EXTENSION}"

    Obfuscation_SCREENSHOT="${OUTPUT_PREFIX}${APP_VERSION}(${BUILD_VERSION})_${FILE_TODAY}_Obfuscation.png"
    Obfuscation_OUTPUT_FILE="${OUTPUT_PREFIX}${APP_VERSION}(${BUILD_VERSION})_${FILE_TODAY}_file.png"
else
    if [ $USING_BUNDLE_LIVESERVER -eq 1 ]; then
        FILE_EXTENSION="aab"
    else
        FILE_EXTENSION="apk"
    fi
    if [[ "$RELEASE_TYPE_LIVESERVER" == "null" ]]; then
        RELEASE_TYPE_LIVESERVER="release"
    fi
    OUTPUT_APK_LIVESERVER="${OUTPUT_PREFIX}${APP_VERSION}.${BUILD_VERSION}_${FILE_TODAY}-${GRADLE_TASK_LIVESERVER}-${RELEASE_TYPE_LIVESERVER}.${FILE_EXTENSION}"

    if [ $USING_BUNDLE_TESTSERVER -eq 1 ]; then
        FILE_EXTENSION="aab"
    else
        FILE_EXTENSION="apk"
    fi
    if [[ "$RELEASE_TYPE_TESTSERVER" == "null" ]]; then
        RELEASE_TYPE_TESTSERVER="debug"
    fi
    OUTPUT_APK_TESTSERVER="${OUTPUT_PREFIX}${APP_VERSION}.${BUILD_VERSION}_${FILE_TODAY}-${GRADLE_TASK_TESTSERVER}-${RELEASE_TYPE_TESTSERVER}.${FILE_EXTENSION}"
fi
SLACK_TEXT=""
MAIL_TEXT=""
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
    if [ $? -ne 0 ]; then
        # Fail-over for `Error: Cannot find module ...`
        $ReactNativeBin install
        $ReactNativeBin install --legacy-peer-deps
    fi
    if test ! -z $NODE_OPTION_FLAG; then
        export NODE_OPTIONS=${NODE_OPTION_FLAG}
    fi

    $ReactNativeBin run build:android
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
    STOREPASS=$(cat $jsonConfig | $JQ '.android.keyStorePassword' | tr -d '"')
    KEYSTORE_FILE=$(cat $jsonConfig | $JQ '.android.keyStoreFile' | tr -d '"')
    KEYSTORE_ALIAS=$(cat $jsonConfig | $JQ '.android.keyStoreAlias' | tr -d '"')
    KEYSTORE_FILE="${WORKSPACE}/${KEYSTORE_FILE}"
    if [ ! -f $KEYSTORE_FILE ]; then
        FOUND_FILE=$(find ${WORKSPACE} -name '*.keystore' -not -name '*debug*' | sed 's/^\.\///g')
        if [ -f $FOUND_FILE ]; then
            KEYSTORE_FILE="${FOUND_FILE}"
        fi
    fi

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
            $FlutterBin clean
            $FlutterBin pub get

            if test -z $FLUTTER_FLAG; then
                $FlutterBin build ${flutterBuildKey} --flavor ${GRADLE_TASK_GOOGLESTORE}
            else
                $FlutterBin build ${flutterBuildKey} --flavor ${GRADLE_TASK_GOOGLESTORE} ${FLUTTER_FLAG}
            fi
        elif [ $isReactNativeEnabled -eq 1 ]; then
            if [ -d ${WORKSPACE}/android ]; then
                cd ${WORKSPACE}/android
            fi
            GRADLE_TASK="${gradleBuildKey}Release"
            if [[ $(./gradlew tasks 2>&1 | grep -v '^Warning' | grep "${gradleBuildKey}${GRADLE_TASK_GOOGLESTORE}" | awk '{print $1}' | tr -d ' ') == "${gradleBuildKey}${GRADLE_TASK_GOOGLESTORE}" ]]; then
                GRADLE_TASK="${gradleBuildKey}${GRADLE_TASK_GOOGLESTORE}Release"
            fi
            ./gradlew "${GRADLE_TASK}"
            if [ -d ${WORKSPACE}/android ]; then
                cd ${WORKSPACE}
            fi
        else
            ./gradlew "${gradleBuildKey}${GRADLE_TASK_GOOGLESTORE}"
        fi

        if test -z "$BUILD_APK_GOOGLESTORE"; then
            LOWER_MODE_NAME="$(echo ${RELEASE_TYPE_GOOGLESTORE} | tr 'A-Z' 'a-z')"
            LOWERCASE_TASK_NAME="$(echo ${GRADLE_TASK_GOOGLESTORE} | tr 'A-Z' 'a-z')"
            makePathForAndroidOutput
            BUILD_APK_GOOGLESTORE="$BUILD_APK_OUTPUT"
        fi
        if [ -f $BUILD_OUTPUT_FOLDER/$BUILD_APK_GOOGLESTORE ]; then
            mv "$BUILD_OUTPUT_FOLDER/$BUILD_APK_GOOGLESTORE" "$OUTPUT_FOLDER/$APK_GOOGLESTORE"
            SIZE_GOOGLE_APP_FILE=$(du -sh ${OUTPUT_FOLDER}/${APK_GOOGLESTORE} | awk '{print $1}')
            SLACK_TEXT="${SLACK_TEXT}${HOSTNAME} > ${GRADLE_TASK_GOOGLESTORE} 배포용 다운로드(${SIZE_GOOGLE_APP_FILE}B): ${HTTPS_PREFIX}${APK_GOOGLESTORE}\n"
            MAIL_TEXT="${MAIL_TEXT}${GRADLE_TASK_GOOGLESTORE} 배포용 다운로드(${SIZE_GOOGLE_APP_FILE}B): <a href=${HTTPS_PREFIX}${APK_GOOGLESTORE}>${HTTPS_PREFIX}${APK_GOOGLESTORE}</a><br />"
            if [[ $USING_BUNDLE_GOOGLESTORE -eq 1 && -f $BUNDLE_TOOL ]]; then
                BUNDLE_APK_FILE="$OUTPUT_FOLDER/${APK_GOOGLESTORE%.aab}.apks"
                if [ -f $KEYSTORE_FILE ]; then
                    $BUNDLE_TOOL build-apks --bundle="$OUTPUT_FOLDER/$APK_GOOGLESTORE" --output="$BUNDLE_APK_FILE" --mode=universal --ks="$KEYSTORE_FILE" --ks-pass="pass:$STOREPASS" --ks-key-alias="$KEYSTORE_ALIAS"
                else
                    $BUNDLE_TOOL build-apks --bundle="$OUTPUT_FOLDER/$APK_GOOGLESTORE" --output="$BUNDLE_APK_FILE" --mode=universal
                fi
                BUNDLE_APK2ZIP="${BUNDLE_APK_FILE%.apks}.zip"
                mv -f "${BUNDLE_APK_FILE}" "${BUNDLE_APK2ZIP}"
                unzip -o "${BUNDLE_APK2ZIP}"
                BUNDLE_APK_FILE="$OUTPUT_FOLDER/${APK_GOOGLESTORE%.aab}.apk"
                if [ -f universal.apk ]; then
                    touch universal.apk
                    mv -f universal.apk "$BUNDLE_APK_FILE"
                    find . -name 'toc.*' -exec rm {} \;
                    if [ -f $BUNDLE_APK2ZIP ]; then
                        rm $BUNDLE_APK2ZIP
                    fi
                fi
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
            $FlutterBin clean
            $FlutterBin pub get

            if test -z $FLUTTER_FLAG; then
                $FlutterBin build ${flutterBuildKey} --flavor ${GRADLE_TASK_ONESTORE}
            else
                $FlutterBin build ${flutterBuildKey} --flavor ${GRADLE_TASK_ONESTORE} ${FLUTTER_FLAG}
            fi
        elif [ $isReactNativeEnabled -eq 1 ]; then
            if [ -d ${WORKSPACE}/android ]; then
                cd ${WORKSPACE}/android
            fi
            GRADLE_TASK="${gradleBuildKey}Release"
            if [[ $(./gradlew tasks 2>&1 | grep -v '^Warning' | grep "${gradleBuildKey}${GRADLE_TASK_ONESTORE}" | awk '{print $1}' | tr -d ' ') == "${gradleBuildKey}${GRADLE_TASK_ONESTORE}" ]]; then
                GRADLE_TASK="${gradleBuildKey}${GRADLE_TASK_ONESTORE}Release"
            fi
            ./gradlew "${GRADLE_TASK}"
            if [ -d ${WORKSPACE}/android ]; then
                cd ${WORKSPACE}
            fi
        else
            ./gradlew "${gradleBuildKey}${GRADLE_TASK_ONESTORE}"
        fi

        if test -z "$BUILD_APK_ONESTORE"; then
            LOWER_MODE_NAME="$(echo ${RELEASE_TYPE_ONESTORE} | tr 'A-Z' 'a-z')"
            LOWERCASE_TASK_NAME="$(echo ${GRADLE_TASK_ONESTORE} | tr 'A-Z' 'a-z')"
            makePathForAndroidOutput
            BUILD_APK_ONESTORE="$BUILD_APK_OUTPUT"
        fi
        if [ -f $BUILD_OUTPUT_FOLDER/$BUILD_APK_ONESTORE ]; then
            mv "$BUILD_OUTPUT_FOLDER/$BUILD_APK_ONESTORE" "$OUTPUT_FOLDER/$APK_ONESTORE"
            SIZE_ONE_APP_FILE=$(du -sh ${OUTPUT_FOLDER}/${APK_ONESTORE} | awk '{print $1}')
            SLACK_TEXT="${SLACK_TEXT}${HOSTNAME} > ${GRADLE_TASK_ONESTORE} 배포용 다운로드(${SIZE_ONE_APP_FILE}B): ${HTTPS_PREFIX}${APK_ONESTORE}\n"
            MAIL_TEXT="${MAIL_TEXT}${GRADLE_TASK_ONESTORE} 배포용 다운로드(${SIZE_ONE_APP_FILE}B): <a href=${HTTPS_PREFIX}${APK_ONESTORE}>${HTTPS_PREFIX}${APK_ONESTORE}</a><br />"
            if [[ $USING_BUNDLE_ONESTORE -eq 1 && -f $BUNDLE_TOOL ]]; then
                BUNDLE_APK_FILE="$OUTPUT_FOLDER/${APK_ONESTORE%.aab}.apks"
                if [ -f $KEYSTORE_FILE ]; then
                    $BUNDLE_TOOL build-apks --bundle="$OUTPUT_FOLDER/$APK_ONESTORE" --output="$BUNDLE_APK_FILE" --mode=universal --ks="$KEYSTORE_FILE" --ks-pass="pass:$STOREPASS" --ks-key-alias="$KEYSTORE_ALIAS"
                else
                    $BUNDLE_TOOL build-apks --bundle="$OUTPUT_FOLDER/$APK_ONESTORE" --output="$BUNDLE_APK_FILE" --mode=universal
                fi
                BUNDLE_APK2ZIP="${BUNDLE_APK_FILE%.apks}.zip"
                mv "${BUNDLE_APK_FILE}" "${BUNDLE_APK2ZIP}"
                unzip "${BUNDLE_APK2ZIP}"
                BUNDLE_APK_FILE="$OUTPUT_FOLDER/${APK_GOOGLESTORE%.aab}.apk"
                if [ -f universal.apk ]; then
                    touch universal.apk
                    mv universal.apk "$BUNDLE_APK_FILE"
                    if [ -f toc.pd ]; then
                        rm toc.pd
                    fi
                    if [ -f $BUNDLE_APK2ZIP ]; then
                        rm $BUNDLE_APK2ZIP
                    fi
                fi
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
            $FlutterBin clean
            $FlutterBin pub get

            if test -z $FLUTTER_FLAG; then
                $FlutterBin build ${flutterBuildKey} --flavor ${GRADLE_TASK_LIVESERVER}
            else
                $FlutterBin build ${flutterBuildKey} --flavor ${GRADLE_TASK_LIVESERVER} ${FLUTTER_FLAG}
            fi
        elif [ $isReactNativeEnabled -eq 1 ]; then
            if [ -d ${WORKSPACE}/android ]; then
                cd ${WORKSPACE}/android
            fi
            GRADLE_TASK="${gradleBuildKey}Release"
            if [[ $(./gradlew tasks 2>&1 | grep -v '^Warning' | grep "${gradleBuildKey}${GRADLE_TASK_LIVESERVER}" | awk '{print $1}' | tr -d ' ') == "${gradleBuildKey}${GRADLE_TASK_LIVESERVER}" ]]; then
                GRADLE_TASK="${gradleBuildKey}${GRADLE_TASK_LIVESERVER}Release"
            fi
            ./gradlew "${GRADLE_TASK}"
            if [ -d ${WORKSPACE}/android ]; then
                cd ${WORKSPACE}
            fi
        else
            ./gradlew "${gradleBuildKey}${GRADLE_TASK_LIVESERVER}"
        fi

        if test -z "$APK_LIVESERVER"; then
            LOWER_MODE_NAME="$(echo ${RELEASE_TYPE_LIVESERVER} | tr 'A-Z' 'a-z')"
            LOWERCASE_TASK_NAME="$(echo ${GRADLE_TASK_LIVESERVER} | tr 'A-Z' 'a-z')"
            makePathForAndroidOutput
            APK_LIVESERVER="$BUILD_APK_OUTPUT"
        fi
        if [ -f $BUILD_OUTPUT_FOLDER/$APK_LIVESERVER ]; then
            mv "$BUILD_OUTPUT_FOLDER/$APK_LIVESERVER" "$OUTPUT_FOLDER/$OUTPUT_APK_LIVESERVER"
            SIZE_LIVE_APP_FILE=$(du -sh ${OUTPUT_FOLDER}/${OUTPUT_APK_LIVESERVER} | awk '{print $1}')
            SLACK_TEXT="${SLACK_TEXT}${HOSTNAME} > ${GRADLE_TASK_LIVESERVER}(debug)(${SIZE_LIVE_APP_FILE}B): ${HTTPS_PREFIX}${OUTPUT_APK_LIVESERVER}\n"
            MAIL_TEXT="${MAIL_TEXT}${GRADLE_TASK_LIVESERVER}(debug)(${SIZE_LIVE_APP_FILE}B): <a href=${HTTPS_PREFIX}${OUTPUT_APK_LIVESERVER}>${HTTPS_PREFIX}${OUTPUT_APK_LIVESERVER}</a><br />"
            if [[ $USING_BUNDLE_LIVESERVER -eq 1 && -f $BUNDLE_TOOL ]]; then
                BUNDLE_APK_FILE="$OUTPUT_FOLDER/${OUTPUT_APK_LIVESERVER%.aab}.apks"
                if [ -f $KEYSTORE_FILE ]; then
                    $BUNDLE_TOOL build-apks --bundle="$OUTPUT_FOLDER/$OUTPUT_APK_LIVESERVER" --output="$BUNDLE_APK_FILE" --mode=universal --ks="$KEYSTORE_FILE" --ks-pass="pass:$STOREPASS" --ks-key-alias="$KEYSTORE_ALIAS"
                else
                    $BUNDLE_TOOL build-apks --bundle="$OUTPUT_FOLDER/$OUTPUT_APK_LIVESERVER" --output="$BUNDLE_APK_FILE" --mode=universal
                fi
                BUNDLE_APK2ZIP="${BUNDLE_APK_FILE%.apks}.zip"
                mv "${BUNDLE_APK_FILE}" "${BUNDLE_APK2ZIP}"
                unzip "${BUNDLE_APK2ZIP}"
                BUNDLE_APK_FILE="$OUTPUT_FOLDER/${APK_GOOGLESTORE%.aab}.apk"
                if [ -f universal.apk ]; then
                    touch universal.apk
                    mv universal.apk "$BUNDLE_APK_FILE"
                    if [ -f toc.pd ]; then
                        rm toc.pd
                    fi
                    if [ -f $BUNDLE_APK2ZIP ]; then
                        rm $BUNDLE_APK2ZIP
                    fi
                fi
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
            $FlutterBin clean
            $FlutterBin pub get

            if test -z $FLUTTER_FLAG; then
                $FlutterBin build ${flutterBuildKey} --flavor ${GRADLE_TASK_TESTSERVER}
            else
                $FlutterBin build ${flutterBuildKey} --flavor ${GRADLE_TASK_TESTSERVER} ${FLUTTER_FLAG}
            fi
        elif [ $isReactNativeEnabled -eq 1 ]; then
            if [ -d ${WORKSPACE}/android ]; then
                cd ${WORKSPACE}/android
            fi
            GRADLE_TASK="${gradleBuildKey}Debug"
            if [[ $(./gradlew tasks 2>&1 | grep -v '^Warning' | grep "${gradleBuildKey}${GRADLE_TASK_TESTSERVER}" | awk '{print $1}' | tr -d ' ') == "${gradleBuildKey}${GRADLE_TASK_TESTSERVER}" ]]; then
                GRADLE_TASK="${gradleBuildKey}${GRADLE_TASK_TESTSERVER}Debug"
            fi
            ./gradlew "${GRADLE_TASK}"
            if [ -d ${WORKSPACE}/android ]; then
                cd ${WORKSPACE}
            fi
        else
            ./gradlew "${gradleBuildKey}${GRADLE_TASK_TESTSERVER}"
        fi

        if test -z "$APK_TESTSERVER"; then
            LOWER_MODE_NAME="$(echo ${RELEASE_TYPE_TESTSERVER} | tr 'A-Z' 'a-z')"
            LOWERCASE_TASK_NAME="$(echo ${GRADLE_TASK_TESTSERVER} | tr 'A-Z' 'a-z')"
            makePathForAndroidOutput
            APK_TESTSERVER="$BUILD_APK_OUTPUT"
        fi
        if [ -f $BUILD_OUTPUT_FOLDER/$APK_TESTSERVER ]; then
            mv "$BUILD_OUTPUT_FOLDER/$APK_TESTSERVER" "$OUTPUT_FOLDER/$OUTPUT_APK_TESTSERVER"
            SIZE_TEST_APP_FILE=$(du -sh ${OUTPUT_FOLDER}/${OUTPUT_APK_TESTSERVER} | awk '{print $1}')
            SLACK_TEXT="${SLACK_TEXT}${HOSTNAME} > ${GRADLE_TASK_TESTSERVER}(${RELEASE_TYPE_TESTSERVER})(${SIZE_TEST_APP_FILE}B): ${HTTPS_PREFIX}${OUTPUT_APK_TESTSERVER}\n"
            MAIL_TEXT="${MAIL_TEXT}${GRADLE_TASK_TESTSERVER}(${RELEASE_TYPE_TESTSERVER})(${SIZE_TEST_APP_FILE}B): <a href=${HTTPS_PREFIX}${OUTPUT_APK_TESTSERVER}>${HTTPS_PREFIX}${OUTPUT_APK_TESTSERVER}</a><br />"
            if [[ $USING_BUNDLE_TESTSERVER -eq 1 && -f $BUNDLE_TOOL ]]; then
                BUNDLE_APK_FILE="$OUTPUT_FOLDER/${OUTPUT_APK_TESTSERVER%.aab}.apks"
                if [ -f $KEYSTORE_FILE ]; then
                    $BUNDLE_TOOL build-apks --bundle="$OUTPUT_FOLDER/$OUTPUT_APK_TESTSERVER" --output="$BUNDLE_APK_FILE" --mode=universal --ks="$KEYSTORE_FILE" --ks-pass="pass:$STOREPASS" --ks-key-alias="$KEYSTORE_ALIAS"
                else
                    $BUNDLE_TOOL build-apks --bundle="$OUTPUT_FOLDER/$OUTPUT_APK_TESTSERVER" --output="$BUNDLE_APK_FILE" --mode=universal
                fi
                BUNDLE_APK2ZIP="${BUNDLE_APK_FILE%.apks}.zip"
                mv "${BUNDLE_APK_FILE}" "${BUNDLE_APK2ZIP}"
                unzip "${BUNDLE_APK2ZIP}"
                BUNDLE_APK_FILE="$OUTPUT_FOLDER/${APK_GOOGLESTORE%.aab}.apk"
                if [ -f universal.apk ]; then
                    touch universal.apk
                    mv universal.apk "$BUNDLE_APK_FILE"
                    if [ -f toc.pd ]; then
                        rm toc.pd
                    fi
                    if [ -f $BUNDLE_APK2ZIP ]; then
                        rm $BUNDLE_APK2ZIP
                    fi
                fi
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
            if [ $USING_BUNDLE_GOOGLESTORE -eq 1 ]; then
                BUNDLE_APK_FILE="$OUTPUT_FOLDER/${APK_GOOGLESTORE%.aab}.apk"
                if [ -f $BUNDLE_APK_FILE ]; then
                    rm -f $OUTPUT_FOLDER/$BUNDLE_APK_FILE
                fi
            fi
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
        if [ $USING_BUNDLE_GOOGLESTORE -eq 1 ]; then
            SCP_BUNDLE_APK_FILE="$OUTPUT_FOLDER/${APK_GOOGLESTORE%.aab}.apk"
            if [ -f ${SCP_BUNDLE_APK_FILE} ]; then
                if [ $(sendFile ${SCP_BUNDLE_APK_FILE} ${NEO2UA_OUTPUT_FOLDER}) -eq 0 ]; then
                    #   echo "Failed to send file"
                    echo "TODO: **NEED** to resend this file => ${SCP_BUNDLE_APK_FILE} to ${NEO2UA_OUTPUT_FOLDER}"
                fi
            fi
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
        if [ -f ${OUTPUT_FOLDER}/${APK_GOOGLESTORE} ]; then
            if [ -f $WORKSPACE/${ANDROID_APP_PATH}/check.sh -a $IS_RELEASE -eq 1 ]; then
                chmod +x $WORKSPACE/${ANDROID_APP_PATH}/check.sh
                if command -v $A2PS >/dev/null && command -v $GS >/dev/null; then
                    cd $WORKSPACE/${ANDROID_APP_PATH} && echo "$GIT_USER $(hostname -s) ${WORKSPACE} (${GIT_BRANCH})" >merong.txt
                    cd $WORKSPACE/${ANDROID_APP_PATH} && echo "$ ./check.sh -a src" >>merong.txt
                    cd $WORKSPACE/${ANDROID_APP_PATH} && ./check.sh -a src >>merong.txt
                    cd $WORKSPACE/${ANDROID_APP_PATH} && cat merong.txt | $A2PS -=book -B -q --medium=A4dj --borders=no -o out1.ps && $GS -sDEVICE=png256 -dNOPAUSE -dBATCH -dSAFER -dTextAlphaBits=4 -q -r300x300 -sOutputFile=out2.png out1.ps
                    if command -v $CONVERT >/dev/null; then
                        cd $WORKSPACE/${ANDROID_APP_PATH} && $CONVERT -trim out2.png $OUTPUT_FOLDER/$Obfuscation_SCREENSHOT
                    else
                        cp out2.png $OUTPUT_FOLDER/$Obfuscation_SCREENSHOT
                    fi
                    cd $WORKSPACE/${ANDROID_APP_PATH} && rm -f out[12].png out[12].ps merong.txt

                    if [ -f $WORKSPACE/$Obfuscation_INPUT_FILE ]; then
                        cp -f $WORKSPACE/$Obfuscation_INPUT_FILE $OUTPUT_FOLDER/$Obfuscation_OUTPUT_FILE
                    elif [ -f ${APP_ROOT_PREFIX}/${TOP_PATH}/$Obfuscation_INPUT_FILE ]; then
                        cp -f ${APP_ROOT_PREFIX}/${TOP_PATH}/$Obfuscation_INPUT_FILE $OUTPUT_FOLDER/$Obfuscation_OUTPUT_FILE
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
fi
