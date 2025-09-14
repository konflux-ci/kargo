//go:build mage

package main

import (
	"fmt"
	"os"

	"github.com/konflux-ci/kargo/internal"
	"github.com/magefile/mage/mg"
	"github.com/magefile/mage/sh"
)

// Kind manages kind cluster operations
type Kind mg.Namespace

const (
	clusterName = "kargo"
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
