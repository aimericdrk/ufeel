set(UFEEL_PREBUILT_DIR "${UFEEL_DEPS_PREFIX}")

if(NOT CMAKE_SYSTEM_PROCESSOR STREQUAL "arm64")
    message(FATAL_ERROR "macOS builds need an Apple silicon (arm64) Mac")
endif()

function(ufeel_link_speech_to_text TARGET)
    target_sources(${TARGET} PRIVATE ${LIBRARY_DIR}/src/SpeechToText/CoreAudioDevices.cpp)
    target_link_libraries(${TARGET}
        PUBLIC
            "${VOSK_DIR}/lib/libvosk.dylib"
            "${PORTAUDIO_DIR}/lib/libportaudio.dylib"
        PRIVATE
            "-framework CoreAudio"
    )
endfunction()

function(ufeel_link_eye_tracking TARGET)
    target_link_libraries(${TARGET} PRIVATE ufeel_feature_eye_tracking ${TFLITE_STATIC_LIBRARIES})
endfunction()

function(ufeel_configure_wrapper TARGET)
    set_target_properties(${TARGET} PROPERTIES
        INSTALL_RPATH "@loader_path/dependencies"
        LINK_DEPENDS "${WRAPPER_DIR}/ufeel.exp"
    )
    target_link_options(${TARGET} PRIVATE "-Wl,-exported_symbols_list,${WRAPPER_DIR}/ufeel.exp")
endfunction()

function(ufeel_install_opencv_library MODULE)
    install(
        FILES "${OPENCV_DIR}/lib/libopencv_${MODULE}.4.8.1.dylib"
        RENAME "libopencv_${MODULE}.408.dylib"
        DESTINATION dependencies
    )
endfunction()

function(ufeel_install_dependencies)
    find_program(INSTALL_NAME_TOOL_EXECUTABLE NAMES install_name_tool REQUIRED)
    find_program(OTOOL_EXECUTABLE NAMES otool REQUIRED)
    find_program(CODESIGN_EXECUTABLE NAMES codesign REQUIRED)

    foreach(MODULE IN ITEMS core videoio imgproc imgcodecs)
        ufeel_install_opencv_library(${MODULE})
    endforeach()

    if(UFEEL_ENABLE_EMOTIONS OR UFEEL_ENABLE_EYE_TRACKING)
        foreach(MODULE IN ITEMS dnn objdetect calib3d features2d flann)
            ufeel_install_opencv_library(${MODULE})
        endforeach()
    endif()

    if(UFEEL_ENABLE_EMOTIONS)
        install(
            FILES
                "${LIBTORCH_DIR}/lib/libtorch.dylib"
                "${LIBTORCH_DIR}/lib/libtorch_cpu.dylib"
                "${LIBTORCH_DIR}/lib/libc10.dylib"
                "${LIBTORCH_DIR}/lib/libomp.dylib"
            DESTINATION dependencies
        )
        file(GLOB YAML_CPP_SHARED_LIBRARIES "${UFEEL_DEPS_PREFIX}/lib/libyaml-cpp*.dylib")
        install(FILES ${YAML_CPP_SHARED_LIBRARIES} DESTINATION dependencies)
    endif()

    if(UFEEL_ENABLE_SPEECH_TO_TEXT)
        file(REAL_PATH "${PORTAUDIO_DIR}/lib/libportaudio.2.dylib" PORTAUDIO_LIBRARY_FILE)
        install(
            FILES "${PORTAUDIO_LIBRARY_FILE}"
            RENAME libportaudio.2.dylib
            DESTINATION dependencies
        )
        install(FILES "${VOSK_DIR}/lib/libvosk.dylib" DESTINATION dependencies)
    endif()

    set(WRAPPER_FILE_NAME "libufeel_wrapper.dylib")
    configure_file(
        "${CMAKE_SOURCE_DIR}/cmake/ConfigureDependenciesMacOS.cmake.in"
        "${CMAKE_BINARY_DIR}/ConfigureDependencies.cmake"
        @ONLY
    )
    install(SCRIPT "${CMAKE_BINARY_DIR}/ConfigureDependencies.cmake")
endfunction()
