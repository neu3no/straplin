#!/bin/bash

# TODO:
# 	* for everything which is build more then once, check if sources exist and 
# 	  only redownload if not

. helpers
for file in $(find conf/??-*.cfg); do
  source $file
done

ARCH=$(uname -m)
VER=0.1

showhelp() {
	echo -e "\
this is straplin-v$VER, a cross compiler bootstrap script of neu3no \n\
usage: \n\
$1 [job] \n\
jobs: \n\
	\033[1mbootstrap\033[0m\tbootstrap the complete environment for $CROSSARCH \n\
		\tchange the architecture in conf/general.cfg \n\
	\033[1mbinutils\033[0m\tjust build and install the binutils for $CROSSARCH \n\
	\033[1mgcc1\033[0m\t\tjust build the first gcc (of 3), binutils need to \n\
		\tbe present \n\
	\033[1mgcc2\033[0m\t\tjust build the second gcc, binutils, the first gcc, \n\
		\tkernelheaders and the preliminary glibc need to be \n\
		\tpresent \n\
	\033[1mgcc3\033[0m\t\tjust build the final gcc, glibc and the second gcc \n\
		\t(and all of his dependencies) \n\
	\033[1mglibc1\033[0m\t\tjust build preliminary glibc, binutils, first gcc \n\
		\tand kernelheaders need to be present \n\
	\033[1mglibc\033[0m\t\tjust build glibc, gcc2 and all of its deps need to be \n\t\t\tpresent \n\
	\033[1mmktree\033[0m\t\tbuild the directory tree needed for building \n\
	\033[1mdownload\033[0m\tdownload all packages \n\
	\033[1munpack\033[0m\t\t(download and) unpack all packages \n\
	"
}
#  >> bootstrap
build_binutils() {
	download $BINUTILS_SRC
	(
		out "cleaning up binutils"
		[ -d $OBJDIR/binutils-build ] && rm -Rf $OBJDIR/binutils-build
		mkdir $OBJDIR/binutils-build
		cd $OBJDIR/binutils-build
		
		out "configuring binutils"
		$SRCDIR/binutils-$BINUTILS_VERSION/configure \
					--prefix=$TOOLSDIR \
					--target=$CROSSTARGET \
					--with-sysroot=$SYSROOT \
					--disable-werror \
					2>&1 | tee -a "$LOGFILE"
		
		out "making binutils"
		make  2>&1 | tee -a "$LOGFILE"
		
		out "installing binutils to $CROSSPREFIX"
		make install 2>&1 | tee -a $LOGFILE
	)
}

build_gcc1() {
	download $GCC_SRC
	(
		cd $SRCDIR/gcc-$GCC_VERSION >> /dev/null
    out "download prerequisites"
    ./contrib/download_prerequisites

		if [ "${#GCC_PATCHES[@]}" -gt "0" ] ; then
			out "patching gcc $(pwd) "
			index=0
			while [ "${#GCC_PATCHES[index]}"  -gt "0" ]; do
				if [[ -f "${GCC_PATCHES[index]}" ]]; then
					out "patching with ${GCC_PATCHES[index]}"
					patch -p 1 < "${GCC_PATCHES[index]}" || exit
				else
					out "error: ${GCC_PATCHES[index]} does not exist!"
				fi
				index=$(( $index + 1 ))
			done
			out "applied $index patches"
		else
			out "there are no patches for gcc"
		fi

		out "cleaning up gcc1"
		[ -d $OBJDIR/gcc1-build ] && rm -Rf $OBJDIR/gcc1-build
		
		mkdir -p $OBJDIR/gcc1-build || exit
		cd $OBJDIR/gcc1-build|| exit
		
		out "configuring first gcc"
		$SRCDIR/gcc-$GCC_VERSION/configure $GCC_CONFIG \
			--target=$CROSSTARGET \
			--prefix=$TOOLSDIR \
			--without-headers --with-newlib \
			--disable-shared --disable-threads --disable-libssp \
			--disable-libgomp --disable-libmudflap \
			--enable-languages=c  --disable-werror \
			2>&1 | tee -a "$LOGFILE" || exit
		
		PATH=$TOOLSDIR/bin:$PATH
		
		out "making first gcc"
		make 2>&1 | tee -a "$LOGFILE" || exit
		
		out "installing first gcc"
		make install 2>&1 | tee -a "$LOGFILE" || exit
	)
}

