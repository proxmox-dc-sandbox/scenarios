# syntax=docker/dockerfile:1
#
# Tools image for the deployment scenarios (Proxmox/KVM lab).
#
# The container drives the libvirt daemon of the HOST through its socket and
# runs with --network host: the VMs run on the host, not in the container.
# Nothing is installed on the host besides Docker.
#
# It includes every tool the scenarios need (virsh, virt-install, qemu-img,
# xorriso, proxmox-auto-install-assistant, OpenTofu, Terragrunt, Terraform)
# and the Go orchestrator binary itself.
#
# Build (from the repo root):
#   docker build -f docker/Dockerfile -t pdcs-scenarios-tools:latest .
# Or simply:
#   docker/run.sh build
#
# Run (see docker/run.sh for the mounts): the image entrypoint is the
# orchestrator, e.g.
#   docker run --rm --network host -v "$PWD:$PWD" -w "$PWD" IMAGE \
#     -scenario scenarios/proxmox-evpn-bgp-public-ip/scenario.yaml -check

ARG GO_VERSION=1.26
ARG TERRAFORM_VERSION=1.9.8

# --- orchestrator binary ----------------------------------------------------
FROM golang:${GO_VERSION}-bookworm AS orchestrator
WORKDIR /src
COPY orchestrator/go.mod orchestrator/go.sum ./
RUN go mod download
COPY orchestrator/ ./
RUN CGO_ENABLED=0 go build -trimpath -o /out/orchestrator ./cmd/orchestrator

# --- terraform binary -------------------------------------------------------
FROM hashicorp/terraform:${TERRAFORM_VERSION} AS terraform

# --- tools image ------------------------------------------------------------
# Debian 13 (trixie): same base as Proxmox VE 9, so the Proxmox packages
# install cleanly.
FROM debian:trixie-slim

ARG TOFU_VERSION=1.12.5
ARG TERRAGRUNT_VERSION=1.2.1

ENV DEBIAN_FRONTEND=noninteractive \
    LIBVIRT_DEFAULT_URI=qemu:///system

# Client tools only: no libvirt daemon, no QEMU emulator (they run on the host).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash ca-certificates curl wget git jq openssh-client sshpass \
      libvirt-clients virtinst qemu-utils xorriso \
      python3 unzip whois findutils procps iproute2 \
 && rm -rf /var/lib/apt/lists/*

# proxmox-auto-install-assistant comes from the Proxmox repository.
# The repository is removed right after the install so nothing else is pulled
# from it.
RUN wget -q https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg \
      -O /usr/share/keyrings/proxmox-archive-keyring.gpg \
 && printf '%s\n' \
      'Types: deb' \
      'URIs: http://download.proxmox.com/debian/pve' \
      'Suites: trixie' \
      'Components: pve-no-subscription' \
      'Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg' \
      > /etc/apt/sources.list.d/pve-temp.sources \
 && apt-get update \
 && apt-get install -y --no-install-recommends proxmox-auto-install-assistant \
 && rm -f /etc/apt/sources.list.d/pve-temp.sources \
 && rm -rf /var/lib/apt/lists/*

# OpenTofu and Terragrunt (multi-arch).
RUN set -eux; \
    ARCH="$(dpkg --print-architecture)"; \
    curl -fsSL \
      "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_${ARCH}.zip" \
      -o /tmp/tofu.zip; \
    unzip -o /tmp/tofu.zip -d /usr/local/bin; \
    rm -f /tmp/tofu.zip; \
    curl -fsSL \
      "https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}/terragrunt_linux_${ARCH}" \
      -o /usr/local/bin/terragrunt; \
    chmod +x /usr/local/bin/terragrunt

COPY --from=terraform /bin/terraform /usr/local/bin/terraform
COPY --from=orchestrator /out/orchestrator /usr/local/bin/orchestrator

# NOTE: no build-time git safe.directory here. The scenario repository is
# mounted at its own host path (docker/run.sh: -v "${REPO_ROOT}:${REPO_ROOT}")
# and the container runs as the invoking user's uid/gid (--user "$(id -u):$(id -g)"),
# so file ownership matches and git never reports "dubious ownership" for the
# core-modules clone. The scenario's node-prep step still adds a safe.directory
# computed from its own location for environments where that is not true.

# Sanity check at build time: every tool used by the scenarios must be there.
RUN virsh --version \
 && virt-install --version \
 && qemu-img --version | head -n1 \
 && xorriso -version | head -n1 \
 && tofu version | head -n1 \
 && terragrunt --version \
 && terraform version | head -n1 \
 && proxmox-auto-install-assistant --help >/dev/null \
 && python3 --version \
 && jq --version \
 && ssh-keygen -? 2>/dev/null | head -n1 \
&& orchestrator -h >/dev/null

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/orchestrator"]
CMD ["-h"]
