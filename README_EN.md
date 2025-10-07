# Kubernetes CTF Samples

Sample challenges for Kubernetes CTF (Capture The Flag).

## Environment

The following playground services are recommended:

- [Killercoda](https://killercoda.com/)
- [iximiuz Labs](https://labs.iximiuz.com/playgrounds?category=kubernetes&filter=all)
- [KodeKloud](https://kodekloud.com/public-playgrounds)

You can also run these challenges in local environments using the following tools:

- [kind](https://github.com/kubernetes-sigs/kind)
- [minikube](https://github.com/kubernetes/minikube)

## Requirements

- `kubectl` command is installed
- Administrator access to a Kubernetes cluster
- Basic knowledge of Kubernetes (Pod, Service, Deployment, etc.)

## Rules

- Flags are in the format `CTF{...}`
- Obtain the flag string within the given permission scope
- You can solve by looking at the code, but it reduces the difficulty

## Getting Started

| Title | Level |
|:-----:|:---------:|
| Challenge 01 | ⭐️ |
| Challenge 02 | ⭐️ |
| Challenge 03 | ⭐️⭐️ |

### Challenge 01

```bash
chmod +x challenge01_setup.sh
./challenge01_setup.sh
```

Cleanup:

```bash
kubectl delete ns ctf-1 --ignore-not-found=true
```

### Challenge 02

```bash
chmod +x challenge02_setup.sh
./challenge02_setup.sh
```

Cleanup:

```bash
kubectl delete ns ctf-2 --ignore-not-found=true
```

### Challenge 03

```bash
chmod +x challenge03_setup.sh
./challenge03_setup.sh
```

Cleanup:

```bash
kubectl delete ns ctf-3 --ignore-not-found=true
```

## Tips & Tricks

<details><summary>Useful Commands</summary>

```bash
# Check your permissions
kubectl auth can-i --list

# List specific resources
# kubectl get [resourceType]
kubectl get po
kubectl get deploy
kubectl get events

# Get resource manifest
# kubectl get [resourceType] [resourceName] -o yaml
kubectl get po pod01 -o yaml

# List all major resources
kubectl get all

# Get detailed resource information and events
# kubectl describe [resourceType] [resourceName]
kubectl describe po pod01

# Execute commands in a Pod
# kubectl exec -it [podName] -- sh
kubectl exec -it pod01 -- sh

# Check logs
# kubectl logs [podName]
kubectl logs pod01
```

</details>

---

## License

Apache License Version 2.0
