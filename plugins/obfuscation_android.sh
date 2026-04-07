# shellcheck shell=sh
##
# Android 난독화 증적 PNG·입력 복사 — platform/android.sh와 동일 구현.
# build.sh Android 분기에서 platform/android.sh가 로드한다. 스모크 테스트는 이 파일만 source해도 된다.
# 전제: TOP_DIR, jb_json_helpers(.android.usingObfuscation), jsonConfig/JQ, DEBUGGING, WORKSPACE,
# ANDROID_APP_PATH, IS_RELEASE, OUTPUT_FOLDER, APK_GOOGLESTORE, GIT_USER, GIT_BRANCH,
# Obfuscation_SCREENSHOT, Obfuscation_INPUT_FILE, Obfuscation_OUTPUT_FILE, APP_ROOT_PREFIX,
# TOP_PATH, USING_SCP(0이면 sendFile 미사용).

. "${TOP_DIR}/platform/jb_json_helpers.sh"

jb_android_make_obfuscation_screenshot() {
    if [ $DEBUGGING -eq 0 ]; then
        USING_OBFUSCATION=$(jb_jq_bool '.android.usingObfuscation')
        if [ $USING_OBFUSCATION -eq 1 ]; then
            if [ -f "${OUTPUT_FOLDER}/${APK_GOOGLESTORE}" ]; then
                CHECK_SHELL="$WORKSPACE/${ANDROID_APP_PATH}/check.sh"
                if test ! -f "$CHECK_SHELL"; then
                    CHECK_SHELL=$(find $WORKSPACE -name 'check.sh' | head -1)
                fi
                if [ -f "$CHECK_SHELL" -a $IS_RELEASE -eq 1 ]; then
                    chmod +x $CHECK_SHELL

                    REQUIRED_COMMANDS="gs convert"
                    MISSING_COMMANDS=""
                    for cmd in $REQUIRED_COMMANDS; do
                        if ! command -v $cmd >/dev/null 2>&1; then
                            MISSING_COMMANDS="$MISSING_COMMANDS $cmd"
                        fi
                    done

                    if [ ! -z "$MISSING_COMMANDS" ]; then
                        echo "Warning: Required commands not found:$MISSING_COMMANDS"
                        echo "Please install missing commands using: brew install ghostscript imagemagick"
                    else
                        GS=$(command -v gs)
                        CONVERT=$(command -v convert)

                        MERONG_FILE="$WORKSPACE/$ANDROID_APP_PATH/merong.txt"

                        echo "$GIT_USER $(hostname -s) ${WORKSPACE} (${GIT_BRANCH})" > "$MERONG_FILE"
                        SRC_PATH="$WORKSPACE/${ANDROID_APP_PATH}/src"
                        echo "$ $CHECK_SHELL -a $SRC_PATH" >> "$MERONG_FILE"
                        $CHECK_SHELL -a $SRC_PATH >> "$MERONG_FILE"

                        if [ -f "$MERONG_FILE" ]; then
                            echo "Created check output file"

                            $CONVERT -background white -fill black -font Courier -pointsize 14 \
                                label:"$(cat $MERONG_FILE)" \
                                -rotate 0 -bordercolor white -border 5 \
                                "$OUTPUT_FOLDER/$Obfuscation_SCREENSHOT"

                            if [ -f "$OUTPUT_FOLDER/$Obfuscation_SCREENSHOT" ]; then
                                echo "Created obfuscation screenshot with ImageMagick"
                            else
                                echo "Failed with ImageMagick, trying GhostScript fallback"

                                $GS -sDEVICE=png256 -dNOPAUSE -dBATCH -dSAFER -r300x300 \
                                    -sOutputFile="$OUTPUT_FOLDER/$Obfuscation_SCREENSHOT" \
                                    -c "/Courier findfont 9 scalefont setfont" \
                                    -c "72 720 moveto" \
                                    -c "($(cat $MERONG_FILE | tr '\n' ' ')) show" \
                                    -c "showpage" \
                                    -f

                                if [ -f "$OUTPUT_FOLDER/$Obfuscation_SCREENSHOT" ]; then
                                    echo "Created obfuscation screenshot with GhostScript"
                                else
                                    echo "Failed to create screenshot with all methods"
                                fi
                            fi

                            rm -f "$MERONG_FILE"
                        else
                            echo "Failed to generate check output"
                        fi
                    fi
                fi

                if [ -f "$WORKSPACE/$Obfuscation_INPUT_FILE" ]; then
                    cp -f $WORKSPACE/$Obfuscation_INPUT_FILE $OUTPUT_FOLDER/$Obfuscation_OUTPUT_FILE
                    echo "Copied obfuscation file: $OUTPUT_FOLDER/$Obfuscation_OUTPUT_FILE"
                elif [ -f "${APP_ROOT_PREFIX}/${TOP_PATH}/$Obfuscation_INPUT_FILE" ]; then
                    cp -f ${APP_ROOT_PREFIX}/${TOP_PATH}/$Obfuscation_INPUT_FILE $OUTPUT_FOLDER/$Obfuscation_OUTPUT_FILE
                    echo "Copied obfuscation file: $OUTPUT_FOLDER/$Obfuscation_OUTPUT_FILE"
                else
                    echo "Obfuscation input file not found: $Obfuscation_INPUT_FILE"
                fi
            else
                echo "APK file not found: ${OUTPUT_FOLDER}/${APK_GOOGLESTORE}"
            fi

            if [ $USING_SCP -eq 1 ]; then
                if [ $(sendFile ${OUTPUT_FOLDER}/${Obfuscation_OUTPUT_FILE} ${NEO2UA_OUTPUT_FOLDER}) -eq 0 ]; then
                    echo "TODO: **NEED** to resend this file => ${OUTPUT_FOLDER}/${Obfuscation_OUTPUT_FILE} to ${NEO2UA_OUTPUT_FOLDER}"
                fi
            fi

        fi
    fi
}
