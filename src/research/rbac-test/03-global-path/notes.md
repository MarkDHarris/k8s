


### Create a cluster role
```bash
k apply -f ./clusterrole.yaml
```

### Create a cluster role binding
```bash
k apply -f ./clusterrolebinding.yaml
```

### Test access with Mark's kubeconfig:

```bash
k get nodes -n rbac-test --context=mark-context
```	