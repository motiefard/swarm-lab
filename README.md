# Docker Swarm Lab — From Vagrant VMs to a Three-Tier Application

A practical, end-to-end Docker Swarm learning project using three Ubuntu 22.04 virtual machines provisioned by Vagrant on an Ubuntu 24.04 host with KVM/QEMU and libvirt.

The lab begins with starting the virtual machines, installing and verifying Docker, and creating a three-node Swarm cluster. It then deploys a three-tier application consisting of Nginx, Python Flask, and Redis using a Docker Stack YAML file.

This README is intended to let someone work through the lab from the host machine to a running application.

---

## 1. What you will learn

### Virtualization and infrastructure

- What Vagrant does and how it manages virtual machines.
- How Vagrant uses the `vagrant-libvirt` provider.
- How KVM/QEMU and libvirt fit into the virtualization stack.
- How to start, stop, access, provision, and destroy VMs.
- How private VM networking and static IP addresses are used for cluster communication.
- How to distinguish the host network, VM management access, and the Swarm node network.

### Docker fundamentals

- Docker Engine, Docker CLI, and containerd.
- Docker images versus containers.
- Pulling public images and building a custom image.
- Dockerfiles and image layers.
- Running a test container.
- Inspecting containers, images, networks, and logs.

### Docker Swarm

- Swarm manager and worker roles.
- Initializing a Swarm and joining worker nodes.
- Advertise addresses and join tokens.
- Node status and availability.
- Services, tasks, replicas, and desired state.
- Service scheduling across nodes.
- Scaling services.
- Overlay networks and service-name DNS discovery.
- Published ports and the ingress routing mesh.
- Deploying and updating a stack from YAML.
- Basic troubleshooting and cleanup.

### Application and multi-service concepts

- Building a Python Flask application.
- Packaging Python dependencies.
- Creating a custom Docker image.
- Running Flask with Gunicorn.
- Configuring Nginx as a reverse proxy.
- Connecting services using Swarm service names rather than fixed container IPs.
- Separating frontend and backend traffic with two overlay networks.
- Using Redis as a shared cache/counter for multiple backend replicas.
- Using a named volume for Redis data.
- Understanding why one Redis replica and a local volume do not provide high availability.

---

## 2. Lab environment

### Host machine

| Component | Version / configuration |
|---|---|
| Host OS | Ubuntu 24.04 |
| Virtualization | KVM/QEMU with libvirt |
| Vagrant | 2.4.9 |
| Vagrant provider plugin | `vagrant-libvirt` 0.12.2 |
| Guest OS | Ubuntu 22.04 |
| Vagrant box | `generic/ubuntu2204` |
| Docker Engine | Installed inside each guest VM |

### Virtual machines

The lab uses three VMs:

| VM name | Swarm role | Swarm network IP |
|---|---|---|
| `swarm-manager` | Manager / Leader | `192.168.56.10` |
| `swarm-worker1` | Worker | `192.168.56.11` |
| `swarm-worker2` | Worker | `192.168.56.12` |

The IP addresses above are the expected private Swarm addresses used throughout this guide. Confirm that they match your `Vagrantfile` before running the commands.

### Architecture

```text
                         Ubuntu 24.04 Host
                                |
                             Vagrant
                                |
                         vagrant-libvirt
                                |
                           KVM / QEMU
                                |
                 +--------------+--------------+
                 |              |              |
            swarm-manager  swarm-worker1  swarm-worker2
            192.168.56.10  192.168.56.11  192.168.56.12
                 |              |              |
                 +--------------+--------------+
                         Docker Swarm
                      1 manager, 2 workers
                                |
                        Three-tier stack
                                |
                    +-----------+-----------+
                    |           |           |
                  Nginx       Flask       Redis
                2 replicas  2 replicas  1 replica
                    |
              Published TCP 8080
                    |
                  Browser
```

---

## 3. Project directory structure

The overall lab directory is expected to look like this:

```text
vagrant-swarm-lab/
├── Vagrantfile
├── scripts/
│   └── install-docker.sh
├── stack/
│   └── docker-compose.yml          # Earlier Nginx-only exercise (optional)
└── project-2/
    ├── backend/
    │   ├── app.py
    │   ├── requirements.txt
    │   └── Dockerfile
    ├── nginx/
    │   └── default.conf
    └── docker-compose.yml
```

