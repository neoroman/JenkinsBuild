# Application Build BASH Shell Script
Language: BASH Shell Script


## Requirements (based on macOS machine)
- Jenkins server on any mac machine
- Install ``Xcode`` command line tools from "https://developer.apple.com/download/more/" for only iOS
- Install ``slack`` from "https://github.com/rockymadden/slack-cli" (also use "brew install rockymadden/rockymadden/slack-cli"), run "slack init", and Enter Slack API token from https://api.slack.com/custom-integrations/legacy-tokens
- Install ``jq`` path with "/usr/local/bin/jq" in "/usr/local/bin/slac"
- Install ``a2ps`` via HomeBrew, brew install a2ps
- Install ``gs`` via HomeBrew, brew install gs
- Install ``convert``(ImageMagick) via HomeBrew, brew install imagemagick


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
    git submodule init
    git submodule update
    git submodule foreach git pull origin master
    bash -ex ${WORKSPACE}/jenkins/build.sh -p ios -tp "NeoRoman/AppProject"
  ```
- for ``Android`` into ``{WebServer}/{DocumentRoot}/NeoRoman/AppProject``
  ```
    git submodule init
    git submodule update
    git submodule foreach git pull origin master
    bash -ex ${WORKSPACE}/jenkins/build.sh -p android -tp "NeoRoman/AppProject"
  ```


## Author

ALTERANT /  neoroman@gmail.com


## License

See the [LICENSE](./LICENSE) file for more info.
