#!/bin/sh

jb_is_dry_run() {
  [ "${DRY_RUN:-0}" -eq 1 ]
}

jb_step_selected() {
  local step_id="$1"
  local selected="${DRY_RUN_STEP:-all}"
  [ -z "$selected" ] && selected="all"
  [ "$selected" = "all" ] && return 0
  [ "$selected" = "$step_id" ] && return 0
  return 1
}

jb_dryrun_header() {
  local platform="$1"
  echo "[DRY-RUN] platform=${platform} release=${IS_RELEASE:-0} debug=${DEBUGGING:-0} step=${DRY_RUN_STEP:-all}"
}

jb_dryrun_step() {
  local step_id="$1"
  local description="$2"
  local command_preview="$3"
  if jb_step_selected "$step_id"; then
    echo "[DRY-RUN][RUN] ${step_id} :: ${description}"
    [ -n "$command_preview" ] && echo "  > ${command_preview}"
  else
    echo "[DRY-RUN][SKIP] ${step_id} :: ${description}"
  fi
}