install_kernelheaders() {
	download $KERNEL_SRC
	(
		out "copy files from linux kernel"
		cp -nr $SRCDIR/linux-$KERNEL_VERSION $OBJDIR/linux
		cd $OBJDIR/linux
		
		if [ "${#KERNEL_PATCHES[@]}" -gt "0" ] ; then
			out "patching kernel $(pwd) "
			index=0
			while [ "${#KERNEL_PATCHES[index]}"  -gt "0" ]; do
				if [[ -f "${KERNEL_PATCHES[index]}" ]]; then
					out "patching with ${KERNEL_PATCHES[index]}"
					patch -p 1 < "${KERNEL_PATCHES[index]}" || exit
				else
					out "error: ${KERNEL_PATCHES[index]} does not exist!"
				fi
				index=$(( $index + 1 ))
			done
			out "applied $index patches"
		else
			out "there are no patches for kernel"
		fi
		
		out "installing kernel headers to sysroot"
		PATH=$TOOLSDIR/bin:$PATH
		
		CARCH=$( echo $CROSSARCH | sed -e s/i.86/i386/ -e s/sun4u/sparc64/ \
                                  -e s/arm.*/arm/ -e s/sa110/arm/ \
                                  -e s/s390x/s390/ -e s/parisc64/parisc/ \
                                  -e s/ppc.*/powerpc/ -e s/mips.*/mips/ )
		
		make headers_install \
			ARCH=$CARCH CROSS_COMPILE=$CROSSTARGET- \
			INSTALL_HDR_PATH=$SYSROOT/usr 2>&1 | tee -a $LOGFILE || exit
	)
}

install_preliminaryglibc() {
	download $GLIBC_SRC
	(
		cd $SRCDIR/glibc-$GLIBC_VERSION >> /dev/null

		if [ "${#GLIBC_PATCHES[@]}" -gt "0" ] ; then
			out "patching glibc $(pwd) "
			index=0
			while [ "${#GLIBC_PATCHES[index]}"  -gt "0" ]; do
				if [[ -f "${GLIBC_PATCHES[index]}" ]]; then
					out "patching with ${GLIBC_PATCHES[index]}"
					patch -p 1 < "${GLIBC_PATCHES[index]}" || exit
				else
					out "error: ${GLIBC_PATCHES[index]} does not exist!"
				fi
				index=$(( $index + 1 ))
			done
			out "applied $index patches"
		else
			out "there are no patches for gcc"
		fi
		
		out "cleaning up preliminary glibc"
		[ -d $OBJDIR/glibc-headers ] && rm -Rf $OBJDIR/glibc-headers
		mkdir -p $OBJDIR/glibc-headers
		cd $OBJDIR/glibc-headers
		
		out "configure preliminary glibc"
		BUILD_CC=gcc \
		    CC=$TOOLSDIR/bin/$CROSSTARGET-gcc \
		    CXX=$TOOLSDIR/bin/$CROSSTARGET-g++ \
		    AR=$TOOLSDIR/bin/$CROSSTARGET-ar \
		    RANLIB=$TOOLSDIR/bin/$CROSSTARGET-ranlib \
		    $SRCDIR/glibc-$GLIBC_VERSION/configure \
		    --prefix=/usr \
		    --with-headers=$SYSROOT/usr/include \
		    --build=$ARCH-pc-linux-gnu \
		    --host=$CROSSTARGET \
		    --disable-profile --without-gd --without-cvs --enable-add-ons \
		    --disable-werror  2>&1 | tee $LOGFILE || exit
		
		
		out "installing preliminary glibc"
		make install-headers 	install_root=$SYSROOT \
							install-bootstrap-headers=yes \
							2>&1 | tee $LOGFILE
		mkdir -p $SYSROOT/usr/lib
		make csu/subdir_lib 2>&1 | tee $LOGFILE
		
		cp csu/crt1.o csu/crti.o csu/crtn.o $SYSROOT/usr/lib
		 
		cp 	$SRCDIR/glibc-$GLIBC_VERSION/include/gnu/stubs.h \
			$SYSROOT/usr/include/gnu/
			
		cp $SRCDIR/glibc-$GLIBC_VERSION/stdio-common/stdio_lim.h.in \
			$SYSROOT/usr/include/bits/stdio_lim.h 
		
		out "creating libc dummy"
		$TOOLSDIR/bin/$CROSSTARGET-gcc -nostdlib -nostartfiles \
			-shared -x c /dev/null -o $SYSROOT/usr/lib/libc.so \
			2>&1 | tee $LOGFILE
	)
}

build_gcc2(){
	(
		out "cleaning up gcc2"
		[ -d $OBJDIR/gcc2-build ] && rm -Rf $OBJDIR/gcc2-build
		
		mkdir -p $OBJDIR/gcc2-build || exit
		cd $OBJDIR/gcc2-build|| exit
		
		out "configure gcc2"
		$SRCDIR/gcc-$GCC_VERSION/configure $GCC_CONFIG \
			--target=$CROSSTARGET \
			--prefix=$TOOLSDIR \
			--with-sysroot=$SYSROOT \
			--disable-libssp \
			--disable-libgomp --disable-libmudflap \
			--enable-languages=c  --disable-werror \
			2>&1 | tee -a "$LOGFILE" || exit
		
		
		PATH=$TOOLSDIR/bin:$PATH
		
		out "making second gcc"
		make 2>&1 | tee -a "$LOGFILE" || exit
		
		out "installing second gcc"
		make install 2>&1 | tee -a "$LOGFILE" || exit
		
	)
}

