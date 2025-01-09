#!/bin/bash
set -e

echo "🔧 Starting Chart Template Validation"
echo "=================================="

# Create temporary kind cluster for schema validation
echo "📋 Creating temporary validation cluster..."
if ! kind create cluster --name template-validator --quiet; then
    echo "❌ Failed to create validation cluster"
    exit 1
fi

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

# Cleanup
echo -e "\n🧹 Cleaning up..."
kind delete cluster --name template-validator

echo -e "\n==============================================="
echo "✅ SUCCESS: All templates validated successfully! ✅"
echo "===============================================" 