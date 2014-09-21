#!/bin/sh -e

name="$(basename $0)"
version="1.0"
cwd="$(dirname $0)"

_echo()
{
        local msg="$1"
        echo "${name}: ${msg}"
}

_usage()
{
        cat << EOF
$name: create user for chroot ssh/sftp

Usage: $name [OPTIONS] ...

        -h             Show help
        -v             Show script version
        -n             Dont run mkchroot.sh script
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

	_echo "Creating user ..."
	useradd -M -d /home/${username} -g ${group} -c "${realname}" ${username} >/dev/null 2>&1; err=$?
	if [ ${err} -ne 0 ]; then
		_echo "useradd failed to create user." >&2
		exit ${err}
	fi
}

create_env()
{
	local username="$1"
	local group="$2"
	local chroot="$3"

	_echo "Creating environment and copying skel ..."
	mkdir -p ${chroot}/home/${username} >/dev/null 2>&1
	cp /etc/skel/.??* ${chroot}/home/${username} >/dev/null 2>&1
	mkdir -p ${chroot}/home/${username}/{webs,logs} >/dev/null 2>&1
	chown -R ${username}.${group} ${chroot}/home/${username} >/dev/null 2>&1
}

if [ $# -eq 0 ]; then
	_usage
	_echo "missing option(s) or argument(s)." >&2
	exit 1
fi

no_chroot=0

while getopts "hvn:u:g:r:c:" opt; do
	case "${opt}" in
		h)
		  _usage
		  exit 0
		;;
		v)
		  echo "${name} ${version}"
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

if [ -z "${username}" ]; then
	_echo "username cant be empty."
	exit 1
fi

if [ -z "${group}" ]; then
	group="users"
fi

if [ -z "${realname}" ]; then
	realname="SSH User"
fi

if [ -z "${location}" ]; then
	location="/srv/chroot"
fi

chroot_location="${location}/${username}"
[ -d ${chroot_location} ] || mkdir -p ${chroot_location} >/dev/null 2>&1

# create user, using useradd
create_user "${username}" "${group}" "${realname}"
# create environment
create_env "${username}" "${group}" "${chroot_location}"

if [ ${no_chroot} -eq 1 ]; then
	if [ -x "${cwd}/mkchroot.sh" ]; then
		${cwd}/mkchroot.sh -u "${username}" -c "${location}"
	else
		_echo "mkchroot.sh not found or its not executable." >&2
		exit 1
	fi
fi

exit $?
