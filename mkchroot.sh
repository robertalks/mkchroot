#!/bin/bash -e

name="$(basename $0)"
version="1.0"

_info()
{
	local msg="$1"
	echo "${name}: ${msg}"
}

_err()
{
	local msg="$1"
	echo "${name}: error: ${msg}" >&2
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
		_info "Copying shared library ${lib} for binary ${binary} ..."
		cp -f "${lib}" "${xdir}/${dir}" >/dev/null 2>&1
	done
}

setup_chroot()
{
	dir_list="bin dev/pts etc home lib usr proc run sys tmp"
	if [ "x${libarch}" != "x" ]; then
		dir_list="${dir_list} ${libarch}"
	fi

	for dir in ${dir_list}; do
		_info "Creating directory: ${chroot_location}/${dir}"
		[ -d ${chroot_location}/${dir} ] || mkdir -p ${chroot_location}/${dir} >/dev/null 2>&1
	done
	chmod 1777 ${chroot_location}/tmp >/dev/null 2>&1

	etc_list="ld.so.cache hostname hosts issue motd nsswitch.conf os-release protocols resolv.conf localtime"
	for etc in ${etc_list}; do
		if ! $(cmd /etc/${etc} ${chroot_location}/etc/${etc} >/dev/null 2>&1); then
			_info "Copying etc file: /etc/${etc}"
			cp -a /etc/${etc} ${chroot_location}/etc >/dev/null 2>&1
		fi
	done

	if [ ! -c "${chroot_location}/dev/null" ]; then
		_info "Creating device node: /dev/null"
		mknod -m 0666 ${chroot_location}/dev/null c 1 3
	fi
	if [ ! -c "${chroot_location}/dev/random" ]; then
		_info "Creating device node: /dev/random"
		mknod -m 0666 ${chroot_location}/dev/random c 1 8
	fi
	if [ ! -c "${chroot_location}/dev/urandom" ]; then
		_info "Creating device node: /dev/urandom"
		mknod -m 0666 ${chroot_location}/dev/urandom c 1 9
	fi
	if [ ! -c "${chroot_location}/dev/zero" ]; then
		_info "Creating device node: /dev/zero"
		mknod -m 0666 ${chroot_location}/dev/zero c 1 5
	fi
	if [ ! -c "${chroot_location}/dev/tty" ]; then
		_info "Creating device node: /dev/tty"
		mknod -m 0666 ${chroot_location}/dev/tty c 5 0
	fi

	bin_list="/bin/busybox /bin/bash /usr/bin/scp /bin/ping /usr/bin/mail"
	for bin in ${bin_list}; do
		dir="$(dirname ${bin})"
		xbin="$(basename ${bin})"
		if [ -x "${bin}" ]; then
			[ -d ${chroot_location}/${dir} ] || mkdir -p ${chroot_location}/${dir}
			if [ -L "${bin}" ]; then
				octal_rights="$(stat -c %a $(readlink -f ${bin}))"
			else
				octal_rights="$(stat -c %a ${bin})"
			fi
			_info "Copying binary file: ${bin} ..."
			cp -f "${bin}" "${chroot_location}/${dir}" 2>/dev/null
			_info "Setting ${octal_rights} rights to ${chroot_location}${bin} ..."
			chmod ${octal_rights} "${chroot_location}${bin}" 2>/dev/null
			resolv_ldd "${chroot_location}" "${bin}"
		else
			_info "Ignoring ${bin}, not found"
		fi
	done

	if [ -x /usr/sbin/mini_sendmail ]; then
		[ -d ${chroot_location}/usr/sbin ] || mkdir -p ${chroot_location}/usr/sbin
		[ -d ${chroot_location}/usr/lib ] || mkdir -p ${chroot_location}/usr/lib
		_info "Copying binary file: /usr/sbin/mini_sendmail ..."
		cp -a /usr/sbin/mini_sendmail ${chroot_location}/usr/sbin 2>/dev/null
		( cd ${chroot_location}/usr/sbin
		  ln -sf mini_sendmail sendmail
		  cd ${chroot_location}/usr/lib
		  ln -sf ../sbin/sendmail .
		)
	fi

	lib_list="/lib/${arch}-linux-gnu/libnss_*.so.2 \
	/lib/${arch}-linux-gnu/libc.so.6 \
	/lib/${arch}-linux-gnu/libdl.so.2 \
	/lib/${arch}-linux-gnu/libnsl.so.1 \
	/lib/${arch}-linux-gnu/libpthread.so.0 \
	/lib/${arch}-linux-gnu/librt.so.1 \
	/lib/${arch}-linux-gnu/libresolv.so.2"
	for lib in ${lib_list}; do
		dir="$(dirname ${lib})"
		bin="$(basename ${lib})"
        	[ -d ${chroot_location}/${dir} ] || mkdir -p ${chroot_location}/${dir}
		_info "Copying library file: ${lib}"
		cp -f ${lib} ${chroot_location}/${dir} >/dev/null 2>&1
	done

	if [ "$arch" == "x86_64" ]; then
		_info "Copying /lib64/ld-linux-x86-64.so.2 for ${arch}"
		cp -f /lib64/ld-linux-x86-64.so.2 ${chroot_location}/${libarch} >/dev/null 2>&1
	else
		_info "Copying /lib/ld-linux.so.2 for ${arch}"
		cp -f /lib/ld-linux.so.2 ${chroot_location}/lib >/dev/null 2>&1
	fi

	if [ -x "${chroot_location}/bin/busybox" ]; then
		_info "Installing /bin/busybox into ${chroot_location}"
		chroot ${chroot_location} /bin/busybox --install -s /bin >/dev/null 2>&1
		if [ $? -ne 0 ]; then
			_err "failed to install/setup busybox"
		fi
	fi

	sed -rn "/(^root\:|^nobody\:|^${username}\:)/p" /etc/passwd > ${chroot_location}/etc/passwd
	awk -F':' '$3 <= 200 || $3 == 65534 {print}' /etc/group > ${chroot_location}/etc/group
}

if [ $# -eq 0 ]; then
	_usage
	_err "missing option(s) or argument(s)"
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

if [ "$(id -u)" -ne 0 ]; then
	_err "requires root privileges"
	exit 1
fi

if [ -z "${username}" ]; then
	_err "missing username"
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

exit $?
