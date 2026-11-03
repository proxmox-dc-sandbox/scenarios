# Deployment tools container

Self-contained image with every tool the scenarios need, including the Go
orchestrator binary. Nothing is installed on the host: the container drives
the host libvirt daemon through its socket (`--network host`), the VMs run on
the host.

## Contents

| Tool | Purpose |
|------|---------|
| `orchestrator` | Go orchestrator (built from `orchestrator/`, entrypoint) |
| `virsh`, `virt-install`, `qemu-img` | libvirt/KVM VM management (host daemon) |
| `xorriso`, `proxmox-auto-install-assistant` | Proxmox VE unattended ISO |
| `tofu`, `terragrunt`, `terraform` | Proxmox provisioning |
| `git` | Terragrunt module clone |
| `ssh`, `ssh-keygen`, `sshpass` | key/token provisioning |
| `jq`, `python3`, `curl`, `wget`, `unzip`, `whois` (`mkpasswd`) | scenario scripts |

Pinned versions (`--build-arg`): `GO_VERSION` (1.26), `TERRAFORM_VERSION`
(1.9.8), `TOFU_VERSION` (1.12.5), `TERRAGRUNT_VERSION` (1.2.1).

## Usage

```bash
docker/run.sh build                                         # build the image
SCENARIO=proxmox-evpn-bgp-public-ip docker/run.sh up        # install
SCENARIO=proxmox-evpn-bgp-public-ip docker/run.sh down      # teardown
SCENARIO=proxmox-evpn-bgp-public-ip docker/run.sh resume    # after a failure
SCENARIO=proxmox-evpn-bgp-public-ip docker/run.sh guided    # step by step
SCENARIO=proxmox-evpn-bgp-public-ip docker/run.sh check     # validate
SCENARIO=proxmox-evpn-bgp-public-ip docker/run.sh shell     # debug shell

# same with an explicit flag (scenario name or path)
docker/run.sh --scenario proxmox-evpn-bgp-public-ip up
```

Extra flags are forwarded to the orchestrator, e.g.
`SCENARIO=<name> docker/run.sh up -continue-on-error`.

If `docker build` needs the host network (restrictive proxy/DNS), set
`DOCKER_BUILD_NETWORK_HOST=true`.
Set `DOCKER_BUILD_NO_CACHE=true DOCKER_BUILD_PULL=true` to fetch base images
and rebuild the full tools image without using cached layers.

## How the container is wired

- `--network host`: the Proxmox API and the libvirt bridge networks are
  reachable exactly as on the host.
- The repository is mounted at the **same absolute path** inside and outside
  the container. The scenario stores its ISO, keys, runtime images and state
  below that root, so no host-specific path file or extra mount is needed.
- Mounts: the repo (read-write), `/var/run/libvirt` (daemon socket),
  `/dev/kvm`, plus any explicit path listed in `EXTRA_MOUNTS`.
- The container runs with the **host UID/GID** and the libvirt socket group,
  so files created in the repo (runtime assets, state, logs and caches) stay
  owned by you. `HOME` is redirected to `/tmp` (ephemeral caches); the real
  home is not mounted.

## Environment

| Variable | Default | Role |
|----------|---------|------|
| `IMAGE` | `pdcs-scenarios-tools:latest` | image name |
| `EXTRA_MOUNTS` | - | extra host paths mounted at the same path |

## Notes

- The image only contains **clients**: libvirtd and QEMU keep running on the
  host. The libvirt socket group is granted automatically when the socket
  exists.
- OpenTofu provider downloads and Terragrunt caches inside the container are
  ephemeral (`/tmp`). The provider cache and unit caches inside the repo are
  persisted and gitignored.
- The `pdcs-core-tf-modules` **git clone** (repo root, mounted with the repo)
  is consumed read-only by Terragrunt (no mirror).
- Scenario inputs come from `scenario.yaml`; generated credentials and values
  emitted by steps are stored in the owner-only `.state/<scenario>.json` file.
