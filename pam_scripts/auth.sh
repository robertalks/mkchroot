#!/bin/sh -e

export PATH="/bin:/usr/bin"

name="$(basename $0)"
pid="$$"
date="$(date '+%b %d %H:%M:%S')"
host="$(hostname -s)"
prog="$name[$pid]"
logfile="/var/log/user.log"

if [ -z "$PAM_USER" ]; then
	exit 0
fi

if [ "$PAM_USER" = "root" ]; then
	exit 0
fi

msg="logged in user=$PAM_USER ruser=$PAM_RUSER rhost=$PAM_RHOST tty=$PAM_TTY type=$PAM_TYPE service=$PAM_SERVICE"
if [ -e "$logfile" ]; then
	perm="$(/usr/bin/stat -c %a $logfile 2>/dev/null)"
	if [ "$perm" != "640" ]; then
		chmod 0640 $logfile 2>/dev/null
	fi
	echo "$date $host $prog: $msg" >> $logfile
else
	echo "$date $host $prog: $msg" > $logfile
	chmod 0640 $logfile 2>/dev/null
fi

/usr/bin/logger -p auth.info -t "$prog" "$msg"

exit 0
