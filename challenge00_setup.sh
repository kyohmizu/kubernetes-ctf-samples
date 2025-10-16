#!/bin/bash
set -e

NS="ctf-0"
SA_NAME="ctf-player-0"
SECRET_NAME="flag-secret"
KUBECONFIG_FILE="./ctf-0.kubeconfig"
FLAG_VALUE="CTF{Welcome_To_Kubernetes_CTF_Tutorial}"

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
kubectl delete secret $SECRET_NAME ${SA_NAME}-token --ignore-not-found=true -n $NS > /dev/null 2>&1
kubectl delete sa $SA_NAME --ignore-not-found=true -n $NS > /dev/null 2>&1
kubectl delete role ctf-player-role-0 --ignore-not-found=true -n $NS > /dev/null 2>&1
kubectl delete rolebinding ctf-player-binding-0 --ignore-not-found=true -n $NS > /dev/null 2>&1
rm -f $KUBECONFIG_FILE
sleep 5 # Wait for cleanup completion

# ------------------------------------
# 2. CTF resources deployment
# ------------------------------------
echo "🛠️  Deploying CTF resources..."

# 2-1. Create Secret containing the flag
kubectl create secret generic $SECRET_NAME \
  --from-literal=flag="$FLAG_VALUE" \
  -n $NS > /dev/null 2>&1

# ------------------------------------
# 3. ServiceAccount and RBAC setup
# ------------------------------------
echo "🔒 Setting up ServiceAccount and RBAC for CTF player..."

kubectl create sa $SA_NAME -n $NS > /dev/null 2>&1

cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ctf-player-role-0
  namespace: $NS
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["list"]
EOF

kubectl create rolebinding ctf-player-binding-0 \
  --role=ctf-player-role-0 \
  --serviceaccount=$NS:$SA_NAME \
  --namespace=$NS > /dev/null 2>&1

# ------------------------------------
# 4. Kubeconfig creation
# ------------------------------------
echo "🔑 Creating Kubeconfig file..."

# Create Token Secret manually for Kubernetes 1.24+
TOKEN_SECRET_NAME="${SA_NAME}-token"
cat <<EOF | kubectl apply -f - -n $NS > /dev/null 2>&1
apiVersion: v1
kind: Secret
metadata:
  name: $TOKEN_SECRET_NAME
  namespace: $NS
  annotations:
    kubernetes.io/service-account.name: $SA_NAME
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
    user: $SA_NAME
  name: $SA_NAME@$CLUSTER_NAME
current-context: $SA_NAME@$CLUSTER_NAME
kind: Config
preferences: {}
users:
- name: $SA_NAME
  user:
    token: $SA_TOKEN
EOF

sleep 10

echo ""
echo "✅ Setup completed!"
echo ""
echo "---"
echo "🎯 Tutorial Challenge 00"
echo ""
echo "Welcome to Kubernetes CTF! This is a tutorial challenge to get you started."
echo ""
echo "Challenge: Find the flag stored in a Kubernetes Secret."
echo ""
echo "You can use the following Kubeconfig file:"
echo "$KUBECONFIG_FILE"
echo ""
echo "To set the environment variable:"
echo "export KUBECONFIG=$KUBECONFIG_FILE"
echo ""
echo "Commands to try:"
echo "kubectl auth can-i --list"
echo "kubectl get secrets"
echo "---"
