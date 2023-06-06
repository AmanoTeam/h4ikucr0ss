#!/bin/bash

set -eu

declare -r revision="$(git rev-parse --short HEAD)"

declare -r gmp_tarball='/tmp/gmp.tar.xz'
declare -r gmp_directory='/tmp/gmp-6.2.1'

declare -r mpfr_tarball='/tmp/mpfr.tar.xz'
declare -r mpfr_directory='/tmp/mpfr-4.2.0'

declare -r mpc_tarball='/tmp/mpc.tar.gz'
declare -r mpc_directory='/tmp/mpc-1.3.1'

declare -r binutils_tarball='/tmp/binutils.tar.xz'
declare -r binutils_directory='/tmp/binutils-2.40'

declare -r gcc_tarball='/tmp/gcc.tar.xz'
declare -r gcc_directory='/tmp/gcc-11.2.0'

declare -r optflags='-Os'
declare -r linkflags='-Wl,-s'

declare -r max_jobs="$(($(nproc) * 8))"

declare -r cpwd="${PWD}"

if ! [ -f "${gmp_tarball}" ]; then
	wget --no-verbose 'https://ftp.gnu.org/gnu/gmp/gmp-6.2.1.tar.xz' --output-document="${gmp_tarball}"
	tar --directory="$(dirname "${gmp_directory}")" --extract --file="${gmp_tarball}"
fi

if ! [ -f "${mpfr_tarball}" ]; then
	wget --no-verbose 'https://ftp.gnu.org/gnu/mpfr/mpfr-4.2.0.tar.xz' --output-document="${mpfr_tarball}"
	tar --directory="$(dirname "${mpfr_directory}")" --extract --file="${mpfr_tarball}"
fi

if ! [ -f "${mpc_tarball}" ]; then
	wget --no-verbose 'https://ftp.gnu.org/gnu/mpc/mpc-1.3.1.tar.gz' --output-document="${mpc_tarball}"
	tar --directory="$(dirname "${mpc_directory}")" --extract --file="${mpc_tarball}"
fi

if ! [ -f "${binutils_tarball}" ]; then
	wget --no-verbose 'https://ftp.gnu.org/gnu/binutils/binutils-2.40.tar.xz' --output-document="${binutils_tarball}"
	tar --directory="$(dirname "${binutils_directory}")" --extract --file="${binutils_tarball}"
fi

if ! [ -f "${gcc_tarball}" ]; then
	wget --no-verbose 'https://ftp.gnu.org/gnu/gcc/gcc-11.2.0/gcc-11.2.0.tar.xz' --output-document="${gcc_tarball}"
	tar --directory="$(dirname "${gcc_directory}")" --extract --file="${gcc_tarball}"
fi

patch --input="$(realpath './patches/gcc-11.2.0.patch')" --strip=1 --directory="${gcc_directory}"
patch --input="$(realpath './patches/no_hardcoded_paths.patch')" --strip=1 --directory="${gcc_directory}"

# https://gcc.gnu.org/bugzilla/show_bug.cgi?id=51720
sed --in-place 's/$(TARGET-stage1-gcc)/$(TARGET-stage1-gcc) LDFLAGS="$(STAGE1_LDFLAGS)"/' "${gcc_directory}/Makefile.in"

sed --in-place 's/#ifdef _GLIBCXX_HAVE_SYS_SDT_H/#ifdef _GLIBCXX_HAVE_SYS_SDT_HHH/g' "${gcc_directory}/libstdc++-v3/libsupc++/unwind-cxx.h"

[ -d "${gcc_directory}/build" ] || mkdir "${gcc_directory}/build"

declare -r toolchain_directory="/tmp/sil"

[ -d "${gmp_directory}/build" ] || mkdir "${gmp_directory}/build"

