FROM nimlang/nim:2.0.8
WORKDIR /app
COPY rwcache.nim .
RUN nim c -d:release --threads:on --hints:off -o:rwcache rwcache.nim
ENTRYPOINT ["/app/rwcache"]
