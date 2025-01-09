#!/bin/bash
set -e

echo "🔧 Checking dependencies..."

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="darwin"
    PACKAGE_MANAGER="brew"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
    # Detect Linux distribution
    if [ -f /etc/debian_version ]; then
        PACKAGE_MANAGER="apt"
    elif [ -f /etc/redhat-release ]; then
        PACKAGE_MANAGER="yum"
    elif [ -f /etc/arch-release ]; then
        PACKAGE_MANAGER="pacman"
    else
        echo "❌ Unsupported Linux distribution"
        exit 1
    fi
else
    echo "❌ Unsupported operating system: $OSTYPE"
    exit 1
fi

# Install package manager if needed (for macOS)
if [[ "$OS" == "darwin" && ! $(command -v brew) ]]; then
    echo "📦 Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Function to install dependencies
install_dependency() {
    local tool=$1
    local install_cmd=$2
    local verify_cmd=$3

    echo "📦 Installing $tool..."
    eval "$install_cmd"
    
    # Verify installation
    if ! eval "$verify_cmd"; then
        echo "❌ Failed to install $tool"
        exit 1
    fi
    echo "✅ Successfully installed $tool"
}

# Check and install dependencies
check_dependency() {
    local tool=$1
    if ! command -v "$tool" &> /dev/null; then
        echo "⚠️ $tool not found. Installing..."
        case $tool in
            kubectl)
                case $PACKAGE_MANAGER in
                    brew)
                        install_dependency "kubectl" "brew install kubectl" "kubectl version --client"
                        ;;
                    apt)
                        install_dependency "kubectl" "sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl && \
                            curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg && \
                            echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee /etc/apt/sources.list.d/kubernetes.list && \
                            sudo apt-get update && sudo apt-get install -y kubectl" "kubectl version --client"
                        ;;
                    yum)
                        install_dependency "kubectl" "curl -LO https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl && \
                            sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl" "kubectl version --client"
                        ;;
                    pacman)
                        install_dependency "kubectl" "sudo pacman -Sy kubectl" "kubectl version --client"
                        ;;
                esac
                ;;
            helm)
                case $PACKAGE_MANAGER in
                    brew)
                        install_dependency "helm" "brew install helm" "helm version"
                        ;;
                    apt)
                        install_dependency "helm" "curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null && \
                            echo 'deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main' | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list && \
                            sudo apt-get update && sudo apt-get install -y helm" "helm version"
                        ;;
                    yum)
                        install_dependency "helm" "curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \
                            chmod 700 get_helm.sh && ./get_helm.sh" "helm version"
                        ;;
                    pacman)
                        install_dependency "helm" "sudo pacman -Sy helm" "helm version"
                        ;;
                esac
                ;;
            kind)
                case $OS in
                    darwin)
                        install_dependency "kind" "brew install kind" "kind version"
                        ;;
                    linux)
                        install_dependency "kind" "curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64 && \
                            chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind" "kind version"
                        ;;
                esac
                ;;
        esac
    else
        echo "✅ Found $tool"
    fi
}

# Check for required tools
check_dependency "kubectl"
check_dependency "helm"
check_dependency "kind"

# Add this function after the dependency checks and before creating the cluster
check_cluster_health() {
    local cluster_name=$1
    echo "🔍 Checking cluster health..."
    
    # Try to get cluster info
    if ! kubectl cluster-info --context "kind-$cluster_name" &> /dev/null; then
        echo "⚠️ Existing cluster is not responding, cleaning up..."
        kind delete cluster --name "$cluster_name"
        return 1
    fi
    return 0
}

echo "🔧 Setting up test environment..."

# Check if cluster exists and is healthy
if kind get clusters | grep -q "chart-testing"; then
    if ! check_cluster_health "chart-testing"; then
        echo "Creating new cluster..."
        kind create cluster --name chart-testing
    else
        echo "Using existing healthy cluster..."
    fi
else
    echo "Creating new cluster..."
    kind create cluster --name chart-testing
fi

# Verify cluster is ready
echo "⏳ Waiting for cluster to be ready..."
for i in {1..30}; do
    if kubectl cluster-info &> /dev/null; then
        echo "✅ Cluster is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "❌ Cluster failed to start"
        exit 1
    fi
    echo "⏳ Waiting for cluster to be ready... ($i/30)"
    sleep 2
done

# Set kubectl context
kubectl cluster-info --context kind-chart-testing

echo "🔄 Installing chart..."
# Create namespace
kubectl create namespace test-infra --dry-run=client -o yaml | kubectl apply -f -

# Install/upgrade chart with longer timeout and debug info
echo "📦 Installing chart (this may take a few minutes)..."
echo "🧹 Cleaning up any stuck releases..."
kubectl delete secret -n test-infra --field-selector type=helm.sh/release.v1 || true

cleanup_previous_install() {
    echo "🧹 Cleaning up previous installation..."
    
    # Delete deployments first
    kubectl delete deployment -n test-infra --all --timeout=2m || true
    
    # Delete the release secret
    kubectl delete secret -n test-infra --field-selector type=helm.sh/release.v1 || true
    
    # Wait for resources to be deleted
    echo "⏳ Waiting for resources to be cleaned up..."
    kubectl wait --for=delete deployment --all -n test-infra --timeout=2m || true
    
    # Force delete if still exists
    kubectl delete deployment -n test-infra --all --force --grace-period=0 || true
}

