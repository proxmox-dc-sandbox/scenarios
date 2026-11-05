# Quickstart

> Fresh host: full setup to run the scenarios

Runbook: prepare a fresh host (Debian 13 "trixie" or Ubuntu 24.04+) so you can
run the `proxmox-evpn-bgp-public-ip` example scenario.

**How it fits together:** the host is the **KVM machine** (libvirtd + QEMU run
directly on it). The Proxmox VE VM runs **nested** inside it. All the tooling
(orchestrator, OpenTofu, Terragrunt, ...) runs in a Docker container, so the
host only needs **Docker + KVM/libvirt**.

> **Not sure your machine can do this?** Run the 30-second test in
> [Prerequisites](/docs/prerequisites.md) first. You need KVM and nested
> virtualization on the host.

---

## 1. System packages

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  ca-certificates curl wget git jq unzip openssh-client sshpass \
  iproute2 procps libvirt-daemon-system libvirt-clients \
  qemu-system-x86 qemu-utils virtinst cpu-checker
```

What each package is for:

| Package | Provides | Used in the lab for |
|---|---|---|
| `libvirt-daemon-system` | `libvirtd` | Daemon that runs the VMs |
| `libvirt-clients` | `virsh` | Managing networks and VMs (`qemu:///system`) |
| `qemu-system-x86` + KVM | `/dev/kvm` | Virtualization (the nested Proxmox VM) |
| `qemu-utils` | `qemu-img` | Incremental disk images |
| `virtinst` | `virt-install` | Creating the lab networks and VMs |
| `cpu-checker` | `kvm-ok` | Diagnosing nested virtualization |

## 2. KVM and nested virtualization

The Proxmox VE VM starts VMs of its own, so the host must allow nested
virtualization.

**Step 1: give your user access to libvirt and start the daemon**

```bash
sudo usermod -aG libvirt "$USER"    # log out and back in afterwards (or run: newgrp libvirt)
sudo systemctl enable --now libvirtd
```

**Step 2: check whether nested virtualization is already on**

```bash
cat /sys/module/kvm_intel/parameters/nested 2>/dev/null || cat /sys/module/kvm_amd/parameters/nested
```

If it prints `Y` or `1`, nested is enabled and you can skip step 3. If both
files are missing, KVM is not available on this machine: go back to
[Prerequisites](/docs/prerequisites.md).

**Step 3: enable it if needed (run only the line matching your CPU)**

```bash
# Intel:
echo 'options kvm_intel nested=1' | sudo tee /etc/modprobe.d/kvm-nested.conf
# AMD:
echo 'options kvm_amd nested=1'   | sudo tee /etc/modprobe.d/kvm-nested.conf

# Reload the KVM modules
sudo modprobe -r kvm_intel kvm_amd 2>/dev/null; sudo modprobe kvm_intel kvm_amd 2>/dev/null || true
```

> Both lines write to the same file, so run only one of them. The module
> reload fails if a VM is running; in that case reboot the host instead.

**Step 4: verify**

```bash
kvm-ok                                 # expected: "KVM acceleration can be used"
ls -l /dev/kvm
cat /sys/module/kvm_intel/parameters/nested 2>/dev/null || cat /sys/module/kvm_amd/parameters/nested
virsh --connect qemu:///system uri     # expected: "qemu:///system"
```

## 3. Install Docker

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"      # log out and back in afterwards (or run: newgrp docker)
```

Nothing else to install on the host: the VMs run on the host's libvirtd, and
the container drives the `/var/run/libvirt` socket with `--network host`
(see `docker/README.md`).

## 4. Get the scenarios and build the tools image

```bash
git clone <scenarios-repo-url>       # replace with the repository URL
cd <scenarios-repo>
docker/run.sh build                  # build the tools image (orchestrator, tofu, terragrunt, virsh...)
```

## 5. Run a scenario

Each scenario has its own README with its steps, required local secrets and
tests. Start with the example scenario:
`scenarios/proxmox-evpn-bgp-public-ip/README.md`.

Launch it from the repository root:

```bash
docker/run.sh guided    # step by step; or use: up / down / resume / check / shell
```

> **Note:** for development, you can also run everything natively, without
> Docker. See the orchestrator README for details.