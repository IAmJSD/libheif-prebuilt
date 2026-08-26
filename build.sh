#!/usr/bin/env bash
# Build a self-contained libheif shared library for runtime loading by
# schist: libde265 (the HEVC decoder) is compiled statically into the
# library, and on Linux libstdc++/libgcc are linked statically too, so
# the artifact depends only on libc/libm. Decode-only: every encoder
# and every other codec is disabled.
#
# Usage: ./build.sh [out-dir]   (defaults to ./dist)
set -euo pipefail

cd "$(dirname "$0")"
DE265=vendor/libde265-1.1.1
HEIF=vendor/libheif-1.23.2
HEIF_VERSION=1.23.2
OUT="${1:-dist}"

case "$(uname -s)" in
    Linux)  os=linux;  ext=so ;;
    Darwin) os=macos;  ext=dylib ;;
    MINGW*|MSYS*) os=windows; ext=dll ;;
    *) echo "unsupported OS" >&2; exit 1 ;;
esac
case "$(uname -m)" in
    x86_64|amd64) arch=x86_64 ;;
    arm64|aarch64) arch=aarch64 ;;
    *) echo "unsupported arch" >&2; exit 1 ;;
esac

prefix="$PWD/build/prefix"
linker_flags=""
if [ "$os" = linux ]; then
    linker_flags="-static-libstdc++ -static-libgcc"
fi

cmake -S "$DE265" -B build/de265 \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DENABLE_SDL=OFF -DENABLE_DECODER=OFF -DENABLE_ENCODER=OFF \
    -DCMAKE_INSTALL_PREFIX="$prefix"
cmake --build build/de265 -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu)"
cmake --install build/de265

PKG_CONFIG_PATH="$prefix/lib/pkgconfig" cmake -S "$HEIF" -B build/heif \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_PREFIX_PATH="$prefix" \
    -DWITH_LIBDE265=ON -DWITH_LIBDE265_PLUGIN=OFF \
    -DWITH_X265=OFF -DWITH_X264=OFF -DWITH_OpenH264_DECODER=OFF \
    -DWITH_AOM_DECODER=OFF -DWITH_AOM_ENCODER=OFF \
    -DWITH_DAV1D=OFF -DWITH_SvtEnc=OFF -DWITH_RAV1E=OFF \
    -DWITH_JPEG_DECODER=OFF -DWITH_JPEG_ENCODER=OFF \
    -DWITH_OpenJPEG_ENCODER=OFF -DWITH_OpenJPEG_DECODER=OFF \
    -DWITH_OPENJPH_ENCODER=OFF -DWITH_FFMPEG_DECODER=OFF \
    -DWITH_KVAZAAR=OFF -DWITH_UVG266=OFF -DWITH_VVDEC=OFF -DWITH_VVENC=OFF \
    -DENABLE_PLUGIN_LOADING=OFF -DWITH_LIBSHARPYUV=OFF \
    -DWITH_EXAMPLES=OFF -DWITH_GDK_PIXBUF=OFF \
    -DBUILD_TESTING=OFF -DBUILD_DOCUMENTATION=OFF \
    -DCMAKE_SHARED_LINKER_FLAGS="$linker_flags" \
    -DCMAKE_INSTALL_PREFIX="$prefix"
cmake --build build/heif -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu)"
cmake --install build/heif

mkdir -p "$OUT"
case "$os" in
    linux)   built="$prefix/lib/libheif.so.$HEIF_VERSION" ;;
    macos)   built="$(find "$prefix/lib" -name 'libheif*.dylib' -type f | head -1)" ;;
    windows) built="$prefix/bin/heif.dll" ;;
esac
artifact="$OUT/libheif-$HEIF_VERSION-$os-$arch.$ext"
cp "$built" "$artifact"
if [ "$os" != windows ]; then
    strip -x "$artifact" 2>/dev/null || strip "$artifact"
fi

cp "$HEIF/COPYING" "$OUT/COPYING-libheif.txt"
cp "$DE265/COPYING" "$OUT/COPYING-libde265.txt"

echo
echo "artifact: $artifact"
shasum -a 256 "$artifact" 2>/dev/null || sha256sum "$artifact"
