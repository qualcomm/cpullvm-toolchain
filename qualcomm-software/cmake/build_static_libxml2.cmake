# Build static libxml2 before LLVM's configuration searches for it.
set(build_static_libxml2_cmake_dir ${CMAKE_CURRENT_LIST_DIR})

macro(build_static_libxml2)
    set(CPULLVM_LIBXML2_SOURCE_DIR "${CMAKE_BINARY_DIR}/libxml2-v2.15.3")
    set(libxml2_install_dir "${CMAKE_BINARY_DIR}/libxml2-build/install")

    find_program(CPULLVM_POWERSHELL_EXECUTABLE NAMES powershell pwsh REQUIRED)
    execute_process(
        COMMAND ${CPULLVM_POWERSHELL_EXECUTABLE}
            -NoProfile
            -ExecutionPolicy Bypass
            -File "${build_static_libxml2_cmake_dir}/../scripts/build_static_libxml2.ps1"
            -BuildDir "${CMAKE_BINARY_DIR}"
        RESULT_VARIABLE libxml2_result
    )
    if(NOT libxml2_result EQUAL 0)
        message(FATAL_ERROR "Failed to build static libxml2: ${libxml2_result}")
    endif()

    set(LIBXML2_INCLUDE_DIR "${libxml2_install_dir}/include/libxml2" CACHE PATH "" FORCE)
    set(LIBXML2_LIBRARY "${libxml2_install_dir}/lib/libxml2s.lib" CACHE FILEPATH "" FORCE)
    set(LIBXML2_LIBRARIES "${libxml2_install_dir}/lib/libxml2s.lib" CACHE FILEPATH "" FORCE)

    foreach(linker_flags_variable CMAKE_EXE_LINKER_FLAGS CMAKE_SHARED_LINKER_FLAGS)
        string(FIND " ${${linker_flags_variable}} " " bcrypt.lib " bcrypt_lib_index)
        if(bcrypt_lib_index EQUAL -1)
            set(${linker_flags_variable} "${${linker_flags_variable}} bcrypt.lib" CACHE STRING "" FORCE)
        endif()
    endforeach()
endmacro()
