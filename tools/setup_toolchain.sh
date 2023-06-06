#!/bin/bash

set -eu

declare -r SIL_HOME='/tmp/sil-toolchain'

if [ -d "${SIL_HOME}" ]; then
	PATH+=":${SIL_HOME}/bin"
	export SIL_HOME \
		PATH
	return 0
fi

declare -r SIL_CROSS_TAG="$(jq --raw-output '.tag_name' <<< "$(curl --retry 10 --retry-delay 3 --silent --url 'https://api.github.com/repos/AmanoTeam/Sil/releases/latest')")"
declare -r SIL_CROSS_TARBALL='/tmp/sil.tar.xz'
declare -r SIL_CROSS_URL="https://github.com/AmanoTeam/Sil/releases/download/${SIL_CROSS_TAG}/x86_64-linux-gnu.tar.xz"

curl --retry 10 --retry-delay 3 --silent --location --url "${SIL_CROSS_URL}" --output "${SIL_CROSS_TARBALL}"
tar --directory="$(dirname "${SIL_CROSS_TARBALL}")" --extract --file="${SIL_CROSS_TARBALL}"

rm "${SIL_CROSS_TARBALL}"

mv '/tmp/sil' "${SIL_HOME}"

PATH+=":${SIL_HOME}/bin"

export SIL_HOME \
	PATH
