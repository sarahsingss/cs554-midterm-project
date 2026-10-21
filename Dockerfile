FROM node:22.23.3-bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends wget \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app


COPY --chown=node:node package.json ./
COPY --chown=node:node src ./src

USER node
ENV PORT=8080
EXPOSE 8080
CMD ["node", "src/server.js"]
