# Официального образа с kotlinc нет - скачиваем компилятор с GitHub на этапе сборки
FROM eclipse-temurin:21-jdk AS build
RUN apt-get update && apt-get install -y --no-install-recommends curl unzip \
    && rm -rf /var/lib/apt/lists/*
ARG KOTLIN=2.0.21
RUN curl -fsSL -o /tmp/kotlin.zip \
        "https://github.com/JetBrains/kotlin/releases/download/v${KOTLIN}/kotlin-compiler-${KOTLIN}.zip" \
    && unzip -q /tmp/kotlin.zip -d /opt && rm /tmp/kotlin.zip
WORKDIR /src
COPY Todo.kt .
RUN /opt/kotlinc/bin/kotlinc Todo.kt -include-runtime -d todo.jar

FROM eclipse-temurin:21-jre
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
COPY --from=build /src/todo.jar /app/todo.jar
ENTRYPOINT ["java", "-jar", "/app/todo.jar"]
