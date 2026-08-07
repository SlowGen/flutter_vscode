# Approximates a GitHub Actions runner for the CI workflow test: Linux with
# Flutter, plus the Docker CLI that the gate job needs.
#
# There is no daemon in here. The host's socket is mounted in, so images the
# gate builds are siblings of this container rather than children -- which is
# why the workflow test mounts its checkout at an identical path inside and
# out, so the gate's own `docker run -v` resolves against the host.
FROM ghcr.io/cirruslabs/flutter:stable

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      docker.io \
      git \
      nodejs \
      npm \
      xz-utils \
 && rm -rf /var/lib/apt/lists/*

# The workflow pins an exact Flutter version; the base image ships whatever
# was current when it was built. The test passes the pinned version in, so
# the container cannot silently verify a different toolchain than CI uses.
ARG FLUTTER_VERSION
RUN test -n "${FLUTTER_VERSION}" \
 && git -C /sdks/flutter fetch --tags --depth 1 origin "${FLUTTER_VERSION}" \
 && git -C /sdks/flutter checkout --quiet "${FLUTTER_VERSION}" \
 && flutter --version

# The gate scripts run as root against a mounted checkout; git refuses to
# operate on a tree owned by another uid without this.
RUN git config --global --add safe.directory '*'
