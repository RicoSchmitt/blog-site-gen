# syntax=docker/dockerfile:1.7

# Stage 1 — build with Hugo v0.148.2 (extended, multi-arch)
FROM --platform=$BUILDPLATFORM hugomods/hugo:0.148.2 AS builder
ARG HUGO_ENV=production
ARG HUGO_BASEURL=""
WORKDIR /src
COPY . .
RUN hugo --minify --gc \
    ${HUGO_BASEURL:+--baseURL "${HUGO_BASEURL}"} \
    -s . -d /out

# Stage 2 — serve with Nginx
FROM --platform=$TARGETPLATFORM nginx:alpine
COPY --from=builder /out /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
