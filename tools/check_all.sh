#!/bin/zsh
# Every check CI runs (.github/workflows/ci.yml), on this Mac, in CI's order.
#   tools/check_all.sh
# Each step's full output goes to build/check-<step>.log; the terminal gets one line per step
# and, for a failure, the end of its log. Every step runs even after one fails, as CI's jobs
# do, and the exit code is nonzero if any failed. The simulator is $DEVICE, iPhone 17 unless
# set (any installed iPhone works).
cd "$(dirname "$0")/.."
DEVICE=${DEVICE:-"iPhone 17"}
DESTINATION="platform=iOS Simulator,name=$DEVICE"
mkdir -p build
FAILED=()

step() {
  local name=$1; shift
  local log=build/check-$name.log
  local start=$SECONDS
  if "$@" > $log 2>&1; then
    printf '  ok    %-16s %4ds\n' $name $(( SECONDS - start ))
  else
    printf '  FAIL  %-16s %4ds   %s\n' $name $(( SECONDS - start )) $log
    tail -n 20 $log | sed 's/^/        /'
    FAILED+=$name
  fi
}

step fixtures      python3 tools/reference_import.py
step release-facts python3 tools/check_release.py
step bundle        python3 tools/check_bundle.py
step swift-test    swift test
step check-core    python3 tools/check_core.py
step app-test      xcodebuild test -scheme JimmsBro -destination $DESTINATION \
                     CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
step release-build xcodebuild build -scheme JimmsBro -configuration Release -destination $DESTINATION \
                     CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

if (( ${#FAILED} )); then
  echo "Failed: ${FAILED[*]}"
  exit 1
fi
echo "All green."
