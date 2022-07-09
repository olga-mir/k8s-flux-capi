#!/bin/bash

set -euo pipefail

# finalize workload cluster(s) bootstrap or create a new workload cluster.
# run `./<repo_root>/scripts/workload-cluster.sh -h` to learn more.

REPO_ROOT=$(dirname "${BASH_SOURCE[0]}")/..
tempdir=$(mktemp -d)

# Management cluster kube config and context
MGMT_CTX="mgmt"
MGMT_CFG="" # default $HOME/.kube/config

# cluster config file containing all settings required for
# spinning up a new cluster
CONFIG_FILE=""

# kubectl configured to talk to management cluster, based on use input
KUBECTL_MGMT=""

CLUSTER_NAME_ARG=""

main() {

while [[ $# -gt 0 ]]; do
  case $1 in
    -m|--management-cluster-context)
      MGMT_CTX=$2; shift
      ;;
    -k|--management-cluster-kubeconfig)
      MGMT_CFG=$2; shift
      ;;
    -n|--cluster-name)
      CLUSTER_NAME_ARG=$2; shift
      ;;
    -h|--help)
      show_help
      ;;
    *)
      show_help
      ;;
  esac
  shift
done

set +x
. $REPO_ROOT/config/shared.env
set -x

if [ -z "$MGMT_CTX" ]; then
  echo Management cluster context is required # && exit 1
fi
if [ -z "$MGMT_CFG" ]; then
  echo Management cluster kubeconfing not provided, $HOME/.kube/config is assumed
  MGMT_CFG="$HOME/.kube/config"
  KUBECTL_MGMT="kubectl --kubeconfig $MGMT_CFG --context $MGMT_CTX"
fi
if [ -z "$CLUSTER_NAME_ARG" ]; then
  echo Finalize existing workload clusters
  finalize
else
  echo Create cluster
  CONFIG_FILE=$REPO_ROOT/config/$CLUSTER_NAME_ARG.env
  if [ ! -f "$CONFIG_FILE" ]; then
    echo Cluster must have config file $CONFIG_FILE && exit 1
  fi
  echo Cluster config file not provided - will finalize existing workload clusters.
  create
fi

}

create() {
  # config file must be created manually before using this script
  # these settings should not be autogenerated, it's up to the user to configure
  set +x
  . $CONFIG_FILE
  set -x

  infra_dir=$REPO_ROOT/infrastructure/control-plane-cluster/$CLUSTER_NAME
  # if directory already exists, then this can be used as a way to upgrade contents
  mkdir -p $infra_dir

  envsubst < $REPO_ROOT/templates/capi-workload-kustomization.yaml > $infra_dir/kustomization.yaml
  envsubst < $REPO_ROOT/templates/capi-workload-namespace.yaml > $infra_dir/namespace.yaml
  envsubst < $REPO_ROOT/templates/aws/cluster.yaml > $infra_dir/cluster.yaml

  # I don't want to give flux deploy key with write permissions, therefore 'bootstrap' is not an option
  # 'flux install --export' does not have options to generate gotk-sync.yaml, so instead this will be
  # instantiated from template
  # This is only needed when adding a cluster for the first time to the repo. On the following invocations, flux is deployed as CRS
  flux_crs=$tempdir/flux-combined.yaml
  cluster_dir=$REPO_ROOT/clusters/staging/${CLUSTER_NAME}/flux-system
  mkdir -p $cluster_dir
  flux install --version=$FLUXCD_VERSION --export > $cluster_dir/gotk-components.yaml
  envsubst < $REPO_ROOT/templates/gotk-sync.yaml > $cluster_dir/gotk-sync.yaml
  generate_kustomizations $cluster_dir/kustomization.yaml clusters/staging/$CLUSTER_NAME/kustomization.yaml

  cp $cluster_dir/gotk-components.yaml $flux_crs
  echo "---" >> $flux_crs
  cat $cluster_dir/gotk-sync.yaml >> $flux_crs

  # now we can put this in CM. (k create cm accepts --from-<whatever> multiple times,
  # but it creates a separate data entry for each occurence, that's why concatenating file was necessary
  kubectl create configmap crs-cm-flux-${FLUXCD_VERSION} --from-file=$flux_crs -n $CLUSTER_NAME --dry-run=client -o yaml > $infra_dir/crs-cm-flux-${FLUXCD_VERSION}.yaml

  if [ -z "$(grep $CLUSTER_NAME $REPO_ROOT/infrastructure/control-plane-cluster/kustomization.yaml)" ]; then
    yq eval ". *+ {\"resources\":[\"$CLUSTER_NAME\"]}" $REPO_ROOT/infrastructure/control-plane-cluster/kustomization.yaml --inplace
  fi

  git add $infra_dir
  git add $cluster_dir

  git commit -m "add generated files for $CLUSTER_NAME"
  git push origin $GITHUB_BRANCH

  finalize_cluster $CLUSTER_NAME
}

