.PHONY: help up down build push logs restart clean

# Configuration
COMPOSE_FILE = ha-agent-hook/docker-compose.yml

help: ## Afficher cette aide
	@echo "Commandes disponibles pour ha-agent-hook:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

up: ## Démarrer le webhook
	@echo "🚀 Démarrage du webhook ha-agent-hook..."
	cd ha-agent-hook && docker compose up -d
	@echo "✅ Webhook démarré"

down: ## Arrêter le webhook
	@echo "🛑 Arrêt du webhook ha-agent-hook..."
	cd ha-agent-hook && docker compose down
	@echo "✅ Webhook arrêté"

build: ## Builder l'image Docker et publier sur Docker Hub
	@echo "🔨 Build et publication de l'image Docker..."
	./scripts/build-docker-image.sh

push: build ## Alias pour build (qui inclut déjà le push)

logs: ## Afficher les logs du webhook
	cd ha-agent-hook && docker compose logs -f

restart: down up ## Redémarrer le webhook

clean: down ## Arrêter et nettoyer les conteneurs
	@echo "🧹 Nettoyage..."
	cd ha-agent-hook && docker compose down -v
	@echo "✅ Nettoyage terminé"
