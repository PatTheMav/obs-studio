#[=======================================================================[.rst
Findxkbcommon
-------------

FindModule for xkbcommon and associated libraries

.. versionchanged:: 3.0
  Updated FindModule to CMake standards

Imported Targets
^^^^^^^^^^^^^^^^

.. versionadded:: 2.0

This module defines the :prop_tgt:`IMPORTED` target ``xkbcommon::xkbcommon``.

Result Variables
^^^^^^^^^^^^^^^^

This module sets the following variables:

``xkbcommon_FOUND``
  True, if all required components and the core library were found.
``xkbcommon_VERSION``
  Detected version of found xkbcommon libraries.

Cache variables
^^^^^^^^^^^^^^^

The following cache variables may also be set:

``xkbcommon_LIBRARY``
  Path to the library component of xkbcommon.
``xkbcommon_INCLUDE_DIR``
  Directory containing ``xkbcommon.h``.

#]=======================================================================]

# cmake-format: off
# cmake-lint: disable=C0103
# cmake-lint: disable=C0301
# cmake-format: on

include(FindPackageHandleStandardArgs)

find_package(PkgConfig QUIET)
if(PKG_CONFIG_FOUND)
  pkg_search_module(PC_xkbcommon QUIET xkbcommon)
endif()

find_path(
  xkbcommon_INCLUDE_DIR
  NAMES xkbcommon.h
  HINTS ${PC_xkbcommon_INCLUDE_DIRS}
  PATHS /usr/include /usr/local/include
  PATH_SUFFIXES xkbcommon
  DOC "xkbcommon include directory")

find_library(
  xkbcommon_LIBRARY
  NAMES xkbcommon libxkbcommon
  HINTS ${PC_xkbcommon_LIBRARY_DIRS}
  PATHS /usr/lib /usr/local/lib
  DOC "xkbcommon location")

if(PC_xkbcommon_VERSION VERSION_GREATER 0)
  set(xkbcommon_VERSION ${PC_xkbcommon_VERSION})
else()
  if(NOT xkbcommon_FIND_QUIETLY)
    message(AUTHOR_WARNING "Failed to find xkbcommon version.")
  endif()
  set(xkbcommon_VERSION 0.0.0)
endif()

find_package_handle_standard_args(
  xkbcommon
  REQUIRED_VARS xkbcommon_LIBRARY xkbcommon_INCLUDE_DIR
  VERSION_VAR xkbcommon_VERSION REASON_FAILURE_MESSAGE "Ensure that xkbcommon is installed on the system.")
mark_as_advanced(xkbcommon_INCLUDE_DIR xkbcommon_LIBRARY)

if(xkbcommon_FOUND)
  if(NOT TARGET xkbcommon::xkbcommon)
    if(IS_ABSOLUTE "${xkbcommon_LIBRARY}")
      add_library(xkbcommon::xkbcommon UNKNOWN IMPORTED)
      set_property(TARGET xkbcommon::xkbcommon PROPERTY IMPORTED_LOCATION "${xkbcommon_LIBRARY}")
    else()
      add_library(xkbcommon::xkbcommon INTERFACE IMPORTED)
      set_property(TARGET xkbcommon::xkbcommon PROPERTY IMPORTED_LIBNAME "${xkbcommon_LIBRARY}")
    endif()

    set_target_properties(
      xkbcommon::xkbcommon
      PROPERTIES INTERFACE_COMPILE_OPTIONS "${PC_xkbcommon_CFLAGS_OTHER}"
                 INTERFACE_INCLUDE_DIRECTORIES "${xkbcommon_INCLUDE_DIR}"
                 VERSION ${xkbcommon_VERSION})
  endif()
endif()

include(FeatureSummary)
set_package_properties(
  xkbcommon PROPERTIES
  URL "https://www.xkbcommon.org"
  DESCRIPTION
    "A library for handling of keyboard descriptions, including loading them from disk, parsing them and handling their state."
)
