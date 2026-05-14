# Changelog

All notable changes to this project will be documented in this file.

## [1.1.2] - 2025-01-28

### Changed
- Optimized package size by excluding debug symbols and build artifacts
- Added comprehensive .pubignore to reduce package size from 234 MB to 20 MB

## [1.1.1] - 2025-01-28

### Fixed
- Fixed package dependencies: moved `http`, `path`, and `path_provider` from `dev_dependencies` to `dependencies` for proper pub.dev publishing
- Resolved package validation errors for service dependencies

### Changed
- Updated package structure for better dependency management

## [1.0.1] - 2025-01-27

### Fixed
- Fixed macOS library build artifacts for pub.dev publishing
- Removed unused imports in multimodal implementation
- Removed unnecessary library name declaration
- Improved .pubignore to reduce package size

### Changed
- Updated package metadata

## [1.0.0] - 2025-01-27

### Added
- Initial stable release
- Full support for llama.cpp GGUF models on iOS and macOS
- GPU acceleration via Metal
- CPU optimization via Accelerate framework
- Streaming text generation
- Batch processing support
- Multiple model format support
- Comprehensive documentation
- Example application with demos
- Integration tests

## [0.1.1] - 2025-01-26

### Added
- Multimodal support (vision models)
- Enhanced model loading
- Improved error handling

## [0.1.0] - 2025-01-25

### Added
- Initial beta release
- Basic llama.cpp integration
- iOS and macOS platform support
- Model loading and text generation
- Basic configuration options

