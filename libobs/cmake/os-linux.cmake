find_package(LibUUID REQUIRED)
find_package(X11 REQUIRED)
find_package(x11-xcb REQUIRED)
# cmake-format: off
find_package(xcb REQUIRED xcb OPTIONAL_COMPONENTS xcb-xinput)
# cmake-format: on
find_package(gio)

target_sources(
  libobs
  PRIVATE # cmake-format: sortable
          obs-nix-platform.c
          obs-nix-platform.h
          obs-nix-x11.c
          obs-nix.c
          util/pipe-posix.c
          util/platform-nix.c
          util/threading-posix.c
          util/threading-posix.h)

target_compile_definitions(libobs PRIVATE USE_XDG $<$<C_COMPILER_ID:GNU>:ENABLE_DARRAY_TYPE_TEST>)

set(CMAKE_M_LIBS "")
include(CheckCSourceCompiles)
set(LIBM_TEST_SOURCE "#include<math.h>\nfloat f; int main(){sqrt(f);return 0;}")
check_c_source_compiles("${LIBM_TEST_SOURCE}" HAVE_MATH_IN_STD_LIB)

target_link_libraries(
  libobs PRIVATE X11::x11-xcb xcb::xcb LibUUID::LibUUID ${CMAKE_DL_LIBS} $<$<NOT:$<BOOL:HAVE_MATH_IN_STD_LIB>>:m>
                 $<$<TARGET_EXISTS:xcb::xcb-input>:xcb::xcb-input>)

if(ENABLE_PULSEAUDIO)
  find_package(PulseAudio REQUIRED)

  target_sources(
    libobs
    PRIVATE # cmake-format: sortable
            audio-monitoring/pulse/pulseaudio-enum-devices.c
            audio-monitoring/pulse/pulseaudio-monitoring-available.c
            audio-monitoring/pulse/pulseaudio-output.c
            audio-monitoring/pulse/pulseaudio-wrapper.c
            audio-monitoring/pulse/pulseaudio-wrapper.h)

  target_link_libraries(libobs PRIVATE PulseAudio::PulseAudio)
  target_enable_feature(libobs "PulseAudio audio monitoring (Linux)")
else()
  target_sources(libobs PRIVATE audio-monitoring/null/null-audio-monitoring.c)
  target_disable_feature(libobs "PulseAudio audio monitoring (Linux)")
endif()

if(TARGET gio::gio)
  target_sources(libobs PRIVATE util/platform-nix-dbus.c util/platform-nix-portal.c)
  target_link_libraries(libobs PRIVATE gio::gio)
endif()

if(ENABLE_WAYLAND)
  find_package(Wayland REQUIRED Client)
  find_package(xkbcommon REQUIRED)

  target_sources(libobs PRIVATE obs-nix-wayland.c)
  target_link_libraries(libobs PRIVATE Wayland::Client xkbcommon::xkbcommon)
  target_enable_feature(libobs "Wayland compositor support (Linux)")
else()
  target_disable_feature(libobs "Wayland compositor support (Linux)")
endif()

set_target_properties(libobs PROPERTIES OUTPUT_NAME obs)
