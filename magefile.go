//go:build mage

package main

import (
	"fmt"
	"os"
	"time"

	"github.com/konflux-ci/kargo/internal"
	"github.com/magefile/mage/mg"
	"github.com/magefile/mage/sh"
)

// Kind manages kind cluster operations
type Kind mg.Namespace

// CertManager manages cert-manager operations
type CertManager mg.Namespace

const (
	clusterName        = "kargo"
	certManagerVersion = "v1.18.2"
	certManagerNS      = "cert-manager"
)

// Default target - shows available targets
func Default() error {
	return sh.Run("mage", "-l")
}

// Kind:Up creates or connects to a kind cluster named 'kargo'
func (Kind) Up() error {
	fmt.Println("🚀 Setting up kind cluster...")

	// Check if cluster already exists
	exists, err := internal.ClusterExists(clusterName)
	if err != nil {
		return fmt.Errorf("failed to check cluster existence: %w", err)
	}

	if exists {
		fmt.Printf("✅ Cluster '%s' already exists\n", clusterName)
	} else {
		fmt.Printf("📦 Creating kind cluster '%s'...\n", clusterName)
		err := internal.CreateCluster(clusterName)
		if err != nil {
			return fmt.Errorf("failed to create cluster: %w", err)
		}
		fmt.Printf("✅ Cluster '%s' created successfully\n", clusterName)
	}

	// Export kubeconfig
	fmt.Printf("🔧 Exporting kubeconfig for cluster '%s'...\n", clusterName)
	err = internal.ExportKubeconfig(clusterName)
	if err != nil {
		return fmt.Errorf("failed to export kubeconfig: %w", err)
	}

	fmt.Printf("✅ Kind cluster '%s' is ready!\n", clusterName)
	return nil
}

// Kind:UpClean forces recreation of the kind cluster (deletes existing cluster and creates new one)
func (Kind) UpClean() error {
	fmt.Println("🚀 Setting up kind cluster (clean recreation)...")

	// Check if cluster already exists
	exists, err := internal.ClusterExists(clusterName)
	if err != nil {
		return fmt.Errorf("failed to check cluster existence: %w", err)
	}

	if exists {
		fmt.Printf("🔄 Deleting existing cluster '%s'...\n", clusterName)
		err := internal.DeleteCluster(clusterName)
		if err != nil {
			return fmt.Errorf("failed to delete existing cluster: %w", err)
		}
		fmt.Printf("✅ Cluster '%s' deleted successfully\n", clusterName)
	}

	// Create new cluster
	fmt.Printf("📦 Creating kind cluster '%s'...\n", clusterName)
	err = internal.CreateCluster(clusterName)
	if err != nil {
		return fmt.Errorf("failed to create cluster: %w", err)
	}
	fmt.Printf("✅ Cluster '%s' created successfully\n", clusterName)

	// Export kubeconfig
	fmt.Printf("🔧 Exporting kubeconfig for cluster '%s'...\n", clusterName)
	err = internal.ExportKubeconfig(clusterName)
	if err != nil {
		return fmt.Errorf("failed to export kubeconfig: %w", err)
	}

	fmt.Printf("✅ Kind cluster '%s' is ready!\n", clusterName)
	return nil
}

// Kind:Down tears down the kind cluster
func (Kind) Down() error {
	fmt.Println("🔥 Tearing down kind cluster...")

	// Check if cluster exists first
	exists, err := internal.ClusterExists(clusterName)
	if err != nil {
		return fmt.Errorf("failed to check cluster existence: %w", err)
	}

	if !exists {
		fmt.Printf("ℹ️  Cluster '%s' does not exist\n", clusterName)
		return nil
	}

	// Delete the cluster
	fmt.Printf("🗑️  Deleting kind cluster '%s'...\n", clusterName)
	err = internal.DeleteCluster(clusterName)
	if err != nil {
		return fmt.Errorf("failed to delete cluster: %w", err)
	}

	fmt.Printf("✅ Cluster '%s' deleted successfully\n", clusterName)
	return nil
}

// Kind:Status shows the status of the kind cluster
func (Kind) Status() error {
	fmt.Println("📊 Checking kind cluster status...")

	// Check if cluster exists
	exists, err := internal.ClusterExists(clusterName)
	if err != nil {
		return fmt.Errorf("failed to check cluster existence: %w", err)
	}

	if !exists {
		fmt.Printf("❌ Cluster '%s' does not exist\n", clusterName)
		return nil
	}

	fmt.Printf("✅ Cluster '%s' exists\n", clusterName)

	// Check kubeconfig
	kubeconfigPath := os.Getenv("KUBECONFIG")
	if kubeconfigPath == "" {
		kubeconfigPath = os.Getenv("HOME") + "/.kube/config"
	}

	// Try to get cluster info
	fmt.Printf("🔍 Checking cluster connectivity...\n")
	output, err := internal.GetClusterInfo(clusterName)
	if err != nil {
		fmt.Printf("⚠️  Could not connect to cluster: %v\n", err)
		fmt.Printf("💡 Try running 'mage kind:up' to ensure kubeconfig is exported\n")
		return nil
	}

	fmt.Printf("✅ Cluster is accessible:\n%s\n", output)

	// Get node status
	fmt.Printf("🖥️  Node status:\n")
	err = internal.GetNodeStatus(clusterName)
	if err != nil {
		fmt.Printf("⚠️  Could not get node status: %v\n", err)
	}

	return nil
}

