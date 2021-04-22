cmake_minimum_required(VERSION 3.19)

# Build options
if(NOT CMAKE_OSX_ARCHITECTURES)
	set(CMAKE_OSX_ARCHITECTURES "x86_64" CACHE STRING "OBS build architecture for macOS - x86_64 required at least" FORCE)
endif()

if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
	set(CMAKE_OSX_DEPLOYMENT_TARGET "10.13" CACHE STRING "OBS deployment target for macOS - 10.13+ required" FORCE)
endif()

if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
	set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}/rundir" CACHE STRING "Directory to install OBS after building" FORCE)
endif()

# Enable modern cmake policies
if(POLICY CMP0011)
	cmake_policy(SET CMP0011 NEW)
endif()

if(POLICY CMP0025)
	cmake_policy(SET CMP0025 NEW)
endif()

if(POLICY CMP0009)
	cmake_policy(SET CMP0009 NEW)
endif()

macro(setup_obs_project)
	# Set code-signing options
	if(NOT DEFINED OBS_BUNDLE_CODESIGN_IDENTITY)
		set(OBS_BUNDLE_CODESIGN_IDENTITY "-" CACHE STRING "OBS code signing identity for macOS" FORCE)
	endif()
	set(OBS_CODESIGN_ENTITLEMENTS "${CMAKE_SOURCE_DIR}/cmake/bundle/macOS/entitlements.plist")

	if(NOT DEFINED OBS_CODESIGN_LINKER)
		set(OBS_CODESIGN_LINKER ON CACHE BOOL "Enable linker code-signing on macOS (v11+ required" FORCE)
	endif()

	# Xcode configuration
	if(XCODE)
		# Tell Xcode to pretend the linker signed binaries so that
		# editing with install_name_tool preserves ad-hoc signatures.
		# See CMake Issue 21854.
		# This option is supported by codesign on macOS 11 or higher.
		set(CMAKE_XCODE_GENERATE_SCHEME ON)
		if(OBS_CODESIGN_LINKER)
			set(CMAKE_XCODE_ATTRIBUTE_OTHER_CODE_SIGN_FLAGS "-o linker-signed")
		endif()
	endif()

	# Set default options for bundling on macOS
	set(CMAKE_MACOSX_RPATH ON)
	set(CMAKE_SKIP_BUILD_RPATH OFF)
	set(CMAKE_BUILD_WITH_INSTALL_RPATH OFF)
	set(CMAKE_INSTALL_RPATH "@executable_path/../Frameworks/")
	set(CMAKE_INSTALL_RPATH_USE_LINK_PATH OFF)

	# Set bundle parameters for cmake's automatic plist generation
	set(MACOSX_BUNDLE_EXECUTABLE_NAME "OBS")
	set(MACOSX_BUNDLE_BUNDLE_NAME "${OBS_PRODUCT_NAME}")
	set(MACOSX_BUNDLE_BUNDLE_VERSION "${OBS_BUILD_NUMBER}")
	set(MACOSX_BUNDLE_COPYRIGHT "${OBS_LEGAL_COPYRIGHT}")
	set(MACOSX_BUNDLE_GUI_IDENTIFIER "com.obsproject.obs-studio")
	set(MACOSX_BUNDLE_ICON_FILE "AppIcon")
	set(MACOSX_BUNDLE_SHORT_VERSION_STRING "${OBS_VERSION_CANONICAL}")

	# Set paths for distribution bundling
	set(OBS_BUNDLE_NAME "OBS")
	set(OBS_INCLUDE_DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/obs")
	set(OBS_LIBRARY_DESTINATION "${CMAKE_INSTALL_LIBDIR}")
	set(OBS_CMAKE_DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/obs")

	# set(OBS_OUTPUT_LOCATION "${CMAKE_BINARY_DIR}/distribution")
	# set(OBS_BUNDLE_LOCATION "${OBS_OUTPUT_LOCATION}/$<CONFIG>/${OBS_BUNDLE_NAME}.app")
	# set(OBS_BUNDLE_BINARY_LOCATION "${OBS_BUNDLE_LOCATION}/Contents/MacOS")
	# set(OBS_BUNDLE_FRAMEWORK_LOCATION "${OBS_BUNDLE_LOCATION}/Contents/Frameworks")
	# set(OBS_BUNDLE_RESOURCE_LOCATION "${OBS_BUNDLE_LOCATION}/Contents/Resources")
	# set(OBS_BUNDLE_PLUGIN_LOCATION "${OBS_BUNDLE_LOCATION}/Contents/PlugIns")

	if(BUILD_FOR_DISTRIBUTION)
		set_option(CMAKE_BUILD_TYPE "Release")
	endif()

	if(BUILD_FOR_DISTRIBUTION OR DEFINED ENV{CI})
		set_option(CMAKE_PREFIX_PATH "/tmp/obsdeps")
		set_option(ENABLE_SPARKLE_UPDATER ON)
		set_option(ENABLE_RTMPS ON)
	endif()

	set(CPACK_PACKAGE_NAME "OBS")
	set(CPACK_PACKAGE_VENDOR "${OBS_WEBSITE}")
	set(CPACK_GENERATOR "DragNDrop")
	set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "${OBS_COMMENTS}")
	# set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_SOURCE_DIR}/UI/data/license/gplv2.txt")
	set(CPACK_PACKAGE_VERSION "${OBS_VERSION_CANONICAL}-${OBS_BUILD_NUMBER}")
	set(CPACK_PACKAGE_FILE_NAME "${CPACK_PACKAGE_NAME}-${CPACK_PACKAGE_VERSION}-macOS")

	set(CPACK_COMPONENTS_ALL obs_app obs_frameworks obs_plugins obs_scripting_plugins obs_resources)
	set(CPACK_COMPONENT_OBS_APP_DISPLAY_NAME "OBS Studio")
	set(CPACK_COMPONENT_OBS_FRAMEWORKS_DISPLAY_NAME "OBS Frameworks")
	set(CPACK_COMPONENT_OBS_PLUGINS_DISPLAY_NAME "OBS Plugins")
	set(CPACK_COMPONENT_OBS_SCRIPTING_PLUGINS_DISPLAY_NAME "OBS Scripting Plugins")
	set(CPACK_COMPONENT_OBS_RESOURCES_DISPLAY_NAME "OBS Resources")

	set(CPACK_DMG_BACKGROUND_IMAGE "${CMAKE_SOURCE_DIR}/cmake/bundle/macOS/background.tiff")
	set(CPACK_PACKAGE_ICON "${CMAKE_SOURCE_DIR}/cmake/bundle/macOS/AppIcon.icns")
	get_filename_component(CPACK_DMG_BACKGROUND_FILENAME ${CPACK_DMG_BACKGROUND_IMAGE} NAME)
	set(CPACK_DMG_FORMAT "UDZO")
	set(CPACK_DMG_DS_STORE_SETUP_SCRIPT "${CMAKE_BINARY_DIR}/package.applescript")

	set(_DMG_WINDOW_X "100")
	set(_DMG_WINDOW_Y "100")
	set(_DMG_WINDOW_WIDTH "540")
	set(_DMG_WINDOW_HEIGHT "380")
	set(_DMG_ICON_SIZE "96")
	set(_DMG_TEXT_SIZE "16")
	set(_DMG_OBS_X "124")
	set(_DMG_OBS_Y "180")
	set(_DMG_APP_LINK_X "416")
	set(_DMG_APP_LINK_Y "180")

	configure_file(
		"${CMAKE_SOURCE_DIR}/cmake/bundle/macOS/package.applescript.in"
		"${CMAKE_BINARY_DIR}/package.applescript"
		@ONLY)

	include(CPack)

	install(CODE "
		set(_BUNDLENAME \"$<TARGET_FILE_BASE_NAME:obs>.app\")
		if(EXISTS \"\${CMAKE_INSTALL_PREFIX}/\${_BUNDLENAME}\")
			file(REMOVE_RECURSE \"\${CMAKE_INSTALL_PREFIX}/\${_BUNDLENAME}\")
		endif()")
endmacro()