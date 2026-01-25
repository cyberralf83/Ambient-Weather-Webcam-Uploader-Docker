#!/bin/bash

# GitHub Actions Docker Workflow Setup Script
# This script sets up GitHub Actions workflows for building and pushing Docker images
# Version: Updated 2026-01-03
# Source: https://github.com/cyberralf83/My-Github-Actions-Workflows

set -e

# Display version info
SCRIPT_VERSION="2026.01.03"
echo "======================================"
echo "Docker Workflow Setup v$SCRIPT_VERSION"
echo "======================================"
echo ""

# Check if we're in a git repository
if [ ! -d ".git" ]; then
    echo "❌ Error: Not in a git repository. Please run this from your repository root."
    exit 1
fi

# Get repository name for defaults
REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
echo "📁 Repository: $REPO_NAME"
echo ""

# Extract GitHub username from remote URL
GIT_REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
if [[ $GIT_REMOTE_URL =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
    REPO_OWNER="${BASH_REMATCH[1]}"
    CURRENT_REPO="${BASH_REMATCH[2]}"
    # Use ralf83 as default Docker Hub username (map cyberralf83 → ralf83)
    if [ "$REPO_OWNER" == "cyberralf83" ]; then
        DEFAULT_USERNAME="ralf83"
    else
        DEFAULT_USERNAME="$REPO_OWNER"
    fi
    echo "✅ Auto-detected: $REPO_OWNER/$CURRENT_REPO"
else
    echo "⚠️  Could not auto-detect GitHub repository"
    DEFAULT_USERNAME=""
fi

# Check for Docker Hub username in environment variables
if [ -n "$DOCKER_USERNAME" ]; then
    DEFAULT_USERNAME="$DOCKER_USERNAME"
    echo "ℹ️  Using DOCKER_USERNAME from environment: $DOCKER_USERNAME"
elif [ -n "$DOCKERHUB_USERNAME" ]; then
    DEFAULT_USERNAME="$DOCKERHUB_USERNAME"
    echo "ℹ️  Using DOCKERHUB_USERNAME from environment: $DOCKERHUB_USERNAME"
fi
echo ""

# Create .github/workflows directory
mkdir -p .github/workflows
echo "✅ Created .github/workflows directory"
echo ""

# Ask for workflow deployment type
echo "======================================"
echo "Workflow Deployment Type"
echo "======================================"
echo ""
echo "Choose your Docker CI/CD workflow setup:"
echo ""
echo "  A) Deploy via Centralized Workflow (Recommended)"
echo "     ✓ References external shared workflow repository"
echo "     ✓ Centralized updates across multiple repos"
echo "     ✓ Update once, apply everywhere"
echo "     ✓ Best for managing many repositories"
echo ""
echo "  B) Install Standalone Deployment (Static)"
echo "     ✓ All steps in one file (.github/workflows/ci.yml)"
echo "     ✓ Easy to understand and modify"
echo "     ✓ No external dependencies"
echo "     ✓ Can be manually triggered to rebuild anytime"
echo ""

ATTEMPT=1
while [ $ATTEMPT -le 2 ]; do
    read -p "Select deployment type [A/B] (default: A): " DEPLOYMENT_TYPE
    DEPLOYMENT_TYPE="${DEPLOYMENT_TYPE:-A}"
    DEPLOYMENT_TYPE=$(echo "$DEPLOYMENT_TYPE" | tr '[:lower:]' '[:upper:]')

    if [[ "$DEPLOYMENT_TYPE" != "A" && "$DEPLOYMENT_TYPE" != "B" ]]; then
        if [ $ATTEMPT -eq 2 ]; then
            echo "❌ Invalid choice. Please select A or B. Exiting."
            exit 1
        else
            echo "⚠️  Invalid choice. Please select A or B."
            ATTEMPT=$((ATTEMPT + 1))
        fi
    else
        break
    fi
done
echo ""

# Ask for remote workflow repo details (only for option A)
if [ "$DEPLOYMENT_TYPE" == "A" ]; then
    DEFAULT_WORKFLOWS_FULL="cyberralf83/My-Github-Actions-Workflows@main"
    read -p "🔗 Shared workflow repository (default: $DEFAULT_WORKFLOWS_FULL): " WORKFLOWS_FULL
    WORKFLOWS_FULL="${WORKFLOWS_FULL:-$DEFAULT_WORKFLOWS_FULL}"

    if [ -z "$WORKFLOWS_FULL" ]; then
        echo "❌ Workflow repository cannot be empty"
        exit 1
    fi

    # Parse repo and version (split by @)
    if [[ "$WORKFLOWS_FULL" == *"@"* ]]; then
        WORKFLOWS_REPO="${WORKFLOWS_FULL%@*}"
        WORKFLOWS_VERSION="${WORKFLOWS_FULL#*@}"
    else
        WORKFLOWS_REPO="$WORKFLOWS_FULL"
        WORKFLOWS_VERSION="main"
    fi

    echo "ℹ️  Using: $WORKFLOWS_REPO @ $WORKFLOWS_VERSION"
    echo ""
fi

# Ask for Docker Hub credentials
echo "======================================"
echo "Docker Hub Credentials"
echo "======================================"
echo ""

# Ask for Docker Hub username
ATTEMPT=1
while [ $ATTEMPT -le 2 ]; do
    if [ -n "$DEFAULT_USERNAME" ]; then
        read -p "🔐 Docker Hub username (default: $DEFAULT_USERNAME): " DOCKERHUB_USERNAME
        DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-$DEFAULT_USERNAME}"
    else
        read -p "🔐 Docker Hub username: " DOCKERHUB_USERNAME
    fi

    if [ -z "$DOCKERHUB_USERNAME" ]; then
        if [ $ATTEMPT -eq 2 ]; then
            echo "❌ Docker Hub username cannot be empty. Exiting."
            exit 1
        else
            echo "⚠️  Docker Hub username cannot be empty. Please try again."
            ATTEMPT=$((ATTEMPT + 1))
        fi
    else
        break
    fi
done

# Ask for Docker Hub token (check environment first)
echo "🔍 Checking for Docker token in environment..."
if [ -n "$DOCKER_TOKEN" ]; then
    DOCKERHUB_TOKEN="$DOCKER_TOKEN"
    echo "✅ Using DOCKER_TOKEN from environment"
elif [ -n "$DOCKERHUB_TOKEN" ]; then
    echo "✅ Using DOCKERHUB_TOKEN from environment"
else
    echo "ℹ️  No DOCKER_TOKEN or DOCKERHUB_TOKEN found in environment"
    ATTEMPT=1
    while [ $ATTEMPT -le 2 ]; do
        read -sp "🔑 Docker Hub access token (create at https://hub.docker.com/settings/security): " DOCKERHUB_TOKEN
        echo ""

        if [ -z "$DOCKERHUB_TOKEN" ]; then
            if [ $ATTEMPT -eq 2 ]; then
                echo "❌ Token cannot be empty. Exiting."
                exit 1
            else
                echo "⚠️  Token cannot be empty. Please try again."
                ATTEMPT=$((ATTEMPT + 1))
            fi
        else
            break
        fi
    done
fi

echo ""
echo "======================================"
echo "Docker Build Configuration"
echo "======================================"
echo ""

# Ask for Docker image name
DEFAULT_APP_NAME="$REPO_NAME"
echo "ℹ️  Note: Image name will be auto-converted to lowercase (Docker requirement)"
echo "ℹ️  Full image will be: $DOCKERHUB_USERNAME/$DEFAULT_APP_NAME"
echo ""
ATTEMPT=1
while [ $ATTEMPT -le 2 ]; do
    read -p "🐳 Docker image name (default: $DEFAULT_APP_NAME): " APP_NAME
    APP_NAME="${APP_NAME:-$DEFAULT_APP_NAME}"

    if [ -z "$APP_NAME" ]; then
        if [ $ATTEMPT -eq 2 ]; then
            echo "❌ Image name cannot be empty. Exiting."
            exit 1
        else
            echo "⚠️  Image name cannot be empty. Please try again."
            ATTEMPT=$((ATTEMPT + 1))
        fi
    else
        break
    fi
done

# Convert to lowercase (Docker requires lowercase image names)
APP_NAME_LOWER=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]')
if [ "$APP_NAME" != "$APP_NAME_LOWER" ]; then
    echo "ℹ️  Converted to lowercase: $APP_NAME_LOWER (Docker requires lowercase)"
    APP_NAME="$APP_NAME_LOWER"
