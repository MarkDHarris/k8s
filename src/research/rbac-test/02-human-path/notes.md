
###  X.509 client certificates signed by the cluster's own Certificate Authority (CA)

```bash
openssl genrsa -out mark.key 2048
openssl req -new -key mark.key -out mark.csr -subj "/CN=mark/O=developers"
```

### Submit CSR to the Kubernetes cluster so the internal Certificate Authority can sign it. 

- We do this by creating a CertificateSigningRequest resource.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: mark
spec:
  request: $(cat mark.csr | base64 | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
  - client auth
EOF
```

### Approve the CSR:

```bash
k certificate approve mark
```

### Retrieve the signed certificate:

```bash
k get csr mark -o jsonpath='{.status.certificate}' | base64 --decode > mark.crt
```

### Create a kubeconfig file for Mark to use the signed certificate for authentication:

```bash
CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')
k config set-credentials mark --client-key=mark.key --client-certificate=mark.crt
k config set-context mark-context --cluster=$CLUSTER_NAME --user=mark
```	

### Test access with Mark's kubeconfig:

```bash
k get pods -n rbac-test --context=mark-context
```	

### Create a group binding to bind the role to the service account
```bash
k apply -f ./groupbinding.yaml
```

### Now, test access with Mark's kubeconfig:

```bash
k get pods -n rbac-test --context=mark-context
```



