# STAGE 1 - Build
FROM node:26-alpine AS build-stage
WORKDIR /app
COPY app/package.json app/pnpm-lock.yaml ./
RUN npm install -g pnpm@9 && pnpm i --frozen-lockfile
COPY app/ .
RUN NODE_OPTIONS=--max-old-space-size=4096 npx vite build

# STAGE 2 - Production
FROM nginx:stable-alpine AS production
COPY --from=build-stage /app/dist /usr/share/nginx/html
COPY app/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]