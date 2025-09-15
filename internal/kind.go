package internal

import (
	"encoding/base64"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"

	"github.com/adrg/xdg"
	"github.com/magefile/mage/sh"
)

// ClusterExists checks if the specified kind cluster exists
func ClusterExists(name string) (bool, error) {
	clusters, err := sh.Output("kind", "get", "clusters")
	if err != nil {
		return false, fmt.Errorf("failed to get clusters: %w", err)
	}

	for _, cluster := range strings.Split(clusters, "\n") {
		if strings.TrimSpace(cluster) == name {
			return true, nil
		}
	}

	return false, nil
}

// CreateCluster creates a new kind cluster with the given name
func CreateCluster(name string) error {
	return sh.Run("kind", "create", "cluster", "--name", name, "--wait", "60s")
}

// DeleteCluster deletes the kind cluster with the given name
func DeleteCluster(name string) error {
	return sh.Run("kind", "delete", "cluster", "--name", name)
}

// ExportKubeconfig exports the kubeconfig for the given cluster
func ExportKubeconfig(name string) error {
	return sh.Run("kind", "export", "kubeconfig", "--name", name)
}

// GetClusterInfo gets cluster info for the given cluster
func GetClusterInfo(name string) (string, error) {
	return sh.Output("kubectl", "cluster-info", "--context", "kind-"+name)
}

// GetNodeStatus runs kubectl get nodes for the given cluster
func GetNodeStatus(name string) error {
	return sh.Run("kubectl", "get", "nodes", "--context", "kind-"+name)
}

// PortForwardPIDFile returns the path to the PID file for port forwarding
func PortForwardPIDFile(service, namespace string) string {
	return filepath.Join(xdg.DataHome, "kargo", fmt.Sprintf("port-forward-%s-%s.pid", service, namespace))
}

// IsPortForwardRunning checks if a port forwarding process is already running
func IsPortForwardRunning(service, namespace string) (bool, int, error) {
	pidFile := PortForwardPIDFile(service, namespace)

	// Check if PID file exists
	if _, err := os.Stat(pidFile); os.IsNotExist(err) {
		return false, 0, nil
	}

	// Read PID from file
	pidBytes, err := os.ReadFile(pidFile)
	if err != nil {
		return false, 0, fmt.Errorf("failed to read PID file: %w", err)
	}

	pid, err := strconv.Atoi(strings.TrimSpace(string(pidBytes)))
	if err != nil {
		return false, 0, fmt.Errorf("failed to parse PID: %w", err)
	}

	// Check if process is still running
	process, err := os.FindProcess(pid)
	if err != nil {
		return false, 0, nil
	}

	// Send signal 0 to check if process exists
	err = process.Signal(syscall.Signal(0))
	if err != nil {
		// Process doesn't exist, clean up PID file
		os.Remove(pidFile)
		return false, 0, nil
	}

	return true, pid, nil
}

// StartPortForward starts a port forwarding process in the background using Go standard library
func StartPortForward(service, namespace string, localPort, remotePort int) (int, error) {
	// Create kargo data directory if it doesn't exist
	kargoDir := filepath.Join(xdg.DataHome, "kargo")
	if err := os.MkdirAll(kargoDir, 0755); err != nil {
		return 0, fmt.Errorf("failed to create kargo data directory: %w", err)
	}

	// Start kubectl port-forward directly
	cmd := exec.Command("kubectl", "port-forward",
		fmt.Sprintf("svc/%s", service),
		fmt.Sprintf("%d:%d", localPort, remotePort),
		"--namespace", namespace)

	// Set process attributes to run in the background
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Setsid: true, // Start in new session to detach from parent
	}

	// Redirect output to avoid blocking
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	// Start the process
	if err := cmd.Start(); err != nil {
		return 0, fmt.Errorf("failed to start port-forward: %w", err)
	}

	// Save PID to file
	pidFile := PortForwardPIDFile(service, namespace)
	if err := os.WriteFile(pidFile, []byte(fmt.Sprintf("%d", cmd.Process.Pid)), 0644); err != nil {
		// If we can't save the PID file, kill the process
		cmd.Process.Kill()
		return 0, fmt.Errorf("failed to save PID file: %w", err)
	}

	return cmd.Process.Pid, nil
}

// StopPortForward stops a running port forwarding process
func StopPortForward(service, namespace string) error {
	// Check if port forwarding is running
	running, pid, err := IsPortForwardRunning(service, namespace)
	if err != nil {
		return fmt.Errorf("failed to check port forwarding status: %w", err)
	}

	if !running {
		return fmt.Errorf("port forwarding is not running")
	}

	// Kill the process group (since we used Setsid)
	if err := syscall.Kill(-pid, syscall.SIGTERM); err != nil {
		return fmt.Errorf("failed to stop port forwarding process: %w", err)
	}

	// Clean up PID file
	pidFile := PortForwardPIDFile(service, namespace)
	os.Remove(pidFile)

	return nil
}

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
