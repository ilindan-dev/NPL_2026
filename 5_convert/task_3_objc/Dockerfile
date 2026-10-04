# Objective-C вне macOS - это GCC + библиотека GNUstep Base (открытая реализация Foundation)
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
        gobjc libgnustep-base-dev \
    && rm -rf /var/lib/apt/lists/*
ENV LANG=C.UTF-8
WORKDIR /app
COPY md2html.m .
# gnustep-config в контейнере без настроенного окружения GNUstep выдаёт пустые флаги,
# поэтому пути к заголовкам находим сами и задаём флаги явно.
RUN set -e; \
    F=$(find /usr -path '*/Foundation/Foundation.h' | head -n1); \
    test -n "$F" || { echo "Foundation.h не найден"; exit 1; }; \
    INC="-I$(dirname "$(dirname "$F")")"; \
    CFG=$(find /usr -name GSConfig.h | head -n1); \
    if [ -n "$CFG" ]; then INC="$INC -I$(dirname "$(dirname "$CFG")")"; fi; \
    gcc $INC -fconstant-string-class=NSConstantString -fobjc-exceptions \
        -DGNUSTEP -DGNUSTEP_BASE_LIBRARY=1 -DGNU_RUNTIME=1 -D_NATIVE_OBJC_EXCEPTIONS \
        md2html.m -o md2html -lgnustep-base -lobjc
# Рабочую папку задаёт run.sh (репозиторий монтируется в /work)
ENTRYPOINT ["/app/md2html"]