fi

# Ask for Dockerfile path
read -p "📄 Path to Dockerfile (default: ./Dockerfile): " DOCKERFILE_PATH
DOCKERFILE_PATH="${DOCKERFILE_PATH:-./Dockerfile}"

# Ask for build context
read -p "📍 Build context path (default: .): " BUILD_CONTEXT
BUILD_CONTEXT="${BUILD_CONTEXT:-.}"

# Ask for platforms
read -p "🖥️  Target platforms (default: linux/amd64,linux/arm64): " PLATFORMS
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

echo ""
echo "📝 Creating workflow files..."
echo ""

# Create workflow files based on deployment type
if [ "$DEPLOYMENT_TYPE" == "A" ]; then
    # Option A: Deploy via Centralized Workflow
    cat > .github/workflows/ci.yml << EOF
name: CI/CD Pipeline

on:
  push:
    branches:
      - main
      - develop
    tags:
      - 'v*'
  workflow_dispatch:

jobs:
  build-and-push-docker:
    permissions:
      contents: write      # Required for auto-versioning (creating Git tags)
      id-token: write      # Required for attestations (public repos only)
      attestations: write  # Required for build provenance (public repos only)
    uses: $WORKFLOWS_REPO/.github/workflows/docker-build-push.yml@$WORKFLOWS_VERSION
    with:
      image-name: $APP_NAME
      docker-username: '$DOCKERHUB_USERNAME'
      dockerfile-path: '$DOCKERFILE_PATH'
      context: '$BUILD_CONTEXT'
      platforms: '$PLATFORMS'
    secrets:
      docker-token: \${{ secrets.DOCKER_TOKEN }}
