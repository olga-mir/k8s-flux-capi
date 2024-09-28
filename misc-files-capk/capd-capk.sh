export SERVICE_CIDR=["172.17.0.0/16"]
export POD_CIDR=["192.168.122.0/24"]
clusterctl generate cluster wow --infrastructure kubemark --flavor capd --kubernetes-version 1.28.0 --control-plane-machine-count=1 --worker-machine-count=4 | kubectl apply -f-
