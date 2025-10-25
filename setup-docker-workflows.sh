#!/bin/bash

# Docker Workflow Setup Script
# This script sets up GitHub Actions workflows for building and pushing Docker images

set -e

echo "======================================"
echo "Docker Workflow Setup Script"
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

# Create .github/workflows directory
mkdir -p .github/workflows
echo "✅ Created .github/workflows directory"

# Ask for Docker Hub username
read -p "🐳 Docker Hub username: " DOCKERHUB_USERNAME
if [ -z "$DOCKERHUB_USERNAME" ]; then
    echo "❌ Docker Hub username cannot be empty"
    exit 1
fi

# Ask for app name
read -p "📦 Docker image name (default: $DOCKERHUB_USERNAME/$REPO_NAME): " APP_NAME
APP_NAME="${APP_NAME:-$DOCKERHUB_USERNAME/$REPO_NAME}"

# Ask for Dockerfile path
read -p "📄 Path to Dockerfile (default: ./Dockerfile): " DOCKERFILE_PATH
DOCKERFILE_PATH="${DOCKERFILE_PATH:-./Dockerfile}"

# Ask for build context
read -p "📍 Build context path (default: .): " BUILD_CONTEXT
BUILD_CONTEXT="${BUILD_CONTEXT:-./}"

# Ask for platforms
read -p "🖥️  Target platforms (default: linux/amd64,linux/arm64): " PLATFORMS
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

echo ""
echo "📝 Creating workflow files..."
echo ""

# Create docker-build-push.yml (reusable workflow)
cat > .github/workflows/docker-build-push.yml << 'EOF'
name: Build and Push Docker Image

on:
  workflow_call:
    inputs:
      image-name:
        description: 'Docker image name (e.g., myusername/myapp)'
        required: true
        type: string
      image-tag:
        description: 'Docker image tag (e.g., latest, v1.0.0)'
        required: false
        default: 'latest'
        type: string
      dockerfile-path:
        description: 'Path to Dockerfile'
        required: false
        default: './Dockerfile'
        type: string
      build-context:
        description: 'Build context path'
        required: false
        default: '.'
        type: string
      platforms:
        description: 'Target platforms (e.g., linux/amd64,linux/arm64)'
        required: false
        default: 'linux/amd64'
        type: string
    secrets:
      DOCKERHUB_USERNAME:
        description: 'Docker Hub username'
        required: true
      DOCKERHUB_TOKEN:
        description: 'Docker Hub access token'
        required: true

jobs:
  build-and-push:
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
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: ${{ inputs.build-context }}
          file: ${{ inputs.dockerfile-path }}
          platforms: ${{ inputs.platforms }}
          push: true
          tags: ${{ inputs.image-name }}:${{ inputs.image-tag }}
EOF
echo "✅ Created .github/workflows/docker-build-push.yml"

# Create ci.yml (workflow that calls the reusable one)
cat > .github/workflows/ci.yml << EOF
name: CI/CD Pipeline

on:
  push:
    branches:
      - main
      - develop
    tags:
      - 'v*'

jobs:
  build-and-push-docker:
    uses: .\/.github\/workflows\/docker-build-push.yml
    with:
      image-name: $APP_NAME
      image-tag: \${{ github.ref_name == 'main' && 'latest' || github.ref_name }}
      dockerfile-path: '$DOCKERFILE_PATH'
      build-context: '$BUILD_CONTEXT'
      platforms: '$PLATFORMS'
    secrets:
      DOCKERHUB_USERNAME: \${{ secrets.DOCKERHUB_USERNAME }}
      DOCKERHUB_TOKEN: \${{ secrets.DOCKERHUB_TOKEN }}
EOF
echo "✅ Created .github/workflows/ci.yml"

echo ""
echo "======================================"
echo "Next Steps:"
echo "======================================"
echo ""
echo "1️⃣  Create Docker Hub access token:"
echo "   - Go to https://hub.docker.com/settings/security"
echo "   - Create a new access token"
echo ""
echo "2️⃣  Add GitHub secrets (choose one method):"
echo ""
echo "   Option A: Using GitHub CLI (faster)"
echo "   $ gh secret set DOCKERHUB_USERNAME --body '$DOCKERHUB_USERNAME'"
echo "   $ gh secret set DOCKERHUB_TOKEN --body 'your_token_here'"
echo ""
echo "   Option B: Manual (via GitHub website)"
echo "   - Go to Settings → Secrets and variables → Actions"
echo "   - Add DOCKERHUB_USERNAME: $DOCKERHUB_USERNAME"
echo "   - Add DOCKERHUB_TOKEN: (your access token)"
echo ""
echo "3️⃣  Commit and push the workflow files:"
echo "   $ git add .github/workflows/"
echo "   $ git commit -m 'Add Docker build and push workflows'"
echo "   $ git push"
echo ""
echo "4️⃣  When you push to main/develop or create a tag, the workflow will run!"
echo ""
echo "======================================"

# Ask if user wants to set up secrets now
echo ""
read -p "Would you like to set up GitHub secrets now? (requires 'gh' CLI) [y/N]: " SETUP_SECRETS

if [[ $SETUP_SECRETS =~ ^[Yy]$ ]]; then
    # Check if gh CLI is installed
    if ! command -v gh &> /dev/null; then
        echo "❌ GitHub CLI not installed. Install it from https://cli.github.com"
        echo "Then run:"
        echo "   gh secret set DOCKERHUB_USERNAME --body '$DOCKERHUB_USERNAME'"
        echo "   gh secret set DOCKERHUB_TOKEN --body 'your_token_here'"
    else
        echo ""
        echo "Setting up secrets with GitHub CLI..."
        echo ""
        gh secret set DOCKERHUB_USERNAME --body "$DOCKERHUB_USERNAME"
        echo "✅ DOCKERHUB_USERNAME secret set"
        
        read -sp "🔐 Docker Hub access token (won't be displayed): " TOKEN
        echo ""
        if [ -z "$TOKEN" ]; then
            echo "❌ Token cannot be empty"
        else
            gh secret set DOCKERHUB_TOKEN --body "$TOKEN"
            echo "✅ DOCKERHUB_TOKEN secret set"
        fi
    fi
fi

echo ""
echo "✨ Setup complete!"
