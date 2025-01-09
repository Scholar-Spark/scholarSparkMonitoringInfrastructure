#!/bin/bash
set -e

echo "🔧 Starting Chart Template Validation"
echo "=================================="

# Check prerequisites
check_prerequisites() {
    echo "📋 Checking prerequisites..."
    
    # Check if kind is installed
    if ! command -v kind &> /dev/null; then
        echo "❌ 'kind' is not installed. Please install it first:"
        echo "  - Mac: brew install kind"
        echo "  - Linux: curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64 && chmod +x ./kind && sudo mv ./kind /usr/local/bin/"
        exit 1
    fi

    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        echo "❌ 'kubectl' is not installed. Please install it first."
        exit 1
    fi

    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        echo "❌ 'helm' is not installed. Please install it first."
        exit 1
    fi

    # Check if yq is installed
    if ! command -v yq &> /dev/null; then
        echo "❌ 'yq' is not installed. Please install it first:"
        echo "  - Mac: brew install yq"
        echo "  - Linux: sudo apt-get install yq"
        exit 1
    fi

    echo "✅ All prerequisites are installed"
}

# Clean up any existing cluster
cleanup_existing() {
    echo "📋 Cleaning up any existing test cluster..."
    kind delete cluster --name template-validator &> /dev/null || true
}

# Create the cluster with proper error handling
create_cluster() {
    echo "📋 Creating temporary validation cluster..."
    if ! kind create cluster --name template-validator --quiet; then
        echo "❌ Failed to create validation cluster. Error details:"
        kind create cluster --name template-validator
        exit 1
    fi
}

# Run the checks
check_prerequisites
cleanup_existing
create_cluster

# Step 1: Validate chart structure and dependencies
echo -e "\n📋 Step 1: Validating chart structure..."
if ! helm lint charts/shared-infra; then
    echo "❌ Chart structure validation failed"
    kind delete cluster --name template-validator
    exit 1
fi
echo "✅ Chart structure is valid"

# Step 2: Test template rendering
echo -e "\n📋 Step 2: Validating template rendering..."
if ! helm template test-release charts/shared-infra > /tmp/rendered-templates.yaml; then
    echo "❌ Template rendering failed"
    kind delete cluster --name template-validator
    exit 1
fi
echo "✅ Templates render successfully"

# Step 3: Validate rendered templates against k8s schema
echo -e "\n📋 Step 3: Validating Kubernetes schema..."
if ! kubectl create --dry-run=client -f /tmp/rendered-templates.yaml; then
    echo "❌ Template validation failed - invalid Kubernetes resources detected"
    kind delete cluster --name template-validator
    exit 1
fi
echo "✅ All templates are valid Kubernetes resources"

# Step 4: Check for common template issues
echo -e "\n📋 Step 4: Checking for common template issues..."
validation_failed=0

# Check for required metadata fields
if grep -q "name: {{ .Release.Name }}" /tmp/rendered-templates.yaml; then
    echo "❌ Found unreplaced Release.Name template values"
    validation_failed=1
fi

if grep -q "namespace: {{ .Release.Namespace }}" /tmp/rendered-templates.yaml; then
    echo "❌ Found unreplaced Release.Namespace template values"
    validation_failed=1
fi

# Check for valid label selectors in deployments/services
if ! grep -q "matchLabels:" /tmp/rendered-templates.yaml; then
    echo "❌ Missing matchLabels in deployments"
    validation_failed=1
fi

if [[ $validation_failed -eq 1 ]]; then
    echo "❌ Template validation failed - see above errors"
    kind delete cluster --name template-validator
    exit 1
fi

echo "✅ No common template issues found"

# Add after template rendering validation
echo -e "\n📋 Step 3a: Validating resource dependencies..."
echo "  ▪️ Checking resource dependencies..."

# First, validate the template rendering
if ! helm template test-release charts/shared-infra > /tmp/rendered-templates.yaml; then
    echo "❌ Failed to render templates"
    exit 1
fi

# Function to check for ConfigMap dependencies
check_configmap_dependencies() {
    echo "  ▪️ Checking ConfigMap dependencies..."
    
    # Use kubectl to validate the templates and extract information
    if ! kubectl create --dry-run=client -f /tmp/rendered-templates.yaml > /dev/null; then
        echo "❌ Invalid resource definitions found"
        exit 1
    fi

    # Get deployments and their ConfigMap dependencies
    while IFS= read -r line; do
        if [[ $line =~ "configMap" ]]; then
            deployment=$(echo "$line" | cut -d':' -f1)
            configmap=$(echo "$line" | grep -o 'name: [^ ]*' | cut -d' ' -f2)
            
            echo "    Checking ConfigMap '$configmap' for deployment '$deployment'"
            
            # Check if ConfigMap exists in templates
            if ! grep -q "kind: ConfigMap" /tmp/rendered-templates.yaml || \
               ! grep -q "name: $configmap" /tmp/rendered-templates.yaml; then
                echo "❌ ConfigMap '$configmap' is referenced in '$deployment' but not defined"
                exit 1
            fi
        fi
    done < <(grep -r "configMap:" /tmp/rendered-templates.yaml)
}

# Run the checks
check_configmap_dependencies

echo "✅ All resource dependencies are properly defined"

# Cleanup
echo -e "\n🧹 Cleaning up..."
kind delete cluster --name template-validator

echo -e "\n==============================================="
echo "✅ SUCCESS: All templates validated successfully! ✅"
echo "===============================================" 