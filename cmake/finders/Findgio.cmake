#[=======================================================================[.rst
Findgio
----------

FindModule for gio and associated libraries

.. versionchanged:: 3.0
  Updated FindModule to CMake standards

Imported Targets
^^^^^^^^^^^^^^^^

.. versionadded:: 2.0

This module defines the :prop_tgt:`IMPORTED` target ``gio::gio``.

Result Variables
^^^^^^^^^^^^^^^^

This module sets the following variables:

``gio_FOUND``
  True, if all required components and the core library were found.
``gio_VERSION``
  Detected version of found gio libraries.

Cache variables
^^^^^^^^^^^^^^^

The following cache variables may also be set:

``gio_LIBRARY``
  Path to the library component of gio.
``gio_INCLUDE_DIR``
  Directory containing ``gio.h``

#]=======================================================================]

# cmake-format: off
# cmake-lint: disable=C0103
# cmake-lint: disable=C0301
# cmake-format: on

include(FindPackageHandleStandardArgs)

find_package(PkgConfig QUIET)
if(PKG_CONFIG_FOUND)
  pkg_search_module(PC_gio QUIET gio-2.0 gio-unix-2.0 gio)
endif()

find_path(
  gio_INCLUDE_DIR
  NAMES glib.h
  HINTS ${PC_gio_INCLUDE_DIRS}
  PATHS /usr/include /usr/local/include
  PATH_SUFFIXES glib-2.0
  DOC "glib include directory")

find_library(
  gio_LIBRARY
  NAMES libgio-2.0 gio-2.0 gio-unix-2.0
  HINTS ${PC_gio_LIBRARY_DIRS}
  PATHS /usr/lib /usr/local/lib
  DOC "gio-2.0 location")

find_path(
  glib_INCLUDE_DIR
  NAMES glibconfig.h
  HINTS ${PC_gio_INCLUDE_DIRS}
  PATH_SUFFIXES glib-2.0/include)

if(PC_gio_VERSION VERSION_GREATER 0)
  set(gio_VERSION ${PC_gio_VERSION})
else()
  if(NOT gio_FIND_QUIETLY)
    message(AUTHOR_WARNING "Failed to find gio version.")
  endif()
  set(gio_VERSION 0.0.0)
endif()

find_package_handle_standard_args(
  gio
  REQUIRED_VARS gio_LIBRARY gio_INCLUDE_DIR glib_INCLUDE_DIR
  VERSION_VAR gio_VERSION REASON_FAILURE_MESSAGE "Ensure that glib is installed on the system.")
mark_as_advanced(gio_INCLUDE_DIR gio_LIBRARY glib_INCLUDE_DIR)

if(gio_FOUND)
  if(NOT TARGET gio::gio)
    if(IS_ABSOLUTE "${gio_LIBRARY}")
      add_library(gio::gio UNKNOWN IMPORTED)
      set_property(TARGET gio::gio PROPERTY IMPORTED_LOCATION "${gio_LIBRARY}")
    else()
      add_library(gio::gio INTERFACE IMPORTED)
      set_property(TARGET gio::gio PROPERTY IMPORTED_LIBNAME "${gio_LIBRARY}")
    endif()

    set_target_properties(
      gio::gio
      PROPERTIES INTERFACE_COMPILE_OPTIONS "${PC_gio_CFLAGS_OTHER}"
                 INTERFACE_INCLUDE_DIRECTORIES "${gio_INCLUDE_DIR};${glib_INCLUDE_DIR}"
                 VERSION ${gio_VERSION})
  endif()
endif()

include(FeatureSummary)
set_package_properties(
  gio PROPERTIES
  URL "https://docs.gtk.org/gio"
  DESCRIPTION
    "A library providing useful classes for general purpose I/O, networking, IPC, settings, and other high level application functionality."
)
