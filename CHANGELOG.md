# Changelog

## [0.1.6] - 2024-01-09
### Fixed
- Fixed Loki configuration causing CrashLoopBackOff
- Added cleanup for stuck Helm releases
- Improved error handling and diagnostics

## [0.1.5] - 2024-01-09
### Fixed
- Corrected Loki storage configuration format
- Removed invalid tsdb reference
- Added proper boltdb_shipper configuration

## [0.1.3] - 2024-01-09
### Fixed
- Fixed Grafana plugin registration issues
- Added proper plugin configuration
- Configured proper paths and server settings

## [0.1.2] - 2024-01-08
### Fixed
- Fixed Loki storage configuration format for tsdb and filesystem paths

## [0.1.1] - 2024-01-08
### Fixed
- Updated Loki configuration to use tsdb and schema v13
- Fixed structured metadata configuration issues

## [0.1.0] - Initial Release
### Added
- Initial chart setup with Grafana, Tempo, and Loki 