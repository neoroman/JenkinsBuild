# Application Build BASH Shell Script
Language: BASH Shell Script


## Requirements (based on macOS machine)
- Jenkins server on any macOS machine
-  0. (Mandatory) Install ``Xcode`` command line tools from "https://developer.apple.com/download/more/" for only iOS
-  1. (Mandatory) Install ``jq`` via HomeBrew, brew install jq
-  2. (Mandatory) Install ``bundletool`` for Android AAB output since 2021 Aug, brew install bundletool
-  3. (Optional) Install ``slack`` from "https://github.com/rockymadden/slack-cli"
      (also use "brew install rockymadden/rockymadden/slack-cli"),
      run "slack init", and Enter Slack API token from https://api.slack.com/custom-integrations/legacy-tokens
-  4. (Optional) Install ``jq`` path with "/usr/local/bin/jq" in "/usr/local/bin/slac"
-  5. (Optional) Install ``a2ps`` via HomeBrew, brew install a2ps
-  6. (Optional) Install ``gs`` via HomeBrew, brew install gs
-  7. (Optional) Install ``convert``(ImageMagick) via HomeBrew, brew install imagemagick


## Installation
- First you should get it into your iOS or Android source working copy like following:
  ```
    git submodule add https://github.com/neoroman/JenkinsBuild.git jenkins
    git submodule init
    git submodule update
  ```


## Jenkins Item Configuration for Build Section
- for ``iOS`` into ``{WebServer}/{DocumentRoot}/NeoRoman/AppProject``
  ```
    git config -f .gitmodules submodule.jenkins.url https://github.com/neoroman/JenkinsBuild.git
    git submodule sync
    git submodule update --force --recursive --init --remote
    git submodule foreach git pull origin master
    bash -ex ${WORKSPACE}/jenkins/build.sh -p ios -tp "NeoRoman/AppProject"
  ```
- for ``Android`` into ``{WebServer}/{DocumentRoot}/NeoRoman/AppProject``
  ```
    git config -f .gitmodules submodule.jenkins.url https://github.com/neoroman/JenkinsBuild.git
    git submodule sync
    git submodule update --force --recursive --init --remote
    git submodule foreach git pull origin master
    bash -ex ${WORKSPACE}/jenkins/build.sh -p android -tp "NeoRoman/AppProject"
  ```


## Author

ALTERANT /  neoroman@gmail.com


## License

See the [LICENSE](./LICENSE) file for more info.
