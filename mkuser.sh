#!/bin/sh -e

name="$(basename $0)"
version="1.0"
cwd="$(dirname $0)"

info()
{
        local msg="$1"
        echo "$name: $msg"
}

err()
{
	local msg="$1"
	echo "$name: error: $msg" >&2
}

usage()
{
        cat << EOF
$name: create user for chroot ssh/sftp

Usage: $name [OPTIONS] ...

        -h             Show help
        -v             Show script version
        -n             Disable calling mkchroot.sh script
                       (default: on)
        -u             Specify username (this cant be empty)
                       (default: none)
        -g             Specify username group
                       (default: users)
        -r             Specify username real name
                       (default: SSH User)
        -c             Specify chroot directory
                       (default: /srv/chroot)

Example:
     $name -u test1 -g sshusers -r "Test user" -c /var/chroot
   or
     $name -u test1 -n

EOF
}

create_user()
{
	local username="$1"
	local group="$2"
	local realname="$3"

	info "Creating user $username ..."
	useradd -M -d /home/$username -g $group -c "$realname" -s /bin/bash $username >/dev/null 2>&1
	if [ $? -ne 0 ]; then
		err "useradd failed to create user"
		exit 1 
	fi
}

create_env()
{
	local username="$1"
	local group="$2"

	info "Creating environment and copying skel ..."
	mkdir -p $chroot_location/home/$username >/dev/null 2>&1
	cp /etc/skel/.??* $chroot_location/home/$username >/dev/null 2>&1
	mkdir -p $chroot_location/home/$username/webs >/dev/null 2>&1
	mkdir -p $chroot_location/home/$username/logs >/dev/null 2>&1
	chown -R $username.$group $chroot_location/home/$username >/dev/null 2>&1
}

if [ $# -eq 0 ]; then
	usage
	err "missing option"
	exit 1
fi

no_chroot=0

while getopts "hvnu:g:r:c:" opt; do
	case "$opt" in
		h)
			usage
			exit 0
		;;
		v)
			echo "$name $version"
			exit 0
		;;
		n)
			no_chroot=1
		;;
		u)
			username="${OPTARG}"
		;;
		g)
			group="${OPTARG}"
		;;
		r)
			realname="${OPTARG}"
		;;
		c)
			location="${OPTARG}"
		;;
		\?)
			exit 1
		;;
	esac
done

if [ "$(id -u)" -ne 0 ]; then
	err "requires root privileges"
	exit 1
fi

if [ -z "$username" ]; then
	err "missing username"
	exit 1
fi

if [ -z "$group" ]; then
	group="users"
fi

if [ -z "$realname" ]; then
	realname="SSH User"
fi

if [ -z "$location" ]; then
	location="/srv/chroot"
fi

chroot_location="$location/$username"
if [ ! -d "$chroot_location" ]; then
	mkdir -p $chroot_location >/dev/null 2>&1
	if [ $? -ne 0 ]; then
		err "failed to create $chroot_location"
		exit 1
	fi
fi

# create user, using useradd
create_user "$username" "$group" "$realname"

# create environment
create_env "$username" "$group"

# check and run mkchroot.sh if not disable at command line
if [ -x "$cwd/mkchroot.sh" ]; then
	if [ $no_chroot -eq 0 ]; then
		info "Running $cwd/mkchroot.sh -u "$username" -c "$location" ..."
		$cwd/mkchroot.sh -u "$username" -c "$location"
	else
		info "Skip running mkchroot.sh, disable at command line"
	fi
else
	err "mkchroot.sh not found or its not executable"
fi

exit 0
