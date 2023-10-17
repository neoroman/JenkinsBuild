#!/bin/sh
##
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
sudo -S xcode-select -s $XCODE_DEVELOPER_LAST <<<"${sudoPassword}"
###################
ZIP="/usr/bin/zip"
POD="/usr/local/bin/pod"
###################
APP_PATH="${TOP_PATH}/ios"
APP_ROOT_SUFFIX="ios_distributions"
if test -z $PROJECT_NAME; then
    echo ""
    echo "Error: please finish setup distribution site, see following path:"
    echo "       ${FRONTEND_POINT}/${TOP_PATH}/config/config.json"
    exit
fi
###################
if [ $isFlutterEnabled -eq 1 ]; then
    export SDKROOT="/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
    export LANG=en_US.UTF-8
    if test -z ${GEM_PATH}; then
        export GEM_PATH="/System/Library/Frameworks/Ruby.framework/Versions/2.6/usr/lib/ruby/gems/2.6.0"
    fi

    POD_EXEC_DIR=$(dirname ${POD})
    export PATH=${POD_EXEC_DIR}:$PATH
    $FlutterBin pub get
    $FlutterBin build ios
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
OUTBOUND_HTTPS_PREFIX="${OUTBOUND_POINT}/${TOP_PATH}/${APP_ROOT_SUFFIX}/${APP_VERSION}/"
###################
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
    if test -z ${GEM_PATH}; then
        export GEM_PATH="/System/Library/Frameworks/Ruby.framework/Versions/2.6/usr/lib/ruby/gems/2.6.0"
    fi
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
        # $XCODE $XCODE_OPTION "${XCODE_WORKSPACE}" -scheme "${SCHEME_APPSTORE}" -sdk iphoneos -configuration AppStoreDistribution archive -archivePath ${ARCHIVE_PATH}
        $XCODE $XCODE_OPTION "${XCODE_WORKSPACE}" -scheme "${SCHEME_APPSTORE}" -sdk iphoneos -skip-test-configuration -configuration archive -archivePath ${ARCHIVE_PATH}
        $XCODE -exportArchive -archivePath ${ARCHIVE_PATH} -exportOptionsPlist ${EXPORT_PLIST} -exportPath ${OUTPUT_FOLDER}
    fi
    xcodeArgument="SYMROOT=${DST_ROOT} DSTROOT=${DST_ROOT}"
    # xcodeArgument="DSTROOT=\"${DST_ROOT}\""
    xcodeVer="$($XCODE -version | grep Xcode | sed -e 's/Xcode //g')"
    usingXcodeAbove_14_3=0
    # TODO: why error occurred by return 2 on 2023.10.17
    if [[ "$xcodeVer" != "14.1" ]]; then
        compareVer="14.3.1"
        vercomp $xcodeVer $compareVer # return 0 mean same, 1 mean $xcodeVer > $compareVer, 2 mean $xcodeVer < $compareVer
        if [ $? -lt 2 ]; then
            xcodeArgument="-derivedDataPath ${DST_ROOT} -archivePath ${DST_ROOT}"
            # xcodeArgument="-archivePath \"${DST_ROOT}\""
            usingXcodeAbove_14_3=1
        fi
    fi
    if [ $USING_ADHOC -eq 1 ]; then
        # Step 1.2: Build target for AdHoc
        $XCODE $XCODE_OPTION "${XCODE_WORKSPACE}" -scheme "${SCHEME_ADHOC}" -destination "generic/platform=iOS" archive ${xcodeArgument}/${SCHEME_ADHOC}
    fi
    if [ $USING_ENTERPRISE -eq 1 ]; then
        # Step 1.3: Build target for Enterprise
        $XCODE $XCODE_OPTION "${XCODE_WORKSPACE}" -scheme "${SCHEME_ENTER}" -destination "generic/platform=iOS" archive ${xcodeArgument}/${SCHEME_ENTER}
    fi
    if [ $USING_ENTER4WEB -eq 1 ]; then
        # Step 1.4: Build target for Enterprise
        $XCODE $XCODE_OPTION "${XCODE_WORKSPACE}" -scheme "${SCHEME_ENTER4WEB}" -destination "generic/platform=iOS" archive ${xcodeArgument}/${SCHEME_ENTER4WEB}
    fi
fi
###################
# Step 2.0: Prepare
if [ $IS_RELEASE -eq 1 ]; then
    VERSION_STRING="${APP_VERSION}(${BUILD_VERSION})"
elif [ "$APP_VERSION" != "" ]; then
    VERSION_STRING="${APP_VERSION}.${BUILD_VERSION}"
else
    VERSION_STRING=""
