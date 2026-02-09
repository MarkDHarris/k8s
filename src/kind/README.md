

### The Journey of a Request

Imagine you type http://localhost:8080 into your browser. Here is the path it takes:

1. The Laptop (Host) -> The Cluster Node

    - The Config: In cluster.yaml, you have extraPortMappings.

    - The Logic: hostPort: 8080 tells Docker: "Listen on my laptop's port 8080."

    - The Handoff: Docker forwards that packet to containerPort: 30000 on the kind-control-plane node.

      >  Note: Even though your pod is on a worker node, the Service makes port 30000 available on every node, including the control plane.

2. The Node -> The Service

    - The Config: In your Service YAML, you defined type: NodePort and nodePort: 30000.

    - The Logic: Kubernetes (specifically kube-proxy) is listening on port 30000 on all nodes. It catches the packet and asks, "Where does this go?"

    - The Handoff: It looks at the Service definition and sees it needs to route to port 80 (targetPort: 80).

3. The Service -> The Pod

    - The Config: In your Service YAML, you have selector: {app: nginx}.

    - The Logic: The Service keeps a live list of all Pods that match that label (your "Endpoints").

    - The Handoff: It picks one of those Pods (your nginx-frontend on Worker 2) and sends the traffic directly to its internal IP address on port 80.

Connecting the Dots


|**Component**|**Port Number**|**Defined In File**|**Purpose**|
|---|---|---|---|
|**Browser**|`8080`|`cluster.yaml` (`hostPort`)|Entry point on your laptop.|
|**Cluster Node**|`30000`|`cluster.yaml` (`containerPort`)|Entry point into the Kubernetes network.|
|**Service**|`30000`|`nginx-service.yaml` (`nodePort`)|Listens on the node to catch traffic.|
|**Pod**|`80`|`nginx-service.yaml` (`targetPort`)|The actual web server port inside the container.|





