#!/bin/sh
# 精简 iOS Payload 二进制体积（仅用于构建非签名侧载 .ipa）

foreachThin() {
  for file in "$1"/*; do
    if [ -f "$file" ]; then
      mime=$(file --mime-type -b "$file")
      if [ "$mime" = "application/x-mach-binary" ] || [ "${file##*.}" = "dylib" ]; then
        echo "thin $file"
        xcrun -sdk iphoneos lipo "$file" -thin arm64 -output "$file" 2>/dev/null || true
        xcrun -sdk iphoneos bitcode_strip "$file" -r -o "$file" 2>/dev/null || true
        strip -S -x "$file" -o "$file" 2>/dev/null || true
      fi
    fi
    if [ -d "$file" ]; then
      foreachThin "$file"
    fi
  done
}

if [ $# -eq 0 ]; then
  echo "no argument"
else
  foreachThin "$1"
fi
