# =============================================================================
# Minimal application container.
#
# The application is deliberately trivial — this project is about the AWS
# architecture, not about application code. What matters here is that the
# image demonstrates container best practice:
#   - pinned base image (never `latest`)
#   - non-root user
#   - small attack surface (alpine)
#   - a /health endpoint the ALB and ECS can probe
# =============================================================================
FROM nginx:1.31-alpine

# Run as a non-root user. nginx:alpine ships an `nginx` user (uid 101).
# Prepare the directories that user needs to write to.
RUN mkdir -p /var/cache/nginx /var/run \
    && chown -R nginx:nginx /var/cache/nginx /var/run /usr/share/nginx/html

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html

# Port 80 is fine because the container never runs as root-bound privileged
# ports inside Fargate's own network namespace.
EXPOSE 80

USER nginx

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD wget -q --spider http://localhost/health || exit 1

CMD ["nginx", "-g", "daemon off;"]
