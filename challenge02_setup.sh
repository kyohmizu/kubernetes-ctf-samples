#!/bin/bash
set -e

NS="ctf-2" 
FLAG_VALUE="CTF{RBAC_Pod_Creation_Escalation}"
FLAG_SECRET_NAME="flag-secret"
CREATOR_SA_NAME="pod-creator-sa"
PLAYER_SA_NAME="ctf-player-2"
TARGET_POD_NAME="creator-pod"
KUBECONFIG_FILE="./ctf-2.kubeconfig"

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
kubectl delete secret $FLAG_SECRET_NAME ${PLAYER_SA_NAME}-token -n $NS --ignore-not-found=true > /dev/null 2>&1
kubectl delete sa $CREATOR_SA_NAME $PLAYER_SA_NAME -n $NS --ignore-not-found=true > /dev/null 2>&1
kubectl delete role pod-creator-role ctf-player-role-2 -n $NS --ignore-not-found=true > /dev/null 2>&1
kubectl delete rolebinding pod-creator-binding ctf-player-binding-2 -n $NS --ignore-not-found=true > /dev/null 2>&1
rm -f $KUBECONFIG_FILE
sleep 5 # Wait for cleanup completion

# 2-1. Create Secret containing the flag (invisible to players)
kubectl create secret generic $FLAG_SECRET_NAME \
  --from-literal=flag.txt="$FLAG_VALUE" \
  -n $NS > /dev/null 2>&1

# ------------------------------------
# 2. CTF resources deployment
# ------------------------------------
echo "🛠️  Deploying CTF resources..."

kubectl create sa $CREATOR_SA_NAME -n $NS > /dev/null 2>&1

# 2-1. Create Role and RoleBinding with Pod creation permissions
cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-creator-role
  namespace: $NS
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["create", "get"]
EOF

kubectl create rolebinding pod-creator-binding \
  --role=pod-creator-role \
  --serviceaccount=$NS:$CREATOR_SA_NAME \
  --namespace=$NS > /dev/null 2>&1

# 2-2. Create target Pod
cat <<EOF | kubectl apply -f - -n $NS > /dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: $TARGET_POD_NAME
  namespace: ctf-2
  labels:
    app: pod-creator
spec:
  serviceAccountName: $CREATOR_SA_NAME
  containers:
  - name: main-container
    image: busybox 
    command: ["/bin/sh", "-c", "echo 'Execute me. kubectl is ready.' && wget -O /bin/kubectl https://dl.k8s.io/release/\$(wget -qO- https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x /bin/kubectl && echo 'Trying to get flag secret...' && /bin/kubectl get secret flag-secret -o yaml || sleep 3600"]
EOF
kubectl wait --for=condition=ready pod/$TARGET_POD_NAME -n $NS --timeout=60s > /dev/null 2>&1

# ------------------------------------
# 3. ServiceAccount and RBAC setup for CTF Player
# ------------------------------------
echo "🔒 Setting up ServiceAccount and RBAC for CTF player..."

kubectl create sa $PLAYER_SA_NAME -n $NS > /dev/null 2>&1

cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ctf-player-role-2
  namespace: $NS
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log", "events"]
  verbs: ["list", "get"]
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create"]
EOF

kubectl create rolebinding ctf-player-binding-2 \
  --role=ctf-player-role-2 \
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

sleep 10

echo ""
echo "✅ Setup completed!"
echo ""
echo "---"
echo "You can challenge CTF using the following Kubeconfig file:"
echo "$KUBECONFIG_FILE"
echo ""
echo "To set environment variable:"
echo "export KUBECONFIG=$KUBECONFIG_FILE"
echo "---"