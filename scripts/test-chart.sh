#!/bin/bash
set -e

echo "🔧 Starting Chart Template Validation"
echo "=================================="

# Check prerequisites
check_prerequisites() {
    echo "📋 Checking prerequisites..."
    for cmd in kind kubectl helm yq; do
        if ! command -v $cmd &> /dev/null; then
            echo "❌ '$cmd' is not installed. Please install it first."
            exit 1
        fi
    done
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
        echo "❌ Failed to create validation cluster"
        exit 1
    fi
}

# Install required CRDs
install_crds() {
    echo "📋 Installing required CRDs..."
    # Install Gateway API CRDs
    kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v0.8.0/config/crd/standard/gateway.networking.k8s.io_gateways.yaml
}

# Validate templates and dependencies
validate_templates() {
    echo -e "\n📋 Step 1: Validating chart structure..."
    if ! helm lint charts/shared-infra; then
        echo "❌ Chart structure validation failed"
        exit 1
    fi

    echo -e "\n📋 Step 2: Validating template rendering..."
    if ! helm template test-release charts/shared-infra --debug > /tmp/rendered-templates.yaml; then
        echo "❌ Template rendering failed"
        exit 1
    fi

    echo -e "\n📋 Step 3: Validating Kubernetes schema..."
    if ! kubectl create --dry-run=client -f /tmp/rendered-templates.yaml; then
        echo "❌ Template validation failed"
        exit 1
    fi
}

# Check for resource dependencies
check_dependencies() {
    echo -e "\n📋 Step 4: Checking resource dependencies..."
    
    # Get all deployments
    echo "  ▪️ Checking all deployments for dependencies..."
    
    # First check if we have any deployments
    deployments=$(grep -l "kind: Deployment" charts/shared-infra/templates/**/*.yaml || true)
    if [ -z "$deployments" ]; then
        echo "    No deployments found in templates"
        return 0
    fi
    
    # Process each deployment file
    for deployment_file in $deployments; do
        deployment_name=$(grep -A1 "metadata:" "$deployment_file" | grep "name:" | awk '{print $2}')
        echo "    Checking deployment: $deployment_name"
        
        # Check ConfigMap dependencies
        while IFS= read -r line; do
            if [[ $line =~ "configMap:" ]]; then
                # Get the next line which should contain the name
                read -r name_line
                configmap_name=$(echo "$name_line" | grep "name:" | awk '{print $2}')
                if [ ! -z "$configmap_name" ]; then
                    echo "      Checking ConfigMap: $configmap_name"
                    if ! find charts/shared-infra/templates -type f -exec grep -l "kind: ConfigMap" {} \; | xargs grep -l "name: $configmap_name" > /dev/null; then
                        echo "❌ ConfigMap '$configmap_name' is referenced in deployment '$deployment_name' but not defined"
                        exit 1
                    fi
                fi
            fi
        done < "$deployment_file"
    done
}

# Check for common template issues
check_template_issues() {
    echo -e "\n📋 Step 5: Checking for common template issues..."
    validation_failed=0

    # Check for unreplaced template values
    if grep -q "{{ .Release." /tmp/rendered-templates.yaml; then
        echo "❌ Found unreplaced Release template values"
        validation_failed=1
    fi

    # Check for required labels in all resources
    if ! grep -q "helm.sh/chart:" /tmp/rendered-templates.yaml; then
        echo "❌ Missing required Helm chart labels"
        validation_failed=1
    fi

    # Check for app labels
    if ! grep -q "app.kubernetes.io/managed-by:" /tmp/rendered-templates.yaml; then
        echo "❌ Missing required Kubernetes app labels"
        validation_failed=1
    fi

    if [[ $validation_failed -eq 1 ]]; then
        echo "❌ Template validation failed - see above errors"
        exit 1
    fi
}

# Main execution
check_prerequisites
cleanup_existing
create_cluster
install_crds
validate_templates
check_dependencies
check_template_issues

echo -e "\n✅ All validations passed successfully!" 