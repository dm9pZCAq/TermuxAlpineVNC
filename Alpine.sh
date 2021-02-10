#!/data/data/com.termux/files/usr/bin/sh --
set -ue

#- config -#

PROMPT='[termux@alpine \\w] \$ '
LAUNCH=alpine  # name of command to start alpine
BIN="${PREFIX}/bin"  # path to bin directory
ALPINE_FS="${PREFIX}/opt/AlpineFS"  # place where will stored Alpine file system
SETUP_VNC_URL='https://raw.githubusercontent.com/dm9pZCAq/TermuxAlpineVNC'\
'/master/SetupVNC.sh'

#- END: config -#


OUT_FD=3
ERR_FD=4
RELEASES=https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases


die() {
	1>&${ERR_FD} echo "${*}"
	exit 1
}

# shellcheck disable=2059
info() { 1>&${OUT_FD} printf "${@}"; }

ok() { info '%s\n' OK; }

nl() { info '\n'; }

check_arch() {
	arch="${1:?}"
	for supported in $(curl -sL "${RELEASES}/" \
		| sed -n 's@.*href="\([^"]\+\)/".*@\1@p')
	do
		[ "${arch}" = "${supported}" ] && return
	done

	die 'unfortunately you have unsupported architecture'
}

check_dependencies() {
	[ "${ALPINE_NO_RECACHE}" ] || {
		info %s '* updating apt cache...'
		apt update
		nl
	}
	info '%s\n'  '* checking dependencies'

	for dependence in sed tar curl proot coreutils; do
		info %s "   * ${dependence}..."
		if command -v "${dependence}"; then
			ok
		else
			info %s 'insatlling...'
			apt -y install "${dependence}" \
				|| die 'unable to install'
			ok
		fi
	done
}

get_alpine() {
	arch="${1:?}"
	pattern="alpine-minirootfs-[0-9\.]\+-${arch}\.tar\.[^<\.]\+"

	info '%s\n' '* downloading latest stable Alpine...'

	file="$(curl -sL -- "${RELEASES}/${arch}/" \
		| sed -n "/${pattern}/{s/.*\(${pattern}\).*/\1/p;q}")"

	if [ -f "./${file}" ]; then
		info '%s\n' "file '${file}' alredy exists"
	else
		curl --retry 3 -LOf "${RELEASES}/${arch}/${file}" 2>&${ERR_FD}
	fi

	curl --retry 3 -Lfs "${RELEASES}/${arch}/${file}.sha512" \
		| sha512sum -c - >/dev/null \
		|| die 'bad checksum'

	echo "${file}"
}

proot_exec() (
	script="${1:?}"
	shift

	unset LD_PRELOAD
	proot -0 \
		-w / \
		-b /dev \
		-b /proc \
		--link2symlink \
		-r "${ALPINE_FS}" \
		/usr/bin/env - sh -uec "${script}" sh "${@}"
)

# shellcheck disable=2016
setup_alpine() {
	file="${1:?}"

	info %s "* extracting..."
	if proot --link2symlink -0 \
		tar xpf "${file}" -C "${ALPINE_FS}" 1>&${OUT_FD}
	then
		ok
		rm -f -- "${file}"
	else
		die 'failed to extract rootfs'
	fi

	info %s 'setting up "resolv.conf"...'
	proot_exec 'printf "%s\n" "${@}" > /etc/resolv.conf' \
		'nameserver 9.9.9.9' \
		'nameserver 1.1.1.1' \
	|| die error
	ok

	info %s 'adding community repo...'
	domain="$(sed -n '/^http/{s@^\(https\?://[^/]\+\).*@\1@p;q}' \
			"${ALPINE_FS}/etc/apk/repositories")"
	proot_exec \
		'printf "%s\n" "${@}" >> /etc/apk/repositories' '' \
			"${domain}/alpine/edge/community" \
			"# ${domain}/alpine/edge/testing" \
	|| die error
	ok

	info %s 'changing PS1...'
	proot_exec \
		'sed -i /etc/profile -e "${1:?}"' \
			"/^\s*export\s\+PS1/s/=.*/='${PROMPT}'/" \
	|| die error
	ok

	info %s 'changing "/etc/motd"...'
	msg="* To setup VNC run 'SetupVNC --help'"
	msg="${msg} and choose graphical environment"
	proot_exec 'printf "%s\n" "${1:?}" "" >> /etc/motd' "${msg}" \
	|| die error
	ok

	info %s 'creating "/etc/profile.d/motd.sh"...'
	args='"${@}"'
	install='install -Dm 755 /proc/self/fd/0 /etc/profile.d/motd.sh'
	proot_exec \
		"printf '%s\n' ${args} | ${install}" \
			'#!/bin/sh --' \
			'cat /etc/motd' \
	|| die error
	ok

	nl
}