| Path | Responsibility |
|---|---|
| `Vagrantfile` | Defines the VMs, resources, hostnames, and network configuration. |
| `scripts/install-docker.sh` | Installs and enables Docker Engine in each VM through Vagrant provisioning. |
| `stack/docker-compose.yml` | YAML file from the earlier Nginx-only Swarm exercise. |
| `project-2/backend/app.py` | Flask application and API endpoints. |
| `project-2/backend/requirements.txt` | Python packages required by Flask. |
| `project-2/backend/Dockerfile` | Builds the custom Flask backend image. |
| `project-2/nginx/default.conf` | Nginx reverse-proxy configuration. |
| `project-2/docker-compose.yml` | Defines Nginx, Flask, Redis, overlay networks, volumes, configs, and deployment settings. |

The Compose-format YAML file is deployed with `docker stack deploy`; it is not run with `docker compose up` for this Swarm exercise.

---

# Part A — Start and prepare the virtual machines

## 4. Check host prerequisites

On the Ubuntu 24.04 host, verify the required tools:

```bash
vagrant --version
vagrant plugin list
vagrant box list
```

Expected relevant versions:

```text
Vagrant 2.4.9
vagrant-libvirt (0.12.2, global)
```

The box list should include:

```text
generic/ubuntu2204 (libvirt, ...)
```

Check libvirt:

```bash
sudo virsh list --all
sudo virsh net-list --all
```

The libvirt `default` network should be active if your Vagrant setup uses it.

Check available host resources:

```bash
free -h
nproc
df -h /
```

Three VMs and container images require sufficient free RAM and disk space. The exact resource requirements depend on the VM settings in your `Vagrantfile`.

> Run Vagrant commands as your normal host user, not with `sudo`.

## 5. Start the VMs

Open a terminal on the host and change to the directory containing the `Vagrantfile`:

```bash
cd ~/python_land/vagrant
```

If your lab directory is elsewhere, use that path instead.

Validate the Vagrantfile:

```bash
vagrant validate
```

Start the VMs using libvirt:

```bash
vagrant up --provider=libvirt
```

Check their state:

```bash
vagrant status
```

All three machines should be running:

```text
swarm-manager
swarm-worker1
swarm-worker2
```

Check libvirt:

```bash
sudo virsh list --all
```

### Connect to each VM

```bash
vagrant ssh swarm-manager
```

Exit the VM when finished:

```bash
exit
```

Connect to the workers in the same way:

```bash
vagrant ssh swarm-worker1
vagrant ssh swarm-worker2
```

### Verify VM network addresses

From the host:

```bash
vagrant ssh swarm-manager -c "ip -br addr"
vagrant ssh swarm-worker1 -c "ip -br addr"
vagrant ssh swarm-worker2 -c "ip -br addr"
```

Confirm that the Swarm-facing interfaces have the expected addresses:

- Manager: `192.168.56.10`
- Worker 1: `192.168.56.11`
- Worker 2: `192.168.56.12`

Test connectivity from the manager:

```bash
vagrant ssh swarm-manager -c "ping -c 3 192.168.56.11"
vagrant ssh swarm-manager -c "ping -c 3 192.168.56.12"
```

If these addresses differ, use the actual addresses configured in your Vagrantfile in the remaining steps.

---

# Part B — Install and verify Docker

## 6. Provision Docker

The Vagrant provisioning script should install Docker Engine and enable its service in all three VMs.

Run:

```bash
vagrant provision
```

If Docker was already installed, provisioning should bring the VMs back to the configured state. Review the script if your installation method differs.

The provisioning script is expected to install:

- Docker Engine (`docker-ce`)
- Docker CLI (`docker-ce-cli`)
- containerd (`containerd.io`)
- Docker Buildx plugin
- Docker Compose plugin

### Verify Docker on every VM

```bash
vagrant ssh swarm-manager -c "docker --version"
vagrant ssh swarm-worker1 -c "docker --version"
vagrant ssh swarm-worker2 -c "docker --version"
```

Check that the daemon is running:

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

This confirms that each VM can run a container and, if the image was not already cached, can pull an image from Docker Hub.

---

