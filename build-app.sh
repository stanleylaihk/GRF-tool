#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h}
# This host's newest SDK and compiler are mismatched; the installed 26.5 SDK works.
if [[ -z "${SDKROOT:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
    export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/private/tmp}/grftool-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
build_args=(--package-path "$project_dir" --scratch-path "$project_dir/.build" --cache-path "${TMPDIR:-/private/tmp}/grftool-spm-cache" --disable-sandbox --configuration release)
swift build "${build_args[@]}" -debug-info-format none
binary_dir=$(swift build "${build_args[@]}" --show-bin-path)
output="$project_dir/release/GRF Tool.app"
mkdir -p "$output/Contents/MacOS" "$output/Contents/Resources"
cp "$binary_dir/GRFToolMac" "$output/Contents/MacOS/GRFToolMac"
cp "$project_dir/Info.plist" "$output/Contents/Info.plist"
if [[ -d "$binary_dir/GRFToolMac_GRFCore.bundle" ]]; then
    ditto "$binary_dir/GRFToolMac_GRFCore.bundle" "$output/Contents/Resources/GRFToolMac_GRFCore.bundle"
fi
cp "$project_dir/LICENSE" "$project_dir/THIRD_PARTY_NOTICES.md" "$output/Contents/Resources/"
codesign --force --sign - "$output"
echo "Built: $output"
