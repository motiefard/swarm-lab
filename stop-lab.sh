#!/bin/bash
set -euo pipefail
echo "Stopping Docker Swarm lab..."

vagrant halt

echo "All VMs stopped safely."
