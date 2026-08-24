# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(mmkb_harmonyos)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})
get_filename_component(KEYMAGIC_REPOSITORY_ROOT "${NATIVERENDER_ROOT_PATH}/../../../../.." ABSOLUTE)

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

if(CMAKE_BUILD_TYPE MATCHES "^[Rr]elease$")
    set(KEYMAGIC_CORE_PROFILE release)
else()
    set(KEYMAGIC_CORE_PROFILE debug)
endif()

set(KEYMAGIC_CORE_TARGET "aarch64-unknown-linux-ohos" CACHE STRING
    "Rust target used for the embedded KeyMagic static library")
set(KEYMAGIC_CORE_LIB
    "${KEYMAGIC_REPOSITORY_ROOT}/target/${KEYMAGIC_CORE_TARGET}/${KEYMAGIC_CORE_PROFILE}/libkeymagic_core.a"
    CACHE FILEPATH "Path to the keymagic-core static library")

if(NOT EXISTS "${KEYMAGIC_CORE_LIB}")
    message(FATAL_ERROR
        "keymagic-core static library was not found at ${KEYMAGIC_CORE_LIB}. "
        "From the repository root, set OHOS_SDK_HOME to the OpenHarmony SDK directory "
        "and run: powershell -ExecutionPolicy Bypass -File mmkb-harmonyos/scripts/build-core-ohos.ps1 -Profile ${KEYMAGIC_CORE_PROFILE}")
endif()

add_library(keymagic_core STATIC IMPORTED GLOBAL)
set_target_properties(keymagic_core PROPERTIES IMPORTED_LOCATION "${KEYMAGIC_CORE_LIB}")

add_library(keymagic3 SHARED
    napi_init.cpp
    keymagic_bridge.cpp)

target_include_directories(keymagic3 PRIVATE
    ${NATIVERENDER_ROOT_PATH})
target_compile_features(keymagic3 PRIVATE cxx_std_17)
target_link_libraries(keymagic3 PUBLIC
    keymagic_core
    libace_napi.z.so
    libhilog_ndk.z.so)
