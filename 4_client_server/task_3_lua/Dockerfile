FROM alpine:3.20
RUN apk add --no-cache lua5.4 lua5.4-socket
ENV LANG=C.UTF-8
COPY weather.lua /app/weather.lua
ENTRYPOINT ["lua5.4", "/app/weather.lua"]
