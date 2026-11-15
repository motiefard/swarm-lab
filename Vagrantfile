Vagrant.configure("2") do |config|

  # config.vm.box = "ubuntu2204-docker"
  config.vm.box = "generic/ubuntu2204"
  config.vm.provision "shell",
    path: "scripts/install-docker.sh"

  # Common libvirt configuration
  config.vm.provider :libvirt do |libvirt|
    libvirt.driver = "kvm"
    libvirt.memory = 1024
    libvirt.cpus = 1
  end

  # Manager node
  config.vm.define "swarm-manager" do |manager|
    manager.vm.hostname = "swarm-manager"

    manager.vm.provider :libvirt do |libvirt|
      libvirt.memory = 1536
      libvirt.cpus = 2
    end

    manager.vm.network :private_network,
      ip: "192.168.56.10",
      libvirt__network_name: "swarm-net"
  end

  # Worker 1
  config.vm.define "swarm-worker1" do |worker1|
    worker1.vm.hostname = "swarm-worker1"

    worker1.vm.network :private_network,
      ip: "192.168.56.11",
      libvirt__network_name: "swarm-net"
  end

  # Worker 2
  config.vm.define "swarm-worker2" do |worker2|
    worker2.vm.hostname = "swarm-worker2"

    worker2.vm.network :private_network,
      ip: "192.168.56.12",
      libvirt__network_name: "swarm-net"
  end

end
