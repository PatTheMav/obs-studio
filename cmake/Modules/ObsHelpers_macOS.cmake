# Helper function to set up runtime or library targets
function(setup_binary_target target)
	set_target_properties(${target} PROPERTIES
		XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.obsproject.${target}"
		XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "${OBS_BUNDLE_CODESIGN_IDENTITY}"
		XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${CMAKE_SOURCE_DIR}/cmake/bundle/macOS/entitlements.plist")

	set(MACOSX_PLUGIN_BUNDLE_NAME "${target}" PARENT_SCOPE)
	set(MACOSX_PLUGIN_GUI_IDENTIFIER "com.obsproject.${target}" PARENT_SCOPE)
	set(MACOSX_PLUGIN_BUNDLE_VERSION "${MACOSX_BUNDLE_BUNDLE_VERSION}" PARENT_SCOPE)
	set(MACOSX_PLUGIN_SHORT_VERSION_STRING "${MACOSX_BUNDLE_SHORT_VERSION_STRING}" PARENT_SCOPE)
	set(MACOSX_PLUGIN_EXECUTABLE_NAME "${target}" PARENT_SCOPE)

	if(${target} STREQUAL libobs)
		setup_framework_target(${target})
	elseif(${target} STREQUAL "obs-ffmpeg-mux")
		add_custom_command(TARGET ${target} POST_BUILD
		  COMMAND "${CMAKE_COMMAND}" -E copy
			  "$<TARGET_FILE:${target}>"
			  "$<TARGET_BUNDLE_CONTENT_DIR:obs>/MacOS/$<TARGET_FILE_NAME:${target}>"
		  VERBATIM)
	elseif(${target} STREQUAL mac-dal-plugin)
		add_custom_command(TARGET ${target} POST_BUILD
			COMMAND "${CMAKE_COMMAND}" -E copy_directory
				"$<TARGET_BUNDLE_DIR:OBS::mac-dal-plugin>"
				"$<TARGET_BUNDLE_CONTENT_DIR:obs>/Resources/$<TARGET_FILE_NAME:OBS::mac-dal-plugin>.plugin"
			VERBATIM)
	else()
		install(TARGETS ${target}
			RUNTIME DESTINATION "$<TARGET_FILE_BASE_NAME:obs>.app/Contents/Frameworks/"
				COMPONENT obs_frameworks
			LIBRARY DESTINATION "$<TARGET_FILE_BASE_NAME:obs>.app/Contents/Frameworks/"
				COMPONENT obs_frameworks
			PUBLIC_HEADER DESTINATION ${OBS_INCLUDE_DESTINATION})
	endif()
endfunction()

# Helper function to set-up framework targets on macOS
function(setup_framework_target target)
	set_target_properties(${target} PROPERTIES
		FRAMEWORK ON
		FRAMEWORK_VERSION A
		OUTPUT_NAME ${target}
		MACOSX_FRAMEWORK_IDENTIFIER "com.obsproject.${target}"
		MACOSX_FRAMEWORK_INFO_PLIST "${CMAKE_SOURCE_DIR}/cmake/bundle/macOS/Plugin-Info.plist.in"
		XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.obsproject.${target}")

	install(TARGETS ${target}
		EXPORT "${target}Targets"
		FRAMEWORK DESTINATION "Frameworks"
			COMPONENT ${target}_Runtime
		INCLUDES DESTINATION "Frameworks/$<TARGET_FILE_BASE_NAME:${target}>.framework/Headers")

	install(TARGETS ${target}
		FRAMEWORK DESTINATION "$<TARGET_FILE_BASE_NAME:obs>.app/Contents/Frameworks/"
			COMPONENT obs_frameworks)
endfunction()

# Helper function to set up OBS plugin targets
function(setup_plugin_target target)
	set(MACOSX_PLUGIN_BUNDLE_NAME "${target}" PARENT_SCOPE)
	set(MACOSX_PLUGIN_GUI_IDENTIFIER "com.obsproject.${target}" PARENT_SCOPE)
	set(MACOSX_PLUGIN_BUNDLE_VERSION "${MACOSX_BUNDLE_BUNDLE_VERSION}" PARENT_SCOPE)
	set(MACOSX_PLUGIN_SHORT_VERSION_STRING "${MACOSX_BUNDLE_SHORT_VERSION_STRING}" PARENT_SCOPE)
	set(MACOSX_PLUGIN_EXECUTABLE_NAME "${target}" PARENT_SCOPE)
	set(MACOSX_PLUGIN_BUNDLE_TYPE "BNDL" PARENT_SCOPE)

	set_target_properties(${target} PROPERTIES
		BUNDLE ON
		BUNDLE_EXTENSION "plugin"
		OUTPUT_NAME ${target}
		MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/cmake/bundle/macOS/Plugin-Info.plist.in"
		XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.obsproject.${target}"
		XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "${OBS_BUNDLE_CODESIGN_IDENTITY}"
		XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${CMAKE_SOURCE_DIR}/cmake/bundle/macOS/entitlements.plist")

	set_property(GLOBAL APPEND PROPERTY OBS_MODULE_LIST "${target}")
	message(STATUS "OBS:   ${target} enabled")

	install_bundle_resources(${target})
endfunction()

# Helper function to set up OBS scripting plugin targets
function(setup_script_plugin_target target)
	set_target_properties(${target} PROPERTIES
		XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.obsproject.${target}"
		XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "${OBS_BUNDLE_CODESIGN_IDENTITY}"
		XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${CMAKE_SOURCE_DIR}/cmake/bundle/macOS/entitlements.plist")

	set_property(GLOBAL APPEND PROPERTY OBS_SCRIPTING_MODULE_LIST "${target}")
	message(STATUS "OBS:   ${target} enabled")
endfunction()

# Helper function to set up target resources (e.g. L10N files)
function(setup_target_resources target destination)
	install_bundle_resources(${target})
endfunction()

# Helper function to set up plugin resources inside plugin bundle
function(install_bundle_resources target)
	if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/data")
		file(GLOB_RECURSE _DATA_FILES "${CMAKE_CURRENT_SOURCE_DIR}/data/*")
		foreach(_DATA_FILE IN LISTS _DATA_FILES)
			file(RELATIVE_PATH _RELATIVE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/data/ ${_DATA_FILE})
			get_filename_component(_RELATIVE_PATH "${_RELATIVE_PATH}" PATH)
			target_sources(${target}
				PRIVATE ${_DATA_FILE})
			set_source_files_properties(${_DATA_FILE} PROPERTIES
				MACOSX_PACKAGE_LOCATION "Resources/${_RELATIVE_PATH}")
			string(REPLACE "\\" "\\\\" _GROUP_NAME "${_RELATIVE_PATH}")
			source_group("Resources\\${_GROUP_NAME}" FILES ${_DATA_FILE})
		endforeach()
	endif()
endfunction()

# Helper function to set up specific resource files for targets
function(add_target_resource target resource destination)
	target_sources(${target}
		PRIVATE ${resource})
	set_source_files_properties(${resource} PROPERTIES
		MACOSX_PACKAGE_LOCATION Resources)
endfunction()

# Helper function to set up OBS app target
function(setup_obs_app target)
	set_target_properties(${target} PROPERTIES
		BUILD_WITH_INSTALL_RPATH OFF
		XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "${OBS_BUNDLE_CODESIGN_IDENTITY}"
		XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${CMAKE_SOURCE_DIR}/cmake/bundle/macOS/entitlements.plist"
		XCODE_SCHEME_ENVIRONMENT "PYTHONDONTWRITEBYTECODE=1")

	install(TARGETS ${target}
		BUNDLE DESTINATION "."
			COMPONENT obs_app)

	if(TARGET OBS::browser)
		setup_target_browser(${target})
	endif()

	setup_obs_modules(${target})
	setup_obs_bundle(${target})
endfunction()

# Helper function to do additional setup for browser source plugin
function(setup_target_browser target)
	get_filename_component(_CEF_FRAMEWORK_NAME "${CEF_LIBRARY}" NAME)

	add_custom_command(TARGET ${target} POST_BUILD
		COMMAND "${CMAKE_COMMAND}" -E copy_directory
			"${CEF_LIBRARY}"
			"$<TARGET_BUNDLE_CONTENT_DIR:obs>/Frameworks/${_CEF_FRAMEWORK_NAME}"
		VERBATIM)

	add_custom_command(TARGET ${target} POST_BUILD
		COMMAND /bin/sh -c "codesign --force --sign \"${OBS_BUNDLE_CODESIGN_IDENTITY}\" $<$<BOOL:${OBS_CODESIGN_LINKER}>:--options linker-signed >\"$<TARGET_BUNDLE_CONTENT_DIR:obs>/Frameworks/${_CEF_FRAMEWORK_NAME}/Libraries/libEGL.dylib\""
		COMMAND /bin/sh -c "codesign --force --sign \"${OBS_BUNDLE_CODESIGN_IDENTITY}\" $<$<BOOL:${OBS_CODESIGN_LINKER}>:--options linker-signed >\"$<TARGET_BUNDLE_CONTENT_DIR:obs>/Frameworks/${_CEF_FRAMEWORK_NAME}/Libraries/libswiftshader_libEGL.dylib\""
		COMMAND /bin/sh -c "codesign --force --sign \"${OBS_BUNDLE_CODESIGN_IDENTITY}\" $<$<BOOL:${OBS_CODESIGN_LINKER}>:--options linker-signed >\"$<TARGET_BUNDLE_CONTENT_DIR:obs>/Frameworks/${_CEF_FRAMEWORK_NAME}/Libraries/libGLESv2.dylib\""
		COMMAND /bin/sh -c "codesign --force --sign \"${OBS_BUNDLE_CODESIGN_IDENTITY}\" $<$<BOOL:${OBS_CODESIGN_LINKER}>:--options linker-signed >\"$<TARGET_BUNDLE_CONTENT_DIR:obs>/Frameworks/${_CEF_FRAMEWORK_NAME}/Libraries/libswiftshader_libGLESv2.dylib\""
		COMMAND /bin/sh -c "codesign --force --sign \"${OBS_BUNDLE_CODESIGN_IDENTITY}\" $<$<BOOL:${OBS_CODESIGN_LINKER}>:--options linker-signed >\"$<TARGET_BUNDLE_CONTENT_DIR:obs>/Frameworks/${_CEF_FRAMEWORK_NAME}/Libraries/libvk_swiftshader.dylib\""
		COMMAND /bin/sh -c "codesign --force --sign \"${OBS_BUNDLE_CODESIGN_IDENTITY}\" $<$<BOOL:${OBS_CODESIGN_LINKER}>:--options linker-signed >--deep \"$<TARGET_BUNDLE_CONTENT_DIR:obs>/Frameworks/${_CEF_FRAMEWORK_NAME}/Chromium Embedded Framework\""
		COMMENT "Codesigning Chromium Embedded Framework"
		VERBATIM)

	if(NOT BROWSER_LEGACY)
		foreach(_SUFFIX IN ITEMS "_gpu" "_plugin" "_renderer" "")
			if(TARGET OBS::browser-helper${_SUFFIX})
				# add_dependencies(${target} OBS::browser-helper${_SUFFIX})

				add_custom_command(TARGET ${target} POST_BUILD
					COMMAND "${CMAKE_COMMAND}" -E copy_directory
						"$<TARGET_BUNDLE_DIR:OBS::browser-helper${_SUFFIX}>"
						"$<TARGET_BUNDLE_CONTENT_DIR:obs>/Frameworks/$<TARGET_FILE_NAME:OBS::browser-helper${_SUFFIX}>.app"
					VERBATIM)
			endif()

			add_custom_command(TARGET ${target} POST_BUILD
				COMMAND /bin/sh -c "codesign --force --sign \"${OBS_BUNDLE_CODESIGN_IDENTITY}\" $<$<BOOL:${OBS_CODESIGN_LINKER}>:--options linker-signed >\"$<TARGET_BUNDLE_CONTENT_DIR:obs>/Frameworks/$<TARGET_FILE_NAME:OBS::browser-helper${_SUFFIX}>.app\""
				COMMENT "Codesigning Browser Helper ${_HELPER_OUTPUT_NAME}"
				VERBATIM)
		endforeach()
	else()
		if(TARGET obs-browser-helper)
			add_custom_command(TARGET ${target} POST_BUILD
				COMMAND "${CMAKE_COMMAND}" -E copy
					"$<TARGET_FILE:obs-browser-helper>"
					"$<TARGET_BUNDLE_CONTENT_DIR:obs>/PlugIns/$<TARGET_FILE_BASE_NAME:obs-browser>/Contents/MacOS/$<TARGET_FILE_NAME:obs-browser-helper>"
				VERBATIM)

			add_custom_command(TARGET ${target} POST_BUILD
				COMMAND /bin/sh -c "codesign --force --sign \"${OBS_BUNDLE_CODESIGN_IDENTITY}\" $<$<BOOL:${OBS_CODESIGN_LINKER}>:--options linker-signed >\"$<TARGET_BUNDLE_CONTENT_DIR:obs>/PlugIns/$<TARGET_FILE_BASE_NAME:obs-browser>/Contents/MacOS/$<TARGET_FILE_NAME:obs-browser-helper>\""
				COMMENT "Codesigning obs-browser-helper"
				VERBATIM)
		endif()
	endif()
endfunction()

# Helper function to set-up OBS plugins and helper binaries for macOS bundling
function(setup_obs_modules target)
	get_property(OBS_MODULE_LIST GLOBAL PROPERTY OBS_MODULE_LIST)
	foreach(_MODULE IN LISTS OBS_MODULE_LIST)
		add_custom_command(TARGET ${target} POST_BUILD
			COMMAND "${CMAKE_COMMAND}" -E copy_directory
			  "$<TARGET_BUNDLE_DIR:${_MODULE}>"
			  "$<TARGET_BUNDLE_CONTENT_DIR:${target}>/PlugIns/$<TARGET_FILE_BASE_NAME:${_MODULE}>.plugin"
			VERBATIM)
	endforeach()

	install(TARGETS ${OBS_MODULE_LIST}
		LIBRARY DESTINATION "$<TARGET_FILE_BASE_NAME:${target}>.app/Contents/PlugIns"
			COMPONENT obs_plugins
			NAMELINK_COMPONENT ${target}_Development)

	get_property(OBS_MODULE_LIST GLOBAL PROPERTY OBS_SCRIPTING_MODULE_LIST)
	foreach(_MODULE IN LISTS OBS_MODULE_LIST)
		add_custom_command(TARGET ${target} POST_BUILD
			COMMAND "${CMAKE_COMMAND}" -E copy
			  "$<TARGET_FILE:${_MODULE}>"
			  "$<TARGET_BUNDLE_CONTENT_DIR:${target}>/PlugIns/$<TARGET_FILE_NAME:${_MODULE}>"
			VERBATIM)

		if(${_MODULE} STREQUAL "obspython")
			install(FILES "$<TARGET_FILE_DIR:${_MODULE}>/${_MODULE}.py"
				DESTINATION "$<TARGET_FILE_BASE_NAME:${target}>.app/Contents/PlugIns"
				COMPONENT obs_scripting_plugins)

			add_custom_command(TARGET ${target} POST_BUILD
				COMMAND "${CMAKE_COMMAND}" -E copy
					"$<TARGET_FILE_DIR:${_MODULE}>/${_MODULE}.py"
					"$<TARGET_BUNDLE_CONTENT_DIR:${target}>/PlugIns/${_MODULE}.py"
				COMMAND /bin/sh -c "codesign --force --sign \"${OBS_BUNDLE_CODESIGN_IDENTITY}\" $<$<BOOL:${OBS_CODESIGN_LINKER}>:--options linker-signed >\"$<TARGET_BUNDLE_CONTENT_DIR:${target}>/PlugIns/${_MODULE}.py\""
				VERBATIM)
		endif()
	endforeach()

	install(TARGETS ${OBS_SCRIPTING_MODULE_LIST}
		RUNTIME DESTINATION "$<TARGET_FILE_BASE_NAME:obs>.app/Contents/PlugIns"
			COMPONENT obs_scripting_plugins)

	if(TARGET obs-ffmpeg-mux)
		install(TARGETS obs-ffmpeg-mux
			RUNTIME DESTINATION "$<TARGET_FILE_BASE_NAME:obs>.app/Contents/MacOS"
				COMPONENT obs_plugins)
	endif()
endfunction()

# Helper function to finalise macOS app bundles
function(setup_obs_bundle)
	install(CODE "
		set(_BUILD_FOR_DISTRIBUTION \"${BUILD_FOR_DISTRIBUTION}\")
		set(_BUNDLENAME \"$<TARGET_FILE_BASE_NAME:obs>.app\")
		set(_BUNDLER_COMMAND \"${CMAKE_SOURCE_DIR}/cmake/bundle/macos/dylibbundler\")
		set(_CODESIGN_IDENTITY \"${OBS_BUNDLE_CODESIGN_IDENTITY}\")
		set(_CODESIGN_ENTITLEMENTS \"${CMAKE_SOURCE_DIR}/cmake/bundle/macOS/entitlements.plist\")"
		COMPONENT obs_resources)

	if(ENABLE_SPARKLE_UPDATER)
		install(DIRECTORY
			${SPARKLE}
			DESTINATION "$<TARGET_FILE_BASE_NAME:obs>.app/Contents/Frameworks"
			COMPONENT obs_frameworks)

		install(FILES
    		${CMAKE_SOURCE_DIR}/cmake/bundle/macOS/OBSPublicDSAKey.pem
        	DESTINATION "$<TARGET_FILE_BASE_NAME:obs>.app/Contents/Resources/"
        	COMPONENT obs_resources)
	endif()

	install(SCRIPT "${CMAKE_SOURCE_DIR}/cmake/bundle/macOS/bundleutils.cmake"
		COMPONENT obs_resources)
endfunction()

# Helper function to export target to build and install tree
# (Allows usage of `find_package(libobs)` by other build trees)
function(export_target target)
	set(OBS_PLUGIN_DESTINATION "")
	set(OBS_DATA_DESTINATION "")

	_export_target(${ARGV})
	set_target_properties(${target} PROPERTIES
		PUBLIC_HEADER "${CMAKE_CURRENT_BINARY_DIR}/${target}_EXPORT.h")
endfunction()

# Helper function to install header files
function(install_headers target)
	install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/"
		DESTINATION "$<IF:$<BOOL:$<TARGET_PROPERTY:${target},FRAMEWORK>>,Frameworks/$<TARGET_FILE_BASE_NAME:${target}>.framework/Headers,${OBS_INCLUDE_DESTINATION}>"
			COMPONENT ${target}_Headers
		FILES_MATCHING
			PATTERN "*.h"
			PATTERN "*.hpp")

	install(FILES "${CMAKE_BINARY_DIR}/config/obsconfig.h"
		DESTINATION "$<IF:$<BOOL:$<TARGET_PROPERTY:${target},FRAMEWORK>>,Frameworks/$<TARGET_FILE_BASE_NAME:${target}>.framework/Headers,${OBS_INCLUDE_DESTINATION}>"
			COMPONENT ${target}_Headers)
endfunction()