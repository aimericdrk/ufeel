#!/usr/bin/env bash

set -euo pipefail

if ((BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] < 404)); then
    printf 'error: bash 4.4 or newer is required, found %s (brew install bash)\n' "$BASH_VERSION" >&2
    exit 1
fi

shopt -s inherit_errexit

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly OUTPUT_DIR="${ROOT_DIR}/3rdparty/macos-arm64"
readonly WORK_DIR="${ROOT_DIR}/.cache/macos-3rdparty"
readonly DOWNLOAD_DIR="${ROOT_DIR}/.cache/downloads"
readonly DEPLOYMENT_TARGET="${UFEEL_MACOS_DEPLOYMENT_TARGET:-14.0}"

readonly LIBTORCH_URL="https://download.pytorch.org/libtorch/cpu/libtorch-macos-arm64-2.10.0.zip"
readonly LIBTORCH_SHA256="13061d97e561235d9e43c132f6dc9b08a60f487a833da53a951614a96d3e7d32"
readonly OPENCV_URL="https://github.com/opencv/opencv/archive/refs/tags/4.8.1.tar.gz"
readonly OPENCV_SHA256="62f650467a60a38794d681ae7e66e3e8cfba38f445e0bf87867e2f2cdc8be9d5"
readonly TFLITE_URL="https://github.com/tensorflow/tensorflow/archive/refs/tags/v2.15.0.tar.gz"
readonly TFLITE_SHA256="9cec5acb0ecf2d47b16891f8bc5bc6fbfdffe1700bdadc0d9ebe27ea34f0c220"
readonly VOSK_URL="https://github.com/alphacep/vosk-api/releases/download/v0.3.42/vosk-osx-0.3.42.zip"
readonly VOSK_SHA256="65395f196c9d0583d79949142b25560acaf9c295f36284e18433097f3adb0ea1"

readonly LIBRARIES=(libtorch opencv tensorflowlite vosk)

usage()
{
    cat <<EOF
Usage: Tools/build-macos-3rdparty.sh [${LIBRARIES[*]}]...

Downloads or builds the macOS arm64 libraries into 3rdparty/macos-arm64, all of them by default.

Environment:
  UFEEL_MACOS_DEPLOYMENT_TARGET (default: 14.0)
EOF
}

error()
{
    printf 'error: %s\n' "$*" >&2
    exit 1
}

run()
{
    printf '+'
    printf ' %q' "$@"
    printf '\n'
    "$@"
}

has_sha256()
{
    [[ -f "$1" && "$(shasum -a 256 < "$1" | cut -d ' ' -f 1)" == "$2" ]]
}

fetch()
{
    local url="$1"
    local sha256="$2"
    local archive="$DOWNLOAD_DIR/$3"
    if ! has_sha256 "$archive" "$sha256"; then
        mkdir -p "$DOWNLOAD_DIR"
        run curl -fsSL --retry 3 -o "$archive.part" "$url" >&2
        has_sha256 "$archive.part" "$sha256" || error "SHA-256 mismatch for $url"
        mv "$archive.part" "$archive"
    fi
    printf '%s' "$archive"
}

