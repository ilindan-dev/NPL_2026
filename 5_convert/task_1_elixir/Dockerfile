FROM elixir:1.17-slim
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8 ELIXIR_ERL_OPTIONS="+fnu"
COPY json2xml.exs /app/json2xml.exs
# Рабочую папку задаёт run.sh (репозиторий монтируется в /work)
ENTRYPOINT ["elixir", "/app/json2xml.exs"]
