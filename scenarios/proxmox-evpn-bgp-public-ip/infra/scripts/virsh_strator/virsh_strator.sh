#!/bin/bash
set -euo pipefail

# Requirements: jq, wget, mkpasswd, virt-install, cloud-init

JSON_FILE=${1:-vms.json}
ASSET_DIR=$(pwd)/assets
BASE_IMAGE_NAME=ubuntu-24.04
BASE_IMAGE_URL=https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
BASE_IMAGE=${ASSET_DIR}/${BASE_IMAGE_NAME}.img
LIBVIRT_IMAGE_DIR=${KVM_STORE_DIR}/disks

mkdir -p "$ASSET_DIR"

# --- Pull base OS image (only once) ---
function pull_base_image() {
    if [[ ! -f "$BASE_IMAGE" ]]; then
        echo "[INFO] Downloading base image..."
        wget -O "$BASE_IMAGE" "$BASE_IMAGE_URL"
    else
        echo "[INFO] Base image already present."
    fi
}

function create_vm_dir(){
    local vm=$1
    local disk_dir=${2:-$LIBVIRT_IMAGE_DIR}
    mkdir -p "${disk_dir}/${vm}"

}

# --- Generate cloud-init config ---
function generate_cloud_init() {
    local vm_name=$1 user=$2 passwd=$3 ssh_key=$4
    local disk_dir=${5:-$LIBVIRT_IMAGE_DIR}
    local networks=${6:-}

    local hashed_passwd
    hashed_passwd=$(mkpasswd --method=SHA-512 --rounds=4096 "$passwd")

    cat > "${disk_dir}/${vm_name}/cloud-config.yaml" <<EOF
#cloud-config
hostname: ${vm_name}
users:
  - name: ${user}
    groups: sudo
    lock_passwd: false
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    passwd: ${hashed_passwd}
    ssh-authorized-keys:
      - ${ssh_key}
ssh_pwauth: true
package_update: true
packages:
  - htop
  - curl
  - wget
EOF

    # NoCloud meta-data: without a unique instance-id, cloud-init derives
    # "iid-datasource-none", which matches the pre-baked state of Ubuntu
    # cloud images -> the user-data would be silently ignored.
    cat > "${disk_dir}/${vm_name}/meta-data" <<EOF
instance-id: ${vm_name}-$(date +%s)
local-hostname: ${vm_name}
EOF

    # Optional netplan network-config: entries carrying a MAC + IP get a static
    # address, entries with a MAC only use DHCP. Required when the VM must be
    # reachable on an isolated network (e.g. the bastion's private interface).
    if [[ -n "$networks" ]]; then
        local netcfg="${disk_dir}/${vm_name}/network-config.yaml"
        local entries
        entries=$(echo "$networks" | jq -sr '
          [to_entries[] | .key as $i | .value
           | select(type == "object" and .mac != null) |
            "  net\($i):\n    match:\n      macaddress: \"" + .mac + "\"\n" +
            (if (.ip // "") != "" then "    addresses: [\"" + .ip + "\"]" else "    dhcp4: true" end)
          ] | join("\n")' 2>/dev/null || true)
        if [[ -n "$entries" ]]; then
            {
                echo "version: 2"
                echo "ethernets:"
                echo "$entries"
            } > "$netcfg"
            echo "[INFO] Generated network-config for ${vm_name}"
        fi
    fi
}

# --- Create a libvirt network (nat or isolated) from JSON ---
function create_network() {
    local name=$1 bridge=$2 mode=$3 ip=$4 netmask=$5 dhcp_start=$6 dhcp_end=$7

    bridge="${bridge:-${name}-br}"
    netmask="${netmask:-255.255.255.0}"
    mode="${mode:-nat}"

    if virsh --connect qemu:///system net-info "$name" >/dev/null 2>&1; then
        echo "[INFO] Network $name already exists."
        if [ "$(virsh --connect qemu:///system net-info "$name" | awk '/^Active:/{print $2}')" != "yes" ]; then
            echo "[INFO] Starting inactive network $name"
            virsh --connect qemu:///system net-start "$name"
        fi
        return 0
    fi

    local forward=""
    if [[ "$mode" == "nat" ]]; then
        forward="  <forward mode='nat'>
    <nat/>
  </forward>"
    fi

    local dhcp=""
    if [[ -n "$dhcp_start" && -n "$dhcp_end" ]]; then
        dhcp="    <dhcp>
      <range start='${dhcp_start}' end='${dhcp_end}'/>
    </dhcp>"
    fi

    local xml="${name}-net.xml"
    cat > "$xml" <<EOF
<network>
  <name>${name}</name>
  <bridge name="${bridge}" stp="on" delay="0"/>
${forward}  <ip address="${ip}" netmask="${netmask}">
${dhcp}  </ip>
</network>
EOF

    echo "[INFO] Defining network $name (${mode})"
    virsh --connect qemu:///system net-define "$xml"
    virsh --connect qemu:///system net-start "$name"
    virsh --connect qemu:///system net-autostart "$name"
}

function delete_network() {
    local name=$1
    echo "[INFO] Deleting network $name"
    virsh --connect qemu:///system net-destroy "$name"
    virsh --connect qemu:///system net-undefine "$name"
}

# --- Build virt-install --network args from a mixed list of
#     network names ("default") or interface objects ---
function build_network_args() {
    local entry
    local net_args=""
    while IFS= read -r entry; do
        if [[ "$entry" == \{* ]]; then
            local ntype source model mac
            ntype=$(echo "$entry" | jq -r '.type // "network"')
            source=$(echo "$entry" | jq -r '.source // empty')
            model=$(echo "$entry" | jq -r '.model // empty')
            mac=$(echo "$entry" | jq -r '.mac // empty')

            local net_arg=""
            case "$ntype" in
                direct)
                    net_arg="--network type=direct,source=${source}"
                    ;;
                bridge)
                    net_arg="--network bridge=${source}"
                    ;;
                *)
                    net_arg="--network network=${source}"
                    ;;
            esac
            [[ -n "$model" ]] && net_arg+=",model=${model}"
            [[ -n "$mac" ]] && net_arg+=",mac=${mac}"
            net_args+=" ${net_arg}"
        else
            entry="${entry%\"}"
            entry="${entry#\"}"
            net_args+=" --network network=${entry}"
        fi
    done
    echo "$net_args"
}

# --- Create VM ---
function create_vm() {
    local vm_name=$1 ram=$2 vcpus=$3 disk_size=$4 networks=$5
    local iso_path=${6:-}
    local disk_dir=${7:-$LIBVIRT_IMAGE_DIR}
    local os_variant=${8:-}

    if virsh --connect qemu:///system dominfo "$vm_name" >/dev/null 2>&1; then
        echo "[OK] VM $vm_name already exists - skipping creation"
        return 0
    fi

    echo "[INFO] Creating VM $vm_name"

    local vm_dir="${disk_dir}/${vm_name}"
    local disk_path="${vm_dir}/${BASE_IMAGE_NAME}.img"

    mkdir -p "$vm_dir"

    # If no os_variant provided, pick a sensible default
    if [[ -z "$os_variant" ]]; then
        if [[ -n "$iso_path" ]]; then
            os_variant=generic
        else
            os_variant=ubuntu20.04
        fi
    fi

    # Build disk / boot args depending on the install method
    local disk_args=""
    local boot_args=""
    local cloud_init_args=""
    if [[ -n "$iso_path" ]]; then
        # Install from ISO: create an empty disk and boot from the ISO
        # disk_args="--disk=size=${disk_size},path=${disk_path},format=qcow2"
        disk_args="--disk path=${disk_path},size=${disk_size},bus=virtio,format=qcow2"
        boot_args="--cdrom=${iso_path} --boot hd,cdrom"
        echo "[INFO] $vm_name will be installed from ISO: $iso_path"
    else
        # Cloud-init install: copy the base image and inject user-data
        cp "${BASE_IMAGE}" "$vm_dir/"
        # disk_args="--disk=size=${disk_size},path=${disk_path}"
        disk_args="--disk path=${disk_path},size=${disk_size},bus=virtio,format=qcow2"
        echo "$disk_args"
        cloud_init_args="--cloud-init user-data=${vm_dir}/cloud-config.yaml"
        if [[ -f "${vm_dir}/meta-data" ]]; then
            cloud_init_args+=",meta-data=${vm_dir}/meta-data"
        fi
        if [[ -f "${vm_dir}/network-config.yaml" ]]; then
            cloud_init_args+=",network-config=${vm_dir}/network-config.yaml"
        fi
    fi

    # Make the VM files readable by the QEMU process (non-root: chown may
    # fail, but world-readable files are enough for libvirt-qemu)
    chown -R libvirt-qemu:kvm "$vm_dir/" 2>/dev/null || \
        echo "[WARN] chown skipped (non-root): ensure files are readable by libvirt-qemu"

    # Build network args dynamically (mixed: names and/or interface objects)
    local net_args=""
    net_args=$(build_network_args <<< "$networks")

    virt-install \
        --connect qemu:///system \
        --name "${vm_name}" \
        --ram "${ram}" \
        --vcpus "${vcpus}" \
        ${disk_args} \
        ${boot_args} \
        --os-variant "${os_variant}" \
        --graphics vnc,listen=0.0.0.0 \
        --console pty,target_type=serial \
        --check path_in_use=off \
        ${cloud_init_args} \
        --noautoconsole \
        ${net_args}
}

function delete_vm() {
    local vm_name=$1
    local disk_dir=${2:-$LIBVIRT_IMAGE_DIR}
    virsh --connect qemu:///system destroy "$vm_name"
    virsh --connect qemu:///system undefine "$vm_name"
    rm -rf "${disk_dir}/${vm_name}/"
    virsh pool-destroy "$vm_name"
    virsh pool-undefine "$vm_name"
}

function get_ip_addr() {
    local ip=$(virsh domifaddr "$vm_name" | awk '/ipv4/ {print $4}' | cut -d'/' -f1)
    echo "$vm_name:$ip"
}

function stop_vm() {
    virsh --connect qemu:///system destroy "$vm_name"
}

function start_vm() {
    virsh --connect qemu:///system start "$vm_name"
}

# --- Main ---
# pull_base_image

# jq -c '.[]' "$JSON_FILE" | while read -r vm; do
#     vm_type=$(echo "$vm" | jq -r '.type // "vm"')

#     if [[ "$vm_type" == "network" ]]; then
#         name=$(echo "$vm" | jq -r '.name')
#         bridge=$(echo "$vm" | jq -r '.bridge // empty')
#         mode=$(echo "$vm" | jq -r '.mode // "nat"')
#         ip=$(echo "$vm" | jq -r '.ip')
#         netmask=$(echo "$vm" | jq -r '.netmask // empty')
#         dhcp_start=$(echo "$vm" | jq -r '.dhcp_start // empty')
#         dhcp_end=$(echo "$vm" | jq -r '.dhcp_end // empty')
#         create_network "$name" "$bridge" "$mode" "$ip" "$netmask" "$dhcp_start" "$dhcp_end"
#         continue
#     fi

#     vm_name=$(echo "$vm" | jq -r '.hostname')
#     ram=$(echo "$vm" | jq -r '.ram')
#     vcpus=$(echo "$vm" | jq -r '.vcpus')
#     disk_size=$(echo "$vm" | jq -r '.disk_size')
#     user=$(echo "$vm" | jq -r '.user_name')
#     passwd=$(echo "$vm" | jq -r '.password')
#     ssh_key=$(echo "$vm" | jq -r '.ssh_pub_key')
#     networks=$(echo "$vm" | jq -c '.networks[]' 2>/dev/null || true)
#     iso_path=$(echo "$vm" | jq -r '.iso_path // empty')
#     disk_dir=$(echo "$vm" | jq -r '.disk_dir // empty')
#     os_variant=$(echo "$vm" | jq -r '.os_variant // empty')

#     disk_dir="${disk_dir:-$LIBVIRT_IMAGE_DIR}"

#     create_vm_dir "$vm_name" "$disk_dir"

#     if [[ -z "$iso_path" ]]; then
#         generate_cloud_init "$vm_name" "$user" "$passwd" "$ssh_key" "$disk_dir"
#     fi
#     create_vm "$vm_name" "$ram" "$vcpus" "$disk_size" "$networks" "$iso_path" "$disk_dir" "$os_variant"
# done
