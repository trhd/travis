#!/bin/bash -eu

MESON=meson
MESONCONF=mesonconf
MESONTEST=mesontest
MESONTEST_ARGS=("--no-stdsplit" "--print-errorlogs")


get_meson()
{
	local url=https://github.com/

	printf "%s: Setting up a local installation of meson.\n" "$0"

	url+=$(curl "${VERBOSE:--s}" -L https://github.com/mesonbuild/meson/releases/latest/ \
		| grep -oE 'mesonbuild/meson/releases/download/[^/]+/meson-[0-9]+(\.[0-9]+)+.tar.gz"' \
		| sed 's/"$//')

	pushd "$BDIR" &>/dev/null

	wget "${VERBOSE:--q}" "$url"

	tar -xf "$(basename "$url")"

	PATH="$PWD/$(basename "${url%.tar.gz}")/:$PATH"

	MESON+=.py
	MESONCONF+=.py
	MESONTEST+=.py

	popd &>/dev/null
}

get_ninja()
{
	local url=https://github.com/

	printf "%s: Setting up a local installation of ninja.\n" "$0"

	url+=$(curl "${VERBOSE:--s}" -L https://github.com/ninja-build/ninja/releases/latest/ \
		| grep -oE 'ninja-build/ninja/releases/download/v[^/]+/ninja-linux.zip' \
		| sed 's/"$//')

	pushd "$BDIR" &>/dev/null

	wget "${VERBOSE:--q}" "$url"

	mkdir ninjabin
	unzip -q "$(basename "$url")" -d ninjabin

	PATH="$PWD/ninjabin:$PATH"

	popd &>/dev/null
}

get_cmocka()
{
	local url=https://cmocka.org/files/1.1/cmocka-1.1.0.tar.xz

	pushd "$BDIR" &>/dev/null

	wget "${VERBOSE:--q}" "$url"
	tar -xf "$(basename "$url")"
	cd "$(basename ${url%.tar.xz})"
	mkdir build
	( cd build ; cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Debug .. )
	make -C build
	sudo make -C build install

	popd &>/dev/null
}

cleanup()
{
	[ ! -d "${BDIR:-}" ] || rm -rf "$BDIR"
}

prepare_env()
{
	trap cleanup EXIT

	BDIR="$(mktemp -d)"

	which $MESON &>/dev/null || get_meson
	which ninja &>/dev/null || get_ninja
	[ -e /usr/lib/libcmocka.so ] || get_cmocka
}

can_do_scanbuild()
{
	which "${SCANBUILD:-scan-build}" &>/dev/null
}

do_scanbuild()
{
	local buildtype="$1"

	printf "### Running scan-build with buildtype=\"%s\".\n" "$buildtype"

	ninja -v -C "$BDIR-$buildtype" scan-build
}

try_scanbuild()
{
	local buildtype="$1"

	! can_do_scanbuild || do_scanbuild "$buildtype"
}

can_do_valgrind()
{
	local v

	v="$(which valgrind 2>/dev/null)" \
		&& [ -x "$v" ]
}

do_valgrind()
{
	local buildtype="$1"

	printf "### Running valgrind with buildtype=\"%s\".\n" "$buildtype"

	$MESONTEST "${MESONTEST_ARGS[@]}" -C "$BDIR-$buildtype" --setup valgrind
}

try_valgrind()
{
	local buildtype="$1"

	! can_do_valgrind || do_valgrind "$buildtype"
}

do_regular()
{
	local buildtype="$1"

	printf "### Running tests with buildtype=\"%s\".\n" "$buildtype"

	$MESONTEST "${MESONTEST_ARGS[@]}" -C "$BDIR-$buildtype"
}

do_build()
{
	local buildtype="$1"

	printf "### Building with buildtype=\"%s\".\n" "$buildtype"

	ninja -v -C "$BDIR-$buildtype"
}

do_configure()
{
	local buildtype="$1"

	printf "### Configuring build directory with buildtype=\"%s\".\n" "$buildtype"

	$MESON --buildtype="$buildtype" "$BDIR-$buildtype"
	$MESONCONF "$BDIR-$buildtype"
}

doit()
{
	local buildtype="$1"

	do_configure "$buildtype"
	do_build "$buildtype"
	do_regular "$buildtype"
	try_valgrind "$buildtype"
	try_scanbuild "$buildtype"
}

main()
{
	if [ "${1:-}" = --verbose ] ; then
		shift
		VERBOSE=""
		set -x
	fi

	prepare_env
	doit debug
	doit release
}

main "$@"