# Part C — Create the Docker Swarm cluster

## 7. Initialize the manager

Connect to the manager:

```bash
vagrant ssh swarm-manager
```

Initialize Swarm using the manager's private Swarm address:

```bash
sudo docker swarm init --advertise-addr 192.168.56.10
```

Docker prints a command containing a worker join token.

The token is a credential. Do not publish it in a public repository or share it unnecessarily.

## 8. Join Worker 1 and Worker 2

On the manager, retrieve the worker join command:

```bash
sudo docker swarm join-token worker
```

Copy the command Docker prints. It has this general form:

```bash
sudo docker swarm join \
  --token <WORKER_JOIN_TOKEN> \
  192.168.56.10:2377
```

Connect to Worker 1:

```bash
exit
```

```bash
vagrant ssh swarm-worker1
```

Run the actual join command printed by the manager.

Repeat on Worker 2:

```bash
vagrant ssh swarm-worker2
```

Run the same join command there.

Do not type the placeholder `<WORKER_JOIN_TOKEN>` literally; use the real token from your manager.

## 9. Verify the Swarm cluster

On the manager:

```bash
vagrant ssh swarm-manager
```

Then:

```bash
sudo docker node ls
```

Expected cluster state:

```text
HOSTNAME        STATUS    AVAILABILITY   MANAGER STATUS
swarm-manager   Ready     Active         Leader
swarm-worker1   Ready     Active
swarm-worker2   Ready     Active
```

Inspect Swarm information:

```bash
sudo docker info
```

Look for:

```text
Swarm: active
Managers: 1
Nodes: 3
```

Important: `docker node ls` is a manager command. It cannot be run from a worker node.

### Swarm network ports

The following ports must be reachable between Swarm nodes:

| Port | Protocol | Purpose |
|---|---|---|
| 2377 | TCP | Swarm management |
| 7946 | TCP and UDP | Node communication and discovery |
| 4789 | UDP | Overlay network data path |

Restrict these ports to the private lab network; do not expose them to untrusted networks.

> This lab has one manager. It is suitable for learning, but it is not a highly available manager cluster. A production Swarm commonly uses three or five managers to maintain quorum if a manager fails.

---

# Part D — Earlier exercise: Nginx as a Swarm service

This section is a short recap of the Nginx-only exercise. It is useful for understanding the difference between creating a service directly and deploying a stack from YAML.

## 10. Create an Nginx service from the CLI

On the manager:

```bash
sudo docker service create \
  --name web \
  --replicas 3 \
  --publish published=8080,target=80 \
  nginx:alpine
```

Check the service:

```bash
sudo docker service ls
```

Inspect its tasks and placement:

```bash
sudo docker service ps web
```

See containers on individual VMs:

```bash
vagrant ssh swarm-manager -c "sudo docker ps"
vagrant ssh swarm-worker1 -c "sudo docker ps"
vagrant ssh swarm-worker2 -c "sudo docker ps"
```

## 11. Test the Nginx service

From the Ubuntu host:

```bash
curl http://192.168.56.10:8080
curl http://192.168.56.11:8080
curl http://192.168.56.12:8080
```

The requests should return the Nginx welcome page.

The published port uses Swarm's ingress routing mesh. A node can accept traffic on the published port and route it to an available task, even if the task is running on another node.

## 12. Scale the service

```bash
sudo docker service scale web=5
sudo docker service ls
sudo docker service ps web
```

Scale it down:

```bash
sudo docker service scale web=2
```

Remove the Nginx-only service before deploying Project 2 because both examples use published port 8080:

```bash
sudo docker service rm web
```

If you deployed the earlier YAML stack named `myapp`, remove it too:

```bash
sudo docker stack rm myapp
```

Wait until its services are removed before continuing.

---

# Part E — Project 2: Nginx + Flask + Redis

## 13. Project overview

The second project is a small three-tier web application.

```text
                     User / Browser
                           |
                           |
                     HTTP port 8080
                           |
                    Swarm Routing Mesh
                           |
                    +--------------+
                    | Nginx x 2    |
                    |  Frontend    |
                    +--------------+
                           |
                    frontend-network
                           |
                    +--------------+
                    | Flask x 2    |
                    |  Backend     |
                    +--------------+
                           |
                     backend-network
                           |
                    +--------------+
                    | Redis x 1    |
                    |    Cache     |
                    +--------------+
```

