FROM node:20-alpine

# Dependencias de compilación para better-sqlite3
RUN apk add --no-cache python3 make g++ sqlite-dev

WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev

COPY . .
RUN mkdir -p /app/data

EXPOSE 8090
CMD ["node", "server.js"]
