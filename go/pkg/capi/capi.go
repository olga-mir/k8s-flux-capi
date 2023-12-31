package capi

import (
	"context"
	"fmt"
	"os"

	"github.com/olga-mir/k8s-multi-cluster/go/pkg/utils"
	"k8s.io/client-go/rest"
	"sigs.k8s.io/cluster-api/cmd/clusterctl/client"
)

func InitClusterAPI(config *rest.Config, kubeconfigPath string) error {
	capiVersion := os.Getenv("CAPI_VERSION")
	if capiVersion == "" {
		return fmt.Errorf("CAPI_VERSION environment variable is not set")
	}
	capaVersion := os.Getenv("CAPA_VERSION")
	if capiVersion == "" {
		return fmt.Errorf("CAPA_VERSION environment variable is not set")
	}

	// Correct providers based on the CAPI version
	coreProvider := fmt.Sprintf("cluster-api:%s", capiVersion)
	bootstrapProvider := fmt.Sprintf("kubeadm:%s", capiVersion)
	controlPlaneProvider := fmt.Sprintf("kubeadm:%s", capiVersion)
	infraProvider := fmt.Sprintf("aws:%s", capaVersion)

	// Create a clusterctl client
	// Get the current context name from the rest.Config
	contextName, err := utils.GetCurrentContextName(config, kubeconfigPath)
	if err != nil {
		return fmt.Errorf("error getting current context name: %w", err)
	}

	// Initialize clusterctl client with the existing kubeconfig and context
	c, err := client.New(context.TODO(), "")
	if err != nil {
		return fmt.Errorf("error creating clusterctl client: %w", err)
	}

	initOptions := client.InitOptions{
		Kubeconfig:              client.Kubeconfig{Path: kubeconfigPath, Context: contextName},
		CoreProvider:            coreProvider,
		BootstrapProviders:      []string{bootstrapProvider},
		ControlPlaneProviders:   []string{controlPlaneProvider},
		InfrastructureProviders: []string{infraProvider},
	}

	// Install Cluster API components on this cluster.
	if _, err := c.Init(context.TODO(), initOptions); err != nil {
		return fmt.Errorf("error initializing Cluster API: %w", err)
	}

	return nil
}