| Service | Image | Replicas | Purpose |
|---|---|---:|---|
| `nginx` | `nginx:alpine` | 2 | Receives HTTP requests and proxies them to Flask. |
| `backend` | Custom Flask image | 2 | Handles application logic and API requests. |
| `redis` | `redis:7-alpine` | 1 | Stores a shared visit counter. |

The user accesses the application through:

```text
http://192.168.56.10:8080
```

The request path is:

1. The request enters the Swarm routing mesh.
2. An Nginx task receives the request.
3. Nginx forwards it to the `backend` service.
4. A Flask task handles the request.
5. Flask increments a counter in Redis.
6. Flask returns JSON to Nginx.
7. Nginx returns the response to the user.

## 14. Dockerfile concepts:

| Instruction | Purpose |
|---|---|
| `FROM` | Selects the base image. |
| `WORKDIR` | Sets the working directory in the image. |
| `COPY` | Copies files into the image. |
| `RUN` | Executes a command during image building. |
| `EXPOSE` | Documents the application port. |
| `CMD` | Defines the default container command. |

## 15. YAML concepts

| Configuration | Purpose |
|---|---|
| `services` | Declares application services. |
| `image` | Selects the image used by a service. |
| `ports` | Publishes the Nginx port through the routing mesh. |
| `configs` | Supplies the Nginx configuration to its containers. |
| `environment` | Configures Flask using environment variables. |
| `networks` | Connects services to overlay networks. |
| `deploy.replicas` | Declares the desired number of tasks. |
| `restart_policy` | Defines when Swarm should restart a task. |
| `resources.limits` | Sets CPU and memory limits. |
| `volumes` | Declares Redis data storage. |

## 16. Why two overlay networks?

The frontend network connects Nginx and Flask:

```text
nginx <---- frontend-network ----> backend
```

The backend network connects Flask and Redis:

```text
backend <---- backend-network ----> redis
```

Redis is not attached to the frontend network and has no published host port. This limits direct network access to the cache.

## 17. Redis storage note

The named volume `redis-data` uses the default local Docker volume driver. It stores data on the node where the Redis task runs; it does not replicate data to other nodes.

The Redis service has one replica, so this is a learning setup, not a highly available Redis deployment. If the task is moved to another node, the new node's local volume may be empty. Treat the counter as lab data.

---

## 18. Distribute the project files to the VMs

Docker Stack does not build images from Dockerfiles. The custom Flask image must be built separately and be available on any node where Swarm may schedule a Flask task.

For this learning lab, build the same image on all three nodes. This avoids the need to set up a container registry.

From the host, in the directory containing `project-2/`:

```bash
tar -czf project-2.tar.gz project-2
```

Upload the archive to each VM:

```bash
vagrant upload project-2.tar.gz \
  /home/vagrant/project-2.tar.gz swarm-manager

vagrant upload project-2.tar.gz \
  /home/vagrant/project-2.tar.gz swarm-worker1

vagrant upload project-2.tar.gz \
  /home/vagrant/project-2.tar.gz swarm-worker2
```

Extract the archive on each node:

```bash
vagrant ssh swarm-manager -c "tar -xzf project-2.tar.gz"
vagrant ssh swarm-worker1 -c "tar -xzf project-2.tar.gz"
vagrant ssh swarm-worker2 -c "tar -xzf project-2.tar.gz"
```

## 19. Build the custom Flask image on every node

Build on the manager:

```bash
vagrant ssh swarm-manager
```

```bash
cd /home/vagrant/project-2/backend

sudo docker build -t swarm-lab-backend:1.0 .
sudo docker images
```

Build on Worker 1:

```bash
vagrant ssh swarm-worker1
```

```bash
cd /home/vagrant/project-2/backend

sudo docker build -t swarm-lab-backend:1.0 .
sudo docker images
```

Build on Worker 2:

```bash
vagrant ssh swarm-worker2
```

```bash
cd /home/vagrant/project-2/backend

sudo docker build -t swarm-lab-backend:1.0 .
sudo docker images
```

All three nodes must have the image with exactly this name and tag:

```text
swarm-lab-backend:1.0
```

