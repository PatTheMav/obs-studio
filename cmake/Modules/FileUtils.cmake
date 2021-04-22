# File helper module, fixing bugs/issues with existing cmake functionality

if(${COMMAND} STREQUAL "COPY_RECURSIVE")
	if(NOT DEFINED SOURCE OR NOT DEFINED DESTINATION)
		message(FATAL_ERROR "COPY_RECUSIVE usage: -DCOPY_RECUSIVE -DSOURCE [source] -DDESTINATION [destination]")
	endif()
	file(COPY "${SOURCE}" DESTINATION "${DESTINATION}" USE_SOURCE_PERMISSIONS)
endif()
