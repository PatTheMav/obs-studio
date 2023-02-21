# OBS CMake Linux cpack configuration module

# cmake-format: off
# cmake-lint: disable=C0103
# cmake-format: on

include_guard(GLOBAL)

include(cpackconfig_common)

# Add GPLv2 license file to CPack
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_SOURCE_DIR}/UI/data/license/gplv2.txt")
set(CPACK_PACKAGE_EXECUTABLES "obs")

if(ENABLE_RELEASE_BUILD)
  set(CPACK_PACKAGE_VERSION "${OBS_VERSION_CANONICAL}")
else()
  set(CPACK_PACKAGE_VERSION "${OBS_VERSION}")
endif()

if(OS_LINUX)
  set(CPACK_GENERATOR "DEB")
  set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS TRUE)
  set(CPACK_SET_DESTDIR TRUE)
  set(CPACK_DEBIAN_DEBUGINFO_PACKAGE TRUE)
elseif(OS_FREEBSD)
  option(ENABLE_CPACK_GENERATOR "Enable FreeBSD CPack generator (experimental)" OFF)

  if(ENABLE_CPACK_GENERATOR)
    set(CPACK_GENERATOR "FreeBSD")
  endif()

  set(CPACK_FREEBSD_PACKAGE_DEPS
      "audio/fdk-aac"
      "audio/jack"
      "audio/pulseaudio"
      "audio/sndio"
      "audio/speexdsp"
      "devel/cmake"
      "devel/dbus"
      "devel/jansson"
      "devel/libsysinfo"
      "devel/libudev-devd"
      "devel/ninja"
      "devel/pkgconf"
      "devel/qt5-buildtools"
      "devel/qt5-core"
      "devel/qt5-qmake"
      "devel/swig"
      "ftp/curl"
      "graphics/mesa-libs"
      "graphics/qt5-imageformats"
      "graphics/qt5-svg"
      "lang/lua52"
      "lang/luajit"
      "lang/python37"
      "multimedia/ffmpeg"
      "multimedia/libv4l"
      "multimedia/libx264"
      "multimedia/v4l_compat"
      "multimedia/vlc"
      "print/freetype2"
      "security/mbedtls"
      "textproc/qt5-xml"
      "x11/xorgproto"
      "x11/libICE"
      "x11/libSM"
      "x11/libX11"
      "x11/libxcb"
      "x11/libXcomposite"
      "x11/libXext"
      "x11/libXfixes"
      "x11/libXinerama"
      "x11/libXrandr"
      "x11-fonts/fontconfig"
      "x11-toolkits/qt5-gui"
      "x11-toolkits/qt5-widgets")
endif()

include(CPack)
