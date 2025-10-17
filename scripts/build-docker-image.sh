#!/bin/bash

# Script de build et publication Docker pour ha-agent-hook
# Incrémente automatiquement la version et publie sur Docker Hub

set -e

# Vérifications des prérequis
command -v jq >/dev/null 2>&1 || { echo "❌ jq est requis mais non installé. Installez avec: sudo apt install jq"; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "❌ Docker est requis mais non installé."; exit 1; }
command -v git >/dev/null 2>&1 || { echo "❌ Git est requis mais non installé."; exit 1; }

# Vérifier la connexion Docker Hub
docker info | grep -q Username || { 
    echo "❌ Non connecté à Docker Hub. Lancez 'docker login' d'abord."; 
    exit 1; 
}

# Configuration
DOCKER_USER=${DOCKER_USER:-"mathmath350"}  # Remplacez par votre nom d'utilisateur Docker Hub
APP_NAME="ha-agent-hook"
APP_DIR="ha-agent-hook"

echo "🚀 Build et publication Docker pour $APP_NAME"
echo "👤 Utilisateur Docker Hub: $DOCKER_USER"

# Se déplacer dans le répertoire de l'application
cd "$(dirname "$0")/../$APP_DIR"

# Récupère la version actuelle du fichier package.json
VERSION=$(jq -r '.version' package.json)
echo "📦 Version actuelle: $VERSION"

# Récupère le hash court du commit git
GIT_REF=$(git rev-parse --short HEAD)
echo "🔀 Ref git: $GIT_REF"

# Vérifie que le working directory est propre
if [ -n "$(git status --porcelain)" ]; then
    echo "⚠️  Warning: Working directory n'est pas propre. Les changements non commités ne seront pas inclus."
    git status --short
    read -p "Continuer quand même ? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Abandon."
        exit 1
    fi
fi

# Build de l'image Docker avec la ref git
echo "🔨 Construction de l'image Docker..."
docker build \
    --build-arg GIT_REF=$GIT_REF \
    --build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
    -t $APP_NAME:latest \
    -t $APP_NAME:$VERSION \
    -t $APP_NAME:$GIT_REF \
    .

# Tag les images avec le nom d'utilisateur Docker Hub
echo "🏷️  Tagging des images..."
docker tag $APP_NAME:latest $DOCKER_USER/$APP_NAME:latest
docker tag $APP_NAME:$VERSION $DOCKER_USER/$APP_NAME:$VERSION
docker tag $APP_NAME:$GIT_REF $DOCKER_USER/$APP_NAME:$GIT_REF

# Pousse les images sur Docker Hub
echo "📤 Publication sur Docker Hub..."
docker push $DOCKER_USER/$APP_NAME:latest
docker push $DOCKER_USER/$APP_NAME:$VERSION
docker push $DOCKER_USER/$APP_NAME:$GIT_REF

# Incrémente le numéro de version (patch)
echo "🔢 Incrémentation de la version..."
IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"
PATCH=$((PATCH + 1))
NEW_VERSION="$MAJOR.$MINOR.$PATCH"

# Met à jour la version dans package.json
echo "📝 Mise à jour de package.json vers $NEW_VERSION..."
jq ".version = \"$NEW_VERSION\"" package.json > package.json.tmp && mv package.json.tmp package.json

# Commit automatique de la nouvelle version
echo "💾 Commit de la nouvelle version..."
git add package.json
git commit -m "🚀 Bump version to $NEW_VERSION

- Auto-increment after Docker build
- Docker images published:
  - $DOCKER_USER/$APP_NAME:latest
  - $DOCKER_USER/$APP_NAME:$VERSION
  - $DOCKER_USER/$APP_NAME:$GIT_REF"

echo ""
echo "✅ Build et publication terminés avec succès!"
echo "📦 Version précédente: $VERSION"
echo "📦 Nouvelle version: $NEW_VERSION"
echo "🐳 Images Docker publiées:"
echo "   - $DOCKER_USER/$APP_NAME:latest"
echo "   - $DOCKER_USER/$APP_NAME:$VERSION" 
echo "   - $DOCKER_USER/$APP_NAME:$GIT_REF"
echo ""
echo "💡 Pour déployer la nouvelle version:"
echo "   docker pull $DOCKER_USER/$APP_NAME:latest"
echo "   docker run -v /path/to/config.json:/usr/src/app/config.json $DOCKER_USER/$APP_NAME:latest"
echo ""
echo "🔄 N'oubliez pas de push le commit de version:"
echo "   git push origin main"