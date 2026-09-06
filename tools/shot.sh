#!/bin/zsh
# Build, seed and screenshot the app on a booted simulator.
#   tools/shot.sh <out.png> [launch args...]
# The container is seeded through the app's own Store (build/seed), so what the screenshot
# shows is what the app would really have written. Rebuilds only when sources changed.
set -e
cd "$(dirname "$0")/.."
DEVICE=${DEVICE:-"iPhone 16"}
OUT="$1"; shift

APP=$(xcodebuild -scheme JimmsBro -destination "platform=iOS Simulator,name=$DEVICE" \
      -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2; exit}')/JimmsBro.app

if [[ -z "$SKIP_BUILD" ]]; then
  xcodebuild build -scheme JimmsBro -destination "platform=iOS Simulator,name=$DEVICE" \
    > build/shot-build.log 2>&1 || { tail -30 build/shot-build.log; exit 1; }
fi

xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" >/dev/null 2>&1 || true
# An unanswered notification prompt from a previous run is re-presented on the next launch and
# would sit over every screenshot, so a seeded run starts from a clean install.
if [[ -n "$SEED" ]]; then
  xcrun simctl uninstall "$DEVICE" com.ohayoune.jimmsbro 2>/dev/null || true
fi
xcrun simctl install "$DEVICE" "$APP"

if [[ -n "$SEED" ]]; then
  CONTAINER=$(xcrun simctl get_app_container "$DEVICE" com.ohayoune.jimmsbro data)
  rm -rf "$CONTAINER/Library/Application Support/JimmsBro"
  mkdir -p "$CONTAINER/Library/Application Support/JimmsBro"
  build/seed/seed "$CONTAINER" JimmsBro/Resources/SamplePlan.json >/dev/null
fi

xcrun simctl terminate "$DEVICE" com.ohayoune.jimmsbro 2>/dev/null || true
xcrun simctl launch "$DEVICE" com.ohayoune.jimmsbro "$@" >/dev/null
sleep ${SETTLE:-4}
xcrun simctl io "$DEVICE" screenshot "$OUT" >/dev/null 2>&1
echo "wrote $OUT"
