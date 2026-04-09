# Building ralphex using only Docker

This document shows a couple of ways to build the `ralphex` binary inside Docker
and place the resulting artifact into a host folder (`.bin/ralphex`) so you don't
need to install Go or other dev tools locally.

Recommended (BuildKit) — exports build output directly to host

1. Ensure Docker BuildKit is enabled:

```bash
export DOCKER_BUILDKIT=1
```

2. Build and export:

```bash
mkdir -p .bin
DOCKER_BUILDKIT=1 docker build --output type=local,dest=.bin -f Dockerfile.build \
  --build-arg VERSION="$(git describe --tags --always --dirty 2>/dev/null || echo dev)" .

# resulting binary: .bin/ralphex
chmod +x .bin/ralphex
```

Fallback (no BuildKit) — build image and copy artifact out

```bash
mkdir -p .bin
docker build -t ralphex-builder -f Dockerfile.build \
  --build-arg VERSION="$(git describe --tags --always --dirty 2>/dev/null || echo dev)" .

# create a temporary container and copy the artifact from it
ctr=$(docker create ralphex-builder)
docker cp ${ctr}:/out/ralphex ./.bin/ralphex
docker rm ${ctr}
chmod +x ./.bin/ralphex
```

Alternate simple run-and-copy (mount host dir as destination)

```bash
mkdir -p .bin
docker build -t ralphex-builder -f Dockerfile.build .
docker run --rm -v "$(pwd)/.bin:/hostbin" ralphex-builder cp /out/ralphex /hostbin/ralphex
chmod +x ./.bin/ralphex
```

Notes
- The `VERSION` build-arg is optional; pass it to embed a revision string into the binary.
- The Dockerfile uses `CGO_ENABLED=0` so the binary is statically linked for linux/amd64.
- If you need other target platforms, pass `--build-arg TARGETARCH=arm64` or similar.
