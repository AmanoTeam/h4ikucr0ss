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
declare -r gcc_directory='/tmp/gcc-13.2.0'

declare -r cflags='-Wno-builtin-declaration-mismatch -Wno-strict-prototypes -Os'
declare -r linkflags='-Wl,-s'

declare -r max_jobs="$(($(nproc) * 8))"

declare build_type="${1}"

if [ -z "${build_type}" ]; then
	build_type='native'
fi

declare is_native='0'

if [ "${build_type}" == 'native' ]; then
	is_native='1'
fi

declare OBGGCC_TOOLCHAIN='/tmp/obggcc-toolchain'
declare CROSS_COMPILE_TRIPLET=''

declare cross_compile_flags=''

if ! (( is_native )); then
	source "./submodules/obggcc/toolchains/${build_type}.sh"
	cross_compile_flags+="--host=${CROSS_COMPILE_TRIPLET}"
fi

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
	wget --no-verbose 'https://ftp.gnu.org/gnu/gcc/gcc-13.2.0/gcc-13.2.0.tar.xz' --output-document="${gcc_tarball}"
	tar --directory="$(dirname "${gcc_directory}")" --extract --file="${gcc_tarball}"
fi

patch --input="$(realpath './patches/gcc-13.2.0.patch')" --strip=1 --directory="${gcc_directory}"
patch --input="$(realpath './patches/no_hardcoded_paths.patch')" --strip=1 --directory="${gcc_directory}"

sed -i 's/#ifdef _GLIBCXX_HAVE_SYS_SDT_H/#ifdef _GLIBCXX_HAVE_SYS_SDT_HHH/g' "${gcc_directory}/libstdc++-v3/libsupc++/unwind-cxx.h"

[ -d "${gcc_directory}/build" ] || mkdir "${gcc_directory}/build"

declare -r toolchain_directory="/tmp/sil"

[ -d "${gmp_directory}/build" ] || mkdir "${gmp_directory}/build"

