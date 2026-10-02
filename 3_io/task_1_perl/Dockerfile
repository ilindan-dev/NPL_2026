FROM perl:5-slim
ENV LANG=C.UTF-8
COPY tree.pl /app/tree.pl
# Рабочую папку задаёт run.sh (репозиторий монтируется в /work)
ENTRYPOINT ["perl", "/app/tree.pl"]
