# Disk and artifact storage

## Default storage

`docker/run.sh` mounts the repository at its own absolute path inside the
container. Relative paths declared with `path: true` in `scenario.yaml` are
resolved by the Go orchestrator from the scenario root, on the host side:
they are not relative to the Docker `WORKDIR`.

| Artifact | Default location | Configuration |
|---|---|---|
| Downloaded Proxmox ISO | `scenarios/proxmox-evpn-bgp-public-ip/assets/proxmox-ve_9.2-1.iso` | `PVE_ISO` |
| Downloaded CHR image and CHR disk | `runtime/kvm_store/mikrotik/` and `runtime/kvm_store/mikrotik-bgp.qcow2` | `KVM_STORE_DIR` |
| Bastion disk | `runtime/kvm_store/disks/pdcs-bastion/` | `KVM_STORE_DIR` |
| Bastion cloud-image cache | `infra/scripts/bastion/assets/` | Script directory |
| Proxmox VM disk and prepared installation ISO | libvirt pool named by `VM_POOL` (default `default`) | `VM_POOL` |
| Generated state and secrets | `.state/` | Managed by the orchestrator |
| Scenario SSH key | `.ssh/id_ed25519` | Managed by the `ssh-keygen` step |

`runtime/`, the ISOs, images, disks, states and keys are gitignored.
The `runtime/` directory is also excluded from the Docker build context, but
remains present in the execution bind mount.

## `KVM_STORE_DIR` and `VM_POOL`

- `KVM_STORE_DIR` holds the files the scripts manipulate directly inside the
  container, notably the CHR image/disk and the bastion disk. The default
  `runtime/kvm_store` lives under the repository: no `EXTRA_MOUNTS` needed.
- `VM_POOL` is a **libvirt pool name**, not a path. Libvirt on the host
  creates the PVE disk in that pool; the container does not need to mount
  the pool path. If the pool does not exist, `proxmox/run.sh` creates it
  under `/var/lib/libvirt/images/<VM_POOL>`.
- The cloudbox VM disks live inside the PVE VM disk; their storage follows
  the `VM_POOL` pool.

## Placing the CHR/bastion disks outside the repository

To store the CHR and bastion disks elsewhere, use an absolute path in
`scenario.yaml`, then mount that path through `EXTRA_MOUNTS`:

```yaml
  - name: KVM_STORE_DIR
    value: "/mnt/lab/kvm_store/scenario"
    path: true
```

```bash
mkdir -p /mnt/lab/kvm_store/scenario
EXTRA_MOUNTS=/mnt/lab/kvm_store/scenario \
  docker/run.sh --scenario proxmox-evpn-bgp-public-ip up
```

`EXTRA_MOUNTS` accepts several absolute paths separated by spaces; each path
is mounted read-write at the same path inside the container. The path must
exist on the host and be accessible to the user running Docker as well as to
libvirt/QEMU.

To move the **PVE disk** elsewhere, create a libvirt pool on the target path,
then set its name in `VM_POOL`:

```bash
mkdir -p /mnt/lab/kvm_store/pve
virsh --connect qemu:///system pool-define-as pve-store dir \
  --target /mnt/lab/kvm_store/pve
virsh --connect qemu:///system pool-build pve-store
virsh --connect qemu:///system pool-start pve-store
virsh --connect qemu:///system pool-autostart pve-store
```

```yaml
  - name: VM_POOL
    value: "pve-store"
```

The external pool is managed by libvirt on the host; do not add it to
`EXTRA_MOUNTS`.

## Keep in mind

- Changing the paths does not move already-created VM disks. Destroy and
  redeploy the scenario, or migrate the disks and update the libvirt domain
  definitions.
- The cleanup removes the VMs/disks it manages, but does not remove the
  external libvirt pool nor the downloaded image caches.
- The Proxmox ISO is deliberately downloaded under `assets/` in the
  scenario so it stays reachable and portable with the repository bind
  mount alone. The script currently refuses a `PVE_ISO` located outside the
  scenario.