cd "${gmp_directory}/build"
rm --force --recursive ./*

../configure \
	--prefix="${toolchain_directory}" \
	--enable-shared \
	--enable-static \
	${cross_compile_flags} \
	CFLAGS="${cflags}" \
	CXXFLAGS="${cflags}" \
	LDFLAGS="${linkflags}"

make all --jobs
make install

[ -d "${mpfr_directory}/build" ] || mkdir "${mpfr_directory}/build"

cd "${mpfr_directory}/build"
rm --force --recursive ./*

../configure \
	--prefix="${toolchain_directory}" \
	--with-gmp="${toolchain_directory}" \
	--enable-shared \
	--enable-static \
	${cross_compile_flags} \
	CFLAGS="${cflags}" \
	CXXFLAGS="${cflags}" \
	LDFLAGS="${linkflags}"

make all --jobs
make install

[ -d "${mpc_directory}/build" ] || mkdir "${mpc_directory}/build"

cd "${mpc_directory}/build"
rm --force --recursive ./*

../configure \
	--prefix="${toolchain_directory}" \
	--with-gmp="${toolchain_directory}" \
	--enable-shared \
	--enable-static \
	${cross_compile_flags} \
	CFLAGS="${cflags}" \
	CXXFLAGS="${cflags}" \
	LDFLAGS="${linkflags}"

make all --jobs
make install

sed -i 's/#include <stdint.h>/#include <stdint.h>\n#include <stdio.h>/g' "${toolchain_directory}/include/mpc.h"

[ -d "${binutils_directory}/build" ] || mkdir "${binutils_directory}/build"

declare -r targets=(
	'i386'
	'amd64'
)

for target in "${targets[@]}"; do
	case "${target}" in
		amd64)
			declare triplet='x86_64-unknown-haiku';;
		i386)
			declare triplet='i586-unknown-haiku';;
	esac
	
	declare sysroot_tarball="/tmp/${triplet}.tar.xz"
	declare sysroot_directory="/tmp/${triplet}"
	
	wget "https://github.com/AmanoTeam/haiku-sysroot/releases/download/0.1/${triplet}.tar.xz" --output-document="${sysroot_tarball}"
	
	tar --directory="$(dirname "${sysroot_directory}")" --extract --file="${sysroot_tarball}"
	
	cd "${binutils_directory}/build"
	rm --force --recursive ./*
	
	../configure \
		--target="${triplet}" \
		--prefix="${toolchain_directory}" \
		--enable-gold \
		--enable-ld \
		--enable-lto \
		--disable-gprofng \
		--with-static-standard-libraries \
		--with-sysroot="${toolchain_directory}/${triplet}" \
		${cross_compile_flags} \
		CFLAGS="${cflags}" \
		CXXFLAGS="${cflags}" \
		LDFLAGS="${linkflags}"
	
	make all --jobs="${max_jobs}"
	make install
	
	declare cinclude_flags="$(
		cat <<- flags | tr '\n' ' '
			-I${toolchain_directory}/${triplet}/include/os
			-I${toolchain_directory}/${triplet}/include/os/app
			-I${toolchain_directory}/${triplet}/include/os/device
			-I${toolchain_directory}/${triplet}/include/os/drivers
			-I${toolchain_directory}/${triplet}/include/os/game
			-I${toolchain_directory}/${triplet}/include/os/interface
			-I${toolchain_directory}/${triplet}/include/os/kernel
			-I${toolchain_directory}/${triplet}/include/os/locale
			-I${toolchain_directory}/${triplet}/include/os/mail
			-I${toolchain_directory}/${triplet}/include/os/media
			-I${toolchain_directory}/${triplet}/include/os/midi
			-I${toolchain_directory}/${triplet}/include/os/midi2
			-I${toolchain_directory}/${triplet}/include/os/net
			-I${toolchain_directory}/${triplet}/include/os/opengl
			-I${toolchain_directory}/${triplet}/include/os/storage
			-I${toolchain_directory}/${triplet}/include/os/support
			-I${toolchain_directory}/${triplet}/include/os/translation
			-I${toolchain_directory}/${triplet}/include/os/add-ons/graphics
			-I${toolchain_directory}/${triplet}/include/os/add-ons/input_server
			-I${toolchain_directory}/${triplet}/include/os/add-ons/mail_daemon
			-I${toolchain_directory}/${triplet}/include/os/add-ons/registrar
			-I${toolchain_directory}/${triplet}/include/os/add-ons/screen_saver
			-I${toolchain_directory}/${triplet}/include/os/add-ons/tracker
			-I${toolchain_directory}/${triplet}/include/os/be_apps/Deskbar
			-I${toolchain_directory}/${triplet}/include/os/be_apps/NetPositive
			-I${toolchain_directory}/${triplet}/include/os/be_apps/Tracker
			-I${toolchain_directory}/${triplet}/include/3rdparty
			-I${toolchain_directory}/${triplet}/include/bsd
			-I${toolchain_directory}/${triplet}/include/glibc
			-I${toolchain_directory}/${triplet}/include/gnu
			-I${toolchain_directory}/${triplet}/include/posix
			-I${toolchain_directory}/${triplet}/include
		flags
	)"
	
	[ -d "${toolchain_directory}/${triplet}/include" ] || mkdir "${toolchain_directory}/${triplet}/include"
	[ -d "${toolchain_directory}/${triplet}/lib" ] || mkdir "${toolchain_directory}/${triplet}/lib"
	
	cp --no-dereference "${sysroot_directory}/system/lib/"* "${toolchain_directory}/${triplet}/lib"
	
	while read filename; do
		declare name="$(basename "${filename}")"
		declare target="${toolchain_directory}/${triplet}/lib/${name}"
		
		if [ -f "${target}" ]; then
			continue
		fi
		
		cp --no-dereference "${filename}" "${target}"
	done <<< "$(ls "${sysroot_directory}/system/develop/lib/"*)"
	
	cp --no-dereference --recursive "${sysroot_directory}/system/develop/headers/"* "${toolchain_directory}/${triplet}/include"
	
	sed -i 's/__GNUC__ <= 12/__GNUC__ <= 13/g' "${toolchain_directory}/${triplet}/include/os/BeBuild.h"
	
	cd "${gcc_directory}/build"
	
	rm --force --recursive ./*
	
	../configure \
		--target="${triplet}" \
		--prefix="${toolchain_directory}" \
		--with-linker-hash-style='sysv' \
		--with-gmp="${toolchain_directory}" \
		--with-mpc="${toolchain_directory}" \
		--with-mpfr="${toolchain_directory}" \
		--with-bugurl='https://github.com/AmanoTeam/Sil/issues' \
		--with-gcc-major-version-only \
		--with-pkgversion="Sil v0.5-${revision}" \
		--with-sysroot="${toolchain_directory}/${triplet}" \
		--with-native-system-header-dir='/include' \
		--with-default-libstdcxx-abi='gcc4-compatible' \
		--includedir="${toolchain_directory}/${triplet}/include" \
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
		--enable-plugin \
		--enable-shared \
		--enable-threads='posix' \
		--enable-libssp \
		--enable-languages='c,c++' \
		--enable-ld \
		--enable-gold \
		--enable-frame-pointer \
		--disable-bootstrap \
		--disable-libatomic \
		--disable-libgomp \
		--disable-libstdcxx-pch \
		--disable-werror \
		--disable-multilib \
		--disable-nls \
		--without-headers \
		${cross_compile_flags} \
		CFLAGS="${cflags}" \
		CXXFLAGS="${cflags}" \
		LDFLAGS="-Wl,-rpath-link,${OBGGCC_TOOLCHAIN}/${CROSS_COMPILE_TRIPLET}/lib"
	
	LD_LIBRARY_PATH="${toolchain_directory}/lib" PATH="${PATH}:${toolchain_directory}/bin" make \
		CFLAGS_FOR_TARGET="${cflags} ${linkflags} ${cinclude_flags}" \
		CXXFLAGS_FOR_TARGET="${cflags} ${linkflags} ${cinclude_flags}" \
		all --jobs="${max_jobs}"
	make install
	
	cd "${toolchain_directory}/${triplet}/bin"
	
	for name in *; do
		rm "${name}"
		ln -s "../../bin/${triplet}-${name}" "${name}"
	done
	
	rm --recursive "${toolchain_directory}/share"
	
	patchelf --add-rpath '$ORIGIN/../../../../lib' "${toolchain_directory}/libexec/gcc/${triplet}/"*"/cc1"
	patchelf --add-rpath '$ORIGIN/../../../../lib' "${toolchain_directory}/libexec/gcc/${triplet}/"*"/cc1plus"
	patchelf --add-rpath '$ORIGIN/../../../../lib' "${toolchain_directory}/libexec/gcc/${triplet}/"*"/lto1"
done
