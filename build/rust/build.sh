#!/usr/bin/bash
#
# {{{ CDDL HEADER
#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source. A copy of the CDDL is also available via the Internet at
# http://www.illumos.org/license/CDDL.
# }}}

# Copyright 2020 OmniOS Community Edition (OmniOSce) Association.

. ../../lib/functions.sh

PROG=rust
PKG=ooce/developer/rust
VER=1.44.1
SUMMARY="Rust systems programming language"
DESC="Rust is a systems programming language that runs blazingly fast, "
DESC+="prevents segfaults, and guarantees thread safety."

#
# to build rust with a bootstrap binary package instead of the installed
# rust, set BOOTSTRAP_VER=<bootstrap_rust_ver> env variable
#
# to use bundled LLVM instead of the system one, set BUNDLED_LLVM
#
LLVM_MAJVER=10.0

# building miri fails currently, ignore it for now
EXPECTED_BUILD_ERRS=2

BUILDDIR=${PROG}c-${VER}-src

BUILD_DEPENDS_IPS="developer/gnu-binutils"
[ -z "$BOOTSTRAP_VER" ] && BUILD_DEPENDS_IPS+=" ooce/developer/rust"

if [ -z "$BUNDLED_LLVM" ]; then
    SYSTEM_LLVM_PATH="/opt/ooce/llvm-$LLVM_MAJVER"
    RUN_DEPENDS_IPS="ooce/developer/llvm-${LLVM_MAJVER//./}"
    BUILD_DEPENDS_IPS+=" $RUN_DEPENDS_IPS"
fi

MAJVER=${VER%.*}            # M.m
sMAJVER=${MAJVER//./}       # Mm

OPREFIX=$PREFIX
PREFIX+=/$PROG
CONFPATH=/etc$PREFIX
LOGPATH=/var/log$OPREFIX/$PROG
VARPATH=/var$OPREFIX/$PROG
RUNPATH=$VARPATH/run

# rust build requires the final install directory to be present
[ -d "$PREFIX" ] || logcmd $PFEXEC mkdir -p $PREFIX

set_arch 64

XFORM_ARGS="
    -DPREFIX=${PREFIX#/}
    -DOPREFIX=${OPREFIX#/}
    -DPROG=$PROG
    -DVERSION=$MAJVER
    -DsVERSION=$sMAJVER
"

export RUSTARCH=x86_64-sun-solaris
export RUSTFLAGS="-C linker=$CC"
export GNUAR=/bin/gar

# Required to enable the POSIX 1003.6 style getpwuid_r() prototype
# __EXTENSIONS__ - Need struct timeval from sys/time.h
#                  and struct procset_t from sys/procset.h
CFLAGS+=" -D_POSIX_PTHREAD_SEMANTICS -D__EXTENSIONS__"
CXXFLAGS+=" -D_POSIX_PTHREAD_SEMANTICS"
export CFLAGS CXXFLAGS

CONFIGURE_CMD="$PYTHON src/bootstrap/configure.py"

CONFIGURE_OPTS_64="
    --prefix=$PREFIX
    --sysconfdir=$CONFPATH
    --localstatedir=$VARPATH
"

CONFIGURE_OPTS+="
    --enable-vendor
    --enable-extended
    --default-linker=$CC
    --set rust.default-linker=$CC
    --set target.$RUSTARCH.cc=$CC
    --set target.$RUSTARCH.cxx=$CXX
    --set target.$RUSTARCH.ar=$GNUAR
    --set target.$RUSTARCH.linker=$CC
    --enable-rpath
    --enable-ninja
    --disable-codegen-tests
    --disable-dist-src
    --disable-llvm-static-stdcpp
    --disable-docs
    --release-channel=stable
    --python=$PYTHON
"

if [ -n "$SYSTEM_LLVM_PATH" ]; then
    CONFIGURE_OPTS+="
        --enable-llvm-link-shared
        --llvm-root=$SYSTEM_LLVM_PATH
    "
    export LD_LIBRARY_PATH="$SYSTEM_LLVM_PATH/lib"
fi

save_function make_install _make_install
make_install() {
    mkdir -p $DESTDIR/$PREFIX
    _make_install "$@"
}

fix_runpaths() {
    pushd $DESTDIR/$PREFIX >/dev/null

    rpath="$PREFIX/lib:/usr/lib/64:/usr/gcc/$DEFAULT_GCC_VER/lib/$ISAPART64"
    [ -n "$SYSTEM_LLVM_PATH" ] && rpath+=":$SYSTEM_LLVM_PATH/lib"
    for f in bin/{cargo,rls,rustc,rustdoc} lib/*.so* lib/rustlib/$RUSTARCH/*/*.so*; do
        logcmd /usr/bin/elfedit -e "dyn:runpath $rpath" $f
    done

    popd >/dev/null
}

fix_checksums() {
    WRKSRC="$TMPDIR/$BUILDDIR"
    cp ${WRKSRC}/vendor/rand-0.6.1/.cargo-checksum.json \
        ${WRKSRC}/vendor/rand-0.6.1/.cargo-checksum.json.orig
    sed -e 's/1e732c2e3b4bd1561f11e0979bf9d20669a96eae7afe0deff9dfbb980ee47bf1/55abd8100db14a076dedbf84ce0f2db08158e1bd33ff1d4978bd3c4ad978f281/' ${WRKSRC}/vendor/rand-0.6.1/.cargo-checksum.json.orig > ${WRKSRC}/vendor/rand-0.6.1/.cargo-checksum.json
    cp ${WRKSRC}/vendor/libc/.cargo-checksum.json \
        ${WRKSRC}/vendor/libc/.cargo-checksum.json.orig
    sed -e 's/721e1609f429b472bc05c9284e15d6e73b39bbc5f79fff46690642342ed4c1cb/1cf80fac8e5edb960539eedd968aa981ebb54949d7a5c9bb3b4ed6ad5901f1b1/' ${WRKSRC}/vendor/libc/.cargo-checksum.json.orig > ${WRKSRC}/vendor/libc/.cargo-checksum.json
    cp ${WRKSRC}/vendor/backtrace-sys/.cargo-checksum.json \
          ${WRKSRC}/vendor/backtrace-sys/.cargo-checksum.json.orig
    sed -e 's/dbe2eb824252135e7a154805c148defb2142a26b0c2267f5b1033ad69f441e33/323987bb2d5b7ec6044b881b70f339472d886fc23bf212392b8a0158b15d3862/' ${WRKSRC}/vendor/backtrace-sys/.cargo-checksum.json.orig > ${WRKSRC}/vendor/backtrace-sys/.cargo-checksum.json
}

get_bootstrap() {
    if [ -n "$BOOTSTRAP_VER" ]; then
        # Download and extract the bootstrap binary package
        STRAPVER=$BOOTSTRAP_VER-$RUSTARCH
        BUILDDIR=$PROG-$STRAPVER download_source $PROG $PROG $STRAPVER
        BOOTSTRAP_PATH=$TMPDIR/$PROG-$STRAPVER
    else
        BOOTSTRAP_PATH=$PREFIX
    fi

    CONFIGURE_OPTS+=" --local-rust-root=$BOOTSTRAP_PATH "
    export RUSTC=$BOOTSTRAP_PATH/bin/rustc
}

init
get_bootstrap
download_source $PROG ${PROG}c $VER-src
patch_source
fix_checksums
prep_build
build
fix_runpaths
make_package
clean_up

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
