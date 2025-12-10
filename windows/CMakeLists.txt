cmake_minimum_required(VERSION 3.10)

# Project level CMake
project(ffmpeg_streamer_plugin LANGUAGES CCXX)

# Source files
set(SOURCE_FILES
  "../src/ffmpeg_core.c"
)

add_library(ffmpeg_streamer SHARED
  ${SOURCE_FILES}
)

# Include directories
target_include_directories(ffmpeg_streamer PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/../src")

# FFmpeg setup for Windows
# Assumes FFMPEG_ROOT is defined or libs are in 'ffmpeg' subdir.
# You can pass -DFFMPEG_ROOT=... or place in windows/ffmpeg/

set(FFMPEG_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/ffmpeg" CACHE PATH "Path to FFmpeg root")

if(EXISTS "${FFMPEG_ROOT}")
    message(STATUS "Found FFmpeg root at ${FFMPEG_ROOT}")
    target_include_directories(ffmpeg_streamer PRIVATE "${FFMPEG_ROOT}/include")
    
    # Link against .lib files
    target_link_libraries(ffmpeg_streamer PRIVATE 
        "${FFMPEG_ROOT}/lib/avcodec.lib"
        "${FFMPEG_ROOT}/lib/avformat.lib"
        "${FFMPEG_ROOT}/lib/avutil.lib"
        "${FFMPEG_ROOT}/lib/swscale.lib"
        "${FFMPEG_ROOT}/lib/swresample.lib"
    )
    
    # On Windows, you also need to ensure DLLs are copied to output, 
    # but that's often handled by a runner script or manual copy.
else()
    message(WARNING "FFMPEG_ROOT not found at ${FFMPEG_ROOT}. Please Configure.")
endif()

# Flutter plugin requirement: export symbols
set_target_properties(ffmpeg_streamer PROPERTIES
  WINDOWS_EXPORT_ALL_SYMBOLS ON
)
