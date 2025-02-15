# Changelog

## [0.1.15] - 2024-02-15

### Added

- Added default ServiceAccount for shared infrastructure components
- Added RBAC configuration for Vault authentication
- Added ClusterRole and ClusterRoleBinding for service-wide permissions

### Fixed

- Fixed missing Vault ServiceAccount configuration
- Fixed service account authentication setup for Vault
- Fixed selector configuration in Vault service definition

### Changed

- Improved service account management for cross-service authentication
- Updated Vault configuration to support standardized service authentication
- Enhanced RBAC permissions structure for platform-wide access

## [0.1.11] - 2024-01-10

### Fixed

- Added missing Helm labels to all resources
- Fixed label consistency across deployments
- Updated helper template with complete label set
- Improved resource tracking and management

## [0.1.10] - 2024-01-10

### Fixed

- Added missing Tempo ConfigMap configuration
- Fixed Tempo deployment dependency issues

## [0.1.9] - 2024-01-10

### Fixed

- Fixed missing ConfigMap dependency validation in test script
- Added comprehensive resource dependency checks
- Improved error handling and validation in test script
- Added prerequisite checks for required tools

## [0.1.8] - 2024-01-10

### Changed

- Refactored test script to be more generic and maintainable
- Improved template validation process
- Added Kubernetes schema validation for templates
- Added checks for common template issues
- Removed hardcoded component checks for better maintainability

## [0.1.7] - 2024-01-10

### Added

- Enhanced test script with improved deployment verification
- Added pre-pull function for container images
- Added comprehensive pod readiness checks
- Improved final health check verification
- Added clear success/failure messaging for test results

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
