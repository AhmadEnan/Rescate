#
# Flutter Llama Podspec - iOS plugin configuration with llama.cpp
#
Pod::Spec.new do |s|
  s.name             = 'flutter_llama'
  s.version          = '1.0.0'
  s.summary          = 'Flutter plugin for LLM inference with llama.cpp and GGUF models'
  s.description      = <<-DESC
Flutter plugin for running LLM inference with llama.cpp and GGUF models on iOS.
Supports GPU acceleration via Metal and CPU optimization via Accelerate framework.
                       DESC
  s.homepage         = 'https://github.com/nativemind/flutter_llama'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'NativeMind' => 'licensing@nativemind.net' }
  s.source           = { :path => '.' }
  
  # Source files
  s.source_files = 'Classes/**/*.{swift,h,m,mm}'
  s.public_header_files = 'Classes/**/*.h'
  
  # Pre-built static libraries (embedded llama.cpp)
  s.vendored_libraries = 'ios_libs/*.a'
  
  # Preserve llama.cpp headers
  s.preserve_paths = '../llama.cpp/include/**/*', '../llama.cpp/ggml/include/**/*'
  
  # C++ settings
  s.library = 'c++'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'GCC_ENABLE_CPP_EXCEPTIONS' => 'YES',
    'GCC_ENABLE_CPP_RTTI' => 'YES',
    'CLANG_WARN_DOCUMENTATION_COMMENTS' => 'NO',
    'GCC_WARN_INHIBIT_ALL_WARNINGS' => 'YES',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/../llama.cpp/include" "${PODS_TARGET_SRCROOT}/../llama.cpp/ggml/include"',
    'OTHER_LDFLAGS' => '$(inherited) -force_load "${PODS_TARGET_SRCROOT}/ios_libs/libllama.a" -force_load "${PODS_TARGET_SRCROOT}/ios_libs/libggml.a" -force_load "${PODS_TARGET_SRCROOT}/ios_libs/libggml-base.a" -force_load "${PODS_TARGET_SRCROOT}/ios_libs/libggml-cpu.a" -force_load "${PODS_TARGET_SRCROOT}/ios_libs/libggml-metal.a" -force_load "${PODS_TARGET_SRCROOT}/ios_libs/libggml-blas.a"'
  }
  
  # Frameworks for GPU acceleration and optimization
  s.frameworks = 'Metal', 'MetalKit', 'MetalPerformanceShaders', 'Accelerate'
  
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
end