Why build on every node? Swarm may schedule either Flask replica on any node. Each node has its own local image storage, so the image must exist wherever a task might run.

> This is a convenient lab technique, not the preferred production workflow. In a production workflow, build the image once, tag it, push it to a registry, and let all Swarm nodes pull the same immutable image.

---

## 20. Deploy Project 2 from the manager

Connect to the manager:

```bash
vagrant ssh swarm-manager
```

If the earlier Nginx-only stack named `myapp` still exists, remove it:

```bash
sudo docker stack rm myapp
```

Wait for its services to be removed before deploying Project 2 because both stacks publish port 8080.

Change to the Project 2 directory:

```bash
cd /home/vagrant/project-2
```

Check the files:

```bash
find . -maxdepth 2 -type f
```

Render and validate the stack configuration:

```bash
sudo docker stack config --compose-file docker-compose.yml
```

Deploy:

```bash
sudo docker stack deploy \
  --compose-file docker-compose.yml \
  --resolve-image never \
  three-tier
```

The stack name is `three-tier`. Swarm prefixes stack resources with this name. For example:

- `three-tier_nginx`
- `three-tier_backend`
- `three-tier_redis`
- `three-tier_frontend-network`
- `three-tier_backend-network`

The `--resolve-image never` option is used because the custom image was built locally on each node rather than pushed to a registry.

---

## 21. Verify the stack

List stacks:

```bash
sudo docker stack ls
```

List services:

```bash
sudo docker stack services three-tier
```

The desired replica counts are:

| Service | Expected replicas |
|---|---:|
| `three-tier_nginx` | 2/2 |
| `three-tier_backend` | 2/2 |
| `three-tier_redis` | 1/1 |

It may take a short time for tasks to start. If a service does not reach its desired replica count, inspect its tasks:

```bash
sudo docker stack ps three-tier
```

Inspect an individual service:

```bash
sudo docker service inspect three-tier_backend
```

View backend logs:

```bash
sudo docker service logs three-tier_backend
```

View Nginx logs:

```bash
sudo docker service logs three-tier_nginx
```

View Redis logs:

```bash
sudo docker service logs three-tier_redis
```

Check the overlay networks:

```bash
sudo docker network ls
```

Inspect them:

```bash
sudo docker network inspect three-tier_frontend-network
sudo docker network inspect three-tier_backend-network
```

Check task placement across nodes:

```bash
sudo docker service ps three-tier_nginx
sudo docker service ps three-tier_backend
sudo docker service ps three-tier_redis
```

---

## 22. Test the application

Run these commands from the Ubuntu host.

### Test the home endpoint

```bash
curl http://192.168.56.10:8080/
```

Expected response shape:

```json
{
  "application": "Docker Swarm Lab",
  "hostname": "container-id",
  "message": "Backend is working!",
  "service": "Flask Backend"
}
```

The hostname identifies the Flask container that handled the request.

### Test the API and Redis counter

```bash
curl http://192.168.56.10:8080/api/
```

Expected response shape:

```json
{
  "application": "Docker Swarm Lab",
  "backend": "Flask",
  "hostname": "container-id",
  "visits": 1
}
```

Call the endpoint repeatedly:

```bash
curl http://192.168.56.10:8080/api/
curl http://192.168.56.10:8080/api/
curl http://192.168.56.10:8080/api/
```

The `visits` value should increase because Redis stores the shared counter.

### Test through each Swarm node

```bash
curl http://192.168.56.10:8080/api/
curl http://192.168.56.11:8080/api/
curl http://192.168.56.12:8080/api/
```

The ingress routing mesh allows the published service port to be accessed through any Swarm node, provided network access is available.

### Observe the Flask replicas

Run the request several times:

```bash
for i in $(seq 1 10); do
  curl -s http://192.168.56.10:8080/api/
  echo
done
```

Compare the `hostname` values. Requests may be handled by different Flask tasks. Do not expect strict alternation; routing is not a round-robin guarantee.

### Test the health endpoint

```bash
curl http://192.168.56.10:8080/health
```

This endpoint checks connectivity to Redis by issuing `PING`.

---

# Part F — Concepts and experiments

## 23. Service discovery

The Flask application uses:

```python
host=os.getenv("REDIS_HOST", "redis")
```

