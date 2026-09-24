FROM rust:1-slim AS build
WORKDIR /app
COPY Cargo.toml ./
COPY src ./src
RUN cargo build --release

FROM debian:bookworm-slim
COPY --from=build /app/target/release/url_checker /usr/local/bin/url_checker
ENTRYPOINT ["url_checker"]
