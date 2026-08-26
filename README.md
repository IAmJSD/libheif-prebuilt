# libheif-prebuilt

Prebuilt, self-contained **decode-only** builds of [libheif](https://github.com/strukturag/libheif)
with [libde265](https://github.com/strukturag/libde265) (HEVC) compiled in,
for [schist](https://github.com/IAmJSD/schist) to download **with the user's
consent** and load at runtime for opening HEIC/HEIF files.

Schist itself contains no C or C++ code and never links these libraries at
build time. When a user opens a `.heic` file and no system libheif is
present, schist offers to download one artifact from this repository's
releases (hash-pinned in schist's source) together with the license texts
below, and then loads it with `dlopen`.

## What's in an artifact

One shared library per platform, e.g. `libheif-1.23.2-linux-x86_64.so`:

- libheif, built with every encoder and every non-HEVC codec disabled
  (`WITH_LIBDE265=ON`, everything else `OFF`, plugin loading disabled)
- libde265 statically linked inside
- on Linux, libstdc++/libgcc statically linked too — the artifact depends
  only on libc/libm

Reproduce with `./build.sh` (needs cmake and a C++ compiler).

## Licensing

libheif and libde265 are licensed under the **GNU LGPL v3**. Because they
are distributed as standalone shared libraries and loaded dynamically —
never statically linked into an application — using them does not impose
relinking obligations on the loading application.

Each release ships `COPYING-libheif.txt` and `COPYING-libde265.txt`
alongside the binaries, and schist installs those texts next to the
downloaded library. Complete corresponding source for every artifact is
the `vendor/` tree at the release's tag; the pristine upstream tarballs
are also attached to each release:

| source | sha256 |
|---|---|
| `libde265-1.1.1.tar.gz` | `fd48a927e94ed74fc7ce8829d222b9d8599fcbfe8b6448ba66705babc56ab219` |
| `libheif-1.23.2.tar.gz` | `8bd5d41d19dc84536d118b04774709f244df6104ef66d623dad5fa4650143405` |

HEVC is additionally covered by patent pools in some jurisdictions;
distribution and use of an HEVC decoder may require a patent license
depending on where and how it is used. That risk profile is the same as
installing a distro's libheif/libde265 packages.

The build scripts and CI configuration in this repository (everything
outside `vendor/`) are MIT licensed; the vendored sources keep their own
licenses.

## Cutting a release

Tag `v<libheif-version>-<n>` (e.g. `v1.23.2-1`) and push; CI builds the
Linux and macOS artifacts and attaches them, the license texts, and the
source tarballs to a draft release. Publish it, then update the
hash-pinned URL table in schist (`plugins/codecs-common/src/heif.rs`).
