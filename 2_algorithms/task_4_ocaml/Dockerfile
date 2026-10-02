FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ocaml-nox gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY water.ml .
RUN ocamlopt water.ml -o water
ENTRYPOINT ["/app/water"]
