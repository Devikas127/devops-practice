#!/bin/bash
set -e

echo "========== Updating System =========="
sudo apt update -y
sudo apt upgrade -y

echo "========== Disabling Swap =========="
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

echo "========== Loading Kernel Modules =========="
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

echo "========== Configuring Sysctl =========="
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
EOF

sudo sysctl --system

echo "========== Installing Containerd =========="
sudo apt install -y containerd

sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null

sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd

echo "========== Installing Kubernetes Packages =========="
sudo apt install -y apt-transport-https ca-certificates curl gpg

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | \
sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /" | \
sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt update

sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

echo "========== Enabling Kubelet =========="
sudo systemctl enable kubelet

ROLE=$1

if [ "$ROLE" = "master" ]; then
    echo "========== Initializing Master =========="
    sudo kubeadm init --pod-network-cidr=192.168.0.0/16

    mkdir -p $HOME/.kube
    sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    echo "========== Installing Calico =========="
    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.0/manifests/calico.yaml

    echo ""
    echo "Master setup completed."
    echo "Run the following command to get the worker join command:"
    echo "kubeadm token create --print-join-command"

elif [ "$ROLE" = "worker" ]; then
    echo "Worker node packages installed."
    echo "Run the kubeadm join command from the master node."
else
    echo "Usage:"
    echo "bash cluster_setup_using_kubeadm.sh master"
    echo "or"
    echo "bash cluster_setup_using_kubeadm.sh worker"
fi
