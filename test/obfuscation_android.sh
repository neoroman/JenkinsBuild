#!/bin/bash
# test_android_obfuscation.sh - Test only the obfuscation functionality

# Set up required environment variables
export WORKSPACE="$(pwd)"
export ANDROID_APP_PATH="./test/android/app"  # Simplified path
export IS_RELEASE=1
export DEBUGGING=0
export OUTPUT_FOLDER="./test/android/output"
export jsonConfig="./test/config.json"
export JQ="jq"
export APP_ROOT_PREFIX="$(pwd)"
export USING_SCP=0
export GIT_USER="test_user"
export GIT_BRANCH="test_branch"
export APK_GOOGLESTORE="test.apk"
export Obfuscation_SCREENSHOT="obfuscation_screenshot.png"
export Obfuscation_INPUT_FILE="images/JenkinsConfigHelp.png"
export Obfuscation_OUTPUT_FILE="obfuscation_output.png"

# Create test directories
mkdir -p "$OUTPUT_FOLDER"
mkdir -p "$WORKSPACE/$ANDROID_APP_PATH"
touch "$OUTPUT_FOLDER/$APK_GOOGLESTORE"  # Create dummy APK file

# Create a dummy check.sh script for testing
cat > "$WORKSPACE/$ANDROID_APP_PATH/check.sh" << 'EOF'
#!/bin/bash
echo "Running obfuscation check..."
echo "Test successful!"
EOF
chmod +x "$WORKSPACE/$ANDROID_APP_PATH/check.sh"

# Create a dummy config file
mkdir -p $(dirname "$jsonConfig")
cat > "$jsonConfig" << 'EOF'
{
  "android": {
    "usingObfuscation": true
  }
}
EOF

# Now run only the obfuscation code
echo "Testing Android obfuscation code..."

# Copy the obfuscation section directly from android.sh
USING_OBFUSCATION=$(test $(cat $jsonConfig | $JQ '.android.usingObfuscation') = true && echo 1 || echo 0)
if [ $USING_OBFUSCATION -eq 1 ]; then
    if [ -f "${OUTPUT_FOLDER}/${APK_GOOGLESTORE}" ]; then
        CHECK_SHELL="$WORKSPACE/$ANDROID_APP_PATH/check.sh"
        if test ! -f "$CHECK_SHELL"; then
            CHECK_SHELL=$(find $WORKSPACE -name 'check.sh' | head -1)
        fi
        
        echo "Using check script: $CHECK_SHELL"
        
        if [ -f "$CHECK_SHELL" -a $IS_RELEASE -eq 1 ]; then
            chmod +x $CHECK_SHELL
            
            # Check required commands
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
                # Get command paths
                GS=$(command -v gs)
                CONVERT=$(command -v convert)
                
                # Execute commands with proper path tracking
                MERONG_FILE="$WORKSPACE/$ANDROID_APP_PATH/merong.txt"
                
                # Create the file in a location we know exists
                echo "$GIT_USER $(hostname -s) ${WORKSPACE} (${GIT_BRANCH})" > "$MERONG_FILE"
                echo "$ $CHECK_SHELL -a src" >> "$MERONG_FILE"
                $CHECK_SHELL -a src >> "$MERONG_FILE"
                
                if [ -f "$MERONG_FILE" ]; then
                    echo "Created check output file"
                    
                    # Try direct text-to-image conversion with ImageMagick
                    $CONVERT -background white -fill black -font Courier -pointsize 14 \
                      label:"$(cat $MERONG_FILE)" \
                      -rotate 0 -bordercolor white -border 5 \
                      "$OUTPUT_FOLDER/$Obfuscation_SCREENSHOT"
                    
                    if [ -f "$OUTPUT_FOLDER/$Obfuscation_SCREENSHOT" ]; then
                        echo "Created obfuscation screenshot with ImageMagick"
                    else
                        echo "Failed with ImageMagick, trying GhostScript fallback"
                        
                        # Create a simple text file that Ghostscript can handle
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
                    
                    # Cleanup
                    rm -f "$MERONG_FILE"
                else
                    echo "Failed to generate check output"
                fi
            fi
        fi

        # Create test directory for input file if needed
        mkdir -p "$(dirname "$WORKSPACE/$Obfuscation_INPUT_FILE")"
        
        # Create a dummy input file if it doesn't exist
        if [ ! -f "$WORKSPACE/$Obfuscation_INPUT_FILE" ]; then
            echo "Creating dummy input file"
            echo "Test file" > "$WORKSPACE/$Obfuscation_INPUT_FILE"
        fi
        
        # Copy input file
        cp -f "$WORKSPACE/$Obfuscation_INPUT_FILE" "$OUTPUT_FOLDER/$Obfuscation_OUTPUT_FILE"
        echo "Copied obfuscation file: $OUTPUT_FOLDER/$Obfuscation_OUTPUT_FILE"
    else
        echo "APK file not found: ${OUTPUT_FOLDER}/${APK_GOOGLESTORE}"
    fi
fi

echo "Test completed."