#!/usr/bin/bash
set -x

pyftsubset="pyftsubset"
odin="odin" 

if ! command -v $pyftsubset &> /dev/null; then
	echo "$pyftsubset not found"
fi

if ! command -v $odin &> /dev/null; then
	echo "$odin not found"
fi

dir=$(dirname "$0")

odin run -file "$dir/loc_subset.odin"

# For Simplified Chinese
# include ASCII characters
pyftsubset "$dir/assets/fonts/NotoSansMonoCJKsc-Regular.otf" \
	--text-file="$dir/loc_subset_sc.txt" \
	--unicodes="U+0020-007E" \
	--output-file="$dir/../assets/fonts/NotoSansMonoCJKsc-Subset.ttf"

# For Japanese
pyftsubset "$dir/assets/fonts/NotoSansMonoCJKjp-Regular.otf" \
	--text-file="$dir/loc_subset_jp.txt" \
	--unicodes="U+0020-007E" \
	--output-file="$dir/../assets/fonts/NotoSansMonoCJKjp-Subset.ttf"

# Keep the thingy
exec bash