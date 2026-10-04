# Официального образа Odin нет, поэтому компилятор собирается из исходников
# (фиксированный релиз dev-2024-12) - это делается один раз, дальше берётся из кэша.
FROM ubuntu:24.04 AS build
RUN apt-get update && apt-get install -y --no-install-recommends \
        clang llvm-dev git make ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch dev-2024-12 https://github.com/odin-lang/Odin /odin \
    && cd /odin && ./build_odin.sh release
ENV PATH=/odin:$PATH
WORKDIR /src
COPY vault.odin .
RUN odin build vault.odin -file -o:speed -out:vault

FROM ubuntu:24.04
COPY --from=build /src/vault /usr/local/bin/vault
# Рабочую папку задаёт run.sh (репозиторий монтируется в /work) - vault.txt появится там
ENTRYPOINT ["vault"]
