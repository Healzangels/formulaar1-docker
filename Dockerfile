# syntax=docker/dockerfile:1

############################
# Stage 1 - build from src #
############################
# Build from source against a known tag so the image is reproducible. We build
# from the Healzangels fork rather than upstream because upstream v0.5.0 is
# broken on current Sonarr -- the bundled APIv3SonarrDotcore NuGet client has
# a closed MediaCoverTypes enum that throws on "clearlogo" (Sonarr v4 schema).
# The fork patches Program.cs to bypass the broken deserializer for series
# lookups. See https://github.com/Healzangels/Formulaar1/tree/fix/clearlogo-tolerance.
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build

ARG FORMULAAR1_REF=v0.5.0-fix8
ARG FORMULAAR1_REPO=https://github.com/Healzangels/Formulaar1.git
WORKDIR /src

# Clone the tagged source (git is preinstalled on the SDK image). Fall back to
# default branch if the tag move/rename ever breaks the shallow fetch.
RUN git clone --depth 1 --branch ${FORMULAAR1_REF} ${FORMULAAR1_REPO} . \
 || git clone --depth 1 ${FORMULAAR1_REPO} .

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
