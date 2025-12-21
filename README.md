# gocryptfs-docker

Dockerized [rfjakob/gocryptfs](https://github.com/rfjakob/gocryptfs) - encrypted filesystem overlay.

## Features

- Multi-arch support (amd64/arm64)
- Daily automated builds checking for new gocryptfs releases
- Published to Docker Hub and GitHub Container Registry

## Images

- `maclucky/gocryptfs:latest`
- `ghcr.io/mac-lucky/gocryptfs-docker:latest`

## Usage

### Initialize encrypted directory

```bash
docker run --rm -it \
  -v /path/to/encrypted:/encrypted \
  maclucky/gocryptfs -init /encrypted
```

### Mount encrypted directory

```bash
docker run -d --privileged \
  --cap-add SYS_ADMIN \
  --device /dev/fuse \
  -v /path/to/encrypted:/encrypted \
  -v /path/to/decrypted:/decrypted:shared \
  maclucky/gocryptfs -allow_other /encrypted /decrypted
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
        - name: gocryptfs-init
          image: maclucky/gocryptfs:latest
          securityContext:
            privileged: true
          command:
            - /bin/sh
            - -c
            - |
              if [ ! -f /encrypted/gocryptfs.conf ]; then
                echo "$GOCRYPTFS_PASSPHRASE" | gocryptfs -init -passfile /dev/stdin /encrypted
              fi
              echo "$GOCRYPTFS_PASSPHRASE" | gocryptfs -passfile /dev/stdin -allow_other /encrypted /decrypted
              touch /decrypted/.ready
              sleep 5
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
        - name: gocryptfs-sidecar
          image: maclucky/gocryptfs:latest
          securityContext:
            privileged: true
          command:
            - /bin/sh
            - -c
            - |
              echo "$GOCRYPTFS_PASSPHRASE" | gocryptfs -passfile /dev/stdin -allow_other -fg /encrypted /decrypted &
              wait $!
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
