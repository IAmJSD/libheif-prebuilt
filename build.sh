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
common_flags=()
if [ "$os" = linux ]; then
    linker_flags="-static-libstdc++ -static-libgcc"
fi
de265_extra=()
heif_extra=()
if [ "$os" = windows ]; then
    # Static MSVC runtime, so the DLL doesn't require a VC redist.
    common_flags+=(
        -DCMAKE_POLICY_DEFAULT_CMP0091=NEW
        -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded
    )
    # libde265 defines HAVE_VISIBILITY for every optimized build, and
    # de265.h then uses the GCC-only __attribute__((__visibility__))
    # syntax, which MSVC rejects. FORCE_FULL_VISIBILITY skips all of
    # that; it only exists to shrink ELF symbol tables, which a static
    # Windows lib doesn't have.
    de265_extra+=(-DFORCE_FULL_VISIBILITY=ON)
    # de265.h decorates the API dllimport unless told the library is
    # static; without this libheif's decoder gets unresolved __imp_
    # symbols. The other flags restate MSVC's defaults, which setting
    # CMAKE_CXX_FLAGS on the command line would otherwise drop. Dash
    # style, not slash: cl.exe accepts both, and Git Bash's MSYS layer
    # rewrites slash-prefixed args into C:/Program Files/... paths.
    heif_extra+=("-DCMAKE_CXX_FLAGS=-DWIN32 -D_WINDOWS -EHsc -DLIBDE265_STATIC_BUILD")
fi

cmake -S "$DE265" -B build/de265 \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DENABLE_SDL=OFF -DENABLE_DECODER=OFF -DENABLE_ENCODER=OFF \
    ${common_flags[@]+"${common_flags[@]}"} \
    ${de265_extra[@]+"${de265_extra[@]}"} \
    -DCMAKE_INSTALL_PREFIX="$prefix"
# --config is required on Windows's multi-config generator; harmless on
# the single-config Unix ones.
cmake --build build/de265 --config Release -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu)"
cmake --install build/de265 --config Release

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
    ${common_flags[@]+"${common_flags[@]}"} \
    ${heif_extra[@]+"${heif_extra[@]}"} \
    -DCMAKE_INSTALL_PREFIX="$prefix"
cmake --build build/heif --config Release -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu)"
cmake --install build/heif --config Release

mkdir -p "$OUT"
case "$os" in
    linux)   built="$prefix/lib/libheif.so.$HEIF_VERSION" ;;
    macos)   built="$(find "$prefix/lib" -name 'libheif*.dylib' -type f | head -1)" ;;
    windows) built="$(find "$prefix/bin" -name '*heif*.dll' | head -1)" ;;
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
