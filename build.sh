#!/usr/bin/env bash
# Build a self-contained libheif shared library for runtime loading by
# schist: libde265 (the HEVC decoder) is compiled statically into the
# library, and on Linux libstdc++/libgcc are linked statically too, so
# the artifact depends only on libc/libm. Decode-only: every encoder
# and every other codec is disabled.
#
# Usage: ./build.sh [out-dir]   (defaults to ./dist)
#
# Android is a cross build from any host with an NDK:
#   ANDROID_ABI=arm64-v8a ./build.sh dist     (or x86_64, for emulators)
# The NDK is $ANDROID_NDK_HOME, else $ANDROID_NDK_LATEST_HOME (set on
# GitHub's runners), else the newest under $ANDROID_HOME/ndk. The NDK's
# libc++ is linked statically for the same reason as libstdc++ on Linux:
# the app that dlopens the artifact ships no libc++_shared.so.
set -euo pipefail

cd "$(dirname "$0")"
DE265=vendor/libde265-1.1.1
HEIF=vendor/libheif-1.23.4
HEIF_VERSION=1.23.4
OUT="${1:-dist}"

ANDROID_ABI="${ANDROID_ABI:-}"
if [ -n "$ANDROID_ABI" ]; then
    os=android; ext=so
    case "$ANDROID_ABI" in
        arm64-v8a) arch=aarch64 ;;
        x86_64) arch=x86_64 ;;
        *) echo "unsupported ANDROID_ABI $ANDROID_ABI (arm64-v8a or x86_64)" >&2; exit 1 ;;
    esac
else
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
fi

prefix="$PWD/build/prefix"
linker_flags=""
common_flags=()
strip_tool=strip
if [ "$os" = linux ]; then
    linker_flags="-static-libstdc++ -static-libgcc"
fi
if [ "$os" = android ]; then
    ndk="${ANDROID_NDK_HOME:-${ANDROID_NDK_LATEST_HOME:-}}"
    if [ -z "$ndk" ] && [ -n "${ANDROID_HOME:-}" ]; then
        ndk=$(ls -d "$ANDROID_HOME"/ndk/* 2>/dev/null | sort -V | tail -1)
    fi
    if [ ! -f "$ndk/build/cmake/android.toolchain.cmake" ]; then
        echo "no NDK: set ANDROID_NDK_HOME" >&2; exit 1
    fi
    # The NDK's toolchain file confines find_package to its sysroot;
    # CMAKE_FIND_ROOT_PATH lets libheif find the libde265 installed in
    # the prefix (the toolchain appends the sysroot to it). android-30
    # matches the app's minSdkVersion.
    common_flags+=(
        -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake"
        -DANDROID_ABI="$ANDROID_ABI"
        -DANDROID_PLATFORM=android-30
        -DANDROID_STL=c++_static
        -DCMAKE_FIND_ROOT_PATH="$prefix"
    )
    strip_tool=$(ls "$ndk"/toolchains/llvm/prebuilt/*/bin/llvm-strip | head -1)
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
    # Android shared libraries carry no version in their name.
    android) built="$prefix/lib/libheif.so" ;;
    macos)   built="$(find "$prefix/lib" -name 'libheif*.dylib' -type f | head -1)" ;;
    windows) built="$(find "$prefix/bin" -name '*heif*.dll' | head -1)" ;;
esac
artifact="$OUT/libheif-$HEIF_VERSION-$os-$arch.$ext"
cp "$built" "$artifact"
if [ "$os" != windows ]; then
    "$strip_tool" -x "$artifact" 2>/dev/null || "$strip_tool" "$artifact"
fi

cp "$HEIF/COPYING" "$OUT/COPYING-libheif.txt"
cp "$DE265/COPYING" "$OUT/COPYING-libde265.txt"

echo
echo "artifact: $artifact"
shasum -a 256 "$artifact" 2>/dev/null || sha256sum "$artifact"
