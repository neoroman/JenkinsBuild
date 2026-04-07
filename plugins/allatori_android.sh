# shellcheck shell=sh
##
# Allatori (Android): release 빌드 전 app 모듈 build.gradle에서 runAllatori(variant) 주석을 해제한다.
# build.sh의 Android 분기에서만 include한다. 전제: TOP_DIR, jsonConfig, JQ(jsonconfig), 그리고
# doExecuteAndroid 실행 시점의 IS_RELEASE, BUILD_GRADLE_CONFIG, WORKSPACE, ANDROID_APP_PATH.

. "${TOP_DIR}/platform/jb_json_helpers.sh"

jb_allatori_prepare_release_gradle() {
    USING_ALLATORI=$(jb_jq_bool '.android.usingAllatori')
    if [ "$IS_RELEASE" -eq 1 ] && [ "$USING_ALLATORI" -eq 1 ]; then
        ALLATORI_EXEC_PATH="${BUILD_GRADLE_CONFIG}"
        ALLATORI_EXEC_TEMP="${WORKSPACE}/${ANDROID_APP_PATH}/build.gradle.new"
        ALLATORI_EXEC=$(grep 'runAllatori(variant)' "${ALLATORI_EXEC_PATH}" | grep -v 'def runAllatori(variant)' | awk 'BEGIN{FS=" "; OFS=""} {print $1$2}')
        if [[ "$ALLATORI_EXEC" = "//"* ]]; then
            sed 's/^\/\/.*runAllatori(variant)/            runAllatori(variant)/' "$ALLATORI_EXEC_PATH" >"$ALLATORI_EXEC_TEMP"

            ALLATORI_EXEC=$(grep 'runAllatori(variant)' "${ALLATORI_EXEC_TEMP}" | grep -v 'def runAllatori(variant)' | awk 'BEGIN{FS=" "; OFS=""} {print $1$2}')
            if [[ "$ALLATORI_EXEC" = "//"* ]]; then
                sed 's/^.*\/\/runAllatori(variant)/            runAllatori(variant)/' "$ALLATORI_EXEC_PATH" >"$ALLATORI_EXEC_TEMP"

                ALLATORI_EXEC=$(grep 'runAllatori(variant)' "${ALLATORI_EXEC_TEMP}" | grep -v 'def runAllatori(variant)' | awk 'BEGIN{FS=" "; OFS=""} {print $1$2}')
                if [[ "$ALLATORI_EXEC" != "//"* ]]; then
                    mv -f "$ALLATORI_EXEC_TEMP" "$ALLATORI_EXEC_PATH"
                fi
            else
                mv -f "$ALLATORI_EXEC_TEMP" "$ALLATORI_EXEC_PATH"
            fi
        fi
    fi
}