The Nginx configuration uses:

```nginx
proxy_pass http://backend:5000;
```

These are service names, not container IP addresses.

Swarm provides internal DNS-based service discovery for services connected to the same overlay network.

Try inspecting service DNS from a temporary container attached to the appropriate network if you want to explore this further.

## 24. Replicas and scheduling

The stack declares:

```yaml
nginx:
  deploy:
    replicas: 2

backend:
  deploy:
    replicas: 2

redis:
  deploy:
    replicas: 1
```

Swarm attempts to maintain the desired number of tasks.

Inspect placement:

```bash
sudo docker service ps three-tier_nginx
sudo docker service ps three-tier_backend
sudo docker service ps three-tier_redis
```

Swarm does not guarantee one replica per node unless placement rules are configured. With two replicas and three nodes, both tasks may run on the same node.

## 25. Scale a service

Scale the backend to three replicas:

```bash
sudo docker service scale three-tier_backend=3
```

Verify:

```bash
sudo docker service ls
sudo docker service ps three-tier_backend
```

Return it to two replicas:

```bash
sudo docker service scale three-tier_backend=2
```

A direct `docker service scale` changes the running service. If you later redeploy the stack YAML with `replicas: 2`, the YAML's declared value is applied again.

## 26. Failure recovery experiment

This exercise demonstrates Swarm's desired-state reconciliation.

Before stopping a worker, inspect task placement:

```bash
sudo docker stack ps three-tier
```

From the host, stop Worker 1:

```bash
vagrant halt swarm-worker1
```

Wait for the manager to detect the node failure, then inspect:

```bash
vagrant ssh swarm-manager -c "sudo docker node ls"
vagrant ssh swarm-manager -c "sudo docker stack ps three-tier"
vagrant ssh swarm-manager -c "sudo docker stack services three-tier"
```

Observe what happens to tasks that were running on the stopped node. Swarm may schedule replacement tasks on available nodes, subject to available resources and service constraints.

Important: this lab has only one manager. Do not stop the manager for this experiment; a single-manager Swarm loses manager control when that VM is unavailable.

Bring Worker 1 back:

```bash
vagrant up swarm-worker1
```

Check its status:

```bash
vagrant ssh swarm-manager -c "sudo docker node ls"
```

A recovered worker should rejoin the cluster. Tasks that were replaced while it was unavailable are not necessarily moved back.

## 27. Drain and reactivate a node

On the manager, prevent new tasks from being scheduled on Worker 1 and ask Swarm to move eligible tasks away:

```bash
sudo docker node update --availability drain swarm-worker1
```

Inspect:

```bash
sudo docker node ls
sudo docker stack ps three-tier
```

Reactivate it:

```bash
sudo docker node update --availability active swarm-worker1
```

`active` makes the node eligible for new tasks again. It does not guarantee that existing tasks will be redistributed to it.

## 38. Other suggested experiments

1. Increase Nginx replicas and inspect placement.
2. Increase Flask replicas and observe backend hostnames.
3. Change the Flask response and rebuild the image.
4. Experiment with a different Nginx configuration.
5. Inspect the overlay networks and service DNS.
6. Inspect Redis keys using `redis-cli` in the Redis container.
7. Remove the Redis volume in a controlled cleanup experiment and observe the counter reset.
8. Add placement constraints to control which nodes run selected services.
9. Explore health checks and rolling updates.
10. Replace the local-image workflow with a container registry.

---

# Part G — Troubleshooting and cleanup

## 29. Troubleshooting

### A node is not Ready

On the manager:

```bash
sudo docker node ls
```

Check network connectivity:

```bash
ping -c 3 192.168.56.10
```

Check Docker on the affected VM:

```bash
sudo systemctl status docker --no-pager
```

### A service has fewer replicas than expected

Inspect tasks and their error messages:

```bash
sudo docker service ps three-tier_backend --no-trunc
```

Check logs:

```bash
sudo docker service logs three-tier_backend
```

Common causes include:

- The custom image is missing from a node.
- The image name or tag differs between nodes.
- A node is down or unavailable.
- The VM does not have enough resources.
- A service cannot connect to another service.
- A port is already in use.

### The backend cannot connect to Redis

Check that the services share `three-tier_backend-network`:

