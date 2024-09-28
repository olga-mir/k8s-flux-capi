# Kubemark Cluster

https://github.com/kubernetes/community/blob/master/contributors/devel/sig-scalability/kubemark-guide.md

https://github.com/kubernetes-sigs/cluster-api-provider-kubemark


Verify your version of `clusterctl` includes `kubemark` provider:
```
% clusterctl config repositories | grep kubemark
kubemark                InfrastructureProvider   https://github.com/kubernetes-sigs/cluster-api-provider-kubemark/releases/v0.7.0/           infrastructure-components.yaml
```

Generate cluster manifests:
```
clusterctl generate cluster wow --infrastructure kubemark:v0.7.0 --kubernetes-version 1.29.2 --control-plane-machine-count=1 --worker-machine-count=4 > capk-manifests.yaml
```
