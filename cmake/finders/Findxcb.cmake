#[=======================================================================[.rst
FindXCB
-------

FindModule for XCB and associated libraries

.. versionchanged:: 3.0
  Updated FindModule to CMake standards

Components
^^^^^^^^^^

.. versionadded:: 1.0

This module contains provides several components:

``xcb-xcb``
``xcb-composite``
``xcb-damage``
``xcb-dri2,``
``xcb-ewmh``
``xcb-glx``
``xcb-icccm``
``xcb-image``
``xcb-keysyms
``xcb-randr``
``xcb-render``
``xcb-renderutil``
``xcb-shape``
``xcb-shm``
``xcb-sync``
``xcb-util
``xcb-xfixes``
``xcb-xtest``
``xcb-xv``
``xcb-xinput``
``xcb-xinerama``

Import targets exist for each component.

Imported Targets
^^^^^^^^^^^^^^^^

.. versionadded:: 2.0

This module defines the :prop_tgt:`IMPORTED` targets:

``xcb::xcb``
  xcb component

``xcb::xcb-composite``
  xcb-composite component

``xcb::xcb-damage``
  xcb-damage component

``xcb::xcb-dri2``
  xcb-dri2 component

``xcb::xcb-ewmh``
  xcb-ewmh component

``xcb::xcb-glx``
  xcb-glx component

``xcb::xcb-icccm``
  xcb-icccm component

``xcb::xcb-image``
  xcb-image component

``xcb::xcb-keysyms``
  xcb-keysyms component

``xcb::xcb-randr``
  xcb-randr component

``xcb::xcb-render``
  xcb-render component

``xcb::xcb-renderutil``
  xcb-renderutil component

``xcb::xcb-shape``
  xcb-shape component

``xcb::xcb-shm``
  xcb-shm component

``xcb::xcb-sync``
  xcb-sync component

``xcb::xcb-util``
  xcb-util component

``xcb::xcb-xfixes``
  xcb-xfixes component

``xcb::xcb-xtest``
  xcb-xtest component

``xcb::xcb-xv``
  xcb-xv component

``xcb::xcb-xinput``
  xcb-xinput component

``xcb::xcb-xinerema``
  xcb-xinerema component

Result Variables
^^^^^^^^^^^^^^^^

This module sets the following variables:

``XCB_<COMPONENT>_FOUND``
  True, if required component was found.
``XCB_<COMPONENT>_VERSION``
  Detected version of found XCB component library.
``XCB_<COMPONENT>_INCLUDE_DIRS``
  Include directories needed for XCB component.
``XCB_<COMPONENT>_LIBRARIES``
  Libraries needed to link to XCB component.

Cache variables
^^^^^^^^^^^^^^^

The following cache variables may also be set:

``XCB_<COMPONENT>_LIBRARY``
  Path to the library component of XCB.
``XCB_<COMPONENT>_INCLUDE_DIR``
  Directory containing ``<COMPONENT>.h``.

#]=======================================================================]

# cmake-format: off
# cmake-lint: disable=C0103
# cmake-lint: disable=C0301
# cmake-lint: disable=R0915
# cmake-format: on

include(FindPackageHandleStandardArgs)

find_package(PkgConfig QUIET)

list(
  APPEND
  _xcb_DEFAULT_COMPONENTS
  xcb
  xcb-composite
  xcb-damage
  xcb-dri2,
  xcb-ewmh
  xcb-glx
  xcb-icccm
  xcb-image
  xcb-keysyms
  xcb-randr
  xcb-render
  xcb-renderutil
  xcb-shape
  xcb-shm
  xcb-sync
  xcb-util
  xcb-xfixes
  xcb-xtest
  xcb-xv
  xcb-xinput
  xcb-xinerama)
list(
  APPEND
  _xcb_HEADERS
  xcb.h
  composite.h
  damage.h
  dri2h.h
  xcb_ewmh.h
  glx.h
  xcb_icccm.h
  xcb_image.h
  xcb_keysyms.h
  randr.h
  render.h
  xcb_renderutil.h
  shape.h
  shm.h
  sync.h
  xcb_util.h
  xfixes.h
  xtest.h
  xv.h
  xinput.h
  xinerama.h)

if(NOT xcb_FIND_COMPONENTS)
  set(xcb_FIND_COMPONENTS ${_DEFAULT_COMPONENTS})
endif()

