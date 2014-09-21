#!/bin/sh -e

name="$(basename $0)"
version="1.0"

_echo()
{
	local msg="$1"
	echo "${name}: ${msg}"
}

_usage()
{
	cat << EOF
$name: create chroot environment for ssh/sftp

Usage: $name [OPTIONS] ...

        -h             Show help
        -v             Show script version
        -u             Specify username (this cant be empty)
                       (default: none)
        -c             Specify chroot directory
                       (default: /srv/chroot)

Example:
     $name -u test1 -c /var/chroot
   or
     $name -u test1

EOF
}

setup_rsyslog()
{
	local user="$1"
	local dir="$2"

	if [ -r /etc/rsyslog.conf ]; then
		_echo "Setting up rsyslog logging ..."
		[ -d /etc/rsyslog.d ] || mkdir -p /etc/rsyslog.d >/dev/null 2>&1
		cat << EOF > /etc/rsyslog.d/${user}.conf
\$ModLoad imuxsock
\$AddUnixListenSocket ${dir}/dev/log
:programname, isequal, "internal-sftp" -/var/log/${user}-sftp.log
:programname, isequal, "internal-sftp" ~
EOF
		if [ -x /etc/init.d/rsyslog ]; then
			/etc/init.d/rsyslog restart >/dev/null 2>&1
		fi
	else
		_echo "rsyslog doesnt seem to be installed, skip this part" >&2
	fi
}

resolv_ldd()
{
	local xdir="$1"
	local binary="$2"
	local dir=""
	local bin=""

	ldd="$(ldd ${binary} | awk '{ print $3 }' | egrep -v ^'\(' | sed '/^$/d')"
	for lib in ${ldd}; do
		dir="$(dirname ${lib})"
		bin="$(basename ${lib})"
		[ -d "${xdir}/${dir}" ] || mkdir -p "${xdir}/${dir}" >/dev/null 2>&1
		if [ -e "${xdir}/${dir}" ]; then
			cp "${lib}" "${xdir}/${dir}" >/dev/null 2>&1
		fi
	done
}

setup_chroot()
{
	dir_list="bin dev etc home lib usr tmp"
	if [ "x${libarch}" != "x" ]; then 
		dir_list="${dir_list} ${libarch}"
	fi

	for dir in ${dir_list}; do
		_echo "Creating directory: ${chroot_location}/${dir}"
		[ -d ${chroot_location}/${dir} ] || mkdir -p ${chroot_location}/${dir} >/dev/null 2>&1
	done
	chmod 1777 ${chroot_location}/tmp >/dev/null 2>&1

	etc_list="ld.so.cache hostname hosts issue motd nsswitch.conf os-release protocols resolv.conf localtime"
	for etc in ${etc_list}; do
		if ! $(cmd /etc/${etc} ${chroot_location}/etc/${etc} >/dev/null 2>&1); then
			_echo "Copying etc file: /etc/${etc}"
			cp -a /etc/${etc} ${chroot_location}/etc >/dev/null 2>&1
		fi
	done

	if [ ! -c "${chroot_location}/dev/null" ]; then
		_echo "Creating device node: /dev/null"
		mknod -m 0666 ${chroot_location}/dev/null c 1 3
	elif [ ! -c "${chroot_location}/dev/random" ]; then
		_echo "Creating device node: /dev/random"
		mknod -m 0666 ${chroot_location}/dev/random c 1 8
	elif [ ! -c "${chroot_location}/dev/urandom" ]; then
		_echo "Creating device node: /dev/urandom"
		mknod -m 0666 ${chroot_location}/dev/urandom c 1 9
	elif [ ! -c "${chroot_location}/dev/zero" ]; then
		_echo "Creating device node: /dev/zero"
		mknod -m 0666 ${chroot_location}/dev/zero c 1 5
	elif [ ! -c "${chroot_location}/dev/tty" ]; then
		_echo "Creating device node: /dev/tty"
		mknod -m 0666 ${chroot_location}/dev/tty c 5 0
	fi

	bin_list="/bin/busybox /bin/bash"
	for bin in ${bin_list}; do
		dir="$(dirname ${bin})"
		xbin="$(basename ${bin})"
		[ -d ${chroot_location}/${dir} ] || mkdir -p ${chroot_location}/${dir}
		_echo "Copying binary file: ${bin} ..."
		if [ ! -x "${chroot_location}/${dir}/${xbin}" ]; then
			cp -a ${bin} ${chroot_location}/${dir}
			resolv_ldd "${chroot_location}" "${bin}"
		fi
	done

	lib_list="/lib/${arch}-linux-gnu/libnss_compat.so.2 \
	/lib/${arch}-linux-gnu/libnss_dns.so.2 \
	/lib/${arch}-linux-gnu/libnss_files.so.2 \
	/lib/${arch}-linux-gnu/libnss_nis.so.2 \
	/lib/${arch}-linux-gnu/libc.so.6 \
	/lib/${arch}-linux-gnu/libdl.so.2 \
	/lib/${arch}-linux-gnu/libnsl.so.1 \
	/lib/${arch}-linux-gnu/libpthread.so.0 \
	/lib/${arch}-linux-gnu/librt.so.1"
	for lib in ${lib_list}; do
		dir="$(dirname ${lib})"
		bin="$(basename ${lib})"
        	[ -d ${chroot_location}/${dir} ] || mkdir -p ${chroot_location}/${dir}
		_echo "Copying library file: ${lib}"
		if [ ! -e "${chroot_location}/${dir}/${bin}" ]; then
			cp ${lib} ${chroot_location}/${dir} >/dev/null 2>&1
		fi
	done

	if [ "$arch" == "x86_64" ]; then
		_echo "Copying /lib64/ld-linux-x86-64.so.2 for ${arch}"
		cp /lib64/ld-linux-x86-64.so.2 ${chroot_location}/${libarch} >/dev/null 2>&1
	else
		_echo "Copying /lib/ld-linux.so.2 for ${arch}"
		cp /lib/ld-linux.so.2 ${chroot_location}/lib >/dev/null 2>&1
	fi

	if [ -x "${chroot_location}/bin/busybox" ]; then
		_echo "Installing /bin/busybox into ${chroot_location}"
		chroot ${chroot_location} /bin/busybox --install -s /bin >/dev/null 2>&1
		if [ $? -ne 0 ]; then
			_echo "failed to install/setup busybox" >&2
		fi
	fi

	sed -rn "/(^root\:|^${username}\:)/p" /etc/passwd > ${chroot_location}/etc/passwd
	awk -F':' '$3 <= 200 {print}' /etc/group > ${chroot_location}/etc/group
}

if [ $# -eq 0 ]; then
	_usage
	_echo "missing option(s) or argument(s)." >&2
	exit 1
fi

while getopts "hvc:u:" opt; do
	case "${opt}" in
		h)
		  _usage
		  exit 0
		;;
		v)
		  echo "${name} ${version}"
		  exit 0
		;;
		u)
		  username="${OPTARG}"
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

if [ -z "${location}" ]; then
	location="/srv/chroot"
fi

if [ "$(uname -m)" = "x86_64" ]; then
	arch="x86_64"
	libarch="lib64"
else
	arch="i386"
	libarch=""
fi

chroot_location="${location}/${username}"
[ -d ${chroot_location} ] || mkdir -p ${chroot_location} >/dev/null 2>&1

# setup chroot environment
setup_chroot
# setup rsyslog to log sftp
setup_rsyslog "${username}" "${chroot_location}"

exit $?
