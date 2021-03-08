MACRO(MYSQL_CHECK_COREDUMPER)
  # We build coredumper by default
  IF(LINUX)
    IF (NOT DEFINED WITH_COREDUMPER)
      SET (WITH_COREDUMPER 1)
    ENDIF ()
    IF (WITH_COREDUMPER)
      MESSAGE(STATUS "Build with DWITH_COREDUMPER = ON")
      ADD_SUBDIRECTORY(extra/coredumper)
      SET (HAVE_LIBCOREDUMPER 1)
    ELSE ()
      MESSAGE(STATUS "Build with DWITH_COREDUMPER = OFF")
      SET (HAVE_LIBCOREDUMPER 0)
    ENDIF ()
  ELSE ()
    IF (WITH_COREDUMPER)
      MESSAGE(STATUS "Build with DWITH_COREDUMPER = OFF. Only supported on linux.")
      SET (WITH_COREDUMPER 0)
      SET (HAVE_LIBCOREDUMPER 0)
    ENDIF ()
  ENDIF ()
ENDMACRO()