// CertManager:Up installs or upgrades cert-manager using Helm
func (CertManager) Up() error {
	mg.Deps(Kind.Up)
	fmt.Println("🔐 Setting up cert-manager...")

	// Create namespace if it doesn't exist
	err := sh.Run("kubectl", "create", "namespace", certManagerNS)
	if err != nil {
		// Namespace might already exist, which is fine
		fmt.Printf("ℹ️  Namespace '%s' might already exist\n", certManagerNS)
	}

	// Check if cert-manager is already installed
	exists, err := internal.ReleaseExists("cert-manager", certManagerNS)
	if err != nil {
		return fmt.Errorf("failed to check cert-manager installation: %w", err)
	}

	if exists {
		fmt.Printf("🔄 cert-manager is already installed, upgrading to v%s...\n", certManagerVersion)
		err = internal.UpgradeHelmChart("cert-manager", "oci://quay.io/jetstack/charts/cert-manager", certManagerNS, certManagerVersion, "--set", "crds.enabled=true")
		if err != nil {
			return fmt.Errorf("failed to upgrade cert-manager: %w", err)
		}
		fmt.Printf("✅ cert-manager upgraded to v%s and is ready\n", certManagerVersion)
	} else {
		fmt.Printf("📦 Installing cert-manager v%s...\n", certManagerVersion)
		err = internal.InstallHelmChart("cert-manager", "oci://quay.io/jetstack/charts/cert-manager", certManagerNS, certManagerVersion, "--set", "crds.enabled=true")
		if err != nil {
			return fmt.Errorf("failed to install cert-manager: %w", err)
		}
		fmt.Printf("✅ cert-manager v%s is ready in namespace '%s'\n", certManagerVersion, certManagerNS)
	}

	return nil
}

// CertManager:Down removes cert-manager and cleans up resources
func (CertManager) Down() error {
	fmt.Println("🔥 Tearing down cert-manager...")

	// Check if cert-manager is installed
	exists, err := internal.ReleaseExists("cert-manager", certManagerNS)
	if err != nil {
		return fmt.Errorf("failed to check cert-manager installation: %w", err)
	}

	if !exists {
		fmt.Printf("ℹ️  cert-manager is not installed\n")
		return nil
	}

	// Uninstall the helm release
	err = internal.UninstallHelmChart("cert-manager", certManagerNS)
	if err != nil {
		return fmt.Errorf("failed to uninstall cert-manager: %w", err)
	}

	// Delete CRDs (as recommended in cert-manager docs)
	fmt.Printf("🧹 Cleaning up cert-manager CRDs...\n")
	sh.Run("kubectl", "delete", "crd",
		"issuers.cert-manager.io",
		"clusterissuers.cert-manager.io",
		"certificates.cert-manager.io",
		"certificaterequests.cert-manager.io",
		"orders.acme.cert-manager.io",
		"challenges.acme.cert-manager.io")

	// Delete APIService if it exists
	sh.Run("kubectl", "delete", "apiservice", "v1beta1.webhook.cert-manager.io")

	fmt.Printf("✅ cert-manager torn down successfully\n")
	return nil
}

// CertManager:UpClean removes and reinstalls cert-manager
func (CertManager) UpClean() error {
	fmt.Println("🧹 Clean setting up cert-manager...")

	// First uninstall if it exists
	err := (CertManager{}).Down()
	if err != nil {
		return fmt.Errorf("failed to uninstall existing cert-manager: %w", err)
	}

	// Wait a moment for cleanup
	fmt.Printf("⏳ Waiting for cleanup to complete...\n")
	time.Sleep(5 * time.Second)

	// Then install fresh
	err = (CertManager{}).Up()
	if err != nil {
		return fmt.Errorf("failed to install cert-manager: %w", err)
	}

	fmt.Printf("✅ cert-manager clean setup completed successfully\n")
	return nil
}

// CertManager:Status shows the status of cert-manager installation
func (CertManager) Status() error {
	fmt.Println("📊 Checking cert-manager status...")

	// Check if helm release exists
	exists, err := internal.ReleaseExists("cert-manager", certManagerNS)
	if err != nil {
		return fmt.Errorf("failed to check cert-manager release: %w", err)
	}

	if !exists {
		fmt.Printf("❌ cert-manager is not installed\n")
		return nil
	}

	fmt.Printf("✅ cert-manager helm release exists\n")

	// Get helm status
	fmt.Printf("🔍 Helm release status:\n")
	err = internal.GetHelmChartStatus("cert-manager", certManagerNS)
	if err != nil {
		fmt.Printf("⚠️  Could not get helm status: %v\n", err)
	}

	// Check pod status
	fmt.Printf("🔍 Checking cert-manager pods...\n")
	podOutput, err := sh.Output("kubectl", "get", "pods", "--namespace", certManagerNS, "-l", "app.kubernetes.io/instance=cert-manager")
	if err != nil {
		fmt.Printf("⚠️  Could not get pod status: %v\n", err)
	} else {
		fmt.Printf("%s\n", podOutput)
	}

	// Check cert-manager CRDs
	fmt.Printf("🔍 Checking cert-manager CRDs...\n")
	crdOutput, err := sh.Output("kubectl", "get", "crd", "-l", "app.kubernetes.io/name=cert-manager")
	if err != nil {
		fmt.Printf("⚠️  Could not get CRD status: %v\n", err)
	} else {
		fmt.Printf("%s\n", crdOutput)
	}

	return nil
}