# Add this before helm upgrade
cleanup_previous_install

helm upgrade --install shared-infra ./charts/shared-infra \
    --namespace test-infra \
    --wait \
    --timeout 10m \
    --debug \
    --atomic || {
        echo "❌ Chart installation failed. Checking pod status..."
        kubectl get pods -n test-infra
        echo "📝 Checking pod events..."
        kubectl get events -n test-infra --sort-by='.lastTimestamp'
        exit 1
    }

# Add readiness check
echo "⏳ Waiting for pods to be ready..."
kubectl wait --for=condition=ready pods --all -n test-infra --timeout=5m || {
    echo "❌ Pods failed to become ready. Checking status..."
    kubectl get pods -n test-infra
    echo "📝 Checking pod events..."
    kubectl get events -n test-infra --sort-by='.lastTimestamp'
    exit 1
}

echo "🔍 Validating deployment..."
# Check pod status
kubectl get pods -n test-infra -w &
WATCH_PID=$!

# Wait for pods to be ready
sleep 30
kill $WATCH_PID

# Validate services
echo "📝 Checking Loki logs..."
kubectl logs -n test-infra deployment/loki --tail=50

echo "📝 Checking Tempo logs..."
kubectl logs -n test-infra deployment/tempo --tail=50

echo "📝 Checking Grafana logs..."
kubectl logs -n test-infra deployment/grafana --tail=50

# Add after cluster is ready
echo "🔑 Getting dashboard access token..."
kubectl -n test-infra create token admin-user

# Optional cleanup
read -p "❓ Do you want to cleanup the test environment? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo "🧹 Cleaning up..."
    helm uninstall shared-infra -n test-infra
    kubectl delete namespace test-infra
    kind delete cluster --name chart-testing
fi

# After cluster creation, add:
echo "🔑 Setting up API server access..."

# Get the client certificate data
CLIENT_CERT=$(kind get kubeconfig --name chart-testing | grep client-certificate-data | awk '{print $2}')
CLIENT_KEY=$(kind get kubeconfig --name chart-testing | grep client-key-data | awk '{print $2}')
CA_CERT=$(kind get kubeconfig --name chart-testing | grep certificate-authority-data | awk '{print $2}')

# Create a directory for certificates
mkdir -p ~/.kind/certs
echo $CLIENT_CERT | base64 -d > ~/.kind/certs/client.crt
echo $CLIENT_KEY | base64 -d > ~/.kind/certs/client.key
echo $CA_CERT | base64 -d > ~/.kind/certs/ca.crt

echo "
🌐 To access the Kubernetes API directly:

Use these certificates with curl:
curl --cert ~/.kind/certs/client.crt \\
     --key ~/.kind/certs/client.key \\
     --cacert ~/.kind/certs/ca.crt \\
     https://127.0.0.1:46429/api/v1/namespaces

Or use this kubectl command:
kubectl --certificate-authority=~/.kind/certs/ca.crt \\
        --client-certificate=~/.kind/certs/client.crt \\
        --client-key=~/.kind/certs/client.key \\
        --server=https://127.0.0.1:46429 \\
        get pods -A

For browser access, you can:
1. Run: kubectl proxy
2. Visit: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
"

# Clean up function
cleanup_certs() {
    echo "🧹 Cleaning up certificates..."
    rm -rf ~/.kind/certs
}

# Add cleanup_certs to your existing cleanup section 

# Add after helm upgrade command
if [ $? -ne 0 ]; then
    echo "❌ Chart installation failed. Getting detailed diagnostics..."
    
    echo "📝 Checking Loki logs..."
    kubectl logs -n test-infra deployment/loki --tail=50
    
    echo "📝 Checking Tempo logs..."
    kubectl logs -n test-infra deployment/tempo --tail=50
    
    echo "📝 Checking Grafana logs..."
    kubectl logs -n test-infra deployment/grafana --tail=50
    
    echo "📝 Checking pod status..."
    kubectl get pods -n test-infra
    
    echo "📝 Checking events..."
    kubectl get events -n test-infra --sort-by='.lastTimestamp'
    
    exit 1
fi 

# Add this function after the cluster setup
check_loki_status() {
    echo "🔍 Checking Loki status..."
    
    # Get pod name
    LOKI_POD=$(kubectl get pod -n test-infra -l app=loki -o jsonpath='{.items[0].metadata.name}')
    
    echo "📝 Loki Pod Status:"
    kubectl describe pod -n test-infra $LOKI_POD
    
    echo "📝 Loki Logs:"
    kubectl logs -n test-infra $LOKI_POD --previous
    kubectl logs -n test-infra $LOKI_POD
    
    echo "📝 Checking Loki ConfigMap:"
    kubectl get configmap -n test-infra loki-config -o yaml
    
    echo "📝 Checking Events:"
    kubectl get events -n test-infra --sort-by='.lastTimestamp' | grep Loki
}

# Add this call after helm upgrade
if ! kubectl rollout status deployment/loki -n test-infra --timeout=2m; then
    echo "❌ Loki deployment failed to roll out"
    check_loki_status
    exit 1
fi 

# Add after cluster creation
echo "⏳ Waiting for nodes to be ready..."
kubectl wait --for=condition=ready nodes --all --timeout=2m || {
    echo "❌ Nodes failed to become ready"
    kubectl get nodes
    kubectl describe nodes
    exit 1
} 