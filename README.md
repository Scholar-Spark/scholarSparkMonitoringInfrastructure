# Scholar Spark Shared Infrastructure

This repository contains the shared infrastructure Helm chart for Scholar Spark development environments.

## Components

- **Grafana**: Visualization and dashboards
- **Tempo**: Distributed tracing backend
- **Loki**: Log aggregation system

## Usage

### Add the repository:
```bash
helm repo add scholar-spark https://scholar-spark.github.io/shared-infrastructure
helm repo update
```

## Configuration

See `values.yaml` for configuration options.

## Local Development

1. Install dependencies:
```bash
helm dependency update charts/shared-infra
```

2. Install chart:
```bash
helm install shared-infra charts/shared-infra
```

## Release Process

### Making Changes
1. Create a new branch for your changes
2. Make your modifications to the chart
3. Update the CHANGELOG.md with your changes under an "Unreleased" section:
   ```markdown
   ## [Unreleased]
   ### Added/Changed/Fixed
   - Description of your change
   ```

### Releasing a New Version
1. Determine the type of version bump needed:
   - Patch (0.1.0 -> 0.1.1): Bug fixes
   - Minor (0.1.0 -> 0.2.0): New features, backward compatible
   - Major (0.1.0 -> 2.0.0): Breaking changes

2. Update the following files:
   - `charts/shared-infra/Chart.yaml`: Increment the `version` field
   - `CHANGELOG.md`: Change [Unreleased] to the new version number and date

3. Create a PR with your changes
   - Title format: `release: bump version to vX.Y.Z`
   - Include all changes in the PR description

4. Once merged to master, the GitHub Action will:
   - Package the chart
   - Push to GHCR
   - Create a new release