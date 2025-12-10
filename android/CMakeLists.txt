cmake_minimum_required(VERSION 3.4.1)

# Platform independent source files
set(SOURCE_FILES
    ../src/ffmpeg_core.c
)

# Add our library
add_library(ffmpeg_streamer SHARED
            ${SOURCE_FILES}
)

# --- FFmpeg Configuration ---

# This setup assumes the user has placed prebuilt FFmpeg libraries in:
# android/src/main/jniLibs/${ANDROID_ABI}/libavcodec.so, etc.
# AND headers in android/src/main/cpp/include

# However, for a cleaner CMake approach, we might use IMPORTED targets.
# We will assume a standard structure:
# android/libs/${ANDROID_ABI}/libavcodec.so ...
# android/include/ ...

set(FFMPEG_LIBS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}")
set(FFMPEG_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../cpp/include")

# Define FFmpeg libraries to link
set(FFMPEG_LIBRARIES
    avformat
    avcodec
    avutil
    swscale
    swresample
)

# Header include path
target_include_directories(ffmpeg_streamer PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/../src")

# Try to find headers if they exist
if(EXISTS "${FFMPEG_INCLUDE_DIR}")
    target_include_directories(ffmpeg_streamer PRIVATE "${FFMPEG_INCLUDE_DIR}")
else()
    message(WARNING "FFmpeg headers not found at ${FFMPEG_INCLUDE_DIR}. Build will likely fail unless provided otherwise.")
endif()

# Link against FFmpeg libraries
foreach(lib ${FFMPEG_LIBRARIES})
    add_library(${lib} SHARED IMPORTED)
    set_target_properties(${lib} PROPERTIES IMPORTED_LOCATION "${FFMPEG_LIBS_DIR}/lib${lib}.so")
    target_link_libraries(ffmpeg_streamer ${lib})
endforeach()

# Link standard libraries
find_library(log-lib log)
target_link_libraries(ffmpeg_streamer ${log-lib})
