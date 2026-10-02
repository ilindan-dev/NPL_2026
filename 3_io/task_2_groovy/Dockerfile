FROM groovy:4.0-jdk17
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
COPY validate.groovy /app/validate.groovy
# Рабочую папку задаёт run.sh (репозиторий монтируется в /work)
ENTRYPOINT ["groovy", "/app/validate.groovy"]
