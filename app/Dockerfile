FROM node:16.0.0-slim as builder
WORKDIR /app
COPY . .
RUN npm install -g @vercel/ncc
RUN npm install --production
RUN ncc build index.js -o dist

FROM node:16.0.0-slim
WORKDIR /app
COPY --from=builder /app/dist/index.js .
USER node
CMD ["node", "index.js"]