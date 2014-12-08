#!/bin/sh -e

export PATH="/bin:/usr/bin"

user="$PAM_USER"
name="$(basename $0)"
pid="$$"
prog="$name[$pid]"

unmount_bind()
{
	local mnt="$1"
	local who="$(/usr/bin/who -u 2>/dev/null | awk '{print $1}' | grep -w ^$user)"

	[ -d "$mnt" ] || exit 0

	if [ "x$who" = "x" ]; then
		if /bin/umount -f $mnt >/dev/null 2>&1; then
			/usr/bin/logger -p local0.notice -t "$prog" "unmounted $mnt"
		else
			/usr/bin/logger -p local0.warning -t "$prog" "failed to unmount $mnt"
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

# unmount $chroot/dev/pts
unmount_bind "$chroot/dev/pts"

# unmount $chroot/dev
unmount_bind "$chroot/dev"

# unmount $chroot/proc
unmount_bind "$chroot/proc"

# unmount $chroot/sys
unmount_bind "$chroot/sys"

# unmount $chroot/run
unmount_bind "$chroot/run"

# unmount $chroot/var/mail
unmount_bind "$chroot/var/mail"

exit 0