fi
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
        mv "$OUTPUT_FILE" "${OUTPUT_FOLDER}/${OUTPUT_FILENAME_APPSTORE_IPA}"
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

                    if command -v $A2PS >/dev/null && command -v $GS >/dev/null; then
                        cd $WORKSPACE && echo "${systemName}:ios appDevTeam$ ./IxShieldCheck.sh -i ./${PROJECT_NAME}" >merong.txt
                        cd $WORKSPACE && ./IxShieldCheck.sh -i ./${PROJECT_NAME} >>merong.txt
                        cd $WORKSPACE && cat merong.txt | $A2PS -=book -B -q --medium=A4dj --borders=no -o out1.ps && $GS -sDEVICE=png256 -dNOPAUSE -dBATCH -dSAFER -dTextAlphaBits=4 -q -r300x300 -sOutputFile=out2.png out1.ps
                        if command -v $CONVERT >/dev/null; then
                            cd $WORKSPACE && $CONVERT -trim out2.png $OUTPUT_FOLDER/$OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK
                        else
                            cd $WORKSPACE && cp out2.png $OUTPUT_FOLDER/$OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK
                        fi
                        cd $WORKSPACE && rm -f out[12].png out[12].ps merong.txt
                    fi
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
    INSTALL_ROOT=${DST_ROOT}
    if [ $usingXcodeAbove_14_3 -eq 1 ]; then
        INSTALL_ROOT="${DST_ROOT}/${SCHEME_ADHOC}.xcarchive/Products"
    else
        INSTALL_ROOT="${DST_ROOT}/${SCHEME_ADHOC}"
    fi
    OUTPUT_FILE="${INSTALL_ROOT}/Applications/${OUTPUT_FILENAME_ADHOC_IPA}"
    if [ -d "${INSTALL_ROOT}/Applications/${TARGET_ADHOC}" ]; then
        if [ -d ${INSTALL_ROOT}/Applications/Payload ]; then
            rm -rf ${INSTALL_ROOT}/Applications/Payload
        fi
        mkdir -p ${INSTALL_ROOT}/Applications/Payload
        mv "${INSTALL_ROOT}/Applications/${TARGET_ADHOC}" "${INSTALL_ROOT}/Applications/Payload"
        cd "${INSTALL_ROOT}/Applications"
        $ZIP -r "${OUTPUT_FILE}" Payload
        mv "$OUTPUT_FILE" "${OUTPUT_FOLDER}/"
        SIZE_ADHOC_APP_FILE=$(du -sh ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ADHOC_IPA} | awk '{print $1}')
    else
        exit -1
    fi
fi
###################
# Step 2.3: Copy ``Enterprise'' target from Applications to OUTPUT_FOLDER
if [ $USING_ENTERPRISE -eq 1 ]; then
    OUTPUT_FILENAME_ENTER_SUFFIX=$(cat $jsonConfig | $JQ '.ios.Enterprise.fileSuffix' | tr -d '"')
    OUTPUT_FILENAME_ENTER="${OUTPUT_PREFIX}${VERSION_STRING}_${FILE_TODAY}${OUTPUT_FILENAME_ENTER_SUFFIX}"
    OUTPUT_FILENAME_ENTER_IPA="${OUTPUT_FILENAME_ENTER}.ipa"
    OUTPUT_FILENAME_ENTER_PLIST="${OUTPUT_FILENAME_ENTER}.plist"
    INSTALL_ROOT=${DST_ROOT}
    if [ $usingXcodeAbove_14_3 -eq 1 ]; then
        INSTALL_ROOT="${DST_ROOT}/${SCHEME_ENTER}.xcarchive/Products"
    else
        INSTALL_ROOT="${DST_ROOT}/${SCHEME_ENTER}"
    fi
    OUTPUT_FILE="${INSTALL_ROOT}/Applications/${OUTPUT_FILENAME_ENTER_IPA}"
    if [ -d "${INSTALL_ROOT}/Applications/${TARGET_ENTER}" ]; then
        if [ -d ${INSTALL_ROOT}/Applications/Payload ]; then
            rm -rf ${INSTALL_ROOT}/Applications/Payload
        fi
        mkdir -p ${INSTALL_ROOT}/Applications/Payload
        mv "${INSTALL_ROOT}/Applications/${TARGET_ENTER}" "${INSTALL_ROOT}/Applications/Payload"
        cd "${INSTALL_ROOT}/Applications"
        $ZIP -r "${OUTPUT_FILE}" Payload
        mv "$OUTPUT_FILE" "${OUTPUT_FOLDER}/"
        SIZE_ENTER_APP_FILE=$(du -sh ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER_IPA} | awk '{print $1}')
    else
        exit -1
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
            rm -rf ${INSTALL_ROOT}/Applications/Payload
        fi
        mkdir -p ${INSTALL_ROOT}/Applications/Payload
        mv "${INSTALL_ROOT}/Applications/${TARGET_ENTER4WEB}" "${INSTALL_ROOT}/Applications/Payload"
        cd "${INSTALL_ROOT}/Applications"
        $ZIP -r "${OUTPUT_FILE}" Payload
        mv "$OUTPUT_FILE" "${OUTPUT_FOLDER}/"
        SIZE_ENTER4WEB_APP_FILE=$(du -sh ${OUTPUT_FOLDER}/${OUTPUT_FILENAME_ENTER4WEB_IPA} | awk '{print $1}')
    else
        exit -1
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
