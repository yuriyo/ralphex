#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build.sh [--docker] [--arch ARCH] [--version VERSION] [--no-cache]

Options:
  --docker       Build inside Docker (outputs .bin/ralphex). This is the
                  selector that forces Docker-based build.
  --arch ARCH    Target architecture for Docker build (amd64|arm64). Default autodetected.
  --version VER  Version string to embed (defaults to git describe or 'dev').
  --no-cache     Pass --no-cache to docker build when using fallback image method.
  -h, --help     Show this help and exit.
EOF
}

DOCKER_BUILD=0
NO_CACHE=0
TARGETARCH=""
TARGETOS=""
VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --docker)
      DOCKER_BUILD=1; shift ;;
    --no-cache)
      NO_CACHE=1; shift ;;
    --arch)
      TARGETARCH="$2"; shift 2 ;;
    --version)
      VERSION="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done


REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

# detect default target OS from host if not provided
if [ -z "$TARGETOS" ]; then
  UNAME_S=$(uname -s)
  case "$UNAME_S" in
    Darwin) TARGETOS=darwin ;;
    Linux) TARGETOS=linux ;;
    CYGWIN*|MINGW*|MSYS*) TARGETOS=windows ;;
    *) TARGETOS=$(echo "$UNAME_S" | tr '[:upper:]' '[:lower:]') ;;
  esac
fi

# detect default arch
if [ -z "$TARGETARCH" ]; then
  UNAME_M=$(uname -m)
  case "$UNAME_M" in
    x86_64|amd64) TARGETARCH=amd64 ;;
    aarch64|arm64) TARGETARCH=arm64 ;;
    i386|i686) TARGETARCH=386 ;;
    *) TARGETARCH=amd64 ;;
  esac
fi

# choose binary name (windows needs .exe)
if [ "$TARGETOS" = "windows" ]; then
  BIN_NAME="ralphex.exe"
else
  BIN_NAME="ralphex"
fi

# (no tarball) final image contains the single binary at /ralphex

if [ -z "$VERSION" ]; then
  if command -v git >/dev/null 2>&1; then
    VERSION="$(git describe --tags --always --dirty 2>/dev/null || echo dev)"
  else
    VERSION=dev
  fi
fi

BUILD_DIR=".bin"
mkdir -p "$BUILD_DIR"

if [ "$DOCKER_BUILD" -eq 1 ]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required for --docker build" >&2
    exit 1
  fi

  echo "Building inside Docker (os=${TARGETOS} arch=${TARGETARCH}) with VERSION=${VERSION}"

  # Try BuildKit export first (fastest: writes files directly to host .bin)
  # ensure output dir exists and is writable by the container
  mkdir -p "$BUILD_DIR"
  chmod 0777 "$BUILD_DIR" || true
  UID_VAL=$(id -u)
  GID_VAL=$(id -g)

  if DOCKER_BUILDKIT=1 docker build ${NO_CACHE:+--no-cache} --output type=local,dest="$BUILD_DIR",uid=$UID_VAL,gid=$GID_VAL \
      -f Dockerfile.build --build-arg VERSION="$VERSION" --build-arg TARGETARCH="$TARGETARCH" --build-arg TARGETOS="$TARGETOS" .; then
    chmod +x "$BUILD_DIR/$BIN_NAME" || true
    echo "Built $BUILD_DIR/$BIN_NAME via BuildKit export"
    exit 0
  fi

  echo "BuildKit export failed — falling back to image+copy method"

  docker build ${NO_CACHE:+--no-cache} -t ralphex-builder -f Dockerfile.build \
    --build-arg VERSION="$VERSION" --build-arg TARGETARCH="$TARGETARCH" --build-arg TARGETOS="$TARGETOS" .

  ctr=$(docker create ralphex-builder)
  # Prefer the final image path (/ralphex); fall back to /out/ralphex for older Dockerfile versions
  if docker cp "${ctr}:/ralphex" "${BUILD_DIR}/${BIN_NAME}" 2>/dev/null; then
    :
  elif docker cp "${ctr}:/out/ralphex" "${BUILD_DIR}/${BIN_NAME}" 2>/dev/null; then
    :
  else
    echo "Failed to copy binary from container" >&2
    docker rm -v "${ctr}" >/dev/null || true
    exit 1
  fi
  docker rm -v "${ctr}" >/dev/null || true
  chmod +x "${BUILD_DIR}/${BIN_NAME}"
  echo "Copied $BUILD_DIR/${BIN_NAME} from ralphex-builder image"
  exit 0
fi

# Local build path (requires Go installed locally)
if ! command -v go >/dev/null 2>&1; then
  echo "go command not found; install Go or use --docker to build inside Docker" >&2
  exit 1
fi

echo "Building locally with go (VERSION=${VERSION}, os=${TARGETOS}, arch=${TARGETARCH})"
GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -trimpath -ldflags "-X main.revision=${VERSION} -s -w" -o "$BUILD_DIR/${BIN_NAME}" ./cmd/ralphex
if [ "$TARGETOS" != "windows" ]; then
  chmod +x "$BUILD_DIR/${BIN_NAME}"
fi
echo "Built $BUILD_DIR/${BIN_NAME} (local)"
