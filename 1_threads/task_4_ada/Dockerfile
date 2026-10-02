FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends gnat gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY life.adb .
RUN gnatmake -O2 -gnat2012 life.adb -o life
ENTRYPOINT ["/app/life"]
