#!/bin/bash

# see <repo_root>/config/README.md

# Common
export CLUSTER_NAME="cluster-02"
export POD_CIDR="192.168.32.0/20"

# CAPI variables
export KUBERNETES_VERSION="1.23.8"
export AWS_CONTROL_PLANE_MACHINE_TYPE="t3.medium"
export AWS_NODE_MACHINE_TYPE="t3.medium"
export CONTROL_PLANE_MACHINE_COUNT="1"
export WORKER_MACHINE_COUNT="1"
export EXP_CLUSTER_RESOURCE_SET="true"

# CNI variables
export CILIUM_VERSION="1.11.6"
export CLUSTER_INT_ID=2
export NODE_MASK_SIZE="24"