extract()
{
    local archive="$1"
    local destination="$2"
    local -a entries
    rm -rf "$destination" "$destination.part"
    mkdir -p "$destination.part"
    (cd "$destination.part" && cmake -E tar xf "$archive")
    entries=("$destination.part"/*)
    ((${#entries[@]} == 1)) && [[ -d "${entries[0]}" ]] ||
        error "$archive does not contain a single top-level directory"
    mv "${entries[0]}" "$destination"
    rm -rf "$destination.part"
}

patch_source()
{
    local file="$1"
    local expression="$2"
    local patched
    patched="$(sed -E "$expression" "$file")"
    [[ "$patched" != "$(cat "$file")" ]] || error "$file no longer needs the patch '$expression'"
    printf '%s\n' "$patched" > "$file"
}

use_rpath_install_name()
{
    local library="$1"
    run install_name_tool -id "@rpath/$(basename -- "$library")" "$library"
    run codesign --force --sign - "$library"
}

copy_licenses()
{
    local name="$1"
    local destination="$2"
    mkdir -p "$destination/share"
    cp -R "$ROOT_DIR/3rdparty/$name/share/licenses" "$destination/share/"
}

readonly CMAKE_OPTIONS=(
    -G Ninja
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_C_COMPILER=clang
    -DCMAKE_CXX_COMPILER=clang++
    -DCMAKE_INSTALL_LIBDIR=lib
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    "-DCMAKE_OSX_DEPLOYMENT_TARGET=$DEPLOYMENT_TARGET"
    "-DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew;/usr/local"
)

build_libtorch()
{
    local destination="$1"
    local openmp
    extract "$(fetch "$LIBTORCH_URL" "$LIBTORCH_SHA256" libtorch-macos-arm64-2.10.0.zip)" "$destination"
    openmp="$(otool -L "$destination/lib/libtorch_cpu.dylib" | awk '$1 ~ /\/libomp\.dylib$/ { print $1 }')"
    [[ -n "$openmp" ]] || error "libtorch_cpu.dylib no longer loads libomp.dylib"
    # LibTorch loads OpenMP from its Homebrew path: use the copy it ships.
    if [[ "$openmp" != @rpath/* ]]; then
        run install_name_tool -change "$openmp" @rpath/libomp.dylib "$destination/lib/libtorch_cpu.dylib"
        run codesign --force --sign - "$destination/lib/libtorch_cpu.dylib"
    fi
    use_rpath_install_name "$destination/lib/libomp.dylib"
    copy_licenses libtorch "$destination"
}

build_opencv()
{
    local destination="$1"
    local source="$WORK_DIR/opencv-source"
    extract "$(fetch "$OPENCV_URL" "$OPENCV_SHA256" opencv-4.8.1.tar.gz)" "$source"
    # Recent SDKs define TARGET_OS_MAC, which the bundled libpng and zlib take for Mac OS 9.
    patch_source "$source/3rdparty/libpng/pngpriv.h" 's/ \|\| defined\(TARGET_OS_MAC\)//'
    run cmake -S "$source" -B "$WORK_DIR/opencv-build" "${CMAKE_OPTIONS[@]}" \
        -DCMAKE_INSTALL_NAME_DIR=@rpath \
        -DBUILD_LIST=core,imgproc,imgcodecs,videoio,dnn,objdetect,calib3d,features2d,flann \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_TESTS=OFF \
        -DBUILD_PERF_TESTS=OFF \
        -DBUILD_EXAMPLES=OFF \
        -DBUILD_DOCS=OFF \
        -DBUILD_JAVA=OFF \
        -DBUILD_opencv_apps=OFF \
        -DBUILD_opencv_python3=OFF \
        -DOPENCV_PYTHON_SKIP_DETECTION=ON \
        -DBUILD_ZLIB=OFF \
        -DBUILD_PNG=ON \
        -DBUILD_JPEG=ON \
        -DBUILD_PROTOBUF=ON \
        -DWITH_AVFOUNDATION=ON \
        -DWITH_FFMPEG=OFF \
        -DWITH_GSTREAMER=OFF \
        -DWITH_OPENCL=OFF \
        -DWITH_OPENEXR=OFF \
        -DWITH_OPENJPEG=OFF \
        -DWITH_JASPER=OFF \
        -DWITH_TIFF=OFF \
        -DWITH_WEBP=OFF \
        -DWITH_AVIF=OFF \
        -DWITH_EIGEN=OFF \
        -DWITH_LAPACK=OFF \
        -DWITH_ITT=OFF \
        -DWITH_IPP=OFF \
        -DWITH_OBSENSOR=OFF \
        -DOPENCV_GENERATE_PKGCONFIG=OFF
    run cmake --build "$WORK_DIR/opencv-build" --parallel
    run cmake --install "$WORK_DIR/opencv-build" --prefix "$destination"
}

build_tensorflowlite()
{
    local destination="$1"
    local source="$WORK_DIR/tensorflow-source"
    local build="$WORK_DIR/tensorflowlite-build"
    local file
    extract "$(fetch "$TFLITE_URL" "$TFLITE_SHA256" tensorflow-2.15.0.tar.gz)" "$source"
    # TensorFlow 2.15 passes std::abs<T> as a function, which recent libc++ versions reject.
    patch_source "$source/tensorflow/lite/kernels/elementwise.cc" \
        's/std::abs<(float|int32_t)>,/[](\1 value) { return std::abs(value); },/g'
    run cmake -S "$source/tensorflow/lite" -B "$build" "${CMAKE_OPTIONS[@]}" \
        -DTFLITE_ENABLE_XNNPACK=OFF \
        -DTFLITE_ENABLE_GPU=OFF
    run cmake --build "$build" --parallel --target tensorflow-lite
    mkdir -p "$destination/include" "$destination/lib/deps"
    cp "$build/libtensorflow-lite.a" "$destination/lib/"
    (cd "$build/_deps" && find . -path './*-build/*' -name '*.a' -print) | while IFS= read -r file; do
        mkdir -p "$destination/lib/deps/$(dirname -- "$file")"
        cp "$build/_deps/$file" "$destination/lib/deps/$file"
    done
    (cd "$source" && find tensorflow/lite -name '*.h' -print) | while IFS= read -r file; do
        mkdir -p "$destination/include/$(dirname -- "$file")"
        cp "$source/$file" "$destination/include/$file"
    done
    cp -R "$build/flatbuffers/include/flatbuffers" "$destination/include/"
    copy_licenses tensorflowlite "$destination"
}

build_vosk()
{
    local destination="$1"
    local source="$WORK_DIR/vosk"
    extract "$(fetch "$VOSK_URL" "$VOSK_SHA256" vosk-osx-0.3.42.zip)" "$source"
    mkdir -p "$destination/include" "$destination/lib"
    cp "$source/vosk_api.h" "$destination/include/"
    run lipo "$source/libvosk.dylib" -thin arm64 -output "$destination/lib/libvosk.dylib"
    use_rpath_install_name "$destination/lib/libvosk.dylib"
    copy_licenses vosk "$destination"
}

main()
{
    local -a selected=("$@")
    local name
    [[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] ||
        error "this script builds on an Apple silicon Mac only"
    ((${#selected[@]})) || selected=("${LIBRARIES[@]}")
    for name in "${selected[@]}"; do
        [[ " ${LIBRARIES[*]} " == *" $name "* ]] || { usage >&2; error "unknown library '$name'"; }
    done
    for name in "${selected[@]}"; do
        rm -rf "${OUTPUT_DIR:?}/$name.part" "$WORK_DIR"
        mkdir -p "$WORK_DIR"
        "build_$name" "$OUTPUT_DIR/$name.part"
        rm -rf "${OUTPUT_DIR:?}/$name"
        mv "$OUTPUT_DIR/$name.part" "$OUTPUT_DIR/$name"
    done
    rm -rf "$WORK_DIR"
}

case "${1:-}" in
    -h|--help) usage ;;
    *) main "$@" ;;
esac
