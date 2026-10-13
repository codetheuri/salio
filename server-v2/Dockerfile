# syntax=docker/dockerfile:1
#
# Salio v2 — one image, five commands:
#   /api          the HTTP server (the default)
#   /migrate      schema migrations; run as the OWNER role, before /api
#   /syncgc       tombstone sweep; `-every 24h` to run on a schedule
#   /createadmin  add a console super admin
#   /importv1     one-off v1 → v2 data migration
#
# Two stages: compile with the Go toolchain, then copy only the static binaries
# into a distroless image — no shell, no package manager, a non-root user. What
# an attacker who got code execution would find there is the binaries and
# nothing to use them with.

FROM golang:1.26-bookworm AS build
WORKDIR /src

# Dependencies first, so a code change does not re-download every module.
COPY go.mod go.sum ./
RUN go mod download

COPY . .
# CGO off: fully static binaries that run on distroless/static. -trimpath and
# -s -w drop local paths and debug symbols from the shipped files.
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags "-s -w" -o /out/api ./cmd/api && \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags "-s -w" -o /out/migrate ./cmd/migrate && \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags "-s -w" -o /out/syncgc ./cmd/syncgc && \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags "-s -w" -o /out/createadmin ./cmd/createadmin && \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags "-s -w" -o /out/importv1 ./cmd/importv1

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/ /
# Time zones are compiled into the binaries (time/tzdata), and console
# templates and assets are embedded, so nothing else needs copying.
USER nonroot:nonroot
EXPOSE 8090
ENTRYPOINT ["/api"]
