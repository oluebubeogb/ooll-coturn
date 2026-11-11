# OOLL Space coturn image: official coturn plus our env-driven entrypoint.
# The entrypoint is baked into the image (no bind mount), so it works on
# Coolify, where repo files are not reliably mounted into containers.
FROM coturn/coturn:4.6
COPY --chmod=0755 docker-entrypoint.sh /usr/local/bin/ooll-turn-entrypoint.sh
ENTRYPOINT ["/bin/sh", "/usr/local/bin/ooll-turn-entrypoint.sh"]
