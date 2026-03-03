

### Create a namespace and service account

```bash
kubectl create namespace rbac-test
kubectl create serviceaccount my-app-sa -n rbac-test
```

### Create a role that allows listing pods

```bash
k apply -f ./role.yaml
```

### Create a role binding to bind the role to the service account
```bash
k apply -f ./rolebinding.yaml
```

### Impersonate the service account to check if it has permissions to list pods

```bash
kubectl auth can-i list pods --as=system:serviceaccount:rbac-test:my-app-sa -n rbac-test
```