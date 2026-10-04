FROM swift:5.10 AS build
WORKDIR /src
COPY main.swift .
RUN swiftc -O main.swift -o monitor

FROM swift:5.10-slim
ENV LANG=C.UTF-8
COPY --from=build /src/monitor /usr/local/bin/monitor
ENTRYPOINT ["monitor"]
