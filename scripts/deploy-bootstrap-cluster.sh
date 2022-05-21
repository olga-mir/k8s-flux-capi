#!/bin/bash

set -eou pipefail

workdir=$(pwd)

# For more details please check docs/bootstrap-and-pivot.md doc in this repo

trap "rm -f bootstrap.yaml" EXIT
cat > bootstrap.yaml << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
EOF

kind create cluster --config bootstrap.yaml

clusterctl init --infrastructure aws

# Setup config environment variables, and AWS_B64ENCODED_CREDENTIALS
# run `clusterctl generate cluster --list-variables aws` to get the list of variables
if [ -z "$AWS_CONTROL_PLANE_MACHINE_TYPE" ] || \
   [ -z "$AWS_NODE_MACHINE_TYPE" ] || \
   [ -z "$AWS_SSH_KEY_NAME" ] || \
   [ -z "$KUBERNETES_VERSION" ] || \
   [ -z "$AWS_B64ENCODED_CREDENTIALS" ]; then
  # unreachable code due to set -u. needs better 'trapping' to provide an error message
  exit 1
fi

set +e
while ! kubectl get clusters; do
  sleep 15
done
set -e
echo
echo \"No resources found in default namespace\" is expected
echo

# TODO. automate mgmt.yaml file - currently not committed because AZs settings are manually hardcoded
# deploy permanent mgmt cluster object in `default` ns in temp cluster
# clusterctl generate cluster mgmt > mgmt.yaml

retries=5
set +e
kubectl apply -f $workdir/mgmt.yaml 2>/dev/null
while [ $? -ne 0 ]; do
  echo Failed to apply cluster config, re-trying
  sleep 10
  [[ retrise -eq 0 ]] && echo "Failed to apply clsuter config, aborting." && exit 1
  ((retries--))
  kubectl apply -f $workdir/mgmt.yaml 2>/dev/null
done
set -e

echo Wait for cluster infrustracture to become ready. This can take a couple of minutes
while ! kubectl wait cluster mgmt --for jsonpath='{.status.infrastructureReady}'=true --timeout=30s; do
  echo $(date '+%F %H:%M:%S') waiting for infra to become ready
  sleep 30 # initialy status doesn't exist so wait returns immediatelly
done

sleep 15 # wait for `k get secret mgmt-kubeconfig`
clusterctl get kubeconfig mgmt > $workdir/target-mgmt.kubeconfig

# backup previous kubeconfig - as necessary
# cp $HOME/.kube/config $HOME/.kube/config-$(date +%F_%H_%M_%S)

KUBECONFIG=$HOME/.kube/config:$workdir/kind.kubeconfig:$workdir/target-mgmt.kubeconfig kubectl config view --raw=true --merge=true > $HOME/.kube/config

##############
############## ------ on AWS mgmt cluster ------
##############

kubectl config use-context mgmt-admin@mgmt

kubectl apply -f https://docs.projectcalico.org/v3.21/manifests/calico.yaml

clusterctl init --infrastructure aws

set +e
set -x
while ! kubectl get clusters; do
  sleep 15
done
set -e
set +x
echo \"No resources found in default namespace\" expected

clusterctl move --to-kubeconfig=./target-mgmt.kubeconfig

# kind delete cluster
# and now what? how do you manage the permanent management cluster? keep it now for simplicity
