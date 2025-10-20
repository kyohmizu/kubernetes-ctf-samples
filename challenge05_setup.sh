#!/bin/bash
set -e

NS="ctf-5" 
FLAG_VALUE="CTF{Anonymous_Access_Security_Risk}"
FLAG_SECRET_NAME="flag-secret"
PLAYER_SA_NAME="ctf-player-5"
KUBECONFIG_FILE="./ctf-5.kubeconfig"

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
kubectl delete secret $FLAG_SECRET_NAME -n $NS --ignore-not-found=true > /dev/null 2>&1
kubectl delete sa $PLAYER_SA_NAME -n $NS --ignore-not-found=true > /dev/null 2>&1
kubectl delete role ctf-player-role-5 anonymous-secret-reader -n $NS --ignore-not-found=true > /dev/null 2>&1
kubectl delete rolebinding ctf-player-view-binding-5 ctf-player-rbac-binding-5 anonymous-secret-access -n $NS --ignore-not-found=true > /dev/null 2>&1
rm -f $KUBECONFIG_FILE
sleep 5 # Wait for cleanup completion

# ------------------------------------
# 2. CTF resources deployment
# ------------------------------------
echo "🛠️  Deploying CTF resources..."

# 2-1. Create Secret containing the flag
kubectl create secret generic $FLAG_SECRET_NAME \
  --from-literal=flag.txt="$FLAG_VALUE" \
  -n $NS > /dev/null 2>&1

# 2-2. Create Role for anonymous access to the flag secret
cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: anonymous-secret-reader
  namespace: $NS
rules:
- apiGroups: [""]
  resources: ["secrets"]
  resourceNames: ["$FLAG_SECRET_NAME"]
  verbs: ["get"]
EOF

# 2-3. Create RoleBinding to grant anonymous access
cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: anonymous-secret-access
  namespace: $NS
subjects:
- kind: Group
  name: system:unauthenticated
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: anonymous-secret-reader
  apiGroup: rbac.authorization.k8s.io
EOF

# ------------------------------------
# 3. ServiceAccount and RBAC setup for CTF Player
# ------------------------------------
echo "🔒 Setting up ServiceAccount and RBAC for CTF player..."

kubectl create sa $PLAYER_SA_NAME -n $NS > /dev/null 2>&1

# Create Role for CTF player with view permissions and RBAC read access
cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ctf-player-role-5
  namespace: $NS
rules:
- apiGroups: ["rbac.authorization.k8s.io"]
  resources: ["roles", "rolebindings"]
  verbs: ["list", "get"]
EOF

# Give the player view permissions within the namespace
kubectl create rolebinding ctf-player-view-binding-5 \
  --clusterrole=view \
  --serviceaccount=$NS:$PLAYER_SA_NAME \
  --namespace=$NS > /dev/null 2>&1

# Give the player RBAC read permissions
kubectl create rolebinding ctf-player-rbac-binding-5 \
  --role=ctf-player-role-5 \
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