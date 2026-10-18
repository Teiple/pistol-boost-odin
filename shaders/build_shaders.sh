#!/usr/bin/bash
shopt -s nullglob

shdc="sokol-shdc"

if ! command -v $shdc &> /dev/null; then
	echo "$shdc not found"
fi

for gl_file in *.glsl; do
	name=$(basename $gl_file .glsl)
	$shdc -i $gl_file -o $name.odin -l glsl430:metal_macos:hlsl5 -f sokol_odin
done

# keep the thingy
exec bash