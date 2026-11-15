# Docker Swarm Lab with Vagrant, KVM/QEMU, and Libvirt

A hands-on Docker Swarm learning project running a three-node cluster of Ubuntu 22.04 virtual machines. The infrastructure is provisioned with Vagrant and the `vagrant-libvirt` provider on an Ubuntu 24.04 host.

The lab starts with independent Docker Engine installations, forms a Swarm cluster, and deploys a replicated Nginx service. It demonstrates both imperative service management (`docker service create`) and declarative deployment using a YAML file (`docker stack deploy`).

> **Current scope:** This README documents the three-node infrastructure and Nginx service/stack exercises. It does not assume that a Flask backend, Redis, or other future application components have already been implemented.

## 1. Learning objectives

By completing this lab, you practise:

- Creating and managing Linux virtual machines with Vagrant.
- Using KVM/QEMU and libvirt as the virtualization provider.
- Configuring private networking and static IP addresses.
- Installing Docker Engine automatically with shell provisioning.
- Understanding Docker images, containers, and the Docker daemon.
- Initializing a Docker Swarm cluster.
- Understanding manager and worker nodes, join tokens, and node availability.
- Creating and inspecting Swarm services and tasks.
- Running replicated containers across a cluster.
- Publishing service ports through the Swarm routing mesh.
- Scaling services by changing their desired replica count.
- Defining services, networks, and deployment settings in YAML.
- Deploying and updating an application with Docker Stack.

## 2. Architecture

### Host environment

| Component | Value |
|---|---|
| Host OS | Ubuntu 24.04 |
| Virtualization | KVM/QEMU with libvirt |
| Vagrant | 2.4.9 |
| vagrant-libvirt plugin | 0.12.2 |
| Guest OS | Ubuntu 22.04 |
| Base box | `generic/ubuntu2204` |
| Container runtime/engine | Docker Engine |

### Virtual machines

| VM | Swarm role | Swarm network IP | RAM | vCPUs |
|---|---|---:|---:|---:|
| `swarm-manager` | Manager / Leader | `192.168.56.10` | 1536 MB | 2 |
| `swarm-worker1` | Worker | `192.168.56.11` | 1024 MB | 1 |
| `swarm-worker2` | Worker | `192.168.56.12` | 1024 MB | 1 |

The Vagrant/libvirt management network is separate from the private `swarm-net` network used for node-to-node Swarm communication. Each VM may therefore have more than one network interface.

### Logical topology

```text
                    Ubuntu 24.04 Host
                           |
                       Vagrant
                           |
                    KVM/QEMU + libvirt
                           |
                 Vagrant management network
                           |
        +------------------+------------------+
        |                  |                  |
  swarm-manager       swarm-worker1      swarm-worker2
  192.168.56.10       192.168.56.11      192.168.56.12
    Manager              Worker              Worker
        |                  |                  |
        +------------------+------------------+
                    swarm-net
                 Docker Swarm cluster
```

## 3. Project structure

```text
vagrant-swarm-lab/
├── Vagrantfile
├── scripts/
│   └── install-docker.sh
└── stack/
    └── docker-compose.yml
```

| File/directory | Purpose |
|---|---|
| `Vagrantfile` | Defines the three VMs, their resources, hostnames, and private network configuration. |
| `scripts/install-docker.sh` | Installs Docker Engine and its CLI/plugins inside each VM. |
| `stack/docker-compose.yml` | Declares the Nginx Swarm service, published port, overlay network, replicas, and deployment settings. |
| `stack/` | Holds Docker Stack YAML files. |

The README assumes the filenames and paths above. If your local project uses different names, update the paths in the commands below.

## 4. Prerequisites

On the Ubuntu 24.04 host, install/configure:

- KVM/QEMU and libvirt.
- Vagrant 2.4.9.
- `vagrant-libvirt` 0.12.2.
- The `generic/ubuntu2204` Vagrant box.

Check the tools and box:

```bash
vagrant --version
vagrant plugin list
vagrant box list
sudo virsh net-list --all
```

The host needs sufficient free RAM and disk space for three VMs, their operating systems, and downloaded container images. Resource use depends on the workload.

Run Vagrant commands as your normal host user; do not run `vagrant` with `sudo`.

## 5. Create and start the virtual machines

From the project root:

```bash
vagrant validate
vagrant up --provider=libvirt
```

Check VM status:

```bash
vagrant status
```

All three machines should be `running`.

