#!/bin/sh
##
. "${TOP_DIR}/platform/jb_json_helpers.sh"
. "${TOP_DIR}/platform/jb_dryrun.sh"
. "${TOP_DIR}/plugins/ixshield_ios.sh"

function makeObfuscationScreenshot() {
    jb_ixshield_make_obfuscation_screenshot
}

function initializeIOSBuildConfig() {
    APP_VERSION="MARKETING_VERSION"
    if test -f "${WORKSPACE}/${INFO_PLIST}"; then
        if test ! -z $(grep 'CFBundleShortVersionString' "${WORKSPACE}/${INFO_PLIST}"); then
            if [ -f "${WORKSPACE}/${INFO_PLIST}" ]; then
                APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${WORKSPACE}/${INFO_PLIST}")
                BUILD_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${WORKSPACE}/${INFO_PLIST}")
            fi
        fi
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
    OUTBOUND_HTTPS_PREFIX="${OUTBOUND_POINT}/${TOP_PATH}/${APP_ROOT_SUFFIX}/${APP_VERSION}/"
    ###################
    USING_APPSTORE=$(jb_jq_bool '.ios.AppStore.enabled')
    if [ $USING_APPSTORE -eq 1 ]; then
        SCHEME_APPSTORE=$(jb_jq_str '.ios.AppStore.schemeName')
        TARGET_APPSTORE=$(jb_jq_str '.ios.AppStore.targetName')
        BUNDLE_ID_APPSTORE=$(jb_jq_str '.ios.AppStore.bundleId')
        BUNDLE_NAME_APPSTORE=$(jb_jq_str '.ios.AppStore.bundleName')
    fi
    USING_ADHOC=$(jb_jq_bool '.ios.Adhoc.enabled')
    if [ $USING_ADHOC -eq 1 ]; then
        SCHEME_ADHOC=$(jb_jq_str '.ios.Adhoc.schemeName')
        TARGET_ADHOC=$(jb_jq_str '.ios.Adhoc.targetName')
        BUNDLE_ID_ADHOC=$(jb_jq_str '.ios.Adhoc.bundleId')
        BUNDLE_NAME_ADHOC=$(jb_jq_str '.ios.Adhoc.bundleName')
        USING_ADHOC_DEBUG=$(jb_jq_bool '.ios.Adhoc.buildDebugVersion')
    fi
    USING_ENTERPRISE=$(jb_jq_bool '.ios.Enterprise.enabled')
    if [ $USING_ENTERPRISE -eq 1 ]; then
        SCHEME_ENTER=$(jb_jq_str '.ios.Enterprise.schemeName')
        TARGET_ENTER=$(jb_jq_str '.ios.Enterprise.targetName')
        BUNDLE_ID_ENTER=$(jb_jq_str '.ios.Enterprise.bundleId')
        BUNDLE_NAME_ENTER=$(jb_jq_str '.ios.Enterprise.bundleName')
    fi
    USING_ENTER4WEB=$(jb_jq_bool '.ios.Enterprise4WebDebug.enabled')
    if [ $USING_ENTER4WEB -eq 1 ]; then
        SCHEME_ENTER4WEB=$(jb_jq_str '.ios.Enterprise4WebDebug.schemeName')
        TARGET_ENTER4WEB=$(jb_jq_str '.ios.Enterprise4WebDebug.targetName')
        BUNDLE_ID_ENTER4WEB=$(jb_jq_str '.ios.Enterprise4WebDebug.bundleId')
        BUNDLE_NAME_ENTER4WEB=$(jb_jq_str '.ios.Enterprise4WebDebug.bundleName')
    fi
    ###################
    if [ ! -d $DST_ROOT ]; then
        jb_fs_write "ios dst root mkdir" mkdir -p "$DST_ROOT"
        chmod 777 $DST_ROOT
    fi
    if [ -d $DST_ROOT/Applications ]; then
        jb_fs_remove "ios cleanup dst applications" rm -rf "${DST_ROOT}/Applications"
    fi
    if [ ! -d $APP_ROOT ]; then
        jb_fs_write "ios app root mkdir" mkdir -p "$APP_ROOT"
        chmod 777 $APP_ROOT
    fi
    if [ ! -d $OUTPUT_FOLDER ]; then
        jb_fs_write "ios output folder mkdir" mkdir -p "$OUTPUT_FOLDER"
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
    ####################
    ##
    if [ $IS_RELEASE -eq 1 ]; then
        VERSION_STRING="${APP_VERSION}(${BUILD_VERSION})"
    elif [ "$APP_VERSION" != "" ]; then
        VERSION_STRING="${APP_VERSION}.${BUILD_VERSION}"
    else
        VERSION_STRING=""
    fi
    OUTPUT_FILENAME_APPSTORE_SUFFIX=$(cat $jsonConfig | $JQ '.ios.AppStore.fileSuffix' | tr -d '"')
    OUTPUT_FILENAME_APPSTORE="${OUTPUT_PREFIX}${VERSION_STRING}_${FILE_TODAY}${OUTPUT_FILENAME_APPSTORE_SUFFIX}"
    OUTPUT_FILENAME_APPSTORE_IPA="${OUTPUT_FILENAME_APPSTORE}.ipa"
    OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK="${OUTPUT_PREFIX}${VERSION_STRING}_${FILE_TODAY}_IxShieldCheck.png"
    OUTPUT_FILENAME_APPSTORE_DSYM="${OUTPUT_FILENAME_APPSTORE}_dSYM.zip"
    TEMP_APPSTORE_APP_FOLDER="${OUTPUT_FILENAME_APPSTORE}.app"
    OUTPUT_FILE="${OUTPUT_FOLDER}/${TARGET_APPSTORE}"
    ##
    OUTPUT_FILENAME_ADHOC_SUFFIX=$(cat $jsonConfig | $JQ '.ios.Adhoc.fileSuffix' | tr -d '"')
    OUTPUT_FILENAME_ADHOC="${OUTPUT_PREFIX}${VERSION_STRING}_${FILE_TODAY}${OUTPUT_FILENAME_ADHOC_SUFFIX}"
    OUTPUT_FILENAME_ADHOC_IPA="${OUTPUT_FILENAME_ADHOC}.ipa"
    OUTPUT_FILENAME_ADHOC_PLIST="${OUTPUT_FILENAME_ADHOC}.plist"
    ##
    OUTPUT_FILENAME_ENTER_SUFFIX=$(cat $jsonConfig | $JQ '.ios.Enterprise.fileSuffix' | tr -d '"')
    OUTPUT_FILENAME_ENTER="${OUTPUT_PREFIX}${VERSION_STRING}_${FILE_TODAY}${OUTPUT_FILENAME_ENTER_SUFFIX}"
    OUTPUT_FILENAME_ENTER_IPA="${OUTPUT_FILENAME_ENTER}.ipa"
    OUTPUT_FILENAME_ENTER_PLIST="${OUTPUT_FILENAME_ENTER}.plist"
    ##
}