build_glibc() {
	if [ ! -d $SRCDIR/glibc-$GLIBC_VERSION ] ; then
		download $GLIBC_SRC
		(
			cd $SRCDIR/glibc-$GLIBC_VERSION >> /dev/null

			if [ "${#GLIBC_PATCHES[@]}" -gt "0" ] ; then
				out "patching glibc $(pwd) "
				index=0
				while [ "${#GLIBC_PATCHES[index]}"  -gt "0" ]; do
					if [[ -f "${GLIBC_PATCHES[index]}" ]]; then
						out "patching with ${GLIBC_PATCHES[index]}"
						patch -p 1 < "${GLIBC_PATCHES[index]}" || exit
					else
						out "error: ${GLIBC_PATCHES[index]} does not exist!"
					fi
					index=$(( $index + 1 ))
				done
				out "applied $index patches"
			else
				out "there are no patches for gcc"
			fi
		)
	fi
	(
		out "cleaning up glibc"
		[ -d $OBJDIR/glibc ] && rm -Rf $OBJDIR/glibc
		mkdir -p $OBJDIR/glibc
		cd $OBJDIR/glibc
		
		out "configure glibc"
		BUILD_CC=gcc \
			CC=$TOOLSDIR/bin/$CROSSTARGET-gcc \
			CXX=$TOOLSDIR/bin/$CROSSTARGET-g++ \
			AR=$TOOLSDIR/bin/$CROSSTARGET-ar \
			RANLIB=$TOOLSDIR/bin/$CROSSTARGET-ranlib \
			$SRCDIR/glibc-$GLIBC_VERSION/configure \
			    --prefix=/usr \
			    --with-headers=$SYSROOT/usr/include \
			    --build=$ARCH-pc-linux-gnu \
			    --host=$CROSSTARGET \
			    --disable-profile --without-gd --without-cvs --enable-add-ons \
			    --disable-werror  2>&1 | tee $LOGFILE || exit
		
		PATH=$TOOLSDIR/bin:$PATH
		
		out "making glibc"
		make 2>&1 | tee -a "$LOGFILE" || exit
		
		out "installing glibc"
		make install install_root=$SYSROOT 2>&1 | tee -a "$LOGFILE" || exit
	)
}

build_gcc3(){
	(
		out "cleaning up gcc3"
		[ -d $OBJDIR/gcc3-build ] && rm -Rf $OBJDIR/gcc3-build
		
		mkdir -p $OBJDIR/gcc3-build || exit
		cd $OBJDIR/gcc3-build|| exit
		
		out "configure final gcc"
		$SRCDIR/gcc-$GCC_VERSION/configure $GCC_CONFIG\
			--target=$CROSSTARGET \
			--prefix=$TOOLSDIR \
			--with-sysroot=$SYSROOT \
			--enable-__cxa_atexit --disable-libssp \
			--disable-libgomp --disable-libmudflap \
			--enable-languages=c,c++  --disable-werror \
			2>&1 | tee -a "$LOGFILE" || exit
		
		
		PATH=$TOOLSDIR/bin:$PATH
		
		out "making final gcc"
		make 2>&1 | tee -a "$LOGFILE" || exit
		
		out "installing final gcc"
		make install 2>&1 | tee -a "$LOGFILE" || exit
		
		out "copy additional libraries to sysroot"
		cp -d $TOOLSDIR/$CROSSTARGET/lib/libgcc_s.so* $SYSROOT/lib/
		cp -d $TOOLSDIR/$CROSSTARGET/lib/libstdc++.so* $SYSROOT/usr/lib/
	)
}

# << bootstrap
[ -f "$LOGFILE" ] && mv "$LOGFILE" "$LOGFILE.1"

case "$1" in 
	"binutils")
		build_binutils
	;;
	"gcc1")
		build_gcc1
	;;
	"gcc2")
		build_gcc2
	;;
	"gcc3")
		build_gcc3
	;;
	"glibc1")
		install_kernelheaders
		install_preliminaryglibc
	;;
	"glibc")
		build_glibc
	;;
	"mktree")
		mktree
	;;
	"download")
		for s in $( set -o posix; set | grep -o "[[:alpha:]]*_SRC"); do
			eval sr=\$$s
			download "$sr" nounpack
		done
	;;
	"unpack")
		for s in $( set -o posix; set | grep -o "[[:alpha:]]*_SRC"); do
			eval sr=\$$s
			download "$sr"
		done
	;;
	"bootstrap")
		if [[ "$@" != *"nomktree"* ]]; then
			rm -Rfv $CROSSPREFIX
			mktree 
		fi
		[[ "$@" != *nobinutils* ]] && build_binutils && \
		[[ "$@" != *nogcc1* ]] && build_gcc1 && \
		[[ "$@" != *nokernel* ]] && install_kernelheaders  && \
		[[ "$@" != *noglibc1* ]] && install_preliminaryglibc && \
		[[ "$@" != *nogcc2* ]] && build_gcc2 && \
		build_glibc && \
		build_gcc3
	;;
	*)
		showhelp $0
	;;
esac