Check libvirt networks:

```bash
sudo virsh net-list --all
```

The Vagrantfile configures a private network named `swarm-net`. Depending on the provider configuration, Vagrant may also create/use a separate management network for SSH access.

### Verify node-to-node networking

From the host:

```bash
vagrant ssh swarm-manager -c "ip -br addr"
vagrant ssh swarm-manager -c "ping -c 3 192.168.56.11"
vagrant ssh swarm-manager -c "ping -c 3 192.168.56.12"
```

The manager should have `192.168.56.10` on its Swarm-facing interface, and both worker addresses should be reachable.

## 6. Install Docker Engine

Docker is installed by the Vagrant shell provisioning script.

Run provisioning for all VMs:

```bash
vagrant provision
```

The script uses Docker's official Ubuntu APT repository and installs:

- `docker-ce` — Docker Engine.
- `docker-ce-cli` — Docker command-line client.
- `containerd.io` — container runtime.
- `docker-buildx-plugin` — Buildx CLI plugin.
- `docker-compose-plugin` — Docker Compose CLI plugin.

It also enables and starts the Docker service.

### Verify Docker on each VM

```bash
vagrant ssh swarm-manager -c "docker --version"
vagrant ssh swarm-worker1 -c "docker --version"
vagrant ssh swarm-worker2 -c "docker --version"
```

Check the daemon:

```bash
vagrant ssh swarm-manager -c "sudo systemctl is-active docker"
vagrant ssh swarm-worker1 -c "sudo systemctl is-active docker"
vagrant ssh swarm-worker2 -c "sudo systemctl is-active docker"
```

Run a test container on each node:

```bash
vagrant ssh swarm-manager -c "sudo docker run --rm hello-world"
vagrant ssh swarm-worker1 -c "sudo docker run --rm hello-world"
vagrant ssh swarm-worker2 -c "sudo docker run --rm hello-world"
```

## 7. Initialize the Docker Swarm cluster

A Swarm cluster is formed from Docker Engines running on separate nodes. One or more nodes have the manager role; worker nodes run assigned service tasks.

### Initialize the manager

Connect to the manager:

```bash
vagrant ssh swarm-manager
```

Initialize Swarm using the manager's Swarm-network address:

```bash
sudo docker swarm init --advertise-addr 192.168.56.10
```

The command prints a worker join command containing a secret token.

### Retrieve the worker token

On the manager:

```bash
sudo docker swarm join-token worker
```

Copy the actual join command printed by Docker. Keep the token secret.

### Join Worker 1

In a host terminal:

```bash
vagrant ssh swarm-worker1
```

Run the join command printed by your manager. It has this form:

```bash
sudo docker swarm join --token <WORKER_JOIN_TOKEN> 192.168.56.10:2377
```

### Join Worker 2

```bash
vagrant ssh swarm-worker2
```

Run the same join command on Worker 2.

### Verify the cluster

On the manager:

```bash
sudo docker node ls
```

Expected state:

- `swarm-manager`: `Ready`, `Active`, manager status `Leader` (in a single-manager cluster).
- `swarm-worker1`: `Ready`, `Active`.
- `swarm-worker2`: `Ready`, `Active`.

Also inspect Swarm information:

```bash
sudo docker info
```

Look for `Swarm: active`, `Managers: 1`, and `Nodes: 3`.

> **Manager availability note:** This lab has only one manager. It is suitable for learning, but it is not a highly available manager configuration. If the manager goes down, existing tasks may continue running, but the cluster cannot make normal manager-controlled scheduling and configuration changes until manager control is restored.

## 8. Deploy Nginx using the Docker service CLI

This first deployment demonstrates the imperative service-management approach.

On the manager:

```bash
sudo docker service create \
  --name web \
  --replicas 3 \
  --publish published=8080,target=80 \
  nginx:alpine
```

Inspect the service and its tasks:

```bash
sudo docker service ls
sudo docker service ps web
```

See containers on each node:

```bash
vagrant ssh swarm-manager -c "sudo docker ps"
vagrant ssh swarm-worker1 -c "sudo docker ps"
vagrant ssh swarm-worker2 -c "sudo docker ps"
```

### Test the application

From the host:

```bash
curl http://192.168.56.10:8080
curl http://192.168.56.11:8080
curl http://192.168.56.12:8080
```

The requests should return the Nginx welcome page.

The published port uses Swarm's default ingress routing mesh. A node can accept traffic on the published port and route it to an available task, even if that task is running on another node. This requires the relevant network connectivity between nodes.

