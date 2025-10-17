#!/bin/bash
set -e

NS="ctf-3" 
FLAG_VALUE="CTF{ConfigMap_Env_Injection_via_Event}"
FLAG_SECRET_NAME="flag-secret"
CRON_SA_NAME="cron-executor-sa"
PLAYER_SA_NAME="ctf-player-3"
CRONJOB_NAME="deployment-creator-job"
DEPLOYMENT_NAME="flag-holder"
CONFIGMAP_NAME="deploy-config"
KUBECONFIG_FILE="./ctf-3.kubeconfig"

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
kubectl delete sa $CRON_SA_NAME $PLAYER_SA_NAME -n $NS --ignore-not-found=true > /dev/null 2>&1
kubectl delete configmap $CONFIGMAP_NAME ${CONFIGMAP_NAME}-template deploy-info -n $NS --ignore-not-found=true > /dev/null 2>&1
kubectl delete role cron-executor-role ctf-player-role-3 -n $NS --ignore-not-found=true > /dev/null 2>&1
kubectl delete rolebinding cron-executor-binding ctf-player-binding-3 -n $NS --ignore-not-found=true > /dev/null 2>&1
kubectl delete networkpolicy restrict-egress-except-cronjob -n $NS --ignore-not-found=true > /dev/null 2>&1
sleep 10 # Wait for cleanup completion

# ------------------------------------
# 2. CTF resources deployment
# ------------------------------------
echo "🛠️  Deploying CTF resources..."

# 2-0. Create NetworkPolicy to restrict egress traffic except for CronJob pods
K8S_API_IP=$(kubectl get endpointslice -l kubernetes.io/service-name=kubernetes -n default -o jsonpath='{.items[0].endpoints[0].addresses[0]}')
cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: restrict-egress-except-cronjob
  namespace: $NS
spec:
  podSelector:
    matchExpressions:
    - key: "cronjob-allowed"
      operator: DoesNotExist
  policyTypes:
  - Egress
  egress:
  # Allow DNS resolution for all pods
  - to: []
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
  # Allow communication within the same namespace
  - to:
    - namespaceSelector:
        matchLabels:
          name: $NS
  # Allow communication to kube-system namespace (for DNS)
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
  # Allow communication to Kubernetes API server by IP CIDR
  - to:
    - ipBlock:
        cidr: $K8S_API_IP/32
    ports:
    - protocol: TCP
      port: 443
    - protocol: TCP
      port: 6443
EOF

# 2-1. Create Secret containing the flag and ConfigMap
kubectl create secret generic $FLAG_SECRET_NAME \
  --from-literal=ctf_flag_key="$FLAG_VALUE" \
  -n $NS > /dev/null 2>&1

DEPLOYMENT_YAML=$(cat <<EOD
apiVersion: apps/v1
kind: Deployment
metadata:
  name: \${DEPLOYMENT_NAME_FROM_CRONJOB_ENV}
  labels:
    app: ctf-3
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ctf-3
  template:
    metadata:
      labels:
        app: ctf-3
    spec:
      containers:
      - name: main-container
        image: busybox
        command: ["/bin/sh", "-c"]
        args:
        - |
          echo The flag is embedded as an environment variable in the CronJob: \${FLAG_FROM_CRONJOB_ENV}
          sleep 3600
        volumeMounts:
        - name: config-volume
          mountPath: /mnt/config
      volumes:
      - name: config-volume
        configMap:
          name: $CONFIGMAP_NAME
          items:
          - key: deploy.yaml
            path: "deploy.yaml"
EOD
)

kubectl create configmap ${CONFIGMAP_NAME}-template -n $NS \
  --from-literal=deploy-template.yaml="$DEPLOYMENT_YAML" > /dev/null 2>&1

kubectl create configmap deploy-info -n $NS \
  --from-literal=deployment-name="$DEPLOYMENT_NAME" > /dev/null 2>&1

# 2-2. Create RBAC for CronJob execution
kubectl create sa $CRON_SA_NAME -n $NS > /dev/null 2>&1

cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: cron-executor-role
  namespace: $NS
rules:
- apiGroups: ["apps"]
  resources: ["deployments"] 
  verbs: ["create", "get", "patch"]
EOF

kubectl create rolebinding cron-executor-binding \
  --role=cron-executor-role \
  --serviceaccount=$NS:$CRON_SA_NAME \
  --namespace=$NS > /dev/null 2>&1

# 2-3. Create CronJob
cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: batch/v1
kind: CronJob
metadata:
  name: $CRONJOB_NAME
  namespace: $NS
spec:
  schedule: "*/1 * * * *" 
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      ttlSecondsAfterFinished: 60 
      template:
        metadata:
          labels:
            cronjob-allowed: "true"
        spec:
          serviceAccountName: $CRON_SA_NAME 
          restartPolicy: OnFailure
          initContainers:
          - name: kubectl-installer
            image: busybox
            command: ["/bin/sh", "-c", "wget -O /tools/kubectl https://dl.k8s.io/release/\$(wget -qO- https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x /tools/kubectl"]
            volumeMounts:
            - name: tools-volume
              mountPath: /tools
          containers:
          - name: main-container
            image: busybox 
            command: ["/bin/sh", "-c"]
            args:
            - |
              DEPLOYMENT_YAML=\$(cat /mnt/config/deploy.yaml)
              /bin/sh -c "cat << EOF | /tools/kubectl apply -f -
              \$DEPLOYMENT_YAML
              EOF"
              
              sleep 3
            env:
            - name: FLAG_FROM_CRONJOB_ENV
              valueFrom:
                secretKeyRef:
                  name: $FLAG_SECRET_NAME
                  key: ctf_flag_key 
            - name: DEPLOYMENT_NAME_FROM_CRONJOB_ENV
              valueFrom:
                configMapKeyRef:
                  name: deploy-info
                  key: deployment-name
            volumeMounts:
            - name: config-vol
              mountPath: /mnt/config
              readOnly: true
            - name: tools-volume
              mountPath: /tools
          volumes:
          - name: config-vol
            configMap:
              name: $CONFIGMAP_NAME
              items:
              - key: deploy.yaml
                path: "deploy.yaml"
          - name: tools-volume
            emptyDir: {}
EOF

# 2-4. Create immediate Job from CronJob template
kubectl create job --from=cronjob/$CRONJOB_NAME ${CRONJOB_NAME}-initial-run -n $NS > /dev/null 2>&1
sleep 5

# ------------------------------------
# 3. ServiceAccount and RBAC setup for CTF Player
# ------------------------------------
echo "🔒 Setting up ServiceAccount and RBAC for CTF player..."

kubectl create sa $PLAYER_SA_NAME -n $NS > /dev/null 2>&1

cat <<EOF | kubectl apply -f - -n $NS > /dev/null 2>&1
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ctf-player-role-3
  namespace: $NS
rules:
- apiGroups: [""]
  resources: ["events"] 
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["configmaps"] 
  verbs: ["list", "get", "create", "patch"]
EOF

kubectl create rolebinding ctf-player-binding-3 \
  --role=ctf-player-role-3 \
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