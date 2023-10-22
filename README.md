# Running Node/NGINX app on GKE
This repository includes examples to bootstrap a Google Cloud environment (project), leverage Terraform (TF) infrastructure as code (IaC) to provision GCP resources, and a test app to illustrate containerizing a NodeJS-powered app fronted by NGINX, all running on Google Kubernetes Engine (GKE).

## Components included
- `app` (test nodejs app accessing Secret Manager secrets)
  - rough example to interact with Secret Manager, and `Dockerfile` with multi-stage build to optimize image
- `app-k8s-config` (K8S manifest files to run app on GKE)
  - configuring `namespace` for Pod Security Admission to enforce on cluster
  - configuring `namespace` and `service account` for Workload Identity to auth pod to access secrets
  - configuring `deployment` with multiple containers in one pod, with security and env var settings
  - configuring `service` to expose app
  - configuring `gateway` to expose and load balance service (internal only)
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

# TODO: more to come ...
