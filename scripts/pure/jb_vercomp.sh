# shellcheck shell=bash
##
# Dot-separated numeric semver-ish comparison (legacy contract).
# Echoes: 0 if equal, 1 if $1 > $2, 2 if $1 < $2.
# Consumed by util/versions and platform scripts (ios.sh, dist_shlib).

vercomp() {
  if [[ $1 == "$2" ]]; then
    echo 0
    return
  fi
  local IFS=.
  local i ver1=($1) ver2=($2)
  for ((i = ${#ver1[@]}; i < ${#ver2[@]}; i++)); do
    ver1[i]=0
  done
  for ((i = 0; i < ${#ver1[@]}; i++)); do
    if [[ -z ${ver2[i]} ]]; then
      ver2[i]=0
    fi
    if ((10#${ver1[i]} > 10#${ver2[i]})); then
      echo 1
      return
    fi
    if ((10#${ver1[i]} < 10#${ver2[i]})); then
      echo 2
      return
    fi
  done
  echo 0
}
