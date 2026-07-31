<img src="icon.svg" width="96" align="right" alt="">

# gocryptfs-docker

Dockerized [rfjakob/gocryptfs](https://github.com/rfjakob/gocryptfs) - encrypted filesystem overlay.

## Features

- Multi-arch support (amd64/arm64)
- Renovate tracks new gocryptfs releases and x/crypto versions, opens a PR,
  and a merge to master tags a release build
- Published to GitHub Container Registry

gocryptfs releases lag their own dependencies - v2.6.1 still pins a
`golang.org/x/crypto` with known advisories, and upstream has not tagged a
release since. The image is built from the release tag with that dependency
raised. Renovate opens a PR when a newer gocryptfs release or x/crypto version
lands; merging bumps the `ARG` in the Dockerfile, which auto-tags a release and
triggers a scanned, multi-arch rebuild.

## Images

- `ghcr.io/mac-lucky/gocryptfs-docker:latest`

Docker Hub (`maclucky/gocryptfs`) has not been updated since December 2025 - use GHCR.

## Usage

### Initialize encrypted directory

```bash
docker run --rm -it \
  -v /path/to/encrypted:/encrypted \
  ghcr.io/mac-lucky/gocryptfs-docker -init /encrypted
```

### Mount encrypted directory

```bash
docker run -d --privileged \
  --cap-add SYS_ADMIN \
  --device /dev/fuse \
  -v /path/to/encrypted:/encrypted \
  -v /path/to/decrypted:/decrypted:shared \
  ghcr.io/mac-lucky/gocryptfs-docker -allow_other /encrypted /decrypted
```

### Kubernetes sidecar

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      initContainers:
        # Creates gocryptfs.conf on first run, nothing else. A mount made here would be
        # torn down when the init container exits, so the sidecar below owns the mount.
        # -e matters: without it a failed init still exits 0 and the pod carries on.
        - name: gocryptfs-init
          image: ghcr.io/mac-lucky/gocryptfs-docker:latest
          command:
            - /bin/sh
            - -eu
            - -c
            - |
              if [ ! -f /encrypted/gocryptfs.conf ]; then
                echo "$GOCRYPTFS_PASSPHRASE" | gocryptfs -init -passfile /dev/stdin /encrypted
              fi
          env:
            - name: GOCRYPTFS_PASSPHRASE
              valueFrom:
                secretKeyRef:
                  name: gocryptfs-passphrase
                  key: passphrase
          volumeMounts:
            - name: encrypted-storage
              mountPath: /encrypted
        # Native sidecar (k8s 1.29+). myapp is not started until the startupProbe sees a
        # real mount on /decrypted, so a failed mount cannot leave myapp writing plaintext
        # into the emptyDir.
        - name: gocryptfs-sidecar
          image: ghcr.io/mac-lucky/gocryptfs-docker:latest
          restartPolicy: Always
          securityContext:
            privileged: true
          command:
            - /bin/sh
            - -eu
            - -c
            - |
              echo "$GOCRYPTFS_PASSPHRASE" | gocryptfs -passfile /dev/stdin -allow_other -fg /encrypted /decrypted
          startupProbe:
            exec:
              command: ["/bin/sh", "-c", "mountpoint -q /decrypted"]
            periodSeconds: 2
            failureThreshold: 30
          env:
            - name: GOCRYPTFS_PASSPHRASE
              valueFrom:
                secretKeyRef:
                  name: gocryptfs-passphrase
                  key: passphrase
          volumeMounts:
            - name: encrypted-storage
              mountPath: /encrypted
            - name: decrypted-data
              mountPath: /decrypted
              mountPropagation: Bidirectional
      containers:
        - name: myapp
          image: myapp:latest
          volumeMounts:
            - name: decrypted-data
              mountPath: /data
              mountPropagation: HostToContainer
      volumes:
        - name: encrypted-storage
          persistentVolumeClaim:
            claimName: encrypted-pvc
        - name: decrypted-data
          emptyDir: {}
```
