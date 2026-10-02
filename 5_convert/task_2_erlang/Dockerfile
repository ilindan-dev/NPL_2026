FROM erlang:27-slim
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
COPY proto2json.escript /app/proto2json.escript
# Рабочую папку задаёт run.sh (репозиторий монтируется в /work)
ENTRYPOINT ["escript", "/app/proto2json.escript"]