### Scale the service

On the manager:

```bash
sudo docker service scale web=5
sudo docker service ls
sudo docker service ps web
```

Scale it back:

```bash
sudo docker service scale web=2
```

Remove the CLI-created service before deploying the stack version, because both examples publish port 8080:

```bash
sudo docker service rm web
```

## 9. Deploy Nginx using a YAML file and Docker Stack

Docker Stack allows the application configuration to be declared in a YAML file and deployed to a Swarm manager.

The example file is `stack/docker-compose.yml`:

```yaml
version: "3.8"

services:
  web:
    image: nginx:alpine

    ports:
      - target: 80
        published: 8080
        protocol: tcp
        mode: ingress

    deploy:
      replicas: 3

      restart_policy:
        condition: on-failure

      update_config:
        parallelism: 1
        delay: 10s

      resources:
        limits:
          cpus: "0.50"
          memory: 128M

    networks:
      - web-network

networks:
  web-network:
    driver: overlay
```

### Make the YAML available on the manager

The file is on the host, while `docker stack deploy` runs on the manager. Upload it:

```bash
vagrant upload stack/docker-compose.yml \
  /home/vagrant/docker-compose.yml swarm-manager
```

### Deploy the stack

```bash
vagrant ssh swarm-manager
```

On the manager:

```bash
sudo docker stack deploy \
  --compose-file /home/vagrant/docker-compose.yml \
  myapp
```

Docker creates a stack named `myapp`. Its service is automatically named `myapp_web`, and its overlay network is named `myapp_web-network`.

### Verify the stack

```bash
sudo docker stack ls
sudo docker stack services myapp
sudo docker stack ps myapp
sudo docker service ls
sudo docker network ls
```

Inspect the overlay network:

```bash
sudo docker network inspect myapp_web-network
```

Test Nginx again from the host:

```bash
curl http://192.168.56.10:8080
curl http://192.168.56.11:8080
curl http://192.168.56.12:8080
```

### Update the stack

Change the replica count in `stack/docker-compose.yml`, for example:

```yaml
deploy:
  replicas: 5
```

Upload the updated file:

```bash
vagrant upload stack/docker-compose.yml \
  /home/vagrant/docker-compose.yml swarm-manager
```

Deploy it again:

```bash
vagrant ssh swarm-manager -c \
  "sudo docker stack deploy --compose-file /home/vagrant/docker-compose.yml myapp"
```

Check the result:

```bash
vagrant ssh swarm-manager -c "sudo docker stack services myapp"
vagrant ssh swarm-manager -c "sudo docker stack ps myapp"
```

Stack deployment is declarative: update the YAML and redeploy to make the running stack converge toward the declared configuration.

> `docker stack deploy` uses the legacy Compose file format supported by Docker Stack. Not every feature of the latest Docker Compose specification is supported. The `version: "3.8"` declaration is included for this Swarm Stack example.

## 10. Important Docker Swarm concepts

| Concept | Meaning | Useful command |
|---|---|---|
| Swarm | A cluster of Docker Engines | `docker info` |
| Manager node | Maintains cluster state and schedules tasks | `docker node ls` |
| Worker node | Runs tasks assigned by managers | `docker node ls` |
| Join token | Credential used to add a node with a particular role | `docker swarm join-token worker` |
| Node availability | Whether a node can receive new tasks | `docker node update --availability drain <node>` |
| Service | Declares the desired state of an application workload | `docker service ls` |
| Task | An individual scheduled unit of a service | `docker service ps <service>` |
| Replica | One desired instance of a replicated service | `deploy.replicas` |
| Overlay network | Connects services across Swarm nodes | `docker network ls` |
| Routing mesh | Routes published-port traffic to service tasks | `ports.mode: ingress` |
| Stack | A group of related services deployed from a YAML file | `docker stack ls` |
| Rolling update | Updates service tasks progressively | `deploy.update_config` |
| Desired state | The declared state Swarm attempts to maintain | `docker service inspect <service>` |

### Important networking ports

Ensure these ports are reachable between Swarm nodes:

| Port | Protocol | Purpose |
|---|---|---|
| 2377 | TCP | Swarm management/control plane |
| 7946 | TCP and UDP | Node communication and discovery |
| 4789 | UDP | Overlay network data path |

Do not expose these ports to untrusted networks. For a local lab, restrict access to the private VM network.

