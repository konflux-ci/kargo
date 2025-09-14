package internal

import (
	"fmt"
	"time"

	"github.com/magefile/mage/sh"
)

// ReleaseExists checks if a helm release exists in the specified namespace
func ReleaseExists(name, namespace string) (bool, error) {
	err := sh.Run("helm", "status", name, "--namespace", namespace)
	if err != nil {
		// If helm status fails, the release doesn't exist
		return false, nil
	}
	return true, nil
}

// EnsureHelmRepo adds a helm repository if it doesn't already exist
func EnsureHelmRepo(name, url string) error {
	fmt.Printf("📦 Ensuring helm repository '%s' is available...\n", name)
	return sh.Run("helm", "repo", "add", name, url)
}

// WaitForNamespaceDeleted waits for a namespace to be completely deleted
func WaitForNamespaceDeleted(namespace string) error {
	fmt.Printf("⏳ Waiting for namespace '%s' to be fully deleted...\n", namespace)

	for i := 0; i < 60; i++ { // Wait up to 60 seconds
		err := sh.Run("kubectl", "get", "namespace", namespace)
		if err != nil {
			// If kubectl get namespace fails, the namespace is gone
			fmt.Printf("✅ Namespace '%s' has been deleted\n", namespace)
			return nil
		}
		time.Sleep(1 * time.Second)
	}

	return fmt.Errorf("timeout waiting for namespace '%s' to be deleted", namespace)
}

// InstallHelmChart installs a Helm chart
func InstallHelmChart(name, chart, namespace, version string, values ...string) error {
	args := []string{"install", name, chart, "--namespace", namespace}
	if version != "" {
		args = append(args, "--version", version)
	}
	args = append(args, values...)
	return sh.Run("helm", args...)
}

// UpgradeHelmChart upgrades a Helm chart
func UpgradeHelmChart(name, chart, namespace, version string, values ...string) error {
	args := []string{"upgrade", name, chart, "--namespace", namespace}
	if version != "" {
		args = append(args, "--version", version)
	}
	args = append(args, values...)
	return sh.Run("helm", args...)
}

// UninstallHelmChart uninstalls a Helm chart
func UninstallHelmChart(name, namespace string) error {
	return sh.Run("helm", "uninstall", name, "--namespace", namespace)
}

// GetHelmChartStatus gets the status of a Helm chart
func GetHelmChartStatus(name, namespace string) error {
	return sh.Run("helm", "status", name, "--namespace", namespace)
}