# xcb_find_component: Find and create targets for specified xcb component
macro(xcb_find_component component)
  list(GET _xcb_DEFAULT_COMPONENTS ${component} COMPONENT_NAME)
  list(GET _xcb_HEADERS ${component} COMPONENT_HEADER)

  if(NOT TARGET xcb::${COMPONENT_NAME})
    if(PKG_CONFIG_FOUND)
      pkg_search_module(PC_xcb_${COMPONENT_NAME} QUIET ${COMPONENT_NAME})
    endif()

    find_path(
      xcb_${COMPONENT_NAME}_INCLUDE_DIR
      NAMES "xcb/${COMPONENT_HEADER}"
      HINTS ${PC_xcb_${COMPONENT_NAME}_INCLUDE_DIRS}
      PATHS /usr/include /usr/local/include
      DOC "XCB component ${COMPONENT_NAME} include directory")

    find_library(
      xcb_${COMPONENT_NAME}_LIBRARY
      NAMES "${COMPONENT_NAME}"
      HINTS ${PC_xcb_${COMPONENT_NAME}_LIBRARY_DIRS}
      PATHS /usr/lib /usr/local/lib
      DOC "XCB component ${COMPONENT_NAME} location")

    if(PC_xcb_${COMPONENT_NAME}_VERSION VERSION_GREATER 0)
      set(xcb_${COMPONENT_NAME}_VERSION ${PC_xcb_${COMPONENT_NAME}_VERSION})
    elseif(EXISTS "${xcb_${COMPONENT_NAME}_INCLUDE_DIR}/xcb/${COMPONENT_HEADER}")
      file(STRINGS "${xcb_${COMPONENT_NAME}_INCLUDE_DIR}/xcb/${COMPONENT_HEADER}" _VERSION_STRING
           REGEX "^.*VERSION_(MAJOR|MINOR|QUERY)[ \t]+[0-9]+[ \t]*$")
      string(REGEX REPLACE ".*VERSION_MAJOR[ \t]+([0-9+).*" VERSION_MAJOR "${_VERSION_STRING}")
      string(REGEX REPLACE ".*VERSION_MINOR[ \t]+([0-9+).*" VERSION_MINOR "${_VERSION_STRING}")
      string(REGEX REPLACE ".*VERSION_QUERY[ \t]+([0-9+).*" VERSION_QUERY "${_VERSION_STRING}")

      set(xcb_${COMPONENT_NAME}_VERSION "${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_QUERY}")
    else()
      if(NOT xcb_FIND_QUIETLY)
        message(AUTHOR_WARNING "Failed to find ${COMPONENT_NAME} version.")
      endif()
      set(xcb_${COMPONENT_NAME}_VERSION 0.0.0)
    endif()

    if(xcb_${COMPONENT_NAME}_LIBRARY AND xcb_${COMPONENT_NAME}_INCLUDE_DIR)
      set(xcb_${COMPONENT_NAME}_FOUND TRUE)
      set(xcb_${COMPONENT_NAME}_LIBRARIES ${xcb_${COMPONENT_NAME}_LIBRARY})
      set(xcb_${COMPONENT_NAME}_INCLUDE_DIRS ${xcb_${COMPONENT_NAME}_INCLUDE_DIR})
      set(xcb_${COMPONENT_NAME}_DEFINITIONS ${PC_xcb_${COMPONENT_NAME}_CFLAGS_OTHER})
      mark_as_advanced(xcb_${COMPONENT_NAME}_LIBRARY xcb_${COMPONENT_NAME}_INCLUDE_DIR)

      if(IS_ABSOLUTE "${xcb_${COMPONENT_NAME}_LIBRARY}")
        add_library(xcb::${COMPONENT_NAME} UNKNOWN IMPORTED)
        set_property(TARGET xcb::${COMPONENT_NAME} PROPERTY IMPORTED_LOCATION "${xcb_${COMPONENT_NAME}_LIBRARY}")
      else()
        add_library(xcb::${COMPONENT_NAME} INTERFACE IMPORTED)
        set_property(TARGET xcb::${COMPONENT_NAME} PROPERTY IMPORTED_LIBNAME "${xcb_${COMPONENT_NAME}_LIBRARY}")
      endif()

      set_target_properties(
        xcb::${COMPONENT_NAME}
        PROPERTIES INTERFACE_COMPILE_OPTIONS "${PC_xcb_${COMPONENT_NAME}_CFLAGS_OTHER}"
                   INTERFACE_INCLUDE_DIRECTORIES "${xcb_${COMPONENT_NAME}_INCLUDE_DIR}"
                   VERSION ${xcb_${COMPONENT_NAME}_VERSION})
      list(APPEND xcb_COMPONENTS xcb::${COMPONENT_NAME})
      list(APPEND xcb_LIBRARIES ${xcb_${COMPONENT_NAME}_LIBRARY})
      list(APPEND xcb_INCLUDE_DIRS ${xcb_${COMPONENT_NAME}_INCLUDE_DIR})
      if(NOT xcb_VERSION)
        set(xcb_VERSION ${xcb_${COMPONENT_NAME}_VERSION})
      endif()
    endif()
  else()
    list(APPEND xcb_COMPONENTS xcb::${COMPONENT_NAME})
    set(xcb_${COMPONENT_NAME}_FOUND TRUE)
    get_target_property(component_location xcb::${COMPONENT_NAME} IMPORTED_LOCATION)
    if(NOT component_location)
      get_target_property(component_location xcb::${COMPONENT_NAME} IMPORTED_LIBNAME)
    endif()
    get_target_property(component_include_dir xcb::${COMPONENT_NAME} INTERFACE_INCLUDE_DIRECTORIES)
    list(APPEND xcb_LIBRARIES ${component_location})
    list(APPEND xcb_INCLUDE_DIRS ${component_include_dir})
    unset(component_location)
    unset(component_include_dir)
  endif()
endmacro()

foreach(component IN LISTS xcb_FIND_COMPONENTS)
  list(FIND _xcb_DEFAULT_COMPONENTS "${component}" valid_component)

  if(valid_component GREATER_EQUAL 0)
    xcb_find_component(${valid_component})
  else()
    message(FATAL_ERROR "Unknown XCB component required: ${component}.")
  endif()
endforeach()

list(REMOVE_DUPLICATES xcb_INCLUDE_DIRS)

find_package_handle_standard_args(
  xcb
  REQUIRED_VARS xcb_LIBRARIES xcb_INCLUDE_DIRS
  VERSION_VAR xcb_VERSION
  HANDLE_COMPONENTS REASON_FAILURE_MESSAGE "Ensure xcb is installed on the system.")

unset(_xcb_DEFAULT_COMPONENTS)
unset(_xcb_HEADERS)

include(FeatureSummary)
set_package_properties(
  xcb PROPERTIES
  URL "https://xcb.freedesktop.org"
  DESCRIPTION
    "A replacement for Xlib featuring a small footprint, latency hiding, direct access to the protocol, improved threading support, and extensibility."
)
