if(CMAKE_SIZEOF_VOID_P EQUAL 8)
	SET(_LIB_SUFFIX 64)
else()
	SET(_LIB_SUFFIX 32)
endif()

find_path(SWIG_DIR
	NAMES swigrun.i
	HINTS
		ENV SWIG_PATH
		${SWIG_PATH}
		${CMAKE_SOURCE_DIR}/${SWIG_PATH}
	PATH_SUFFIXES
		../swig/Lib
		swig/Lib
		)

find_program(SWIG_EXECUTABLE
	NAMES swig
	HINTS
		ENV SWIG_PATH
		${SWIG_PATH}
		${CMAKE_SOURCE_DIR}/${SWIG_PATH}
	PATH_SUFFIXES
		../swig
		swig
		)

find_package(SWIG QUIET 2)
