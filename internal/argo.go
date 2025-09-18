package internal

import (
	"encoding/base64"
	"fmt"
	"strings"
	"time"

	"github.com/magefile/mage/sh"
)

// GetArgoCDAdminPassword retrieves the ArgoCD admin password
func GetArgoCDAdminPassword(namespace string) (string, error) {
	// Get the admin password from the secret
	password, err := sh.Output("kubectl", "get", "secret", "argocd-initial-admin-secret",
		"--namespace", namespace, "-o", "jsonpath={.data.password}")
	if err != nil {
		return "", fmt.Errorf("failed to get ArgoCD admin password: %w", err)
	}

	// Decode base64 using Go standard library
	decoded, err := base64.StdEncoding.DecodeString(strings.TrimSpace(password))
	if err != nil {
		return "", fmt.Errorf("failed to decode password: %w", err)
	}

	return string(decoded), nil
}

// ArgoRolloutsExists checks if Argo Rollouts is installed by checking for the controller pod
func ArgoRolloutsExists(namespace string) (bool, error) {
	// Check if the argo-rollouts-controller pod exists and is running
	output, err := sh.Output("kubectl", "get", "pods", "--namespace", namespace, "-l", "app.kubernetes.io/name=argo-rollouts", "--no-headers")
	if err != nil {
		return false, nil
	}

	// If we get output, it means pods exist
	return strings.TrimSpace(output) != "", nil
}

// WaitForArgoRolloutsReady waits for Argo Rollouts to be ready
func WaitForArgoRolloutsReady(namespace string) error {
	fmt.Printf("⏳ Waiting for Argo Rollouts to be ready in namespace '%s'...\n", namespace)

	for i := 0; i < 60; i++ { // Wait up to 60 seconds
		// Check if the controller pod is running
		output, err := sh.Output("kubectl", "get", "pods", "--namespace", namespace, "-l", "app.kubernetes.io/name=argo-rollouts", "--no-headers")
		if err == nil && strings.Contains(output, "Running") {
			fmt.Printf("✅ Argo Rollouts is ready\n")
			return nil
		}
		time.Sleep(1 * time.Second)
	}

	return fmt.Errorf("timeout waiting for Argo Rollouts to be ready in namespace '%s'", namespace)
}
