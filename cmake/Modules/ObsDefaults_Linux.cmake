       cmake_minimum_required(VERSION 3.10)

if(POLICY CMP0011)
	cmake_policy(SET CMP0011 NEW)
endif()

if(POLICY CMP0072)
	cmake_policy(SET CMP0072 NEW)
endif()

if(POLICY CMP0095)
	cmake_policy(SET CMP0095 NEW)
endif()

if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT AND LINUX_PORTABLE)
	set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}/install" CACHE STRING "Directory to install OBS after building" FORCE)
endif()

macro(setup_obs_project)
	#[[
	POSIX directory setup (portable)
	CMAKE_BINARY_DIR
		└ rundir
			└ CONFIG
				└ bin
					└ ARCH
				└ data
					└ libobs
					└ obs-plugins
						└ PLUGIN
					└ obs-scripting
						└ ARCH
					└ obs-studio
				└ obs-plugins
					└ ARCH

	POSIX directory setup (non-portable)
	/usr/local/
		└ bin
		└ include
			└ obs
		└ libs
			└ cmake
			└ obs-plugins
			└ obs-scripting
		└ share
			└ obs
				└ libobs
				└ obs-plugins
				└ obs-studio
	]]

	if(CMAKE_SIZEOF_VOID_P EQUAL 8)
		set(_ARCH_SUFFIX 64)
	else()
		set(_ARCH_SUFFIX 32)
	endif()

	if(NOT OBS_MULTIARCH_SUFFIX AND DEFINED ENV{OBS_MULTIARCH_SUFFIX})
		set(OBS_MULTIARCH_SUFFIX "$ENV{OBS_MULTIARCH_SUFFIX}")
	endif()

	set(OBS_OUTPUT_DIR "${CMAKE_BINARY_DIR}/rundir")

	IF(NOT LINUX_PORTABLE)
		set(OBS_EXECUTABLE_DESTINATION "${CMAKE_INSTALL_BINDIR}")
		set(OBS_INCLUDE_DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/obs")
		set(OBS_LIBRARY_DESTINATION "${CMAKE_INSTALL_LIBDIR}")
		set(OBS_PLUGIN_DESTINATION "${OBS_LIBRARY_DESTINATION}/obs-plugins")
		set(OBS_SCRIPT_PLUGIN_DESTINATION "${OBS_LIBRARY_DESTINATION}/obs-scripting")
		set(OBS_DATA_DESTINATION "${CMAKE_INSTALL_DATAROOTDIR}/obs")
		set(OBS_CMAKE_DESTINATION "${OBS_LIBRARY_DESTINATION}/cmake")

		set(OBS_INSTALL_PREFIX "${CMAKE_INSTALL_PREFIX}/")
		set(OBS_DATA_PATH "${OBS_DATA_DESTINATION}")

		set(OBS_SCRIPT_PLUGIN_PATH "${CMAKE_INSTALL_PREFIX}/${OBS_SCRIPT_PLUGIN_DESTINATION}")
		set(CMAKE_INSTALL_RPATH "${CMAKE_INSTALL_PREFIX}/lib")
	else()
		set(OBS_EXECUTABLE_DESTINATION "bin/${_ARCH_SUFFIX}bit")
		set(OBS_INCLUDE_DESTINATION "include")
		set(OBS_LIBRARY_DESTINATION "bin/${_ARCH_SUFFIX}bit")
		set(OBS_PLUGIN_DESTINATION "obs-plugins/${_ARCH_SUFFIX}bit")
		set(OBS_SCRIPT_PLUGIN_DESTINATION "data/obs-scripting/${_ARCH_SUFFIX}bit")
		set(OBS_DATA_DESTINATION "data")
		set(OBS_CMAKE_DESTINATION "cmake")

		set(OBS_INSTALL_PREFIX "")
		set(OBS_DATA_PATH "../../${OBS_DATA_DESTINATION}")

		set(OBS_SCRIPT_PLUGIN_PATH "../../${OBS_SCRIPT_PLUGIN_DESTINATION}")
		set(CMAKE_INSTALL_RPATH "$ORIGIN/" "${CMAKE_INSTALL_PREFIX}/${OBS_LIBRARY_DESTINATION}")
	endif()


	if(BUILD_FOR_DISTRIBUTION)
		set_option(CMAKE_BUILD_TYPE "Release")
	endif()

	if(BUILD_FOR_DISTRIBUTION OR DEFINED ENV{CI})
		set_option(ENABLE_RTMPS ON)
	endif()

	set(CPACK_PACKAGE_NAME "obs-studio")
	set(CPACK_PACKAGE_VENDOR "${OBS_WEBSITE}")
	set(CPACK_DEBIAN_PACKAGE_MAINTAINER "${OBS_COMPANY_NAME}")
	set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "${OBS_COMMENTS}")
	set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_SOURCE_DIR}/UI/data/license/gplv2.txt")
	set(CPACK_PACKAGE_VERSION "${OBS_VERSION_CANONICAL}-${OBS_BUILD_NUMBER}")
	set(CPACK_STRIP_FILES "bin/obs" "bin/obs-ffmpeg-mux")
	set(CPACK_SOURCE_STRIP_FILES "")
	set(CPACK_PACKAGE_EXECUTABLES "obs")

	if(OS_LINUX)
		set(CPACK_GENERATOR "DEB")
		set(CPACK_DEBIAN_PACKAGE_DEPENDS
			"libavcodec57 (>= 7:3.4.2) | libavcodec-extra57 (>= 7:3.4.2), libavdevice57 (>= 7:3.4.2), \
			libavformat57 (>= 7:3.4.2), libavutil55 (>= 7:3.4.2), libswscale4 (>= 7:3.4.2), libc6 (>= 2.14), \
			libcurl3-gnutls (>= 7.16.2), libgcc1 (>= 1:3.0), libqt5core5a (>= 5.9.0~beta), \
			libqt5gui5 (>= 5.3.0), libqt5widgets5 (>= 5.7.0), libstdc++6 (>= 6), \
			libasound2 (>= 1.0.16), libfontconfig1 (>= 2.12), libfreetype6 (>= 2.2.1), \
			libjack-jackd2-0 (>= 1.9.5~dfsg-14) | libjack-0.116, libjansson4 (>= 2.0.1), \
			libpulse0 (>= 0.99.1), libspeexdsp1 (>= 1.2~beta3.2-1), \
			libudev1 (>= 183), libv4l-0 (>= 0.5.0), libdbus-1-3 (>= 1.9.14), zlib1g (>= 1:1.2.6), \
			libx11-6, libx264-152, libxcb-shm0, libxcb-xfixes0, libxcb-xinerama0, libx11-xcb1, \
			libxcb1, libxcomposite1 (>= 1:0.3-1), libxfixes3")

		if(NOT LINUX_PORTABLE)
			set(CPACK_SET_DESTDIR ON)
		endif()
	elseif(OS_FREEBSD)
		option(ENABLE_CPACK_GENERATOR "Enable FreeBSD cpack generator (experimental)" OFF)

		if(ENABLE_CPACK_GENERATOR)
			set(CPACK_GENERATOR "FreeBSD")
		endif()
		
		set(CPACK_FREEBSD_PACKAGE_DEPS
			"multimedia/v4l_compat" "devel/swig" "devel/cmake" "devel/ninja" "devel/pkgconf" "lang/python37"
			"x11/xorgproto" "x11/libICE" "x11/libSM" "x11/libX11" "x11/libxcb" "x11/libXcomposite" "x11/libXext"
			"x11/libXfixes" "x11/libXinerama" "x11/libXrandr" "devel/qt5-buildtools" "devel/qt5-qmake" "lang/python37"
			"graphics/qt5-imageformats" "multimedia/ffmpeg" "ftp/curl" "devel/dbus" "audio/fdk-aac" "x11-fonts/fontconfig"
			"print/freetype2 devel/jansson" "security/mbedtls" "audio/speexdsp" "devel/libsysinfo" "devel/libudev-devd"
			"multimedia/libv4l" "multimedia/vlc" "multimedia/libx264" "lang/luajit" "audio/jack" "audio/pulseaudio" "audio/sndio"
			"graphics/mesa-libs" "lang/lua52" "devel/qt5-core" "x11-toolkits/qt5-gui" "graphics/qt5-svg" "x11-toolkits/qt5-widgets"
			"x11/qt5-x11extras" "textproc/qt5-xml")
	endif()
	include(CPack)
endmacro()
