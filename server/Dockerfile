# Build stage
FROM golang:alpine AS builder

WORKDIR /app

# Copy go mod and sum files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy the source code
COPY . .

# Build the application (disable CGO for a static binary)
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o salio-api ./cmd/api/main.go
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o salio-migrate ./cmd/migrate/main.go
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o salio-seed ./cmd/seed/main.go

# Final stage
FROM alpine:latest  

# Add CA certificates for secure connections
RUN apk --no-cache add ca-certificates tzdata

WORKDIR /app

# Copy the pre-built binaries from the builder stage
COPY --from=builder /app/salio-api .
COPY --from=builder /app/salio-migrate .
COPY --from=builder /app/salio-seed .
COPY --from=builder /app/migrations ./migrations
COPY --from=builder /app/templates ./templates
COPY --from=builder /app/static ./static

# Expose port 8080
EXPOSE 8080

# Run the binary
CMD ["./salio-api"]
