package internal

import (
	"encoding/base64"
	"fmt"
	"strings"

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