cd "${gmp_directory}/build"
rm --force --recursive ./*

../configure \
	--prefix="${toolchain_directory}" \
	--enable-shared \
	--enable-static \
	CFLAGS="${optflags}" \
	CXXFLAGS="${optflags}" \
	LDFLAGS="${linkflags}"

make all --jobs="${max_jobs}"
make install

[ -d "${mpfr_directory}/build" ] || mkdir "${mpfr_directory}/build"

cd "${mpfr_directory}/build"
rm --force --recursive ./*

../configure \
	--prefix="${toolchain_directory}" \
	--with-gmp="${toolchain_directory}" \
	--enable-shared \
	--enable-static \
	CFLAGS="${optflags}" \
	CXXFLAGS="${optflags}" \
	LDFLAGS="${linkflags}"

make all --jobs="${max_jobs}"
make install

[ -d "${mpc_directory}/build" ] || mkdir "${mpc_directory}/build"

cd "${mpc_directory}/build"
rm --force --recursive ./*

../configure \
	--prefix="${toolchain_directory}" \
	--with-gmp="${toolchain_directory}" \
	--enable-shared \
	--enable-static \
	CFLAGS="${optflags}" \
	CXXFLAGS="${optflags}" \
	LDFLAGS="${linkflags}"

make all --jobs="${max_jobs}"
make install

sed -i 's/#include <stdint.h>/#include <stdint.h>\n#include <stdio.h>/g' "${toolchain_directory}/include/mpc.h"

[ -d "${binutils_directory}/build" ] || mkdir "${binutils_directory}/build"

declare -r targets=(
	'amd64'
	'i386'
)

for target in "${targets[@]}"; do
	case "${target}" in
		amd64)
			declare triple='x86_64-unknown-haiku';;
		i386)
			declare triple='i586-unknown-haiku';;
	esac
	
	declare sysroot_tarball="/tmp/${triple}.tar.xz"
	declare sysroot_directory="/tmp/${triple}"
	
	wget "https://github.com/AmanoTeam/haiku-sysroot/releases/download/0.1/${triple}.tar.xz" --output-document="${sysroot_tarball}"
	
	tar --directory="$(dirname "${sysroot_directory}")" --extract --file="${sysroot_tarball}"
	
	cd "${binutils_directory}/build"
	rm --force --recursive ./*
	
	../configure \
		--target="${triple}" \
		--prefix="${toolchain_directory}" \
		--enable-gold \
		--enable-ld \
		--enable-lto \
		--disable-gprofng \
		--with-static-standard-libraries \
		--program-prefix="${triple}-" \
		CFLAGS="${optflags}" \
		CXXFLAGS="${optflags}" \
		LDFLAGS="${linkflags}"
	
	make all --jobs="${max_jobs}"
	make install
	
	declare cinclude_flags="$(
		cat <<- flags | tr '\n' ' '
			-I${toolchain_directory}/${triple}/include/os
			-I${toolchain_directory}/${triple}/include/os/app
			-I${toolchain_directory}/${triple}/include/os/device
			-I${toolchain_directory}/${triple}/include/os/drivers
			-I${toolchain_directory}/${triple}/include/os/game
			-I${toolchain_directory}/${triple}/include/os/interface
			-I${toolchain_directory}/${triple}/include/os/kernel
			-I${toolchain_directory}/${triple}/include/os/locale
			-I${toolchain_directory}/${triple}/include/os/mail
			-I${toolchain_directory}/${triple}/include/os/media
			-I${toolchain_directory}/${triple}/include/os/midi
			-I${toolchain_directory}/${triple}/include/os/midi2
			-I${toolchain_directory}/${triple}/include/os/net
			-I${toolchain_directory}/${triple}/include/os/opengl
			-I${toolchain_directory}/${triple}/include/os/storage
			-I${toolchain_directory}/${triple}/include/os/support
			-I${toolchain_directory}/${triple}/include/os/translation
			-I${toolchain_directory}/${triple}/include/os/add-ons/graphics
			-I${toolchain_directory}/${triple}/include/os/add-ons/input_server
			-I${toolchain_directory}/${triple}/include/os/add-ons/mail_daemon
			-I${toolchain_directory}/${triple}/include/os/add-ons/registrar
			-I${toolchain_directory}/${triple}/include/os/add-ons/screen_saver
			-I${toolchain_directory}/${triple}/include/os/add-ons/tracker
			-I${toolchain_directory}/${triple}/include/os/be_apps/Deskbar
			-I${toolchain_directory}/${triple}/include/os/be_apps/NetPositive
			-I${toolchain_directory}/${triple}/include/os/be_apps/Tracker
			-I${toolchain_directory}/${triple}/include/3rdparty
			-I${toolchain_directory}/${triple}/include/bsd
			-I${toolchain_directory}/${triple}/include/glibc
			-I${toolchain_directory}/${triple}/include/gnu
			-I${toolchain_directory}/${triple}/include/posix
			-I${toolchain_directory}/${triple}/include
		flags
	)"
	
	[ -d "${toolchain_directory}/${triple}/include" ] || mkdir "${toolchain_directory}/${triple}/include"
	[ -d "${toolchain_directory}/${triple}/lib" ] || mkdir "${toolchain_directory}/${triple}/lib"
	
	cp --no-dereference "${sysroot_directory}/system/lib/"* "${toolchain_directory}/${triple}/lib"
	
	while read filename; do
		declare name="$(basename "${filename}")"
		
		declare target="${toolchain_directory}/${triple}/lib/${name}"
		
		if [ -f "${target}" ]; then
			continue
		fi
		
		cp --no-dereference "${filename}" "${target}"
	done <<< "$(ls "${sysroot_directory}/system/develop/lib/"*)"
	
	cp --no-dereference --recursive "${sysroot_directory}/system/develop/headers/"* "${toolchain_directory}/${triple}/include"
	
	cd "${gcc_directory}/build"
	
	rm --force --recursive ./*
	
	../configure \
		--target="${triple}" \
		--prefix="${toolchain_directory}" \
		--with-linker-hash-style='sysv' \
		--with-gmp="${toolchain_directory}" \
		--with-mpc="${toolchain_directory}" \
		--with-mpfr="${toolchain_directory}" \
		--with-bugurl='https://github.com/AmanoTeam/Sil/issues' \
		--enable-__cxa_atexit \
		--enable-cet='auto' \
		--enable-checking='release' \
		--enable-default-ssp \
		--enable-gnu-indirect-function \
		--enable-gnu-unique-object \
		--enable-libstdcxx-backtrace \
		--enable-link-serialization='1' \
		--enable-linker-build-id \
		--enable-lto \
		--disable-multilib \
		--enable-plugin \
		--enable-shared \
		--enable-threads='posix' \
		--enable-libssp \
		--disable-libstdcxx-pch \
		--disable-werror \
		--enable-languages='c,c++' \
		--disable-bootstrap \
		--disable-libatomic \
		--disable-libgomp \
		--without-headers \
		--enable-ld \
		--enable-gold \
		--with-gcc-major-version-only \
		--with-pkgversion="Sil v0.2-${revision}" \
		--with-sysroot="${toolchain_directory}/${triple}" \
		--with-native-system-header-dir='/include' \
		--disable-nls \
		--with-default-libstdcxx-abi='gcc4-compatible' \
		--enable-frame-pointer \
		--with-boot-ldflags='-Wl,-rpath,$ORIGIN/../../../../lib' \
		CFLAGS="${optflags}" \
		CXXFLAGS="${optflags}" \
		LDFLAGS=""
	
	LD_LIBRARY_PATH="${toolchain_directory}/lib" PATH="${PATH}:${toolchain_directory}/bin" make \
		CFLAGS_FOR_TARGET="${optflags} ${linkflags} ${cinclude_flags}" \
		CXXFLAGS_FOR_TARGET="${optflags} ${linkflags} ${cinclude_flags}" \
		all --jobs="${max_jobs}"
	make install
	
	cd "${toolchain_directory}/${triple}/bin"
	
	for name in *; do
		rm "${name}"
		ln -s "../../bin/${triple}-${name}" "${name}"
	done
	
	rm --recursive "${toolchain_directory}/share"
done

while read name; do
	declare mime_type="$(file --brief --mime-type "${name}")"
	
	if ! ( [ "${mime_type}" == 'application/x-executable' ] || [ "${mime_type}" == 'application/x-sharedlib' ] ); then
		continue
	fi

	strip --discard-all "${name}"
done <<< "$(find "${toolchain_directory}" -type 'f')"

tar --directory="$(dirname "${toolchain_directory}")" --create --file=- "$(basename "${toolchain_directory}")" |  xz --threads=0 --compress -9 > "${cpwd}/haiku-cross.tar.xz"
