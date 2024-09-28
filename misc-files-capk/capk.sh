set -x
export AWS_SSH_KEY_NAME=aws
export AWS_CONTROL_PLANE_MACHINE_TYPE=t3.medium
export AWS_NODE_MACHINE_TYPE=t3.medium

clusterctl generate cluster wow --infrastructure aws      --kubernetes-version 1.28.0 --control-plane-machine-count=1 | kubectl apply -f-
# clusterctl generate cluster wow --infrastructure kubemark --kubernetes-version 1.28.0 --worker-machine-count=4        | kubectl apply -f-
