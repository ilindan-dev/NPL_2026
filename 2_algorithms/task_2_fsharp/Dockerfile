FROM mcr.microsoft.com/dotnet/sdk:8.0
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
WORKDIR /app
COPY lca.fsx .
ENTRYPOINT ["dotnet", "fsi", "/app/lca.fsx"]
