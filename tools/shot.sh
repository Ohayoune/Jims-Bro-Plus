#!/bin/zsh
# Build, seed and screenshot the app on a booted simulator.
#   tools/shot.sh <out.png> [launch args...]
# The container is seeded through the app's own Store (tools/seed), so what the screenshot
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
  # The seeder's source is tracked in tools/seed; the binary is built into the ignored
  # build/ folder, and only when it is missing or older than any source it compiles.
  mkdir -p build/seed
  if [[ ! -x build/seed/seed || -n $(find tools/seed/main.swift JimmsBro/Core JimmsBro/Store -newer build/seed/seed 2>/dev/null) ]]; then
    xcrun swiftc -O -o build/seed/seed tools/seed/main.swift \
      JimmsBro/Core/*.swift JimmsBro/Store/*.swift > build/seed-build.log 2>&1 \
      || { tail -30 build/seed-build.log; exit 1; }
  fi
  CONTAINER=$(xcrun simctl get_app_container "$DEVICE" com.ohayoune.jimmsbro data)
  rm -rf "$CONTAINER/Library/Application Support/JimmsBro"
  mkdir -p "$CONTAINER/Library/Application Support/JimmsBro"
  # v1.3: SEED_PROGRESSION=1 attaches a four-week progression to the seeded plan (D44).
  # v1.5: SEED_STEPS=1 makes that progression one of steps you earn (D53).
  # v1.7: SEED_NO_HISTORY=1 seeds the plan and no workouts, for History's empty state (D63).
  # v1.9: SEED_SWAP=1 finishes an unexpected workout today, so Today shows a swap's marks (D74).
  # v1.9: SEED_PLANS=1 adds two built-in plans, not active, so Plans has circles to mark (D78).
  # v1.11: the README's add-plan.png is `-uiScreen import` — Add plan's Ask state since D90 —
  #        with SEED_NO_HISTORY=1, so Full Body still wears D57's "Start here" badge.
  build/seed/seed "$CONTAINER" JimmsBro/Resources/SamplePlan.json ${SEED_PROGRESSION:+--progression} ${SEED_STEPS:+--steps} ${SEED_NO_HISTORY:+--no-history} ${SEED_SWAP:+--swap} ${SEED_PLANS:+--plans} >/dev/null
fi

xcrun simctl terminate "$DEVICE" com.ohayoune.jimmsbro 2>/dev/null || true
xcrun simctl launch "$DEVICE" com.ohayoune.jimmsbro "$@" >/dev/null
sleep ${SETTLE:-4}
xcrun simctl io "$DEVICE" screenshot "$OUT" >/dev/null 2>&1
echo "wrote $OUT"
