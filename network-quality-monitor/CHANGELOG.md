# Changelog

All notable changes to the Network Quality Monitor project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2025-05-12

### Added
- Project restructuring with professional folder organization
- Improved modular architecture for better code organization
- Comprehensive documentation in the docs directory
- Enhanced installation and configuration guides

### Changed
- Refactored main script into modular components
- Improved configuration file structure and locations
- Better error handling across all modules

### Fixed
- Various minor bug fixes and improvements

## [1.1.0] - 2025-05-01

### Added
- Slack notification integration
- Offline alert queueing system
- Enhanced connectivity detection
- Grace period for connectivity restoration

### Changed
- Improved jitter calculation using RFC 3550 method
- More accurate MOS and R-factor calculations
- Better error handling for lost connections

### Fixed
- Issue with false alerts during network transitions
- Process cleanup for proper termination

## [1.0.0] - 2025-04-15

### Added
- Initial release
- Basic network monitoring with fping
- RTT, jitter, TTL and packet loss monitoring
- Color-coded console output
- Multiple target support
- DOWN and UP alerts