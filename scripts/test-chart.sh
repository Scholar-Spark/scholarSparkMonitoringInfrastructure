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

echo "🔧 Setting up test environment..."

# Create kind cluster if it doesn't exist
if ! kind get clusters | grep -q "chart-testing"; then
    echo "Creating kind cluster..."
    kind create cluster --name chart-testing
else
    echo "Using existing kind cluster..."
fi

# Set kubectl context
kubectl cluster-info --context kind-chart-testing

echo "🔄 Installing chart..."
# Create namespace
kubectl create namespace test-infra --dry-run=client -o yaml | kubectl apply -f -

# Install/upgrade chart
helm upgrade --install shared-infra ./charts/shared-infra \
    --namespace test-infra \
    --wait \
    --timeout 5m

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