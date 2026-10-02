FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ldc gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY mapreduce.d .
RUN ldc2 -O3 -release mapreduce.d -of=mapreduce
ENTRYPOINT ["/app/mapreduce"]