EOF
    echo "✅ Created .github/workflows/ci.yml"
    DEPLOYMENT_DESC="Centralized workflow ($WORKFLOWS_REPO@$WORKFLOWS_VERSION)"

elif [ "$DEPLOYMENT_TYPE" == "B" ]; then
    # Option B: Install Standalone Deployment (Static)
    cat > .github/workflows/ci.yml << EOF
name: CI/CD Pipeline

on:
  push:
    branches:
      - main
      - develop
    tags:
      - 'v*'
  workflow_dispatch:

jobs:
  build-and-push-docker:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to Docker Hub
        uses: docker/login-action@v3
        with:
          username: $DOCKERHUB_USERNAME
          password: \${{ secrets.DOCKER_TOKEN }}

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: $BUILD_CONTEXT
          file: $DOCKERFILE_PATH
          platforms: $PLATFORMS
          push: true
          tags: $APP_NAME:\${{ github.ref_name == 'main' && 'latest' || github.ref_name }}
EOF
    echo "✅ Created .github/workflows/ci.yml (standalone)"
    DEPLOYMENT_DESC="Standalone deployment (static)"
fi

echo ""
echo "======================================"
echo "Setting up GitHub Secrets & Deploying"
echo "======================================"
echo ""

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI not installed. Install it from https://cli.github.com"
    echo ""
    echo "Manual setup required:"
    echo "1. Go to Settings → Secrets and variables → Actions"
    echo "2. Add DOCKER_TOKEN: (your Docker Hub token)"
    echo "3. Run: git add .github/workflows/ && git commit -m 'Add Docker workflows' && git push"
    exit 1