# shellcheck disable=2016
get_vnc_setup() {
	info %s '* downloading VNC setup...'

	curl --retry 3 -Lfs -- "${SETUP_VNC_URL}" \
		| proot_exec \
			'install -Dm 755 /proc/self/fd/0 "${1:?}"' \
				/usr/local/bin/SetupVNC
	nl
}

create_launcher() {
	launch="${BIN}/${LAUNCH}"

	cat <<- EOM | install -Dm 750 /proc/self/fd/0 "${launch}"
	#!/data/data/com.termux/files/usr/bin/sh --
	set -ue

	unset LD_PRELOAD

	ALPINE_FS="${ALPINE_FS}"

	args="\${*}"
	set -- proot -0 \\
	    -b /mnt \\
	    -b /dev \\
	    -b /proc \\
	    -b /sdcard \\
	    -b /storage \\
	    --link2symlink \\
	    -r "\${ALPINE_FS}"

	# set -- "\${@}" -b /data/data/com.termux
	# uncomment above line to mount termux file system

	init='exec "\$(getent passwd "\${USER:-\$(whoami)}" '\\
	'| sed "s/.*://")" "\${@}"'

	set -- "\${@}" \\
	    -w "\$(sed -n 's/^root:.*:\(.*\):.*/\1/p' \\
	            "\${ALPINE_FS}/etc/passwd")" \\
	    /usr/bin/env -i \\
	    TERM="\${TERM}" \\
	    sh -ec "\${init}" sh

	[ "\${args}" ] && exec "\${@}" -c "\${args}"
	exec "\${@}" --login
	EOM
}

alpine_info() {
	if [ -f "${BIN}/${LAUNCH}" ] && [ -d "${ALPINE_FS}" ]; then
		info '%s\n' \
			"command for start Alpine: '${LAUNCH}'" \
			"AlpineFS stored in [${ALPINE_FS}]"
	else
		die 'Alpine not installed'
	fi
}

# shellcheck disable=2016
main() {
	mkdir -p -- "${ALPINE_FS}"
	cd -- "${ALPINE_FS}"

	check_dependencies

	arch="$(uname -m)"

	check_arch "${arch}"
	nl
	file="$(get_alpine "${arch}")"
	nl
	setup_alpine "${file}"
	nl
	get_vnc_setup
	create_launcher

	alpine_info
	nl
	vnc_info='to lounch VNC setup you must execute `SetupVNC`'
	vnc_info="${vnc_info} !!! after starting Alpine !!!"
	info '%s\n' "${vnc_info}"
}

eval "exec ${OUT_FD}>&1"
eval "exec ${ERR_FD}>&2"

: "${PREFIX:=}"
: "${LAUNCH:=alpine}"
: "${BIN:=${PREFIX}/bin}"
: "${ALPINE_FS:=${PREFIX}/opt/AlpineFS}"

case "${1:-}" in
uninstall|rm|del*)
	rm -rf -- "${ALPINE_FS}" "${BIN:?}/${LAUNCH}"
	info '%s\n' 'done'
	;;

info)
	alpine_info
	;;

install|'')
	main >/dev/null 2>/dev/null
	;;

*)
	printf '%s\n' \
		"'sh ${0} rm' to unintsall alpine from defasult path" \
		"'sh ${0} info' to see this path " \
		"you can also edit it in file: [$(readlink -e "${0}")]" \
		'run without arguments to install'
	;;
esac

eval "exec ${OUT_FD}>&-"
eval "exec ${ERR_FD}>&-"
