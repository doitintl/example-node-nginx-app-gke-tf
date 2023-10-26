# Running Node/NGINX app on GKE
This repository includes examples to bootstrap a Google Cloud environment (project), leverage Terraform (TF) infrastructure as code (IaC) to provision GCP resources, and a test app to illustrate containerizing a NodeJS-powered app fronted by NGINX, all running on Google Kubernetes Engine (GKE).

## Components included
- `app` (test nodejs app accessing Secret Manager secrets)
  - rough example to interact with Secret Manager, and `Dockerfile` with multi-stage build to optimize image
- `app-k8s-config` (K8S manifest files to run app on GKE)
  - configuring `namespace` for Pod Security Admission to enforce on cluster
    - [Documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/podsecurityadmission)
    - [Alternatives](https://cloud.google.com/kubernetes-engine/docs/how-to/podsecurityadmission#alternatives)
  - configuring `namespace` and `service account` for Workload Identity to auth pod to access secrets
    - [Documentation](https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity)
    - [Usage](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
  - configuring `deployment` with multiple containers in one pod, with security and env var settings
    - [Security Context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
    - [Service Accounts](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)
  - configuring `service` to expose app
  - configuring `gateway` to expose and load balance service (internal only)
    - [Documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/secure-gateway)
- `app-proxy` (nginx proxy example in front of node app)
  - example building unprivileged NGINX proxy bundled with custom config
- `cloud-config` (TF files to provision cloud infra)
  - TF example to provision Artifact Registry 
    - custom module provisioning Artifact Registry
    - (ideally deployed in separate, shared project)
    - (optional) example of Project Factory module
  - TF example of `dev` env provisioning:
    - custom module provisioning a list of Secret Manager secrets
    - secure GKE cluster leveraging Google "safer-cluster" module
      - [Documentation](https://registry.terraform.io/modules/terraform-google-modules/kubernetes-engine/google/latest/submodules/safer-cluster)
      - offers support for Shared VPC networking
    - secure bastion host leveraging Google "bastion" module
      - [Documentation](https://registry.terraform.io/modules/terraform-google-modules/bastion-host/google/latest)
    - Cloud Nat example if apps need to reach public Internet (cluster is private)
      - [Documentation](https://github.com/terraform-google-modules/terraform-google-cloud-nat)
    - (optional) example of Project Factory module
      - [Documentation](https://registry.terraform.io/modules/terraform-google-modules/project-factory/google/latest)
- `setup.sh` (test commands to bootstrap infra, and test above)
  - sets up local shell (in my case Apple Silicon Mac) and env vars
  - illustrates authenticating to run TF commands without long-lived key using short-lived tokens
  - illustrates authenticating local env to test Google SDK for node app
  - provisions Cloud Storage bucket for shared TF state
  - configures IAM policies for app service account to test app
  - builds and deploys `Dockerfile` for app/proxy, pushing to Artifact Registry
  - test `gcloud` commands to run app in Cloud Run, etc.
  - commands to generate self-signed certificate for testing ILB in GKE Gateway
  - create Cloud Nat for bastion to interact with metadata server
    - see also Private Access

# Usage
These steps are illustrated within the `setup.sh` file, in addition to Google Cloud APIs that were enabled first and common env vars instantiated.

```bash
PROJECT_ID=$(gcloud config get-value project)
PROJECT_USER=$(gcloud config get-value core/account) # set current user
GCP_REGION="us-central1" # CHANGEME (OPT)
GCP_ZONE="us-central1-a" # CHANGEME (OPT)
NETWORK_NAME="safer-cluster-network-dev"  # from TF code

# enable apis
gcloud services enable compute.googleapis.com \
    oslogin.googleapis.com \
    container.googleapis.com \
    containersecurity.googleapis.com \
    secretmanager.googleapis.com \
    artifactregistry.googleapis.com \
    cloudbuild.googleapis.com \
    storage.googleapis.com \
    run.googleapis.com \
    iap.googleapis.com

# configure gcloud sdk
gcloud config set compute/region $GCP_REGION
gcloud config set compute/zone $GCP_ZONE
```

## Bootstrapping state store bucket
This example bootstraps the Google Cloud Project in a local terminal environment (assume project created), and then leverages GCloud SDK (`gcloud`) commands to first create a Cloud Storage Bucket for saving Terraform state.

```bash
# create bucket for shared state
BUCKET_NAME="$PROJECT_ID-tfstate"

gcloud storage buckets create gs://$BUCKET_NAME
```

## Configuring Terraform
There are some configurable variables in the environment directories and you'll either edit the `locals` in the `main.tf` file, or `terraform.tfvars` file (not saved in repo) to customize to your needs. Examples of the settings are below:

### 01_shared/
```
project_id    = "mike-test-cmdb-gke"
region        = "us-central1"
repository_id = "mike-test-repo"
```

### dev/
```
project_id          = "mike-test-cmdb-gke"
registry_project_id = "mike-test-cmdb-gke" # suggest using shared project instead
region              = "us-central1"
zone                = "us-central1-c"
secret_ids          = ["foo", "bar", ]
master_auth_cidrs   = "10.60.0.0/17" # some bastion
bastion_users       = ["user:mike.sparr@doit.com", "user:mike.sparr@doit-intl.com"]
```

## Authenticating Terraform (TF) with short-lived tokens
Assuming the logged-in user in the terminal has IAM role permissions to execute the TF commands against the project, we first add a shell environment variable (instead of downloading service account keys). We use [short-lived credentials](https://cloud.google.com/iam/docs/create-short-lived-credentials-direct) instead of long-lived service account keys that could be compromised, so they will need to be refreshed after 1 hour if you need to run TF commands throughout the day.

```bash
# (optional) set tf env for Apple silicon env
TFENV_ARCH=amd64
TFENV_CONFIG_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/tfenv/${TFENV_ARCH}

# authenticate current user with short-lived token for tf
GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token)

# (example) cd to desired environment and run TF
BASE_DIR=$(pwd)
cd $BASE_DIR/cloud-config/environments/01_shared
terraform init
terraform plan
terraform apply
cd $BASE_DIR # to return
```

## Creating Secrets
Google Cloud Secret Manager secrets created by the TF module create the keys, but the actual stored values (a.k.a. `versions`) should be created by your team either in the console or command line. For security purposes it's not recommended to explicitly declare them in TF code, or persist in source repos.

- [Add a secret version](https://cloud.google.com/secret-manager/docs/add-secret-version)

## Pushing Demo Apps To Artifact Registry
Your CI server will be building and pushing your app images to the registry, but these are commands to test locally (or used in CI scripts).

```bash
############################################################
# push test images to the repo 
# *** assuming repo created by TF in cloud-config/environments/01_shared ***
############################################################
BASE_DIR=$(pwd)  # like above as well
REPO_NAME="mike-test-repo"
IMAGE1_NAME="app"
TAG1_NAME="v1"
IMAGE1_URL=${GCP_REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE1_NAME}:${TAG1_NAME}
# optional (or use public image in manifest)
IMAGE2_NAME="proxy"
TAG2_NAME="v1"
IMAGE2_URL=${GCP_REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE2_NAME}:${TAG2_NAME}

# configure auth
gcloud auth configure-docker ${GCP_REGION}-docker.pkg.dev

# run this in app dir
cd $BASE_DIR/app
gcloud builds submit --tag $IMAGE1_URL

# (optional) run this in app-proxy dir
cd $BASE_DIR/app-proxy
gcloud builds submit --tag $IMAGE2_URL

cd $BASE_DIR
```

## Generate Self-Signed Certificate
You may already have certificate `key` and `crt` files, but here are steps to create them for testing, and saving both as a self-managed certificate or as K8S secret for later usage in your GKE Gateway or Ingress (internal).

```bash
############################################################
# TLS self-signed test for Gateway
############################################################
export PRIVATE_KEY_FILE="app.key"
export CSR_CONFIG_FILE="app-csr.conf"
export CSR_FILE="app.csr"
export CERTIFICATE_FILE="app.crt"
export CERTIFICATE_TERM="730" # 2 yrs
export CERTIFICATE_NAME="app-internal-cert"

openssl genrsa -out $PRIVATE_KEY_FILE 2048
openssl ecparam -name prime256v1 -genkey -noout -out $PRIVATE_KEY_FILE

# create CSR config
cat <<EOF > $CSR_CONFIG_FILE
[req]
default_bits              = 2048
req_extensions            = extension_requirements
distinguished_name        = dn_requirements
prompt                    = no

[extension_requirements]
basicConstraints          = CA:FALSE
keyUsage                  = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName            = @sans_list

[dn_requirements]
countryName               = US
stateOrProvinceName       = MT
localityName              = Missoula
0.organizationName        = Your Company
organizationalUnitName    = engineering
commonName                = app.example.com
emailAddress              = you@example.com

[sans_list]
DNS.1                     = app.example.com

EOF

# create CSR
openssl req -new -key $PRIVATE_KEY_FILE \
    -out $CSR_FILE \
    -config $CSR_CONFIG_FILE

# create certificate
openssl x509 -req \
    -signkey $PRIVATE_KEY_FILE \
    -in $CSR_FILE \
    -out $CERTIFICATE_FILE \
    -extfile $CSR_CONFIG_FILE \
    -extensions extension_requirements \
    -days $CERTIFICATE_TERM

# create regional SSL cert
gcloud compute ssl-certificates create $CERTIFICATE_NAME \
    --certificate=$CERTIFICATE_FILE \
    --private-key=$PRIVATE_KEY_FILE \
    --region=$GCP_REGION

# verify
gcloud compute ssl-certificates describe $CERTIFICATE_NAME \
    --region=$GCP_REGION
```

## Applying Kubernetes (K8S) Manifests To Cluster / Testing
Given this example creates a private-only Google Kubernetes Engine (GKE) cluster, with private control plane, the only way to run `kubectl` commands would be from Google's private network. This example illustrates deploying a bastion host (with no external IP), and using Identity Aware Proxy to log into the instance and apply the manifests.

```bash
# access bastion and apply k8s configs
BASTION_NAME="bastion-vm"        # named in TF
BASTION_ZONE="us-central1-c"     # named in TF
K8S_CONFIG_DIR="app-k8s-config"

# remotely copy k8s manifests to Linux VM
gcloud compute scp --recurse $(pwd)/$K8S_CONFIG_DIR $BASTION_NAME:$K8S_CONFIG_DIR

# remotely copy certificate files to Linux VM
gcloud compute scp $PRIVATE_KEY_FILE $BASTION_NAME:/
gcloud compute scp $CERTIFICATE_FILE $BASTION_NAME:/

# log into bastion using gcloud sdk
gcloud compute ssh $BASTION_NAME --zone $BASTION_ZONE

# FROM BASTION, run kubectl commands
# - note: you may need to recreate some env vars in that shell)
# - note: you may need to install kubectl and tools with package manager (requires Cloud Nat)

# FROM BASTION, create kubernetes TLS secret (when cluster avail)
kubectl create secret tls app-example-com \
    --namespace=$KNS \
    --cert=$CERTIFICATE_FILE \
    --key=$PRIVATE_KEY_FILE

# FROM BASTION, apply k8s manifests
kubectl apply -f $K8S_CONFIG_DIR

# FROM BASTION, test gateway internal IP and TLS works with curl
curl -k https://app.example.com --resolve 'app.example.com:443:10.0.0.9' # where 10.0.0.9 is Gateway IP
```

# CI/CD App Deployment Options
Your CI server should have access to Artifact Registry repo to push versioned images (with tag) per build. You will then need to update your K8S manifests stored in a separate source repo, updating the image version tag in your `Deployment` manifest and applying to the cluster.

Separate repos for your cloud config, app code, and app k8s config are suggested:
- org/my-app (source code and `Dockerfile` for app)
- org/my-app-config (kubernetes manifests for app)
- org/cloud-config (terraform source)

1. Your CI server would check out or clone the app repo, run tests, build, and push image to registry.
2. Your CI server would edit the K8S `deployment.yaml` file image version in your app-config repo and push to branch.
3. Your CD (or CI) would recognize changed app-config, and apply the updated manifest(s) to cluster.

## VPN Tunnel
With a Cloud VPN tunnel connecting your CI server network to the Google Cloud VPC Network, it solves the transitive networking issue from peering the managed GKE control plane to the nodes. Add your CI server CIDR range to the `cloud-config/environments/dev/network.tf` for "master_auth_network" config to authorize it to perform `kubectl commands`.

## Cloud Build
Google Cloud's managed [Cloud Build](https://cloud.google.com/build/docs/overview) could monitor registry changes and handle deployments.

## Net Proxy
Dedicating a bastion host within GCP's network, you can install a proxy server and run `kubectl` commands against this host. The [documentation](https://cloud.google.com/kubernetes-engine/docs/archive/creating-kubernetes-engine-private-clusters-with-net-proxies) is dated and other approaches are recommended.

## Pull-based using Argo CD (or Anthos Config Management)
You could authenticate apps running on your cluster to monitor your k8s config source repo, and upon changes they will clone and apply manifest files against your cluster.

- [Argo CD](https://argo-cd.readthedocs.io/en/stable/) is very popular and GCP may soon offer a managed version
- [ACM](https://cloud.google.com/anthos-config-management/docs/concepts/config-controller-overview) is a paid alternative
