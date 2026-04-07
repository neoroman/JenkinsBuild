# shellcheck shell=sh
##
# IxShield (iOS): 난독화 증적용 스플래시소스 sed 치환, IxShieldCheck/check.sh 실행, PNG 생성.
# platform/ios.sh에서만 include한다. 전제: TOP_DIR, jb_json_helpers, jsonConfig/JQ, WORKSPACE,
# PROJECT_NAME, OBFUSCATION_SOURCE, OUTPUT_FOLDER, OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK,
# DEBUGGING, systemName( defaultconfig 등).

. "${TOP_DIR}/platform/jb_json_helpers.sh"

jb_ixshield_make_obfuscation_screenshot() {
    echo "===================="
    if [ $DEBUGGING -eq 0 ]; then
        echo "Debugging mode: $DEBUGGING"
        USING_OBFUSCATION=$(jb_jq_bool '.ios.usingObfuscation')
        echo "Using obfuscation: $USING_OBFUSCATION"
        if [ $USING_OBFUSCATION -eq 1 ]; then
            # Step 2.1.1: Run IxShiedCheck script and take screenshot, nees 'convert' and 'gs' here...!!!
            echo "Using USING_OBFUSCATION = ${USING_OBFUSCATION}"
            if [[ -z "$OBFUSCATION_SOURCE" ]]; then
                SPLASH_VIEW="${WORKSPACE}/${PROJECT_NAME}/ObjC/SplashViewController.m"
                SPLASH_TEMP1="${WORKSPACE}/${PROJECT_NAME}/ObjC/zzz1.m"
            else
                SPLASH_VIEW="${WORKSPACE}/${OBFUSCATION_SOURCE}"
                SPLASH_TEMP1="${SPLASH_VIEW}zzz1"
            fi
            if [ -f $SPLASH_VIEW ]; then
                sed -e 's/ix_set_debug/zzz1/g' $SPLASH_VIEW >$SPLASH_TEMP1
                mv -f $SPLASH_TEMP1 $SPLASH_VIEW

                CHECK_SHELL="./IxShieldCheck.sh"
            fi
            if test ! -f "$CHECK_SHELL"; then
                CHECK_SHELL=$(find $WORKSPACE -name 'check.sh' | head -1)
            fi
            if [ -f "$CHECK_SHELL" ]; then
                echo "Using OBFUSCATION script: $CHECK_SHELL"
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
                    echo "Please install missing commands using: brew install a2ps ghostscript imagemagick"
                else
                    GS=$(command -v gs)
                    CONVERT=$(command -v convert)

                    # Execute commands with proper path tracking
                    MERONG_FILE="$WORKSPACE/merong.txt"

                    cd $WORKSPACE && echo "${systemName}:ios AppDevTeam$ $CHECK_SHELL -i ./${PROJECT_NAME}" >merong.txt
                    cd $WORKSPACE && $CHECK_SHELL -i ./${PROJECT_NAME} >>merong.txt

                    if [ -f "$MERONG_FILE" ]; then
                        echo "Created check output file"

                        # Try direct text-to-image conversion with ImageMagick
                        $CONVERT -background white -fill black -font Courier -pointsize 14 \
                        label:"$(cat $MERONG_FILE)" \
                        -rotate 0 -bordercolor white -border 5 \
                        "$OUTPUT_FOLDER/$OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK"

                        if [ -f "$OUTPUT_FOLDER/$OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK" ]; then
                            echo "Created obfuscation screenshot with ImageMagick"
                        else
                            echo "Failed with ImageMagick, trying GhostScript fallback"

                            # Create a simple text file that Ghostscript can handle
                            $GS -sDEVICE=png256 -dNOPAUSE -dBATCH -dSAFER -r300x300 \
                            -sOutputFile="$OUTPUT_FOLDER/$OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK" \
                            -c "/Courier findfont 9 scalefont setfont" \
                            -c "72 720 moveto" \
                            -c "($(cat $MERONG_FILE | tr '\n' ' ')) show" \
                            -c "showpage" \
                            -f

                            if [ -f "$OUTPUT_FOLDER/$OUTPUT_FILENAME_APPSTORE_IX_SHIELD_CHECK" ]; then
                                echo "Created obfuscation screenshot with GhostScript"
                            else
                                echo "Failed to create screenshot with all methods"
                            fi
                        fi

                        # Cleanup
                        rm -f "$MERONG_FILE"
                    else
                        echo "Failed to generate check output"
                    fi
                fi
            fi
        fi
    fi
}
