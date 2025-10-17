# Étape 1: Utiliser une image Node.js légère
FROM node:18-alpine

# Étape 2: Définir le répertoire de travail dans le conteneur
WORKDIR /usr/src/app

# Étape 3: Copier les fichiers de définition du projet et installer les dépendances
# On copie package.json et package-lock.json d'abord pour profiter du cache de Docker
COPY package*.json ./
RUN npm install

# Étape 4: Copier le reste du code de l'application
COPY . .

# Étape 5: Exposer le port sur lequel l'application va tourner
EXPOSE 3000

# Étape 6: Définir la commande pour démarrer l'application
CMD [ "node", "index.js" ]
