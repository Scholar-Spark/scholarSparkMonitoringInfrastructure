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

## Accessing Services

| Service  | URL                     |
|----------|-------------------------|
| Grafana  | http://localhost:3000  |
| Tempo    | http://localhost:3200  |
| Loki     | http://localhost:3100  |