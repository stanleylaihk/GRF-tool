#!/bin/zsh
set -euo pipefail
# Supply a checkout of Stitchuuuu/granny-ro-js at the pinned revision.
source_root=${1:?Usage: build.sh /path/to/granny-ro-js}
script_dir=${0:A:h}
revision=$(git -C "$source_root" rev-parse HEAD)
[[ "$revision" == 955189e060bf38270cbc3ea8cba610e98c7f62dc ]] || { echo 'Unexpected upstream revision'; exit 1; }
npx --yes --package=esbuild@0.25.0 esbuild "$script_dir/entry.js" --bundle --platform=neutral --format=iife --global-name=GRFGranny --inject:"$script_dir/utf8.js" --alias:granny-ro-js="$source_root/src" --outfile="$script_dir/../../Sources/GRFCore/Resources/granny-preview.js"
