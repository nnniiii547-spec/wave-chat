FROM node:22-alpine

WORKDIR /app

COPY server ./server
COPY css ./css
COPY js ./js
COPY demo ./demo
COPY index.html ./

RUN mkdir -p /data && chown -R node:node /app /data

USER node

ENV NODE_ENV=production \
    WAVECHAT_HOST=0.0.0.0 \
    WAVECHAT_PORT=8123 \
    WAVECHAT_DATA=/data

EXPOSE 8123

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8123/api/health || exit 1

CMD ["node", "server/server.js"]
