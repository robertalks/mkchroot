#!/bin/sh -e

export PATH="/bin:/usr/bin"

user="$PAM_USER"
name="$(basename $0)"
pid="$$"
prog="$name[$pid]"

bind_mount()
{
	local src="$1"
	local dest="$2"

	[ -d "$src" ] || exit 0
	[ -d "$dest" ] || exit 0

	if ! /usr/bin/awk '{print $2}' /proc/mounts | /bin/grep -wq "^$dest\$" >/dev/null 2>&1; then
		if /bin/mount --bind $src $dest >/dev/null 2>&1; then
			/usr/bin/logger -p local0.notice -t "$prog" "mounted $dest"
		else
			/usr/bin/logger -p local0.warning -t "$prog" "failed to mount $dest"
		fi
	fi
}

if [ -z "$user" ]; then
	exit 0
fi

if [ "$user" = "root" ]; then
	exit 0
fi

chroot="/srv/chroot/$user"

# bind mount /dev
bind_mount "/dev" "$chroot/dev"

# bind mount /dev/pts
bind_mount "/dev/pts" "$chroot/dev/pts"

# bind mount /proc
bind_mount "/proc" "$chroot/proc"

# bind mount /sys
bind_mount "/sys" "$chroot/sys"

# bind mount /run
bind_mount "/run" "$chroot/run"

# bind mount /var/mail
bind_mount "/var/mail" "$chroot/var/mail"

exit 0
