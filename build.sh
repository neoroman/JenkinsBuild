#!/bin/sh
##
# Script for iOS and Android Release Build on Jenkins
# Written by Henry Kim on 5/22/2018
# Modified by Henry Kim on 2019.06.19 referenced from jenkins-shell-AOS-preRelease.sh
# Modified by Henry Kim on 2021.07.29 for GApp4 and integrations of Android and iOS
# Modified by Henry Kim on 2021.09.30 for normalized for most Applicaiton project
# Modified by Henry Kim on 2022.04.22 for functionize shell script
#
# Prerequisites for executing this script
#  0. (Mandatory) Install Xcode command line tools from "https://developer.apple.com/download/more/" for only iOS
#  1. (Mandatory) Install jq via HomeBrew, brew install jq
#  2. (Mandatory) Install bundletool for Android AAB output since 2021 Aug, brew install bundletool
#  3. (Optional) Install slack from "https://github.com/rockymadden/slack-cli"
#     (also use "brew install rockymadden/rockymadden/slack-cli"),
#     run "slack init", and Enter Slack API token from https://api.slack.com/custom-integrations/legacy-tokens
#  4. (Optional) Install jq path with "/usr/local/bin/jq" in "/usr/local/bin/slac"
#  5. (Optional) Install a2ps via HomeBrew, brew install a2ps
#  6. (Optional) Install gs via HomeBrew, brew install gs
#  7. (Optional) Install convert(ImageMagick) via HomeBrew, brew install imagemagick
#
################################################################################
if test -z $TOP_DIR; then
  TOP_DIR="$(dirname $0)"
fi
################################################################################
. ${TOP_DIR}/config/defaultconfig ### Import Default Configurations ##########
################################################################################
################################################################################
. ${TOP_DIR}/config/argsparser ### Import Argument Parser ####################
################################################################################
################################################################################
. ${TOP_DIR}/config/jsonconfig ### Import JSON Configurations ################
################################################################################
################################################################################
. ${TOP_DIR}/config/sshfunctions  ### Import SSH Funtions ####################
################################################################################
################################################################################
. ${TOP_DIR}/config/utilconfig  ### Import SSH Funtions ######################
################################################################################
##
# Update distribution site source ##############################################
if [ -f ${APP_ROOT_PREFIX}/${TOP_PATH}/.htaccess ]; then
  if [ -f ${APP_ROOT_PREFIX}/${TOP_PATH}/installOrUpdate.sh ]; then
    ${APP_ROOT_PREFIX}/${TOP_PATH}/installOrUpdate.sh  2>&1
    chmod -R 777 ${APP_ROOT_PREFIX}/${TOP_PATH}  2>&1
  fi
fi
################################################################################
if [[ "$INPUT_OS" == "android" ]]; then
    ## for Android
    ############################################################################
    . ${TOP_DIR}/util/makePath        ### Import Android Path maker ###########
    ############################################################################
    ##
    ############################################################################
    . ${TOP_DIR}/platform/android.sh  ### Import Android Shell Script ########
    ############################################################################
elif [[ "$INPUT_OS" == "ios" ]]; then
    ## for iOS
    ############################################################################
    . ${TOP_DIR}/platform/ios.sh  ### Import iOS Shell Script ################
    ############################################################################
fi
##
################################################################################
##### JSON Generation START ######
################################################################################
. ${TOP_DIR}/util/makejson  ### Import JSON Generations ######################
################################################################################
##### JSON Generation END ########
################################################################################
##
################################################################################
. ${TOP_DIR}/util/makehtml  ### Import HTML Generations ######################
################################################################################
##
if [ -f $OUTPUT_FOLDER/$OUTPUT_FILENAME_JSON ]; then
  ##############################################################################
  . ${TOP_DIR}/config/buildenvironment  ### Import Build Environment #########
  ##############################################################################
  ##
  ##############################################################################
  . ${TOP_DIR}/util/sendslack  ### Import Slack Handler ######################
  ##############################################################################
  ##
  ##############################################################################
  . ${TOP_DIR}/util/sendteams  ### Import Teams Handler ######################
  ##############################################################################
  ##
  ##############################################################################
  . ${TOP_DIR}/util/sendemail  ### Import Email Handler ######################
  ##############################################################################
  ##
  ##############################################################################
  ## Reorder html filetime by builTime in json file
  if [ -f ${APP_ROOT_PREFIX}/${TOP_PATH}/src/shell/reorderFileTime.sh ]; then
    ${APP_ROOT_PREFIX}/${TOP_PATH}/src/shell/reorderFileTime.sh -p $INPUT_OS >/dev/null 2>&1
  fi
  ##############################################################################
fi