fi

# Set up GitHub secrets
echo "🔐 Setting up GitHub secrets..."
echo ""

# Check if DOCKER_TOKEN secret already exists
if gh secret list | grep -q "^DOCKER_TOKEN"; then
    echo "ℹ️  DOCKER_TOKEN secret already exists"
    read -p "   Overwrite existing secret? [y/N]: " OVERWRITE
    OVERWRITE=$(echo "$OVERWRITE" | tr '[:upper:]' '[:lower:]')

    if [[ "$OVERWRITE" == "y" || "$OVERWRITE" == "yes" ]]; then
        if echo "$DOCKERHUB_TOKEN" | gh secret set DOCKER_TOKEN; then
            echo "✅ DOCKER_TOKEN secret updated"
        else
            echo "❌ Failed to update DOCKER_TOKEN secret"
            exit 1
        fi
    else
        echo "⏭️  Skipping DOCKER_TOKEN update (using existing secret)"
    fi
else
    # Set Docker Hub token secret
    if echo "$DOCKERHUB_TOKEN" | gh secret set DOCKER_TOKEN; then
        echo "✅ DOCKER_TOKEN secret set"
    else
        echo "❌ Failed to set DOCKER_TOKEN secret"
        exit 1
    fi
fi

echo ""
echo "📤 Committing and pushing workflow files to GitHub..."
git add .github/workflows/
git commit -m "Add Docker CI/CD workflow ($DEPLOYMENT_DESC)"
git push

echo ""
echo "✅ Workflows pushed to GitHub!"

echo ""
echo "======================================"
echo "Deployment Summary"
echo "======================================"
echo ""
echo "   Repository: $REPO_OWNER/$CURRENT_REPO"
echo "   Deployment Type: $DEPLOYMENT_DESC"
echo "   Docker Image: $DOCKERHUB_USERNAME/$APP_NAME"
echo "   Platforms: $PLATFORMS"
echo ""

echo "======================================"
echo "🚀 Workflow Triggered!"
echo "======================================"
echo ""
echo "The push to 'main' branch triggered the workflow automatically."
echo "Waiting for workflow to start..."
echo ""

# Wait for GitHub to process and start the workflow
sleep 5

# Check if workflow run started and watch it
echo "📊 Monitoring workflow status..."
echo ""

# Watch the latest workflow run
if gh run watch --exit-status 2>/dev/null; then
    echo ""
    echo "======================================"
    echo "✅ Workflow Completed Successfully!"
    echo "======================================"
    echo ""
    echo "🎉 Your Docker image has been built and pushed to Docker Hub!"
    echo ""
    echo "📦 Image: $DOCKERHUB_USERNAME/$APP_NAME:latest"
    echo ""
    echo "💡 Useful commands:"
    echo "   View all runs:    gh run list --workflow=ci.yml"
    echo "   Trigger manually: gh workflow run ci.yml"
    echo "   Pull image:       docker pull $DOCKERHUB_USERNAME/$APP_NAME:latest"
    echo ""
    echo "🔗 GitHub Actions:"
    echo "   https://github.com/$REPO_OWNER/$CURRENT_REPO/actions"
    echo ""
    exit 0
else
    EXIT_CODE=$?
    echo ""
    echo "======================================"
    echo "❌ Workflow Failed or Was Cancelled"
    echo "======================================"
    echo ""
    echo "The workflow encountered an issue. Common causes:"
    echo "  • Docker Hub credentials are incorrect"
    echo "  • Dockerfile has syntax errors"
    echo "  • Build context or paths are incorrect"
    echo ""
    echo "💡 To view details:"
    echo "   $ gh run view"
    echo "   $ gh run list --workflow=ci.yml"
    echo ""
    echo "🔗 GitHub Actions:"
    echo "   https://github.com/$REPO_OWNER/$CURRENT_REPO/actions"
    echo ""
    exit $EXIT_CODE
fi
