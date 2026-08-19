# Retrieve the display name to use for a given libc in when printing license
# information.
function(get_libc_license_display_name clib_name display_name_out)
    if(${clib_name} MATCHES "^picolibc")
        set(${display_name_out} "Picolibc" PARENT_SCOPE)
    elseif(${clib_name} STREQUAL musl-embedded OR
           ${clib_name} STREQUAL musl)
        set(${display_name_out} ${clib_name} PARENT_SCOPE)
    else()
        message(FATAL_ERROR "Unknown library name!")
    endif()
endfunction()

# Returns a list of filenames that should be copied or referenced for a
# given libc, as well as what that file should be called in the final
# distribution. These occur in sequential pairs.
# So the list might look like:
#   "LICENSE1;LIBC-LICENSE1;LICENSE2;LIBC-LICENSE2;..."
# Where LICENSE1 should be copied and renamed to LIBC-LICENSE1, etc.
function(get_libc_license_files clib_name license_file_list_out)
    if(${clib_name} STREQUAL picolibc)
        set(
            ${license_file_list_out}
            COPYING.NEWLIB COPYING.NEWLIB
            COPYING.picolibc COPYING.picolibc
            PARENT_SCOPE
        )
    elseif(${clib_name} STREQUAL picolibc-v1812)
        # COPYING.NEWLIB has been removed
        set(${license_file_list_out} COPYING.picolibc COPYING.picolibc PARENT_SCOPE)
    elseif(${clib_name} STREQUAL musl-embedded)
        set(${license_file_list_out} COPYRIGHT musl-embedded-COPYRIGHT.txt PARENT_SCOPE)
    elseif(${clib_name} STREQUAL musl)
        set(${license_file_list_out} COPYRIGHT musl-COPYRIGHT.txt PARENT_SCOPE)
    else()
        message(FATAL_ERROR "Unknown library name!")
    endif()
endfunction()
