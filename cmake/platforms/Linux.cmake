set(UFEEL_PREBUILT_DIR "${THIRDPARTY_DIR}")

add_link_options("-Wl,--disable-new-dtags")

function(ufeel_link_speech_to_text TARGET)
    find_path(PULSEAUDIO_INCLUDE_DIR pulse/pulseaudio.h REQUIRED)
    find_library(PULSEAUDIO_LIBRARY pulse REQUIRED)

    set(VOSK_KALDI_LIBRARIES
        "${VOSK_DIR}/lib/kaldi/online2/kaldi-online2.a"
        "${VOSK_DIR}/lib/kaldi/decoder/kaldi-decoder.a"
        "${VOSK_DIR}/lib/kaldi/ivector/kaldi-ivector.a"
        "${VOSK_DIR}/lib/kaldi/gmm/kaldi-gmm.a"
        "${VOSK_DIR}/lib/kaldi/tree/kaldi-tree.a"
        "${VOSK_DIR}/lib/kaldi/feat/kaldi-feat.a"
        "${VOSK_DIR}/lib/kaldi/lat/kaldi-lat.a"
        "${VOSK_DIR}/lib/kaldi/lm/kaldi-lm.a"
        "${VOSK_DIR}/lib/kaldi/rnnlm/kaldi-rnnlm.a"
        "${VOSK_DIR}/lib/kaldi/hmm/kaldi-hmm.a"
        "${VOSK_DIR}/lib/kaldi/nnet3/kaldi-nnet3.a"
        "${VOSK_DIR}/lib/kaldi/transform/kaldi-transform.a"
        "${VOSK_DIR}/lib/kaldi/cudamatrix/kaldi-cudamatrix.a"
        "${VOSK_DIR}/lib/kaldi/matrix/kaldi-matrix.a"
        "${VOSK_DIR}/lib/kaldi/fstext/kaldi-fstext.a"
        "${VOSK_DIR}/lib/kaldi/util/kaldi-util.a"
        "${VOSK_DIR}/lib/kaldi/base/kaldi-base.a"
        "${VOSK_DIR}/lib/openfst/libfst.a"
        "${VOSK_DIR}/lib/openfst/libfstngram.a"
        "${VOSK_DIR}/lib/openblas/liblapack.a"
        "${VOSK_DIR}/lib/openblas/libf2c.a"
        "${VOSK_DIR}/lib/openblas/libblas.a"
        "${VOSK_DIR}/lib/openblas/libopenblas-r0.3.20.a"
    )

    target_sources(${TARGET} PRIVATE ${LIBRARY_DIR}/src/SpeechToText/PulseSources.cpp)
    target_include_directories(${TARGET} SYSTEM PRIVATE "${PULSEAUDIO_INCLUDE_DIR}")
    target_link_libraries(${TARGET}
        PUBLIC
            "-Wl,--start-group"
            "${VOSK_DIR}/lib/libvosk.a"
            ${VOSK_KALDI_LIBRARIES}
            "-Wl,--end-group"
            "${PORTAUDIO_DIR}/lib/libportaudio.so"
        PRIVATE
            "${PULSEAUDIO_LIBRARY}"
    )
endfunction()

function(ufeel_link_eye_tracking TARGET)
    target_link_libraries(${TARGET}
        PRIVATE
            "$<LINK_GROUP:RESCAN,ufeel_feature_eye_tracking,${TFLITE_STATIC_LIBRARIES}>"
    )
endfunction()

function(ufeel_configure_wrapper TARGET)
    set_target_properties(${TARGET} PROPERTIES INSTALL_RPATH "$ORIGIN/dependencies")
    target_link_options(${TARGET}
        PRIVATE
            "-Wl,--no-undefined"
            "-Wl,--exclude-libs,ALL"
            "-Wl,--version-script=${WRAPPER_DIR}/ufeel.map"
    )
endfunction()

function(ufeel_install_opencv_library MODULE)
    install(
        FILES "${OPENCV_DIR}/lib/libopencv_${MODULE}.so.4.8.1"
        RENAME "libopencv_${MODULE}.so.408"
        DESTINATION dependencies
    )
endfunction()

function(ufeel_install_dependencies)
    find_program(PATCHELF_EXECUTABLE NAMES patchelf REQUIRED)

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
                "${LIBTORCH_DIR}/lib/libtorch.so"
                "${LIBTORCH_DIR}/lib/libtorch_cpu.so"
                "${LIBTORCH_DIR}/lib/libc10.so"
                "${LIBTORCH_DIR}/lib/libgomp-98b21ff3.so.1"
            DESTINATION dependencies
        )
        file(GLOB YAML_CPP_SHARED_LIBRARIES "${UFEEL_DEPS_PREFIX}/lib/libyaml-cpp.so*")
        install(FILES ${YAML_CPP_SHARED_LIBRARIES} DESTINATION dependencies)
    endif()

    if(UFEEL_ENABLE_SPEECH_TO_TEXT)
        file(REAL_PATH "${PORTAUDIO_DIR}/lib/libportaudio.so.2" PORTAUDIO_LIBRARY_FILE)
        install(
            FILES "${PORTAUDIO_LIBRARY_FILE}"
            RENAME libportaudio.so.2
            DESTINATION dependencies
        )
    endif()

    configure_file(
        "${CMAKE_SOURCE_DIR}/cmake/ConfigureDependencies.cmake.in"
        "${CMAKE_BINARY_DIR}/ConfigureDependencies.cmake"
        @ONLY
    )
    install(SCRIPT "${CMAKE_BINARY_DIR}/ConfigureDependencies.cmake")
endfunction()
