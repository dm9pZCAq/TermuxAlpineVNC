#!/bin/sh --
set -ue

case "${1:-}" in
xfce*)
	set -- xfce4
	CMD=/usr/bin/startxfce4
	;;
openbox*|'')
	set -- openbox
	CMD=/usr/bin/openbox
	;;
i3*)
	set -- i3wm i3status
	CMD=/usr/bin/i3
	;;
*)
	printf '%s\n' \
		'chose from:' \
		'  * openbox [default]' \
		'  * xfce' \
		'  * i3' \
		'' \
		"${0##*/} {openbox|xfce|i3}"
	exit 0
	;;
esac

echo 'installing packages...'
apk add \
	supervisor \
	xvfb x11vnc \
	"${@}" xfce4-terminal \
	faenza-icon-theme ttf-liberation


cat << EOF >/etc/supervisord.conf
[supervisord]
nodaemon=true

[program:xvfb]
command=/usr/bin/Xvfb :1 -screen 0 720x1024x24
autorestart=true
priority=100
user=root

[program:x11vnc]
command=/usr/bin/x11vnc \
 -permitfiletransfer \
 -tightfilexfer \
 -display :1 \
 -noxrecord \
 -noxdamage \
 -noxfixes \
 -shared \
 -wait 5 \
 -noshm \
 -nopw \
 -xkb
autorestart=true
priority=200
user=root

[program:GraphicalEnvironment]
environment=DISPLAY=":1"
autorestart=true
command=${CMD}
priority=300
user=root
EOF

cat << EOF | install -Dm 755 /proc/self/fd/0 /usr/local/bin/startvnc
#!/bin/sh --
set -ue

case "\${1:-}" in
'')
	/usr/bin/supervisord -c /etc/supervisord.conf
	;;
bg)
	(
		/usr/bin/supervisord -c /etc/supervisord.conf \\
			>/dev/null 2>/dev/null &
	) &
	;;
kill)
	killall supervisord 2>/dev/null || echo 'not running'
	;;
*)
	printf '%s\n' \\
		"\${0##*/} {bg|kill}" \\
		'  * bg - run in background' \\
		'  * kill - stop VNC' \\
		'run without arguments to start and see log'
		;;
esac
EOF


printf '%s\n' \
	'' \
	'done' \
	'' \
	'"startvnc" to start VNC' \
	'also you cen edit config in "/etc/supervisord.conf"'
