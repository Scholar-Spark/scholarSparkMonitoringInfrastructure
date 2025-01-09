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

# Add this function
pre_pull_images() {
    echo "📥 Pre-pulling images..."
    
    # Pull images first
    echo "Pulling Loki image..."
    docker pull grafana/loki:2.9.0
    
    echo "Pulling Tempo image..."
    docker pull grafana/tempo:2.3.0
    
    echo "Pulling Grafana image..."
    docker pull grafana/grafana:10.2.0
    
    # Load images into kind
    echo "Loading images into kind cluster..."
    kind load docker-image grafana/loki:2.9.0 --name chart-testing
    kind load docker-image grafana/tempo:2.3.0 --name chart-testing
    kind load docker-image grafana/grafana:10.2.0 --name chart-testing
}

# Add this function
wait_for_pods() {
    local namespace=$1
    local timeout=$2
    local interval=5
    local elapsed=0

    echo "⏳ Waiting for pods in namespace $namespace to be ready..."
    while true; do
        if [ $elapsed -gt $timeout ]; then
            echo "❌ Timeout waiting for pods to be ready"
            kubectl get pods -n $namespace
            kubectl describe pods -n $namespace
            return 1
        fi

        if kubectl get pods -n $namespace | grep -q "ContainerCreating\|PodInitializing"; then
            echo "⏳ Pods still initializing... ($elapsed/${timeout}s)"
            sleep $interval
            elapsed=$((elapsed + interval))
            continue
        fi

        if kubectl get pods -n $namespace | grep -q "Error\|CrashLoopBackOff"; then
            echo "❌ Pod(s) in error state"
            kubectl get pods -n $namespace
            kubectl describe pods -n $namespace
            return 1
        fi

        if kubectl get pods -n $namespace | grep -v "Running\|Completed" | grep -q .; then
            echo "⏳ Waiting for pods to be ready... ($elapsed/${timeout}s)"
            sleep $interval
            elapsed=$((elapsed + interval))
            continue
        fi

        echo "✅ All pods are ready!"
        return 0
    done
}

echo "🔧 Setting up test environment..."

# Create kind cluster if it doesn't exist
if ! kind get clusters | grep -q "chart-testing"; then
    echo "Creating kind cluster..."
    kind create cluster --name chart-testing
else
    echo "Using existing kind cluster..."
    # Add cleanup of existing deployments
    echo "🧹 Cleaning up existing deployments..."
    kubectl delete deployment,service,configmap,secret -n test-infra --all --ignore-not-found=true
    # Wait for resources to be deleted
    kubectl wait --for=delete deployment --all -n test-infra --timeout=2m || true
fi

# Pre-pull images
pre_pull_images

echo "⏳ Waiting for node to be ready..."
kubectl wait --for=condition=ready nodes --all --timeout=5m || {
    echo "❌ Node failed to become ready"
    kubectl get nodes -o wide
    kubectl describe nodes
    exit 1
}

echo "🔄 Installing chart..."
# Create namespace
kubectl create namespace test-infra --dry-run=client -o yaml | kubectl apply -f -

# Install/upgrade chart
helm upgrade --install shared-infra ./charts/shared-infra \
    --namespace test-infra \
    --wait \
    --timeout 10m \
    --atomic \
    --debug || {
        echo "❌ Chart installation failed. Getting diagnostics..."
        kubectl get pods -n test-infra -o wide
        kubectl get events -n test-infra --sort-by='.lastTimestamp'
        kubectl describe pods -n test-infra
        exit 1
    }

# Wait for pods to be ready
if ! wait_for_pods "test-infra" 300; then
    echo "❌ Pods failed to become ready"
    exit 1
fi

echo "✅ Installation complete!"
kubectl get pods -n test-infra 

verify_deployment() {
    local deployment=$1
    local namespace=$2
    local timeout=$3

    echo "🔍 Verifying deployment: $deployment"
    
    # Wait for deployment rollout
    if ! kubectl rollout status deployment/$deployment -n $namespace --timeout=$timeout; then
        echo "❌ Deployment $deployment failed to roll out"
        kubectl describe deployment $deployment -n $namespace
        kubectl get pods -n $namespace -l app=$deployment
        kubectl logs -n $namespace -l app=$deployment --previous
        return 1
    fi

    # Check pod status
    local pod=$(kubectl get pod -n $namespace -l app=$deployment -o jsonpath='{.items[0].metadata.name}')
    if [[ -z "$pod" ]]; then
        echo "❌ No pod found for deployment $deployment"
        return 1
    fi

    # Check pod logs
    echo "📝 Logs for $deployment:"
    kubectl logs $pod -n $namespace
}

# After helm install
echo "🔍 Verifying deployments..."
verify_deployment "grafana" "test-infra" "5m" || exit 1
verify_deployment "loki" "test-infra" "5m" || exit 1
verify_deployment "tempo" "test-infra" "5m" || exit 1

echo "✅ All deployments verified successfully!"

# Add final health check
echo "🔍 Performing final health check..."

# Check all pods are running
if ! kubectl get pods -n test-infra | grep -v "Running\|Completed" | grep -q .; then
    # Check all services are present
    if kubectl get services -n test-infra | grep -q "grafana\|loki\|tempo"; then
        # Check endpoints are available
        if kubectl get endpoints -n test-infra | grep -q "grafana\|loki\|tempo"; then
            echo "🎉 All systems operational!"
            echo "✨ Test completed successfully - all resources are healthy and running"
            echo ""
            echo "==============================================="
            echo "✅ SUCCESS: All tests passed successfully! ✅"
            echo "==============================================="
            exit 0
        fi
    fi
fi

echo "❌ Final health check failed - some resources are not in the expected state"
kubectl get all -n test-infra
exit 1 