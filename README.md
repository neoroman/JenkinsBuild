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
-  4. (Optional) If using slack, Adjust ``jq`` path as "/usr/local/bin/jq" in "/usr/local/bin/slac"
-  5. (Optional) Install ``gs`` via HomeBrew, brew install gs
-  6. (Optional) Install ``convert``(ImageMagick) via HomeBrew, brew install imagemagick


## Installation
- First you should get it into your iOS or Android source working copy like following:
  ```
    git config --local submodule.rebase true
    git submodule add https://github.com/neoroman/JenkinsBuild.git jenkins
    git submodule init
    git submodule update
  ```
- Add pull rebase true to global configuration of git
  ```
    git config pull.rebase true
  ```


## Jenkins Item Configuration for Build Section
- Just put following line if you don't want add as submodule
  ```
    git submodule add https://github.com/neoroman/JenkinsBuild.git jenkins
  ```

- Update submodule for ``iOS`` into ``{WebServer}/{DocumentRoot}/NeoRoman/AppProject``
  ```
    git config --local submodule.rebase true
    git config -f .gitmodules submodule.jenkins.url https://github.com/neoroman/JenkinsBuild.git
    git submodule sync
    git submodule update --force --recursive --init --remote
    git submodule foreach git pull origin main
    ## Actual script for executing build
    bash -ex ${WORKSPACE}/jenkins/build.sh -p ios --toppath "NeoRoman/AppProject"
  ```
- Update submodule for ``Android`` into ``{WebServer}/{DocumentRoot}/NeoRoman/AppProject``
  ```
    git config --local submodule.rebase true
    git config -f .gitmodules submodule.jenkins.url https://github.com/neoroman/JenkinsBuild.git
    git submodule sync
    git submodule update --force --recursive --init --remote
    git submodule foreach git pull origin main
    ## Actual script for executing build
    bash -ex ${WORKSPACE}/jenkins/build.sh -p android --toppath "NeoRoman/AppProject"
  ```
- Here's a sample screenshot of the jenkins configuration
![help](images/JenkinsConfigHelp.png)


## Jenkins Item Configuration in jenkins/build.sh configuration for Distribution Sites
  ```
    ## Actual script for executing build
    bash -ex ${WORKSPACE}/jenkins/build.sh -p android --toppath "NeoRoman/AppProject" \
                  --config "${WORKSPACE}/jenkins_config/config.json" \
                  --language "${WORKSPACE}/jenkins_config/lang_ko.json"
  ```
- Add configurations of distribution sites with --config argument.
- Add language for display messages of distribution sites with --language argument.


## Author

ALTERANT /  neoroman@gmail.com


## License

See the [LICENSE](./LICENSE) file for more info.
