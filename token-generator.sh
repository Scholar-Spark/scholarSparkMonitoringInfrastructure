#!/bin/bash
# interactive-helm-setup.sh

echo "🚀 Setting up Helm registry authentication"

# Check and install dependencies
for cmd in gh helm jq; do
    if ! command -v $cmd &> /dev/null; then
        echo "📦 $cmd is not installed. Attempting to install..."
        
        case $cmd in
            gh)
                if command -v brew &> /dev/null; then
                    brew install gh
                elif command -v apt-get &> /dev/null; then
                    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
                    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
                    sudo apt update
                    sudo apt install gh
                else
                    echo "❌ Could not install gh. Please install manually: https://github.com/cli/cli#installation"
                    exit 1
                fi
                ;;
            helm)
                if command -v brew &> /dev/null; then
                    brew install helm
                elif command -v apt-get &> /dev/null; then
                    curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
                    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
                    sudo apt update
                    sudo apt install helm
                else
                    echo "❌ Could not install helm. Please install manually: https://helm.sh/docs/intro/install/"
                    exit 1
                fi
                ;;
            jq)
                if command -v brew &> /dev/null; then
                    brew install jq
                elif command -v apt-get &> /dev/null; then
                    sudo apt update
                    sudo apt install -y jq
                elif command -v dnf &> /dev/null; then
                    sudo dnf install -y jq
                elif command -v pacman &> /dev/null; then
                    sudo pacman -S --noconfirm jq
                elif command -v yum &> /dev/null; then
                    sudo yum install -y jq
                else
                    echo "❌ No supported package manager found (tried: brew, apt-get, dnf, pacman, yum)"
                    echo "📋 Your system info:"
                    echo "OS: $(uname -s)"
                    echo "Distribution: $(cat /etc/*release 2>/dev/null | grep -E '^(NAME|VERSION)=' || echo 'Unknown')"
                    echo "❌ Could not install jq. Please install manually: https://stedolan.github.io/jq/download/"
                    exit 1
                fi
                ;;
        esac
        
        # Verify installation
        if ! command -v $cmd &> /dev/null; then
            echo "❌ Failed to install $cmd"
            exit 1
        fi
        echo "✅ Successfully installed $cmd"
    fi
done

# GitHub login
if ! gh auth status &> /dev/null; then
    echo "📝 Please login to GitHub..."
    
    # Detect environment and choose best auth method
    if [[ "$OSTYPE" == "darwin"* ]] || [ -n "$DISPLAY" ]; then
        # GUI environment (macOS or Linux with DISPLAY)
        echo "🌐 Opening browser for authentication..."
        BROWSER_CMD=""
        if command -v google-chrome &> /dev/null; then
            BROWSER_CMD="google-chrome"
        elif command -v firefox &> /dev/null; then
            BROWSER_CMD="firefox"
        fi
        
        if [ ! -z "$BROWSER_CMD" ]; then
            # Set the default browser temporarily
            export BROWSER="$BROWSER_CMD"
        fi
        
        gh auth login --git-protocol ssh --web
    else
        # No GUI environment, use manual mode
        echo "ℹ️ Using manual authentication method..."
        echo "📋 Please visit https://github.com/login/device in your browser"
        gh auth login --git-protocol ssh --web
    fi
    
    # Check authentication status
    if [ $? -ne 0 ]; then
        echo "❌ Authentication failed"
        exit 1
    fi
    
    echo "✨ Authentication successful!"
fi

# Get username
GITHUB_USER=$(gh api user | jq -r .login)
echo "👋 Hello, $GITHUB_USER!"

# Create token
echo "🔑 Creating new GitHub token..."
# Create a new token with the required scopes using the new syntax
TOKEN=$(gh auth token)

if [ ! -z "$TOKEN" ]; then
    # Login to helm registry
    echo "🔄 Logging into Helm registry..."
    if helm registry login ghcr.io -u $GITHUB_USER -p $TOKEN; then
        echo "✅ Successfully logged into Helm registry!"
        
        # Ask if they want to store the token
        read -p "Would you like to store the token securely? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                security add-generic-password -a "$USER" -s "helm-registry-token" -w "$TOKEN"
                echo "🔐 Token stored in Keychain"
            else
                mkdir -p ~/.helm-auth
                echo "$TOKEN" > ~/.helm-auth/token
                chmod 600 ~/.helm-auth/token
                echo "🔐 Token stored in ~/.helm-auth/token"
            fi
        fi
    else
        echo "❌ Failed to login to Helm registry"
        exit 1
    fi
else
    echo "❌ Failed to create token"
    exit 1
fi

echo "🎉 Setup complete!"