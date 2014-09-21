#!/bin/sh -e

name="$(basename $0)"
version="1.0"

_echo()
{
	local msg="$1"
	echo -e "${name}: ${msg}"
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
		[ -d /etc/rsyslog.d ] || mkdir -p /etc/rsyslog.d
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
		[ -d "${xdir}/${dir}" ] || mkdir -p "${xdir}/${dir}" 2>/dev/null
		if [ -e "${xdir}/${dir}" ]; then
			cp "${lib}" "${xdir}/${dir}" 2>/dev/null
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
		mkdir -p ${chroot_location}/${dir} 2>/dev/null
	done
	chmod 1777 ${chroot_location}/tmp 2>/dev/null

	etc_list="ld.so.cache hostname hosts issue motd nsswitch.conf os-release protocols resolv.conf localtime"
	for etc in ${etc_list}; do
		if ! $(cmd /etc/${etc} ${chroot_location}/etc/${etc} >/dev/null 2>&1); then
			cp -a /etc/${etc} ${chroot_location}/etc 2>/dev/null
		fi
	done

	if [ ! -c "${chroot_location}/dev/null" ]; then
		mknod -m 0666 ${chroot_location}/dev/null c 1 3
	elif [ ! -c "${chroot_location}/dev/random" ]; then
		mknod -m 0666 ${chroot_location}/dev/random c 1 8
	elif [ ! -c "${chroot_location}/dev/urandom" ]; then
		mknod -m 0666 ${chroot_location}/dev/urandom c 1 9
	elif [ ! -c "${chroot_location}/dev/zero" ]; then
		mknod -m 0666 ${chroot_location}/dev/zero c 1 5
	elif [ ! -c "${chroot_location}/dev/tty" ]; then
		mknod -m 0666 ${chroot_location}/dev/tty c 5 0
	fi

	bin_list="/bin/busybox /bin/bash"
	for bin in ${bin_list}; do
		dir="$(dirname ${bin})"
		xbin="$(basename ${bin})"
		[ -d ${chroot_location}/${dir} ] || mkdir -p ${chroot_location}/${dir}
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
		if [ ! -e "${chroot_location}/${dir}/${bin}" ]; then
			cp ${lib} ${chroot_location}/${dir} 2>/dev/null
		fi
	done

	if [ "$arch" == "x86_64" ]; then
		cp /lib64/ld-linux-x86-64.so.2 ${chroot_location}/${libarch} 2>/dev/null
	else
		cp /lib/ld-linux.so.2 ${chroot_location}/lib 2>/dev/null
	fi

	if [ -x "${chroot_location}/bin/busybox" ]; then
		chroot ${chroot_location} /bin/busybox --install -s /bin 2>/dev/null
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
	chroot_location="/srv/chroot/${username}"
else
	chroot_location="${location}/${username}"
fi

if [ "$(uname -m)" == "x86_64" ]; then
	arch="x86_64"
	libarch="lib64"
else
	arch="i386"
	libarch=""
fi

# [ -d ${chroot_location} ] || mkdir -p ${chroot_location} 2>/dev/null
# setup_chroot
# setup_rsyslog "${username}" "${chroot_location}"

exit $?