## 11. Useful day-to-day commands

### Vagrant / VM management

```bash
vagrant status
vagrant up
vagrant halt
vagrant reload
vagrant provision
vagrant ssh swarm-manager
vagrant destroy
```

### Swarm management

```bash
sudo docker node ls
sudo docker node inspect self
sudo docker swarm join-token worker
sudo docker swarm leave
```

### Service management

```bash
sudo docker service ls
sudo docker service ps myapp_web
sudo docker service inspect myapp_web
sudo docker service logs myapp_web
sudo docker service scale myapp_web=5
```

### Stack management

```bash
sudo docker stack ls
sudo docker stack services myapp
sudo docker stack ps myapp
sudo docker stack config --compose-file /home/vagrant/docker-compose.yml
sudo docker stack deploy -c /home/vagrant/docker-compose.yml myapp
sudo docker stack rm myapp
```

## 12. Cleanup

Remove the stack from the manager:

```bash
vagrant ssh swarm-manager -c "sudo docker stack rm myapp"
```

If you deployed the CLI-created service separately, remove it too:

```bash
vagrant ssh swarm-manager -c "sudo docker service rm web"
```

Allow a little time for stack resources to be removed, then verify:

```bash
vagrant ssh swarm-manager -c "sudo docker stack ls"
vagrant ssh swarm-manager -c "sudo docker service ls"
```

To stop the VMs but keep them:

```bash
vagrant halt
```

To destroy the VMs:

```bash
vagrant destroy
```

> `vagrant destroy` deletes the lab VMs and their local VM data. It does not necessarily remove libvirt networks or storage resources created separately by the provider. Inspect `sudo virsh net-list --all` and `sudo virsh pool-list --all` before manually removing any resources.

## 13. Troubleshooting

### A node is not Ready

On the manager:

```bash
sudo docker node ls
```

Check network reachability from the affected VM:

```bash
ping -c 3 192.168.56.10
```

Check Docker on the affected VM:

```bash
sudo systemctl status docker --no-pager
```

### A service has fewer replicas than requested

Inspect its tasks:

```bash
sudo docker service ps myapp_web --no-trunc
```

Check service logs:

```bash
sudo docker service logs myapp_web
```

Look for image-pull errors, resource constraints, port conflicts, placement constraints, or unavailable nodes.

### A worker cannot join

Check that the manager is reachable and that TCP port 2377 is accessible:

```bash
ping -c 3 192.168.56.10
```

On the manager:

```bash
sudo ss -lntp | grep 2377
```

Retrieve a fresh worker token on the manager:

```bash
sudo docker swarm join-token worker
```

### Nginx is not reachable

Check service state:

```bash
sudo docker service ls
sudo docker service ps myapp_web
```

Check the published port and host/guest firewall rules. Verify that the service is publishing port 8080 and that the relevant Swarm networking ports are allowed between nodes.

## 14. Suggested next exercises

After the basic deployment works, extend the lab with these exercises:

1. **Failure recovery:** Stop a worker VM and observe task state and rescheduling. Restore the worker and observe it rejoin.
2. **Drain a node:** Use `docker node update --availability drain swarm-worker1` and observe task relocation. Restore it with `active`.
3. **Rolling updates:** Change the Nginx image tag and observe `update_config`.
4. **Custom web page:** Build a custom Nginx image with your own `index.html`.
5. **Multi-service application:** Add a Python Flask backend and Redis service.
6. **Service discovery:** Let services communicate using service names over an overlay network.
7. **Volumes and persistence:** Explore where persistent data lives and how it behaves when tasks move.
8. **Manager availability:** Learn about Raft consensus and why production Swarms generally use an odd number of managers, commonly three or five.

## 15. References

- [Docker Engine installation on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Docker Swarm mode overview](https://docs.docker.com/engine/swarm/)
- [Docker Swarm tutorial](https://docs.docker.com/engine/swarm/swarm-tutorial/)
- [Deploy a stack to a Swarm](https://docs.docker.com/engine/swarm/stack-deploy/)
- [Docker Swarm networking](https://docs.docker.com/engine/swarm/networking/)
- [Vagrant documentation](https://developer.hashicorp.com/vagrant/docs)
- [vagrant-libvirt documentation](https://github.com/vagrant-libvirt/vagrant-libvirt)

---

**Lab status:** Three-node Docker Swarm cluster with Nginx service deployment through both the Docker service CLI and Docker Stack YAML.
