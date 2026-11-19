# Wallabag wrapper for Railway. Upstream is Alpine + nginx + php-fpm under s6, installs the schema through an entrypoint that
# creates the database and role from a superuser login, and ships a default administrator (wallabag / wallabag). The wrapper
# keeps that entrypoint, maps Railway's variables onto it, makes nginx listen on Railway's injected PORT, holds nginx back until
# the default login is replaced by a generated one, creates the OAuth API client from variables, and keeps data on a volume.
# upstream: wallabag/wallabag
FROM wallabag/wallabag:2.6.17@sha256:9055d92d6e7973abea2d902ecb5459f6063fce05595eaef37f6750e49ff8cdee

COPY --chmod=0755 boot.sh /railway-boot.sh
COPY --chmod=0644 api-client.php /railway-api-client.php

ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["/railway-boot.sh"]
CMD ["wallabag"]