# iOS Shell Script
XCODE=$(command -v xcodebuild)
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
if [[ -z "$OBFUSCATION_TEST" ]]; then
    if jb_is_dry_run; then
        echo "[DRY-RUN] skip xcode-select switch: ${XCODE_DEVELOPER_LAST}"
    elif test ! -z "$sudoPassword"; then
        sudo -S xcode-select -s $XCODE_DEVELOPER_LAST <<<"${sudoPassword}"
    fi
fi
###################
ZIP="/usr/bin/zip"
POD=$(which pod)
if test -z "$POD"; then
    POD="/usr/local/bin/pod"
fi
###################
APP_PATH="${TOP_PATH}/ios"
APP_ROOT_SUFFIX="ios_distributions"
if test -z $PROJECT_NAME; then
    echo ""
    echo "Error: please finish setup distribution site, see following path:"
    if [ $CUSTOM_CONFIG -eq 1 ]; then
        echo "       ${CUSTOM_CONFIG_PATH}"
    else
        echo "       ${DEFAULT_CONFIG_JSON}"
    fi
    exit
fi
###################
###################
function doExecuteIOS() {
    if jb_is_dry_run; then
        jb_dryrun_header "ios"
        jb_dryrun_step "ios.pre.flutter_or_react" "Flutter/React Native 사전 빌드 준비" "$FlutterBin build ios || $ReactNativeBin run build:ios"
        jb_dryrun_step "ios.pre.init_config" "버전/출력 경로/대상 설정 초기화" "initializeIOSBuildConfig"
        jb_dryrun_step "ios.pre.pods" "Pod install/update (선택)" "pod install|update"
        jb_dryrun_step "ios.pre.unlock_keychain" "서명용 keychain unlock (선택)" "security unlock-keychain"
        jb_dryrun_step "ios.build.archive" "xcodebuild archive/export 실행" "xcodebuild ... archive; xcodebuild -exportArchive ..."
        jb_dryrun_step "ios.output.package" "IPA 패키징/이동(zip, mv)" "zip -r ... Payload && mv ... ${OUTPUT_FOLDER}"
        jb_dryrun_step "ios.output.cleanup" "산출물 제거/정리(옵션)" "rm -f <distribution binary>"
        jb_dryrun_step "ios.output.plist" "OTA plist 생성" "echo <plist> > ${OUTPUT_FOLDER}/*.plist"
        jb_dryrun_step "ios.scp.upload" "원격 배포 경로 전송(옵션)" "sendFile <artifact> <remote dir>"
        jb_dryrun_step "ios.obfuscation.proof" "IxShield 증적 스크린샷 생성" "makeObfuscationScreenshot"
        return 0
    fi

    if [ $isFlutterEnabled -eq 1 ]; then
        export SDKROOT="/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
        export LANG=en_US.UTF-8
        # if test -z ${GEM_PATH}; then
        #     export GEM_PATH="/System/Library/Frameworks/Ruby.framework/Versions/2.6/usr/lib/ruby/gems/2.6.0"
        # fi

        POD_EXEC_DIR=$(dirname ${POD})
        export PATH=${POD_EXEC_DIR}:$PATH
        $FlutterBin clean
        $FlutterBin pub get
        if test -z "$FLUTTER_FLAG"; then
            $FlutterBin build ios
        else
            $FlutterBin build ios ${FLUTTER_FLAG}
        fi
        # Flutter 빌드 후 생성된 *null 파일들 확인 및 삭제
        # APP_ROOT_PREFIX 내에서 *null 파일들 검색
        NULL_FILES=$(find ${APP_ROOT_PREFIX} -name "*null" -type f 2>/dev/null)
        if [ ! -z "$NULL_FILES" ]; then
            find ${APP_ROOT_PREFIX} -name "*null" -type f -delete 2>/dev/null
            echo "Removed all *null files from ${APP_ROOT_PREFIX}"
        else
            echo "No *null files found in ${APP_ROOT_PREFIX}"
        fi
    elif [ $isReactNativeEnabled -eq 1 ]; then
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

        $ReactNativeBin run build:ios
    fi
    ############################################################################
    ## Make path and version info 호출
    initializeIOSBuildConfig
    ############################################################################
    if [ $isFlutterEnabled -ne 1 -a -f ${WORKSPACE}/${POD_FILE} ]; then
        POD_LOCK_FILE="${WORKSPACE}/${POD_FILE}.lock"
        cd $(dirname ${WORKSPACE}/${POD_FILE})
        export LANG=en_US.UTF-8
        # if test -z ${GEM_PATH}; then
        #     export GEM_PATH="/System/Library/Frameworks/Ruby.framework/Versions/2.6/usr/lib/ruby/gems/2.6.0"
        # fi
        if [ ! -f $POD_LOCK_FILE ]; then
            if [ $(uname -p) == "arm" -a $isReactNativeEnabled -ne 1 ]; then
                arch -x86_64 $POD install
            else
                $POD install
            fi
        else
            if [ $(uname -p) == "arm" -a $isReactNativeEnabled -ne 1 ]; then
                arch -x86_64 $POD update
            else
                $POD update
            fi
        fi
    fi
    ###################
    XCODE_OPTION="-workspace"
    XCODE_WORKSPACE="${WORKSPACE}/${PROJECT_NAME}.xcworkspace"
    if [ ! -d $XCODE_WORKSPACE ]; then
        XCODE_WORKSPACE="${WORKSPACE}/${PROJECT_NAME}.xcodeproj"
        if [ ! -d $XCODE_WORKSPACE ]; then
            echo ""
            echo "Error: cannot find the target workspace or project, $XCODE_WORKSPACE"
            echo ""
            exit
        else
            XCODE_OPTION="-project"
        fi
    fi
    ###################
    if [ $DEBUGGING -eq 0 ]; then
        # unlock the keychain to make code signing work
        if test -n "$sudoPassword"; then
            if [[ "$sudoPassword" != "qwer1234" ]]; then
                sudo -S su ${jenkinsUser} -c "security unlock-keychain -p "${sudoPassword}" ${HOME}/Library/Keychains/login.keychain" <<<"${sudoPassword}"
            fi
        fi
    fi
    ###################
    # Step 1.1: Build target for AppStore (We don't need AppStore version for preRelease)
    if [ $DEBUGGING -eq 0 ]; then
        if [ $IS_RELEASE -eq 1 -a $USING_APPSTORE -eq 1 ]; then
            ARCHIVE_FILE="${OUTPUT_PREFIX}${VERSION_STRING}_${FILE_TODAY}.xcarchive"
            ARCHIVE_PATH="${OUTPUT_FOLDER}/${ARCHIVE_FILE}"
            if [ $CUSTOM_EXPORT_OPTIONS -eq 1 -a -f "$CUSTOM_EXPORT_OPTIONS_PATH" ]; then
                plistConfig="${CUSTOM_EXPORT_OPTIONS_PATH}"
            else
                plistConfig="${APP_ROOT_PREFIX}/${TOP_PATH}/config/ExportOptions_AppStore.plist"
            fi
            EXPORT_PLIST="${APP_ROOT}/ExportOptions.plist"
            if [ -f $plistConfig ]; then
                jb_fs_copy "ios copy export options plist" cp "$plistConfig" "$EXPORT_PLIST"
                chmod 777 $EXPORT_PLIST
                echo ""
                echo "Warning: should modify ``ExportOptions.plist`` for binary(IPK) of App Store"
                echo ""
            fi
            if [ ! -f "$EXPORT_PLIST" ]; then
                APPSTORE_BUNDLE_IDENTIFIER=$(cat $jsonConfig | $JQ '.ios.AppStore.bundleId' | tr -d '"')
                APPSTORE_TEAM_ID=$(cat $jsonConfig | $JQ '.ios.AppStore.teamId' | tr -d '"')
                APPSTORE_KEY_STRING=$(cat $jsonConfig | $JQ '.ios.AppStore.appKeyString' | tr -d '"')
                APPSTORE_NOTIFICATION_KEY_STRING=$(cat $jsonConfig | $JQ '.ios.AppStore.notificationKeyString' | tr -d '"')
                printf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<"'!'"DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n\t<key>method</key>\n\t<string>app-store-connect</string>\n\t<key>provisioningProfiles</key>\n\t<dict>\n\t\t<key>${APPSTORE_BUNDLE_IDENTIFIER}</key>\n\t\t<string>${APPSTORE_KEY_STRING}</string>\n\t\t<key>${APPSTORE_BUNDLE_IDENTIFIER}.NotificationServiceExtension</key>\n\t\t<string>${APPSTORE_NOTIFICATION_KEY_STRING}</string>\n\t</dict>\n\t<key>signingCertificate</key>\n\t<string>iPhone Distribution</string>\n\t<key>signingStyle</key>\n\t<string>manual</string>\n\t<key>stripSwiftSymbols</key>\n\t<true/>\n\t<key>teamID</key>\n\t<string>${APPSTORE_TEAM_ID}</string>\n\t<key>uploadBitcode</key>\n\t<false/>\n\t<key>uploadSymbols</key>\n\t<true/>\n</dict>\n</plist>\n" \
                >$EXPORT_PLIST
            elif [ -f "$EXPORT_PLIST" ]; then
                APPSTORE_BUNDLE_IDENTIFIER=$(cat $jsonConfig | $JQ '.ios.AppStore.bundleId' | tr -d '"')
                APPSTORE_KEY_STRING=$(/usr/libexec/PlistBuddy -c "Print :provisioningProfiles:${APPSTORE_BUNDLE_IDENTIFIER}" $EXPORT_PLIST)
                if [[ "$APPSTORE_KEY_STRING" == "company_iphone_Appstore" ]]; then
                    APPSTORE_TEAM_ID=$(cat $jsonConfig | $JQ '.ios.AppStore.teamId' | tr -d '"')
                    APPSTORE_KEY_STRING=$(cat $jsonConfig | $JQ '.ios.AppStore.appKeyString' | tr -d '"')
                    APPSTORE_NOTIFICATION_KEY_STRING=$(cat $jsonConfig | $JQ '.ios.AppStore.notificationKeyString' | tr -d '"')
                    printf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<"'!'"DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n\t<key>method</key>\n\t<string>app-store-connect</string>\n\t<key>provisioningProfiles</key>\n\t<dict>\n\t\t<key>${APPSTORE_BUNDLE_IDENTIFIER}</key>\n\t\t<string>${APPSTORE_KEY_STRING}</string>\n\t\t<key>${APPSTORE_BUNDLE_IDENTIFIER}.NotificationServiceExtension</key>\n\t\t<string>${APPSTORE_NOTIFICATION_KEY_STRING}</string>\n\t</dict>\n\t<key>signingCertificate</key>\n\t<string>iPhone Distribution</string>\n\t<key>signingStyle</key>\n\t<string>manual</string>\n\t<key>stripSwiftSymbols</key>\n\t<true/>\n\t<key>teamID</key>\n\t<string>${APPSTORE_TEAM_ID}</string>\n\t<key>uploadBitcode</key>\n\t<false/>\n\t<key>uploadSymbols</key>\n\t<true/>\n</dict>\n</plist>\n" \
                    >$EXPORT_PLIST
                fi
            fi
            # $XCODE $XCODE_OPTION "${XCODE_WORKSPACE}" -scheme "${SCHEME_APPSTORE}" -sdk iphoneos -configuration AppStoreDistribution archive -archivePath ${ARCHIVE_PATH}
            $XCODE $XCODE_OPTION "${XCODE_WORKSPACE}" -scheme "${SCHEME_APPSTORE}" -sdk iphoneos -skip-test-configuration -configuration archive -archivePath ${ARCHIVE_PATH}
            $XCODE -exportArchive -archivePath ${ARCHIVE_PATH} -exportOptionsPlist ${EXPORT_PLIST} -exportPath ${OUTPUT_FOLDER}
        fi
        xcodeArgument="SYMROOT=${DST_ROOT} DSTROOT=${DST_ROOT}"
        # xcodeArgument="DSTROOT=\"${DST_ROOT}\""
        xcodeVer="$($XCODE -version | grep Xcode | sed -e 's/Xcode //g')"
        usingXcodeAbove_14_3=0
        compareVer="14.3.1"
        resultcomp=$(vercomp $xcodeVer $compareVer) # return 0 mean same, 1 mean $xcodeVer > $compareVer, 2 mean $xcodeVer < $compareVer
        if [ $resultcomp -lt 2 ]; then
            xcodeArgument="-derivedDataPath ${DST_ROOT} -archivePath ${DST_ROOT}"
            # xcodeArgument="-archivePath \"${DST_ROOT}\""
            usingXcodeAbove_14_3=1
        fi
        if [ $USING_ADHOC -eq 1 ]; then
            # Step 1.2: Build target for AdHoc
            $XCODE $XCODE_OPTION "${XCODE_WORKSPACE}" -scheme "${SCHEME_ADHOC}" -destination "generic/platform=iOS" archive ${xcodeArgument}/${SCHEME_ADHOC} -verbose

            # Step 1.2.1: Build target for AdHoc as 'DEBUG' mode
            if [ $USING_ADHOC_DEBUG -eq 1 -a $IS_RELEASE -eq 1 -a $USING_APPSTORE -eq 1 ]; then
                # /usr/bin/xcodebuild -workspace /Users/company/.jenkins/workspace/Gapp4/GApp4-iOS/Gapp3.xcworkspace -scheme GApp3_Adhoc -destination generic/platform=iOS archive -derivedDataPath /tmp/Gapp3/R4.3.1_2 -archivePath /tmp/Gapp3/R4.3.1_2/GApp3_Adhoc_Debug -verbose OTHER_CFLAGS='$(inherited) -DADHOC_DEBUG=1'
                $XCODE $XCODE_OPTION "${XCODE_WORKSPACE}" -scheme "${SCHEME_ADHOC}" -destination "generic/platform=iOS" archive ${xcodeArgument}/${SCHEME_ADHOC}_Debug -verbose OTHER_CFLAGS='$(inherited) -DDEBUG=1'
            fi
        fi
        if [ $USING_ENTERPRISE -eq 1 ]; then
            BUILD_CONFIG=""
            # DONE: add condition for flutter or react-native
            if [ -d "$WORKSPACE/ios" ]; then
                cd "$WORKSPACE/ios"
                # xcodebuild -list 실행 및 Scheme 목록 추출
                SCHEMES=$(xcodebuild -list | awk '/Schemes:/ {found=1; next} found && NF')
                # "${SCHEME_ENTER}" Scheme 확인
                ENTER_SCHEME=$(echo "$SCHEMES" | tr -d " " | grep -E "^${SCHEME_ENTER}$")
                # 'enter'가 없으면 다른 Scheme 선택 (첫 번째 값)
                if [[ -z "$ENTER_SCHEME" ]]; then
                    TMP_SCHEME_ENTER="${SCHEME_ENTER}"
                    SCHEME_ENTER=$(echo "$SCHEMES" | head -n 1 | sed 's/^[ \t]*//')
                    if xcodebuild -list | awk "/Build Configurations:/ {flag=1; next} /^[[:space:]]*$/ {flag=0} flag && /Release-${TMP_SCHEME_ENTER}/"; then
                        BUILD_CONFIG="-configuration Release-${TMP_SCHEME_ENTER}"
                    fi
                fi
            fi
            # Step 1.3: Build target for Enterprise
            $XCODE $XCODE_OPTION "${XCODE_WORKSPACE}" -scheme "${SCHEME_ENTER}" ${BUILD_CONFIG} -destination "generic/platform=iOS" archive ${xcodeArgument}/${SCHEME_ENTER} -verbose
        fi
        if [ $USING_ENTER4WEB -eq 1 ]; then
            # Step 1.4: Build target for Enterprise
            $XCODE $XCODE_OPTION "${XCODE_WORKSPACE}" -scheme "${SCHEME_ENTER4WEB}" -destination "generic/platform=iOS" archive ${xcodeArgument}/${SCHEME_ENTER4WEB} -verbose
        fi
    fi
    ###################
    # Step 2.0: Prepare
    if [ $USING_APPSTORE -eq 1 -a $IS_RELEASE -eq 1 ]; then
        ###################
        # Step 2.1: Copy ``App Store'' target from Applications to OUTPUT_FOLDER
        if [ -f "${OUTPUT_FILE}" ]; then
            jb_fs_copy "ios move appstore ipa" mv "$OUTPUT_FILE" "${OUTPUT_FOLDER}/${OUTPUT_FILENAME_APPSTORE_IPA}"
            SIZE_STORE_APP_FILE=$(du -sh "${OUTPUT_FOLDER}/${OUTPUT_FILENAME_APPSTORE_IPA}" | awk '{print $1}')

            if [ ! -d $OUTPUT_FOLDER/$TEMP_APPSTORE_APP_FOLDER ]; then
                jb_fs_write "ios mkdir temp appstore folder" mkdir -p "$OUTPUT_FOLDER/$TEMP_APPSTORE_APP_FOLDER"
            fi
            if [ -f $OUTPUT_FOLDER/DistributionSummary.plist ]; then
                jb_fs_copy "ios move DistributionSummary plist" mv -f "$OUTPUT_FOLDER/DistributionSummary.plist" "$OUTPUT_FOLDER/$TEMP_APPSTORE_APP_FOLDER/"
            fi
            if [ -f $OUTPUT_FOLDER/ExportOptions.plist ]; then
                jb_fs_copy "ios move ExportOptions plist" mv -f "$OUTPUT_FOLDER/ExportOptions.plist" "$OUTPUT_FOLDER/$TEMP_APPSTORE_APP_FOLDER/"
            fi
            if [ -f $OUTPUT_FOLDER/Packaging.log ]; then
                jb_fs_copy "ios move Packaging log" mv -f "$OUTPUT_FOLDER/Packaging.log" "$OUTPUT_FOLDER/$TEMP_APPSTORE_APP_FOLDER/"
            fi
            if [ -d $ARCHIVE_PATH ]; then
                if [ -d $OUTPUT_FOLDER/$TEMP_APPSTORE_APP_FOLDER/$ARCHIVE_FILE ]; then
                    jb_fs_remove "ios remove stale archive folder" rm -rf "$OUTPUT_FOLDER/$TEMP_APPSTORE_APP_FOLDER/$ARCHIVE_FILE"
                fi
                jb_fs_copy "ios move archive folder" mv -f "$ARCHIVE_PATH" "$OUTPUT_FOLDER/$TEMP_APPSTORE_APP_FOLDER/"
            fi
            ###################
            ## 난독화 증적 자료 생성
            makeObfuscationScreenshot
        fi
        ###################
        # Step 2.1.2: Remove archive folder
        if [ -d $OUTPUT_FOLDER/$TEMP_APPSTORE_APP_FOLDER ]; then
            if [ $USING_DSYM -eq 1 ]; then
                # find dSYM file for App Store binary(IPA)
                if [ -d /tmp/${PROJECT_NAME}/${LOCAL_BRANCH}/${TEMP_APPSTORE_APP_FOLDER} ]; then
                    jb_fs_remove "ios remove stale tmp app folder" rm -rf "/tmp/${PROJECT_NAME}/${LOCAL_BRANCH}/${TEMP_APPSTORE_APP_FOLDER}"
                fi
                jb_fs_copy "ios move temp app folder to tmp" mv "$OUTPUT_FOLDER/$TEMP_APPSTORE_APP_FOLDER" "/tmp/${PROJECT_NAME}/${LOCAL_BRANCH}/"
                cd /tmp/${PROJECT_NAME}/${LOCAL_BRANCH}/${TEMP_APPSTORE_APP_FOLDER}/${ARCHIVE_FILE}
                DSYM_FOLDER=$(find . -name '*.dSYM' | grep -v 'Intermediates')
                zip -vr ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_APPSTORE_DSYM} ${DSYM_FOLDER} -x "*.DS_Store"
                cd -
                SIZE_STORE_DSYM_FILE=$(du -sh "${OUTPUT_FOLDER}/${OUTPUT_FILENAME_APPSTORE_DSYM}" | awk '{print $1}')
            else
                jb_fs_remove "ios cleanup temp appstore folder" rm -rf "$OUTPUT_FOLDER/$TEMP_APPSTORE_APP_FOLDER"
            fi
        fi
    fi
    ###################
    # Step 2.2: Copy ``Ad-Hoc'' target from Applications to OUTPUT_FOLDER
    if [ $USING_ADHOC -eq 1 ]; then
        INSTALL_ROOT=${DST_ROOT}
        if [ $usingXcodeAbove_14_3 -eq 1 ]; then
            INSTALL_ROOT="${DST_ROOT}/${SCHEME_ADHOC}.xcarchive/Products"
        else
            INSTALL_ROOT="${DST_ROOT}/${SCHEME_ADHOC}"
        fi
        OUTPUT_FILE="${INSTALL_ROOT}/Applications/${OUTPUT_FILENAME_ADHOC_IPA}"
        if [ -d "${INSTALL_ROOT}/Applications/${TARGET_ADHOC}" ]; then
            if [ -d ${INSTALL_ROOT}/Applications/Payload ]; then
                jb_fs_remove "ios cleanup adhoc payload" rm -rf "${INSTALL_ROOT}/Applications/Payload"
            fi
            jb_fs_write "ios mkdir adhoc payload" mkdir -p "${INSTALL_ROOT}/Applications/Payload"
            jb_fs_copy "ios move adhoc app to payload" mv "${INSTALL_ROOT}/Applications/${TARGET_ADHOC}" "${INSTALL_ROOT}/Applications/Payload"
            cd "${INSTALL_ROOT}/Applications"
            $ZIP -r "${OUTPUT_FILE}" Payload
            jb_fs_copy "ios move adhoc ipa output" mv "$OUTPUT_FILE" "${OUTPUT_FOLDER}/"
            SIZE_ADHOC_APP_FILE=$(du -sh ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ADHOC_IPA} | awk '{print $1}')
        else
            exit 255
        fi

        # Target AdHoc for Debug
        if [ $USING_ADHOC_DEBUG -eq 1 -a $IS_RELEASE -eq 1 -a $USING_APPSTORE -eq 1 ]; then
            INSTALL_ROOT="${DST_ROOT}/${SCHEME_ADHOC}_Debug.xcarchive/Products"
            OUTPUT_FILENAME_ADHOC_IPA="${OUTPUT_FILENAME_ADHOC}_Debug.ipa"
            OUTPUT_FILE="${INSTALL_ROOT}/Applications/${OUTPUT_FILENAME_ADHOC_IPA}"
            if [ -d "${INSTALL_ROOT}/Applications/${TARGET_ADHOC}" ]; then
                if [ -d ${INSTALL_ROOT}/Applications/Payload ]; then
                    jb_fs_remove "ios cleanup adhoc debug payload" rm -rf "${INSTALL_ROOT}/Applications/Payload"
                fi
                jb_fs_write "ios mkdir adhoc debug payload" mkdir -p "${INSTALL_ROOT}/Applications/Payload"
                jb_fs_copy "ios move adhoc debug app to payload" mv "${INSTALL_ROOT}/Applications/${TARGET_ADHOC}" "${INSTALL_ROOT}/Applications/Payload"
                cd "${INSTALL_ROOT}/Applications"
                $ZIP -r "${OUTPUT_FILE}" Payload
                jb_fs_copy "ios move adhoc debug ipa output" mv "$OUTPUT_FILE" "${OUTPUT_FOLDER}/"
                SIZE_ADHOC_DEBUG_FILE=$(du -sh ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ADHOC_IPA} | awk '{print $1}')
            fi
        fi
    fi
    ###################
    # Step 2.3: Copy ``Enterprise'' target from Applications to OUTPUT_FOLDER
    if [ $USING_ENTERPRISE -eq 1 ]; then
        INSTALL_ROOT=${DST_ROOT}
        if [ $usingXcodeAbove_14_3 -eq 1 ]; then
            INSTALL_ROOT="${DST_ROOT}/${SCHEME_ENTER}.xcarchive/Products"
        else
            INSTALL_ROOT="${DST_ROOT}/${SCHEME_ENTER}"
        fi
        OUTPUT_FILE="${INSTALL_ROOT}/Applications/${OUTPUT_FILENAME_ENTER_IPA}"
        if [ -d "${INSTALL_ROOT}/Applications/${TARGET_ENTER}" ]; then
            if [ -d ${INSTALL_ROOT}/Applications/Payload ]; then
                jb_fs_remove "ios cleanup enterprise payload" rm -rf "${INSTALL_ROOT}/Applications/Payload"
            fi
            jb_fs_write "ios mkdir enterprise payload" mkdir -p "${INSTALL_ROOT}/Applications/Payload"
            jb_fs_copy "ios move enterprise app to payload" mv "${INSTALL_ROOT}/Applications/${TARGET_ENTER}" "${INSTALL_ROOT}/Applications/Payload"
            cd "${INSTALL_ROOT}/Applications"
            $ZIP -r "${OUTPUT_FILE}" Payload
            jb_fs_copy "ios move enterprise ipa output" mv "$OUTPUT_FILE" "${OUTPUT_FOLDER}/"
            SIZE_ENTER_APP_FILE=$(du -sh ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER_IPA} | awk '{print $1}')
        else
            exit 255
        fi
    fi
    ###################
    # Step 2.3.1: Copy ``Enterprise4WebDebugging'' target from Applications to OUTPUT_FOLDER
    if [ $USING_ENTER4WEB -eq 1 ]; then
        OUTPUT_FILENAME_ENTER4WEB_SUFFIX=$(cat $jsonConfig | $JQ '.ios.Enterprise4WebDebug.fileSuffix' | tr -d '"')
        OUTPUT_FILENAME_ENTER4WEB="${OUTPUT_PREFIX}${VERSION_STRING}_${FILE_TODAY}${OUTPUT_FILENAME_ENTER4WEB_SUFFIX}"
        OUTPUT_FILENAME_ENTER4WEB_IPA="${OUTPUT_FILENAME_ENTER4WEB}.ipa"
        OUTPUT_FILENAME_ENTER4WEB_PLIST="${OUTPUT_FILENAME_ENTER4WEB}.plist"
        INSTALL_ROOT=${DST_ROOT}
        if [ $usingXcodeAbove_14_3 -eq 1 ]; then
            INSTALL_ROOT="${DST_ROOT}/${SCHEME_ENTER4WEB}.xcarchive/Products"
        else
            INSTALL_ROOT="${DST_ROOT}/${SCHEME_ENTER4WEB}"
        fi
        OUTPUT_FILE="${INSTALL_ROOT}/Applications/${OUTPUT_FILENAME_ENTER4WEB_IPA}"
        if [ -d "${INSTALL_ROOT}/Applications/${TARGET_ENTER4WEB}" ]; then
            if [ -d ${INSTALL_ROOT}/Applications/Payload ]; then
                jb_fs_remove "ios cleanup enterprise4web payload" rm -rf "${INSTALL_ROOT}/Applications/Payload"
            fi
            jb_fs_write "ios mkdir enterprise4web payload" mkdir -p "${INSTALL_ROOT}/Applications/Payload"
            jb_fs_copy "ios move enterprise4web app to payload" mv "${INSTALL_ROOT}/Applications/${TARGET_ENTER4WEB}" "${INSTALL_ROOT}/Applications/Payload"
            cd "${INSTALL_ROOT}/Applications"
            $ZIP -r "${OUTPUT_FILE}" Payload
            jb_fs_copy "ios move enterprise4web ipa output" mv "$OUTPUT_FILE" "${OUTPUT_FOLDER}/"
            SIZE_ENTER4WEB_APP_FILE=$(du -sh ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER4WEB_IPA} | awk '{print $1}')
        else
            exit 255
        fi
    fi
    ###################
    # Step 2.4-1: Exit if output not using for distribution, maybe it's for Jenkins PR Checker
    if [ $PRODUCE_OUTPUT_USE -eq 0 ]; then
        if [ $OUTPUT_AND_EXIT_USE -ne 1 ]; then
            # Exit here with remove all binary outputs
            if [ -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER_IPA} ]; then
                jb_fs_remove "ios cleanup enterprise ipa" rm -f "${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER_IPA}"
            fi
            if [ -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER4WEB_IPA} ]; then
                jb_fs_remove "ios cleanup enterprise4web ipa" rm -f "${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER4WEB_IPA}"
            fi
            if [ -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ADHOC_IPA} ]; then
                jb_fs_remove "ios cleanup adhoc ipa" rm -f "${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ADHOC_IPA}"
            fi
            if [ -f $OUTPUT_FOLDER/$OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK ]; then
                jb_fs_remove "ios cleanup appstore ixshield check" rm -f "$OUTPUT_FOLDER/$OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK"
            fi
            if [ -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_APPSTORE_IPA} ]; then
                jb_fs_remove "ios cleanup appstore ipa" rm -f "${OUTPUT_FOLDER}/${OUTPUT_FILENAME_APPSTORE_IPA}"
            fi
        fi
        exit
    elif [ $DEBUGGING -eq 1 ]; then
        if [ $USING_ENTERPRISE -eq 1 ]; then
            if [ ! -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER_IPA} ]; then
                jb_fs_write "ios debug touch enterprise ipa" touch "${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER_IPA}"
            fi
        fi
        if [ $USING_ENTER4WEB -eq 1 ]; then
            if [ ! -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER4WEB_IPA} ]; then
                jb_fs_write "ios debug touch enterprise4web ipa" touch "${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER4WEB_IPA}"
            fi
        fi
        if [ $USING_ADHOC -eq 1 ]; then
            if [ ! -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ADHOC_IPA} ]; then
                jb_fs_write "ios debug touch adhoc ipa" touch "${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ADHOC_IPA}"
            fi
        fi
        if [ $IS_RELEASE -eq 1 -a $USING_APPSTORE -eq 1 ]; then
            if [ ! -f $OUTPUT_FOLDER/$OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK ]; then
                jb_fs_write "ios debug touch ixshield check" touch "$OUTPUT_FOLDER/$OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK"
            fi
            if [ ! -f ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_APPSTORE_IPA} ]; then
                jb_fs_write "ios debug touch appstore ipa" touch "${OUTPUT_FOLDER}/${OUTPUT_FILENAME_APPSTORE_IPA}"
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
        if [[ -z "$RELEASE_KEYWORD" ]]; then
            RELEASE_KEYWORD="검증용"
        fi
    fi

    if [ $USING_ADHOC -eq 1 ]; then
        ADHOC_IPA_DOWNLOAD_URL=${OUTBOUND_HTTPS_PREFIX}${OUTPUT_FILENAME_ADHOC_IPA}
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
        ENTER_IPA_DOWNLOAD_URL=${OUTBOUND_HTTPS_PREFIX}${OUTPUT_FILENAME_ENTER_IPA}
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
}
