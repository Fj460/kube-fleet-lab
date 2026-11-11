# KubeFleet Lab

A lightweight, disposable multi-cluster Kubernetes environment for experimenting with [KubeFleet](https://kubefleet.dev/).

The infrastructure is provisioned on DigitalOcean using Terraform. Each Droplet runs an independent single-node [k0s](https://k0sproject.io/) cluster, configured through [k0sctl](https://github.com/k0sproject/k0sctl).

The environment consists of one KubeFleet hub and two member clusters.

## Architecture

| Cluster | Role | Droplet size |
|---|---|---|
| `fleet-hub` | KubeFleet hub | 2 vCPU / 4 GiB |
| `member-1` | Member cluster | 1 vCPU / 2 GiB |
| `member-2` | Member cluster | 1 vCPU / 2 GiB |

All Droplets run Ubuntu and are deployed inside a dedicated DigitalOcean VPC.

**Infrastructure workflow:**

```text
Terraform
    |
    v
DigitalOcean Droplets + VPC + Firewall
    |
    v
k0sctl
    |
    +---- fleet-hub
    |
    +---- member-1
    |
    +---- member-2
    |
    v
KubeFleet
    |
    +---- Hub installation
    |
    +---- Member registration
    |
    v
Cross-cluster resource placement
```

This setup focuses on fleet management, cluster registration, and cross-cluster resource placement. Member clusters are single-node installations and do not provide multi-node scheduling or high availability.

## Prerequisites

The following tools are required on the provisioning machine:

- [Terraform](https://developer.hashicorp.com/terraform)
- [DigitalOcean CLI](https://docs.digitalocean.com/reference/doctl/)
- [kubectl](https://kubernetes.io/docs/reference/kubectl/)
- [Helm](https://helm.sh/)
- [jq](https://jqlang.org/)
- [k0sctl](https://github.com/k0sproject/k0sctl)

On macOS, install them with Homebrew:

```bash
brew install terraform doctl kubectl helm jq
brew install k0sproject/tap/k0sctl
```

A DigitalOcean API token and an SSH key registered with DigitalOcean are also required.

## Configuration

Authenticate the DigitalOcean CLI:

```bash
doctl auth init
```

List registered SSH keys:

```bash
doctl compute ssh-key list
```

Create an SSH key if necessary:

```bash
doctl compute ssh-key create macbook-lab \
  --public-key-file "$HOME/.ssh/id_ed25519.pub"
```

Create the Terraform configuration:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Configure the required variables in `terraform.tfvars`, including:

- DigitalOcean SSH key fingerprint or ID.
- SSH private key path.
- Administrator public IPv4 address in CIDR notation (`/32`).
- Other deployment-specific variables.

The `terraform.tfvars` file contains environment-specific configuration and must not be committed.

Export the DigitalOcean API token:

```bash
export TF_VAR_do_token="YOUR_DIGITALOCEAN_API_TOKEN"
```

## Deployment

### 1. Provision infrastructure

From the `terraform/` directory:

```bash
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Terraform provisions:

- Three DigitalOcean Droplets.
- A dedicated VPC.
- A Cloud Firewall.
- Network rules for SSH and Kubernetes API access.

SSH access is restricted to the configured administrator CIDR. Kubernetes API access is restricted to the administrator and lab Droplets.

### 2. Bootstrap Kubernetes clusters

From the repository root:

```bash
./scripts/apply-k0s.sh
```

The script retrieves Droplet addresses from Terraform outputs, prepares the k0sctl configurations, installs k0s on each Droplet, retrieves the cluster kubeconfigs, and merges them into:

```text
.generated/kubeconfig
```

Configure kubectl to use the generated kubeconfig:

```bash
export KUBECONFIG="$PWD/.generated/kubeconfig"
```

Verify the available contexts and cluster nodes:

```bash
kubectl config get-contexts

kubectl --context fleet-hub get nodes -o wide
kubectl --context member-1 get nodes -o wide
kubectl --context member-2 get nodes -o wide
```

### 3. Install KubeFleet

KubeFleet is installed on the hub cluster using Helm.

The installation and member registration workflow is handled by:

```bash
./scripts/install-kubefleet.sh
```

The script:

1. Installs the KubeFleet hub components on `fleet-hub`.
2. Retrieves the upstream member registration script for the configured KubeFleet release.
3. Registers `member-1` and `member-2` with the hub.

The KubeFleet version is configurable through `KUBEFLEET_VERSION` in `scripts/install-kubefleet.sh`.

Available releases: [KubeFleet GitHub Releases](https://github.com/kubefleet-dev/kubefleet/releases).

Verify member registration:

```bash
kubectl --context fleet-hub get memberclusters
kubectl --context fleet-hub get memberclusters -o wide
```

Members should report a `JOINED` condition with status `True`.

For additional registration details, refer to the [KubeFleet cluster management documentation](https://kubefleet.dev/docs/how-tos/clusters/).

### 4. Test cross-cluster placement

The `clusters/` directory contains sample Kubernetes resources for testing KubeFleet placement.

Apply the sample namespace and placement policy:

```bash
kubectl --context fleet-hub apply \
  -f clusters/sample-namespace.yaml

kubectl --context fleet-hub apply \
  -f clusters/sample-placement.yaml
```

Inspect placement status:

```bash
kubectl --context fleet-hub get clusterresourceplacements

kubectl --context fleet-hub describe \
  clusterresourceplacement sample-namespace
```

Verify resource distribution across member clusters:

```bash
for ctx in member-1 member-2; do
  echo "== $ctx =="

  kubectl --context "$ctx" get namespace fleet-demo

  kubectl --context "$ctx" get configmap -n fleet-demo
done
```

## Infrastructure teardown

Remove the lab environment:

```bash
./scripts/destroy.sh
```

The script removes generated kubeconfigs and invokes `terraform destroy`.

Terraform displays the destruction plan before requesting confirmation.

The Terraform state is retained locally after destruction and can be removed when no longer needed.

**Note:** DigitalOcean Droplets incur charges while they exist, including when powered off. Destroying the infrastructure removes the provisioned Droplets, VPC, and firewall.

Do not remove Terraform state before completing the destruction process.

## Repository structure

```text
kube-fleet-lab/
├── clusters/
│   ├── sample-namespace.yaml
│   └── sample-placement.yaml
│
├── k0sctl/
│   ├── fleet-hub.yaml
│   ├── member-1.yaml
│   └── member-2.yaml
│
├── scripts/
│   ├── apply-k0s.sh
│   ├── install-kubefleet.sh
│   └── destroy.sh
│
└── terraform/
    ├── versions.tf
    ├── variables.tf
    ├── main.tf
    ├── outputs.tf
    └── terraform.tfvars.example
```

## Design considerations

- **Disposable infrastructure:** Intended for short-lived experimentation rather than permanent workloads.
- **Independent clusters:** Each Droplet hosts its own single-node k0s installation.
- **Infrastructure as Code:** DigitalOcean resources are managed through Terraform.
- **Cluster provisioning:** k0s installations are managed through k0sctl.
- **Fleet management:** KubeFleet handles member registration and cross-cluster resource placement.
- **Network isolation:** A dedicated VPC and Cloud Firewall control access between the lab and external networks.
- **Minimal infrastructure:** No load balancers, block storage volumes, snapshots, reserved IPs, or backup infrastructure are provisioned.

## References

- [KubeFleet Documentation](https://kubefleet.dev/)
- [KubeFleet GitHub Repository](https://github.com/kubefleet-dev/kubefleet)
- [k0s Documentation](https://docs.k0sproject.io/)
- [k0sctl GitHub Repository](https://github.com/k0sproject/k0sctl)
- [Terraform DigitalOcean Provider](https://registry.terraform.io/providers/digitalocean/digitalocean/latest/docs)
- [DigitalOcean Documentation](https://docs.digitalocean.com/)