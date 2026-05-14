#
# Flutter Llama Podspec - macOS plugin configuration with llama.cpp
#
Pod::Spec.new do |s|
  s.name             = 'flutter_llama'
  s.version          = '0.1.0'
  s.summary          = 'Flutter plugin for LLM inference with llama.cpp and GGUF models (macOS)'
  s.description      = <<-DESC
Flutter plugin for running LLM inference with llama.cpp and GGUF models on macOS.
Supports GPU acceleration via Metal and CPU optimization via Accelerate framework.
                       DESC
  s.homepage         = 'https://github.com/nativemind/flutter_llama'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'NativeMind' => 'licensing@nativemind.net' }
  s.source           = { :path => '.' }
  
  # Include Swift/ObjC++ files and headers
  s.source_files = 'Classes/**/*.{swift,h,m,mm}'
  
  # Public headers
  s.public_header_files = 'Classes/llama_cpp_bridge.h'
  
  # Resource bundle for Metal shaders
  s.resource_bundles = {
    'flutter_llama_resources' => ['../llama.cpp/ggml/src/ggml-metal/*.metal']
  }
  
  # Pre-built llama.cpp library path (we'll build it via script)
  s.preserve_paths = '../llama.cpp/**/*'
  
  # Build llama.cpp as part of pod install
  # Note: Libraries are pre-built and located in macos_libs/
  # Uncomment this to build from source:
  # s.prepare_command = <<-CMD
  #   set -e
  #   echo "=== Building llama.cpp for macOS ==="
  #   
  #   LLAMA_DIR="../llama.cpp"
  #   BUILD_DIR="llama_build_macos"
  #   
  #   rm -rf "${BUILD_DIR}"
  #   mkdir -p "${BUILD_DIR}"
  #   cd "${BUILD_DIR}"
  #   
  #   cmake "../${LLAMA_DIR}" \
  #     -DCMAKE_BUILD_TYPE=Release \
  #     -DGGML_METAL=ON \
  #     -DGGML_ACCELERATE=ON \
  #     -DGGML_METAL_EMBED_LIBRARY=ON \
  #     -DBUILD_SHARED_LIBS=OFF \
  #     -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  #     -DCMAKE_OSX_DEPLOYMENT_TARGET=10.15 \
  #     -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  #   
  #   cmake --build . --config Release -j$(sysctl -n hw.ncpu)
  #   
  #   # Create fat library directory
  #   mkdir -p ../macos_libs
  #   cp -f libllama.a ../macos_libs/
  #   cp -f ggml/src/libggml.a ../macos_libs/
  #   
  #   cd ..
  #   echo "=== llama.cpp built successfully ==="
  #   ls -lh macos_libs/
  # CMD
  
  # Vendored libraries
  s.vendored_libraries = 'macos_libs/*.a'
  
  # C++ settings
  s.library = 'c++'
  
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'GCC_ENABLE_CPP_EXCEPTIONS' => 'YES',
    'GCC_ENABLE_CPP_RTTI' => 'YES',
    'CLANG_WARN_DOCUMENTATION_COMMENTS' => 'NO',
    'GCC_WARN_INHIBIT_ALL_WARNINGS' => 'YES',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/../llama.cpp/include" "${PODS_TARGET_SRCROOT}/../llama.cpp/src" "${PODS_TARGET_SRCROOT}/../llama.cpp/ggml/include" "${PODS_TARGET_SRCROOT}/../llama.cpp/ggml/src" "${PODS_TARGET_SRCROOT}/../llama.cpp/ggml/src/ggml-cpu" "${PODS_TARGET_SRCROOT}/../llama.cpp/ggml/src/ggml-metal"',
    'USER_HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/../llama.cpp/include" "${PODS_TARGET_SRCROOT}/../llama.cpp/ggml/include"',
    'OTHER_LDFLAGS' => '$(inherited) -force_load "${PODS_TARGET_SRCROOT}/macos_libs/libllama.a" -force_load "${PODS_TARGET_SRCROOT}/macos_libs/libggml.a" -force_load "${PODS_TARGET_SRCROOT}/macos_libs/libggml-base.a" -force_load "${PODS_TARGET_SRCROOT}/macos_libs/libggml-cpu.a" -force_load "${PODS_TARGET_SRCROOT}/macos_libs/libggml-metal.a" -force_load "${PODS_TARGET_SRCROOT}/macos_libs/libggml-blas.a"'
  }
  
  # Frameworks for GPU acceleration and optimization (macOS)
  s.frameworks = 'Metal', 'MetalKit', 'MetalPerformanceShaders', 'Accelerate', 'Foundation'
  
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.swift_version = '5.0'
end
