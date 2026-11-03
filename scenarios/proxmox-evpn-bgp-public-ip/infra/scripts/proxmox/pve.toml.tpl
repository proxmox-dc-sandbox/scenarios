# Proxmox VE unattended answer file — rendered at install time by run.sh.
# ${VAR} and ${VAR:-default} placeholders come from values injected from
# scenario.yaml and private orchestrator state. PVE_ROOT_PASSWORD is required;
# PVE_SSH_PUBKEY is provided by the ssh-keygen step (LAB_VM_SSH_KEY fallback).

[global]
keyboard = "${PVE_KEYBOARD}"
country = "${PVE_COUNTRY}"
fqdn = "${PVE_FQDN}"
mailto = "${PVE_MAILTO}"
timezone = "${PVE_TIMEZONE}"
root-password = "${PVE_ROOT_PASSWORD}"
root-ssh-keys = ["${PVE_SSH_PUBKEY}"]

[network]
source = "from-answer"
cidr = "${PVE_CIDR}"
dns = "${PVE_DNS}"
gateway = "${PVE_GATEWAY}"
filter.INTERFACE = "${PVE_NIC}"

[disk-setup]
filesystem = "ext4"
disk-list = ["vda"]
