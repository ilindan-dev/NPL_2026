FROM julia:1.10
ENV LANG=C.UTF-8
COPY yaml2toml.jl /app/yaml2toml.jl
# Рабочую папку задаёт run.sh (репозиторий монтируется в /work)
ENTRYPOINT ["julia", "--startup-file=no", "/app/yaml2toml.jl"]
