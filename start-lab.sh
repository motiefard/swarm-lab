#!/bin/bash

set -e

echo "Starting Docker Swarm lab..."

vagrant up swarm-manager
sleep 10
vagrant up swarm-worker1
sleep 5
vagrant up swarm-worker2

echo "Waiting for Swarm nodes..."

sleep 15

vagrant ssh swarm-manager -c "sudo docker node ls"

echo "Lab started!"
echo "Application: http://192.168.56.10:8080"
