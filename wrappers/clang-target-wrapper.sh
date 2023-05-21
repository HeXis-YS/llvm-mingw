#!/bin/sh
#
# Copyright (c) 2018 Martin Storsjo
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

DIR="$(cd "$(dirname "$0")" && pwd)"
BASENAME="$(basename "$0")"
TARGET="${BASENAME%-*}"
EXE="${BASENAME##*-}"
DEFAULT_TARGET=x86_64-w64-mingw32
if [ "$TARGET" = "$BASENAME" ]; then
    TARGET=$DEFAULT_TARGET
fi
ARCH="${TARGET%%-*}"
TARGET_OS="${TARGET##*-}"

# Check if trying to compile Ada; if we try to do this, invoking clang
# would end up invoking <triplet>-gcc with the same arguments, which ends
# up in an infinite recursion.
case "$*" in
*-x\ ada*)
    echo "Ada is not supported" >&2
    exit 1
    ;;
*)
    ;;
esac

# Allow setting e.g. CCACHE=1 to wrap all building in ccache.
if [ -n "$CCACHE" ]; then
    CCACHE=ccache
fi

# If changing this wrapper, change clang-target-wrapper.c accordingly.
CLANG="$DIR/clang"
FLAGS=""
FLAGS="$FLAGS --start-no-unused-arguments"
case $EXE in
clang++|g++|c++)
    FLAGS="$FLAGS --driver-mode=g++"
    ;;
c99)
    FLAGS="$FLAGS -std=c99"
    ;;
c11)
    FLAGS="$FLAGS -std=c11"
    ;;
esac
case $ARCH in
i686)
    # Dwarf is the default for i686.
    ;;
x86_64)
    # SEH is the default for x86_64.
    ;;
armv7)
    # SEH is the default for armv7.
    ;;
aarch64)
    # SEH is the default for aarch64.
    ;;
esac
LINKER_FLAGS=""
case $TARGET_OS in
mingw32uwp)
    # the UWP target is for Windows 10
    FLAGS="$FLAGS -D_WIN32_WINNT=0x0A00 -DWINVER=0x0A00"
    # the UWP target can only use Windows Store APIs
    FLAGS="$FLAGS -DWINAPI_FAMILY=WINAPI_FAMILY_APP"
    # the Windows Store API only supports Windows Unicode (some rare ANSI ones are available)
    FLAGS="$FLAGS -DUNICODE"
    # Force the Universal C Runtime
    FLAGS="$FLAGS -D_UCRT"

    # Default linker flags; passed after any user specified -l options,
    # to let the user specified libraries take precedence over these.

    # add the minimum runtime to use for UWP targets
    LINKER_FLAGS="$LINKER_FLAGS --start-no-unused-arguments"
    LINKER_FLAGS="$LINKER_FLAGS -Wl,-lwindowsapp"
    # This still requires that the toolchain (in particular, libc++.a) has
    # been built targeting UCRT originally.
    LINKER_FLAGS="$LINKER_FLAGS -Wl,-lucrtapp"
    LINKER_FLAGS="$LINKER_FLAGS --end-no-unused-arguments"
    ;;
esac

FLAGS="$FLAGS -target $TARGET"
FLAGS="$FLAGS -rtlib=compiler-rt"
FLAGS="$FLAGS -unwindlib=libunwind"
FLAGS="$FLAGS -stdlib=libc++"
FLAGS="$FLAGS -fuse-ld=lld"
FLAGS="$FLAGS --end-no-unused-arguments"

# Initialize the variable to store processed parameters
processed_params="-O3 -march=skylake -mtune=skylake -flto=full -fuse-ld=lld"

# Iterate over the input parameters
for param in "$@"; do
    # Check if the parameter starts with "-O"
    case $param in
        -O*)
            # Check if the parameter is equal to "-Ofast"
            if [ "$param" != "-Ofast" ]; then
                # Ignore the parameter
                continue
            fi
            ;;
    esac

    # Append the processed parameter to the variable
    processed_params="$processed_params $param"
done

$CCACHE "$CLANG" $FLAGS "$processed_params" $LINKER_FLAGS
