[
  {
    "hostname": "pdcs-bastion",
    "ram": "2048",
    "vcpus": "1",
    "disk_size": "20",
    "user_name": "lab_user",
    "password": "${LAB_VM_PASSWORD}",
    "ssh_pub_key": "${LAB_VM_SSH_KEY}",
    "networks": [
      {
        "type": "network",
        "source": "pdcs-public-network",
        "model": "virtio",
        "mac": "52:54:00:00:00:ba"
      },
      {
        "type": "network",
        "source": "pdcs-private-network",
        "model": "virtio",
        "mac": "52:54:00:00:00:bb",
        "ip": "10.10.0.2/24"
      }
    ]
  }
]
