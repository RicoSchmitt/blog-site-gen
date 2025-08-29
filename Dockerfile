# syntax=docker/dockerfile:1.7

# Stage 1 — build with Hugo (extended)
FROM hugomods/hugo:0.148.2 AS builder
WORKDIR /src
COPY . .

# If modules are vendored, Hugo will use ./vendor automatically.
# Fail the build if no index.html is produced.
RUN --mount=type=cache,target=/root/.cache/hugo \
    hugo --minify --gc -s . -d /out && test -s /out/index.html

# Stage 2 — serve with Nginx
FROM nginx:alpine
COPY --from=builder /out /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
