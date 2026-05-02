FROM node:20-bookworm-slim
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY public ./public
COPY server.js ./server.js
RUN mkdir -p /app/data
ENV NODE_ENV=production
# Railway 等平台会注入 PORT；本地默认 8080 与 EXPOSE 一致
ENV PORT=8080
EXPOSE 8080
CMD ["node", "server.js"]
