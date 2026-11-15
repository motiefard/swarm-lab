#!/bin/bash

set -e

echo "=== Installing Docker Engine ==="

# Configure IUT mirror
echo "Configure IUT mirror ..."
cat > /etc/apt/sources.list <<'EOFIUT'
deb http://repo.iut.ac.ir/ubuntu/ jammy main restricted universe multiverse
deb http://repo.iut.ac.ir/ubuntu/ jammy-updates main restricted universe multiverse
deb http://repo.iut.ac.ir/ubuntu/ jammy-security main restricted universe multiverse
#deb http://repo.iut.ac.ir/ubuntu/ jammy-backports main restricted universe multiverse
#deb http://repo.iut.ac.ir/ubuntu/ jammy-proposed main restricted universe multiverse
EOFIUT


# Disabling DNSSEC validation
echo "=== Fixing DNS resolution ==="
mkdir -p /etc/systemd/resolved.conf.d

cat > /etc/systemd/resolved.conf.d/swarm-dns.conf <<'EOF'
[Resolve]
DNS=1.1.1.1 8.8.8.8
DNSSEC=no
EOF

systemctl restart systemd-resolved

# Apply DNS settings to the internet-facing interface
resolvectl dns eth0 1.1.1.1 8.8.8.8
resolvectl domain eth0 '~.'
resolvectl dnssec eth0 no

resolvectl flush-caches

echo "=== DNS configuration ==="
resolvectl status



# Update packages
apt-get update

# Install prerequisites
apt-get install -y ca-certificates curl

# Create keyrings directory
install -m 0755 -d /etc/apt/keyrings

# Download Docker GPG key
# curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
#   -o /etc/apt/keyrings/docker.asc
sudo curl -fsSL https://repo.abrha.net/docker/ubuntu/gpg -o /etc/apt/keyrings/docker.asc

chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker repository
cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://repo.abrha.net/docker/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

# Update repository information
apt-get update

# Install Docker Engine and plugins
apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

# Enable Docker service
systemctl enable docker
systemctl start docker

echo "=== Docker installation completed ==="

docker --version

systemctl is-active docker
