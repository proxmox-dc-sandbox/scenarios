# Prerequisites

> **TL;DR**: you do **not** necessarily need a bare metal server. You need a machine
> (physical or virtual) that exposes **hardware virtualization (KVM)**.
> Run the 30-second test below before installing anything.

## 1. Quick test - Check that the host has KVM support

On the machine that will host PDCS:

```bash
# 1. Does the CPU expose virtualization? (expected result: > 0)
egrep -c '(vmx|svm)' /proc/cpuinfo

# 2. Is KVM usable?
sudo apt install -y cpu-checker && sudo kvm-ok
# expected: "KVM acceleration can be used"

# 3. Does the device exist?
ls -l /dev/kvm
```

| Result | Meaning |
|--------|---------|
| All 3 tests pass | You have what you need, go to the quickstart |
| Test 1 = 0 | Virtualization is not exposed (see section 2) |
| Test 1 > 0 but `kvm-ok` fails | Enable VT-x/AMD-V in the BIOS, or load the `kvm_intel` / `kvm_amd` module |

## 2. Bare metal or virtual machine?

The real requirement is **nested virtualization**:
the machine hosting PDCS must itself be able to run KVM VMs.

- **Bare metal**: works out of the box, the simplest option.
- **VM**: the parent hypervisor must expose the virtualization instructions to the guest.
  - Proxmox: set the VM's CPU type to `host`
  - Check that nested virtualization is enabled on the host:
    - Intel: `cat /sys/module/kvm_intel/parameters/nested` (expected: `Y` or `1`)
    - AMD: `cat /sys/module/kvm_amd/parameters/nested`
- **Cloud**: see the matrix below.

## 3. Where it runs

| Environment | Status | Notes |
|-------------|--------|-------|
| Local machine / homelab (KVM enabled) | To be configured if not activated | |
| Rented bare metal (Vultr, hourly billing) | Tested | Handy for one-off tests, destroy after use |
| AWS EC2 (nested virtualization) | Announced, untested | [AWS announcement](https://aws.amazon.com/about-aws/whats-new/2026/02/amazon-ec2-nested-virtualization-on-virtual/): check which instance types are supported |
| Other clouds | Untested | |

Legend: **Tested** = validated end to end · **Announced** = the provider claims support, not validated here · **Untested**.

> Tested another environment? Open an issue or a PR to update this table.


**Indicative cost** on hourly bare metal: `<to be completed>`.
Remember to destroy everything at the end of your session to avoid paying for nothing.

## 4. What's next?

Prerequisites validated → [Quickstart](/docs/quickstart.md)

## FAQ

**Do I need a bare metal server?**
No, nested virtualization is enough. See section 2.

**Does it work on EC2?**
AWS has announced nested virtualization support on virtual instances. Run the quick test on your instance to check.

**How do I know if I have what I need?**
Run the 3 commands from section 1.