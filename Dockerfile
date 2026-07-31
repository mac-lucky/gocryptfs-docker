FROM golang:1.26-alpine@sha256:0178a641fbb4858c5f1b48e34bdaabe0350a330a1b1149aabd498d0699ff5fb2 AS builder

ARG GOCRYPTFS_VERSION=2.6.1
# gocryptfs v2.6.1 pins golang.org/x/crypto v0.33.0, which carries a batch of
# critical advisories in x/crypto/ssh. gocryptfs only imports scrypt, hkdf and
# chacha20poly1305, so none of that code is reachable, but the module version is
# recorded in the binary and image scanners flag it. Upstream master has already
# bumped x/crypto; no release carries it yet, so do the bump here.
# Renovate keeps this current - see .github/renovate.json. Keep the "v" in the
# value: the version it writes back is a Go module version, prefix included.
ARG XCRYPTO_VERSION=v0.54.0

RUN apk add --no-cache bash gcc git musl-dev openssl-dev

# Built from a checkout rather than "go install pkg@version" because that form
# honours the upstream go.mod pin and gives no way to patch a dependency.
RUN git clone --depth 1 --branch "v${GOCRYPTFS_VERSION}" \
        https://github.com/rfjakob/gocryptfs.git /src

WORKDIR /src

# go get raises the go directive from 1.19 to the 1.25 x/crypto needs, the same
# combination upstream master builds with. The -ldflags replace the version
# metadata "go install" used to supply; a git checkout reports itself as
# "(devel)" and gocryptfs would print a "not set" placeholder without them.
# -version at the end fails the build if the bumped dependency broke anything.
RUN go get "golang.org/x/crypto@${XCRYPTO_VERSION}" && \
    go build -o /go/bin/gocryptfs \
      -ldflags="-X main.GitVersion=v${GOCRYPTFS_VERSION} -X main.GitVersionFuse=$(go list -m -f '{{.Version}}' github.com/hanwen/go-fuse/v2) -X main.BuildDate=$(date -u +%Y-%m-%d)" \
      . && \
    /go/bin/gocryptfs -version

FROM alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b

COPY --from=builder /go/bin/gocryptfs /usr/local/bin/gocryptfs

RUN apk add --no-cache fuse bash && \
    echo "user_allow_other" >> /etc/fuse.conf

LABEL org.opencontainers.image.source="https://github.com/mac-lucky/gocryptfs-docker"
LABEL org.opencontainers.image.description="gocryptfs - encrypted filesystem overlay"

ENTRYPOINT ["/usr/local/bin/gocryptfs"]
