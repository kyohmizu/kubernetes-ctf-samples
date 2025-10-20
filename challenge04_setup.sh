#!/bin/bash
set -e

# ===============================================================================
# ⚠️  WARNING  ⚠️
# 
# 🇬🇧 ENGLISH:
# DO NOT READ THIS SCRIPT BEFORE ATTEMPTING THE CHALLENGE!
# This script contains the solution and will spoil the challenge.
#
# -------------------------------------------------------------------------------
#
# 🇯🇵 日本語:
# チャレンジ前にこのスクリプトを読まないでください！
# このスクリプトには解答が含まれており、CTFチャレンジのネタバレになります。
#
# ===============================================================================




NS="ctf-4" 
FLAG_VALUE="CTF{Lease_Resources_Are_Hidden_Gems}"
LEASE_NAME="flag-is-here"
PLAYER_SA_NAME="ctf-player-4"
KUBECONFIG_FILE="./ctf-4.kubeconfig"

# ------------------------------------
# 0. Permission check
# ------------------------------------
echo "🔍 Checking permissions (kubectl get ns)..."
if ! kubectl get ns > /dev/null 2>&1; then
    echo "❌ Error: No connection or permission to Kubernetes cluster."
    echo "   Please check the following:"
    echo "   - kubectl is properly installed"
    echo "   - kubeconfig is properly configured"
    exit 1
fi
echo "✅ Permission check completed."
echo ""

# ------------------------------------
# 1. Initialization
# ------------------------------------
echo "🆕 Creating Namespace ($NS)..."
kubectl create namespace $NS --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1
echo "🧹 Cleaning up existing resources..."
kubectl delete all --all -n $NS --ignore-not-found=true > /dev/null 2>&1
kubectl delete sa $PLAYER_SA_NAME -n $NS --ignore-not-found=true > /dev/null 2>&1
kubectl delete rolebinding ctf-player-admin-binding-4 -n $NS --ignore-not-found=true > /dev/null 2>&1
kubectl delete lease $LEASE_NAME -n $NS --ignore-not-found=true > /dev/null 2>&1
rm -f $KUBECONFIG_FILE
sleep 5 # Wait for cleanup completion

# ------------------------------------
# 2. CTF resources deployment
# ------------------------------------
echo "🛠️  Deploying CTF resources..."

# Create the Lease with the hidden flag
cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: coordination.k8s.io/v1
kind: Lease
metadata:
  name: $LEASE_NAME
  namespace: $NS
  annotations:
    description: "${FLAG_VALUE}"
spec:
  holderIdentity: "ctf-4"
  leaseDurationSeconds: 3600
EOF

sleep 10

# ------------------------------------
# 3. ServiceAccount and RBAC setup for CTF Player
# ------------------------------------
echo "🔒 Setting up ServiceAccount and RBAC for CTF player..."

kubectl create sa $PLAYER_SA_NAME -n $NS > /dev/null 2>&1

# Give the player Admin permissions within the namespace
kubectl create rolebinding ctf-player-admin-binding-4 \
  --clusterrole=cluster-admin \
  --serviceaccount=$NS:$PLAYER_SA_NAME \
  --namespace=$NS > /dev/null 2>&1

# ------------------------------------
# 4. Kubeconfig creation
# ------------------------------------
echo "🔑 Creating Kubeconfig file..."

# Get token (Create Token Secret manually for Kubernetes 1.24+)
TOKEN_SECRET_NAME="${PLAYER_SA_NAME}-token"
cat <<EOF | kubectl apply -f - -n $NS > /dev/null 2>&1
apiVersion: v1
kind: Secret
metadata:
  name: $TOKEN_SECRET_NAME
  namespace: $NS
  annotations:
    kubernetes.io/service-account.name: $PLAYER_SA_NAME
type: kubernetes.io/service-account-token
EOF

# Wait for Secret creation and get token
sleep 5
SA_TOKEN=$(kubectl get secret $TOKEN_SECRET_NAME -n $NS -o jsonpath='{.data.token}' | base64 -d)

# Get cluster information
CURRENT_CONTEXT=$(kubectl config current-context)
CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.contexts[?(@.name=="'$CURRENT_CONTEXT'")].context.cluster}')
CA_CERT_DATA=$(kubectl config view --raw -o jsonpath='{.clusters[?(@.name=="'$CLUSTER_NAME'")].cluster.certificate-authority-data}')
K8S_SERVER=$(kubectl config view --raw -o jsonpath='{.clusters[?(@.name=="'$CLUSTER_NAME'")].cluster.server}')

# Write Kubeconfig file
cat > $KUBECONFIG_FILE <<EOF
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: $CA_CERT_DATA
    server: $K8S_SERVER
  name: $CLUSTER_NAME
contexts:
- context:
    cluster: $CLUSTER_NAME
    namespace: $NS
    user: $PLAYER_SA_NAME
  name: $PLAYER_SA_NAME@$CLUSTER_NAME
current-context: $PLAYER_SA_NAME@$CLUSTER_NAME
kind: Config
preferences: {}
users:
- name: $PLAYER_SA_NAME
  user:
    token: $SA_TOKEN
EOF

sleep 5

echo ""
echo "✅ Setup completed!"
echo ""
echo "---"
echo "You can start the CTF challenge using the following Kubeconfig file:"
echo "$KUBECONFIG_FILE"
echo ""
echo "To set environment variable:"
echo "export KUBECONFIG=$KUBECONFIG_FILE"
echo "---"