finalize_cluster() {
  local cluster=$1
  local ns=$cluster
  echo Finalizing cluster $cluster in $ns namespace

  while ! $KUBECTL_MGMT wait --for condition=ResourcesApplied=True clusterresourceset crs -n $ns --timeout=15s ; do
    echo $(date '+%F %H:%M:%S') waiting for workload cluster to become ready
    sleep 15
  done

  kubeconfig=$REPO_ROOT/$cluster.kubeconfig
  clusterctl --kubeconfig=$MGMT_CFG --kubeconfig-context $MGMT_CTX get kubeconfig $cluster -n $ns > $kubeconfig
  chmod go-r $kubeconfig

  KUBECTL_WORKLOAD="kubectl --kubeconfig $kubeconfig --context admin@$CLUSTER_NAME"
  set +e
  echo $(date '+%F %H:%M:%S') - Waiting for workload cluster to become responsive
  while [ -z $($KUBECTL_WORKLOAD get pod -n kube-system -l component=kube-apiserver -o name) ]; do sleep 10; done
  set -e

  kas=$($KUBECTL_WORKLOAD get pod -n kube-system -l component=kube-apiserver -o name)
  export K8S_SERVICE_HOST=$($KUBECTL_WORKLOAD get $kas -n kube-system --template '{{.status.podIP}}')
  export K8S_SERVICE_PORT='6443'

  set +x
  . $REPO_ROOT/config/$cluster.env
  set -x

  # envsubst in heml values.yaml: https://github.com/helm/helm/issues/10026
  envsubst < ${REPO_ROOT}/templates/cni/cilium-values-${CILIUM_VERSION}.yaml | \
    helm install cilium cilium/cilium --version $CILIUM_VERSION \
    --kubeconfig $kubeconfig \
    --namespace kube-system -f -

  # on clusters that already existed in the git repo before deploying
  # flux is installed via CRS, so no need to do it in script
  kubectl --kubeconfig=$kubeconfig create secret generic flux-system -n flux-system \
    --from-file identity=$FLUX_KEY_PATH  \
    --from-file identity.pub=$FLUX_KEY_PATH.pub \
    --from-literal known_hosts="$GITHUB_KNOWN_HOSTS"
}

# Discover workload clusters and complete setup if required.
finalize() {
  clusters=$($KUBECTL_MGMT get clusters -A --no-headers=true -o name)
  for line in $clusters; do
    cluster=$(echo $line |  cut -d'/' -f 2)
    if :; then # if required then
      finalize_cluster $cluster
    fi
  done
}

generate_kustomizations() {
  local flux_kustomization_filepath=$1
  local infra_kustomization_filepath=$2

cat > $flux_kustomization_filepath << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- gotk-components.yaml
- gotk-sync.yaml
EOF

cat > $infra_kustomization_filepath << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../base/infrastructure-workload.yaml
- ../base/tenants.yaml
EOF

}

show_help() {
  echo Bootstrap a new workload cluster or finalise
  echo installation of existing CAPI workload clusters
  echo Usage:
  echo "-k|--management-cluster-kubeconfig - optional, management cluster kubeconfig, default $HOME/.kube/config"
  echo "-m|--management-cluster-context - optional, management cluster kubeconfig context"
  echo "-n|--cluster-name - optional, if provided, a config file in $REPO_ROOT/config/<cluster_name>.env must exist."
  echo "  In this case, the script will generate all required manifest for the new cluster and commit it to the repo"
  echo "  then it will be synced by flux on the management cluster, and the script will wait until this cluster is"
  echo "  up and running and will finalize the installation (cni, and flux secret)"
  exit 0
}

main "$@"
