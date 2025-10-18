# syntax=docker/dockerfile:1

# Build stage
FROM golang:1.23 AS builder
WORKDIR /app

COPY go.mod ./
RUN go mod download

COPY . ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o server ./cmd/server

# Runtime stage
FROM gcr.io/distroless/base-debian12

ENV PORT=8080

USER nonroot:nonroot
WORKDIR /home/nonroot
COPY --from=builder /app/server ./server

EXPOSE 8080

ENTRYPOINT ["./server"]