```bash
sudo docker service inspect three-tier_backend
sudo docker service inspect three-tier_redis
```

Check Redis logs:

```bash
sudo docker service logs three-tier_redis
```

Check backend logs:

```bash
sudo docker service logs three-tier_backend
```

### Nginx returns 502 Bad Gateway

Check backend tasks:

```bash
sudo docker service ps three-tier_backend
```

Check Flask logs:

```bash
sudo docker service logs three-tier_backend
```

Check Nginx logs:

```bash
sudo docker service logs three-tier_nginx
```

Confirm that the Nginx configuration refers to:

```nginx
proxy_pass http://backend:5000;
```

and that Nginx and Flask are attached to the same overlay network.

### The host cannot access port 8080

Check the service publication:

```bash
sudo docker service inspect three-tier_nginx
```

Check tasks:

```bash
sudo docker service ps three-tier_nginx
```

Check host/guest firewall rules and network reachability. Confirm that TCP 8080 is reachable on the VM addresses.

### The backend image cannot be found

On every node, run:

```bash
sudo docker image ls swarm-lab-backend
```

The image must be tagged:

```text
swarm-lab-backend:1.0
```

If necessary, upload the project archive again and rebuild the image on the node.

## 30. Remove Project 2

On the manager:

```bash
sudo docker stack rm three-tier
```

Check that the stack's services are removed:

```bash
sudo docker stack ls
sudo docker service ls
```

Stack removal removes the stack's services and stack-managed networks/configs. Named volume data may remain on the nodes after the service is removed.

If you want to remove the lab image from each node:

```bash
sudo docker image rm swarm-lab-backend:1.0
```

Only do this after no containers use that image.

## 31. Stop or destroy the VMs

From the host, in the directory containing the Vagrantfile:

Stop the VMs but keep them:

```bash
vagrant halt
```

Start them again later:

```bash
vagrant up --provider=libvirt
```

Destroy the VMs:

```bash
vagrant destroy
```

> `vagrant destroy` deletes the VMs and their VM disks. It is destructive. Confirm that you do not need data stored inside the VMs before running it.

---

## 32. Quick command reference

### Vagrant

| Command | Purpose |
|---|---|
| `vagrant status` | Show VM states. |
| `vagrant up --provider=libvirt` | Start/create VMs. |
| `vagrant ssh swarm-manager` | Connect to manager. |
| `vagrant provision` | Run provisioning scripts. |
| `vagrant halt` | Stop VMs. |
| `vagrant destroy` | Delete VMs. |
| `vagrant upload LOCAL REMOTE VM` | Upload a file to a VM. |

### Docker Swarm

| Command | Purpose |
|---|---|
| `docker swarm init` | Initialize a Swarm. |
| `docker swarm join-token worker` | Show worker join command/token. |
| `docker node ls` | List cluster nodes. |
| `docker service ls` | List services. |
| `docker service ps SERVICE` | Inspect service tasks. |
| `docker service scale SERVICE=N` | Change desired replicas. |
| `docker stack deploy -c FILE STACK` | Deploy/update a stack. |
| `docker stack services STACK` | List stack services. |
| `docker stack ps STACK` | List stack tasks. |
| `docker stack rm STACK` | Remove a stack. |
| `docker service logs SERVICE` | View service logs. |

---

## 33. Official documentation

- [Vagrant documentation](https://developer.hashicorp.com/vagrant/docs)
- [vagrant-libvirt project](https://github.com/vagrant-libvirt/vagrant-libvirt)
- [Docker Engine installation on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Docker Swarm mode overview](https://docs.docker.com/engine/swarm/)
- [Docker Swarm tutorial](https://docs.docker.com/engine/swarm/swarm-tutorial/)
- [Deploy a stack to a Swarm](https://docs.docker.com/engine/swarm/stack-deploy/)
- [Swarm networking](https://docs.docker.com/engine/swarm/networking/)
- [Flask documentation](https://flask.palletsprojects.com/)
- [Redis documentation](https://redis.io/docs/)

---

**Project outcome:** A three-node Docker Swarm cluster provisioned with Vagrant and libvirt, running a YAML-deployed application with two Nginx frontend replicas, two Flask backend replicas, and one Redis cache replica.
