# Objective-C вне macOS - это GCC + библиотека GNUstep Base (открытая реализация Foundation)
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
        gobjc gnustep-make libgnustep-base-dev \
    && rm -rf /var/lib/apt/lists/*
ENV LANG=C.UTF-8
WORKDIR /app
COPY md2html.m .
RUN gcc $(gnustep-config --objc-flags) md2html.m -o md2html $(gnustep-config --base-libs)
# Рабочую папку задаёт run.sh (репозиторий монтируется в /work)
ENTRYPOINT ["/app/md2html"]
