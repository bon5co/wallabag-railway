# wallabag-railway

Thin wrapper over the official [wallabag](https://github.com/wallabag/wallabag) image (2.6.17, pinned by digest) for the Railway template.

It maps Railway's variables onto upstream's entrypoint (PostgreSQL), makes nginx listen on Railway's `PORT`, replaces the default
`wallabag` / `wallabag` login with a generated one before nginx starts, creates an OAuth API client from variables, and keeps the
data directory on a volume. Image: `ghcr.io/bon5co/wallabag-railway`.
