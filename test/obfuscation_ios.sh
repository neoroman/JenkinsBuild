#!/bin/bash

WORKSPACE=.
OUTPUT_FOLDER=.

# Required commands
REQUIRED_COMMANDS="a2ps gs convert"

# Test obfuscation function
test_obfuscation() {
    echo "Testing iOS obfuscation in $WORKSPACE (debug: $DEBUGGING)"
    
    # Check required commands
    MISSING_COMMANDS=""
    for cmd in $REQUIRED_COMMANDS; do
        if ! command -v $cmd >/dev/null 2>&1; then
            MISSING_COMMANDS="$MISSING_COMMANDS $cmd"
        fi
    done
    
    if [ ! -z "$MISSING_COMMANDS" ]; then
        echo "Warning: Required commands not found:$MISSING_COMMANDS"
        echo "Please install missing commands using: brew install a2ps ghostscript imagemagick"
        return 1
    fi
    
    # Test IxShield check
    CHECK_SHELL="${WORKSPACE}/IxShieldCheck.sh"
    if test ! -f "$CHECK_SHELL"; then
        CHECK_SHELL=$(find $WORKSPACE -name 'check.sh' | head -1)
    fi
    if [ -f "$CHECK_SHELL" ]; then
        A2PS=$(command -v a2ps)
        GS=$(command -v gs)
        CONVERT=$(command -v convert)
        
        cd $WORKSPACE
        echo "${systemName}:ios appDevTeam$ $CHECK_SHELL -i ./${PROJECT_NAME}" > merong.txt
        $CHECK_SHELL -i ./${PROJECT_NAME} >> merong.txt
        
        if [ -f merong.txt ]; then
            $A2PS -=book -B -q --medium=A4 --borders=no -o out1.ps merong.txt && \
            $GS -sDEVICE=png256 -dNOPAUSE -dBATCH -dSAFER -dTextAlphaBits=4 -q -r300x300 -sOutputFile=out2.png out1.ps && \
            $CONVERT -trim out2.png $OUTPUT_FOLDER/IxShieldCheck.png
            
            if [ -f "$OUTPUT_FOLDER/IxShieldCheck.png" ]; then
                echo "✅ IxShield check screenshot generated"
            else
                echo "❌ IxShield check screenshot failed"
                return 1
            fi
            
            # Cleanup
            rm -f out[12].png out[12].ps merong.txt
        else
            echo "❌ IxShield check output file not generated"
            return 1
        fi
    else
        echo "❌ IxShield check script not found"
        return 1
    fi
    
    echo "✅ All tests passed"
    return 0
}

# Run tests
test_obfuscation
test_result=$?

exit $test_result