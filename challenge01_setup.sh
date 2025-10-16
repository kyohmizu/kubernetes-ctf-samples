#!/bin/bash
set -e

NS="ctf-1"
SA_NAME="ctf-player"
DEPLOYMENT_NAME="hidden-flag-app"
SECRET_NAME="flag-secret"
KUBECONFIG_FILE="./ctf-1.kubeconfig"
FLAG_VALUE="CTF{Exec_Into_The_Old_Pod_And_Win}"

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
kubectl delete deployment $DEPLOYMENT_NAME --ignore-not-found=true -n $NS > /dev/null 2>&1
kubectl delete secret $SECRET_NAME ${SA_NAME}-token --ignore-not-found=true -n $NS > /dev/null 2>&1
kubectl delete sa $SA_NAME --ignore-not-found=true -n $NS > /dev/null 2>&1
kubectl delete role ctf-player-role --ignore-not-found=true -n $NS > /dev/null 2>&1
kubectl delete rolebinding ctf-player-binding --ignore-not-found=true -n $NS > /dev/null 2>&1
rm -f $KUBECONFIG_FILE
sleep 5 # Wait for cleanup completion

# ------------------------------------
# 2. CTF resources deployment
# ------------------------------------
echo "🛠️  Deploying CTF resources..."

# 2-1. Create Secret containing the flag
kubectl create secret generic $SECRET_NAME \
  --from-literal=flag.txt="$FLAG_VALUE" \
  -n $NS > /dev/null 2>&1

# 2-2. Create Deployment
cat <<EOF | kubectl apply -f - -n $NS > /dev/null 2>&1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEPLOYMENT_NAME
  namespace: $NS
spec:
  replicas: 1
  revisionHistoryLimit: 2
  selector:
    matchLabels:
      app: ctf-app
      version: v1
  template:
    metadata:
      labels:
        app: ctf-app
        version: v1
    spec:
      containers:
      - name: main-container
        image: busybox
        command: ["/bin/sh", "-c", "echo 'Application v1 running (Flag Present).'; sleep 3600"]
        volumeMounts:
        - name: flag-volume
          mountPath: /flag
          readOnly: true
      volumes:
      - name: flag-volume
        secret:
          secretName: $SECRET_NAME
EOF

# Wait for rollout completion
kubectl rollout status deployment/$DEPLOYMENT_NAME -n $NS > /dev/null 2>&1

# 2-3. Update Deployment
cat <<EOF | kubectl apply -f - -n $NS > /dev/null 2>&1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEPLOYMENT_NAME
  namespace: $NS
spec:
  replicas: 1
  revisionHistoryLimit: 2
  selector:
    matchLabels:
      app: ctf-app
      version: v1
  template:
    metadata:
      labels:
        app: ctf-app
        version: v1
    spec:
      containers:
      - name: main-container
        image: busybox
        command: ["/bin/sh", "-c", "echo 'Application v2 running (No Flag).'; sleep 3600"]
EOF

# Wait for rollout completion
kubectl rollout status deployment/$DEPLOYMENT_NAME -n $NS > /dev/null 2>&1

# 2-4. Update Deployment
cat <<EOF | kubectl apply -f - -n $NS > /dev/null 2>&1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEPLOYMENT_NAME
  namespace: $NS
spec:
  replicas: 1
  revisionHistoryLimit: 2
  selector:
    matchLabels:
      app: ctf-app
      version: v1
  template:
    metadata:
      labels:
        app: ctf-app
        version: v1
    spec:
      containers:
      - name: main-container
        image: busybox
        command: ["/bin/sh", "-c", "echo 'Application is running (No Flag).'; sleep 3600"]
EOF

kubectl rollout status deployment/$DEPLOYMENT_NAME -n $NS > /dev/null 2>&1
sleep 5

# ------------------------------------
# 3. ServiceAccount and RBAC setup for CTF Player
# ------------------------------------
echo "🔒 Setting up ServiceAccount and RBAC for CTF player..."

kubectl create sa $SA_NAME -n $NS > /dev/null 2>&1

cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ctf-player-role
  namespace: $NS
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "describe", "patch"]
- apiGroups: ["apps"]
  resources: ["replicasets"]
  verbs: ["list"]
- apiGroups: [""]
  resources: ["pods", "events"]
  verbs: ["get", "list", "describe"]
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create"]
EOF

cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ctf-player-binding
  namespace: $NS
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ctf-player-role
subjects:
- kind: ServiceAccount
  name: $SA_NAME
  namespace: $NS
EOF

# ------------------------------------
# 4. Kubeconfig creation
# ------------------------------------
echo "🔑 Creating Kubeconfig file..."

# Get token (Create Token Secret manually for Kubernetes 1.24+)
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
echo "You can challenge CTF using the following Kubeconfig file:"
echo "$KUBECONFIG_FILE"
echo ""
echo "Example:"
echo "kubectl --kubeconfig=$KUBECONFIG_FILE get deployments -n $NS"
echo ""
echo "To set environment variable:"
echo "export KUBECONFIG=$KUBECONFIG_FILE"
echo "---"