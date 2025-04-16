#!/bin/bash

for ip in 136.204.36.{19..23} 136.204.36.{25..28}; do
    echo "Updating Proxmox node at $ip..."
    ssh root@$ip "apt update && apt -y full-upgrade" || echo "Failed to update $ip"
    echo "----------------------------------"
done

echo "Update process completed on all nodes."
