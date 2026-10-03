FROM virtuslab/scala-cli:latest
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
WORKDIR /app
COPY TopK.scala .
# компилируем (и скачиваем Scala) на этапе сборки образа, чтобы запуск был быстрым
RUN scala-cli compile TopK.scala --server=false
ENTRYPOINT ["scala-cli", "run", "TopK.scala", "--server=false", "--"]
