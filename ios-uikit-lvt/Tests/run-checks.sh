#!/bin/sh
# Offline source checks for the standalone UIKit app (ios-uikit-lvt). Compiles each Tests/*Checks.swift with
# the actual Foundation sources and runs it. No app launch, credentials or network; injected fixtures only.
# Usage (from the repository root or ios-uikit-lvt/): sh ios-uikit-lvt/Tests/run-checks.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
app="$here/../LvtCrmUIKit"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/lvt-uikit-checks.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
export TMPDIR="$scratch"
sources="AuthModels CredentialStore ConvexHttpClient HomeroomRepository HomeroomDetail HomeroomWrites HomeroomUploadSupport HomeroomManagement HomeroomPendingJournal HomeroomPresentation DutyWeekPresentation SupervisorAttendance PersonalTodos"
files=""
for name in $sources; do files="$files $app/$name.swift"; done
status=0
for check in "$here"/*Checks.swift; do
  name=$(basename "$check" .swift)
  # shellcheck disable=SC2086
  if swiftc -module-cache-path "$scratch/cache" $files "$check" -o "$scratch/$name" 2>"$scratch/$name.log" && "$scratch/$name"; then
    :
  else
    echo "FAIL $name"; cat "$scratch/$name.log"; status=1
  fi
done
[ "$status" -eq 0 ] && echo "ALL UIKIT SOURCE CHECKS PASSED"
exit "$status"
