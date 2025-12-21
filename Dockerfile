FROM golang:alpine AS builder

ARG GOCRYPTFS_VERSION=v2.6.1

RUN apk add --no-cache bash gcc git musl-dev openssl-dev

RUN go install github.com/rfjakob/gocryptfs/v2@${GOCRYPTFS_VERSION}

FROM alpine:latest

COPY --from=builder /go/bin/gocryptfs /usr/local/bin/gocryptfs

RUN apk add --no-cache fuse bash && \
    echo "user_allow_other" >> /etc/fuse.conf

LABEL org.opencontainers.image.source="https://github.com/mac-lucky/gocryptfs-docker"
LABEL org.opencontainers.image.description="gocryptfs - encrypted filesystem overlay"

ENTRYPOINT ["/usr/local/bin/gocryptfs"]
