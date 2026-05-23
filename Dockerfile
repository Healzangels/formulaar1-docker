# syntax=docker/dockerfile:1

############################
# Stage 1 - build from src #
############################
# Build from source against a known upstream tag so the image is reproducible
# and we aren't trusting whatever the latest release artifact happens to be.
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build

ARG FORMULAAR1_REF=v0.5.0
WORKDIR /src

# Clone the tagged source (git is preinstalled on the SDK image). Fall back to
# default branch if the tag move/rename ever breaks the shallow fetch.
RUN git clone --depth 1 --branch ${FORMULAAR1_REF} https://github.com/Jimmy062006/Formulaar1.git . \
 || git clone --depth 1 https://github.com/Jimmy062006/Formulaar1.git .

# Target the app csproj directly so the Formulaar1.Tests project is excluded
# from the publish output.
RUN dotnet restore Formulaar1/Formulaar1.csproj \
 && dotnet publish Formulaar1/Formulaar1.csproj \
      -c Release \
      -o /app \
      --no-restore \
      /p:UseAppHost=true

############################
# Stage 2 - runtime image  #
############################
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime

WORKDIR /app
COPY --from=build /app/ ./

# Listen on all interfaces; TLS is terminated upstream (NPM/Cloudflare) and
# AutoBrr talks to it on the LAN.
ENV ASPNETCORE_URLS=http://0.0.0.0:5000
ENV ASPNETCORE_ENVIRONMENT=Production
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

EXPOSE 5000

# appsettings.json is bind-mounted at runtime, so config edits don't rebuild.
ENTRYPOINT ["./Formulaar1"]
