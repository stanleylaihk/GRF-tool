#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h}
if [[ -z "${SDKROOT:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
    export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/private/tmp}/grftool-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
plugin_args=()
testing_plugin="$(xcode-select -p)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$testing_plugin" ]]; then
    plugin_args=(-Xswiftc -load-plugin-library -Xswiftc "$testing_plugin")
fi
swift test --package-path "$project_dir" --scratch-path "$project_dir/.build" --cache-path "${TMPDIR:-/private/tmp}/grftool-spm-cache" --disable-sandbox "${plugin_args[@]}" "$@"
