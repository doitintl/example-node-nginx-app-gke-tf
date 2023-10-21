#!/usr/bin/env bash

#####################################################################
# REFERENCES
# - https://cloud.google.com/docs/terraform/best-practices-for-terraform 
# - https://registry.terraform.io/modules/terraform-google-modules/kubernetes-engine/google/latest/submodules/safer-cluster
# - https://cloud.google.com/kubernetes-engine/docs/how-to/hardening-your-cluster#restrict_self_modify 
# - https://ashwin9798.medium.com/nginx-with-docker-and-node-js-a-beginners-guide-434fe1216b6b
# - https://docs.docker.com/develop/develop-images/dockerfile_best-practices/
# - https://webbylab.com/blog/minimal_size_docker_image_for_your_nodejs_app/
# - https://github.com/nodejs/docker-node/blob/main/docs/BestPractices.md
# - https://cloud.google.com/nodejs/docs/reference/secret-manager/latest 
# - https://cloud.google.com/secret-manager/docs/manage-access-to-secrets#secretmanager-create-secret-gcloud 
# - https://cloud.google.com/run/docs/securing/service-identity 
# - https://aandhsolutions.com/blog/run-nginx-as-unprivileged-user-in-docker-container-on-kubernetes/
# - https://forums.docker.com/t/running-nginx-official-image-as-non-root/135759 
# - https://kubernetes.io/blog/2021/11/09/non-root-containers-and-devices/
# - https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-security
# - https://cloud.google.com/kubernetes-engine/docs/how-to/secure-gateway#secure-using-secret
#####################################################################

export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_USER=$(gcloud config get-value core/account) # set current user
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
export IDNS=${PROJECT_ID}.svc.id.goog # workflow identity domain

export GCP_REGION="us-central1" # CHANGEME (OPT)
export GCP_ZONE="us-central1-a" # CHANGEME (OPT)
export NETWORK_NAME="default"

# enable apis
gcloud services enable compute.googleapis.com \
    container.googleapis.com \
    containersecurity.googleapis.com \
    secretmanager.googleapis.com \
    artifactregistry.googleapis.com \
    cloudbuild.googleapis.com \
    storage.googleapis.com \
    run.googleapis.com

# configure gcloud sdk
gcloud config set compute/region $GCP_REGION
gcloud config set compute/zone $GCP_ZONE


############################################################
# initialize project for Terraform
# using short-lived token (1hr) instead of permanent key
############################################################
# create bucket for shared state
export BUCKET_NAME="$PROJECT_ID-tfstate"

gcloud storage buckets create gs://$BUCKET_NAME

# set tf env for Apple silicon env
export TFENV_ARCH=amd64
export TFENV_CONFIG_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/tfenv/${TFENV_ARCH}

# authenticate current user with short-lived token for tf
export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token)

# authenticate current user for local SDK testing
gcloud auth application-default login


############################################################
# create secret versions in secret manager
# *** assuming secret created by TF in cloud-config/environments/dev ***
############################################################
export SECRET_ID="foo"
export SECRET_VALUE="Super_Secret" # just for demo but would never do this
export VERSION_ID="latest"

# add secret version
echo -n $SECRET_VALUE | \
    gcloud secrets versions add $SECRET_ID --data-file=-
  
# verify
gcloud secrets versions access $VERSION_ID --secret=$SECRET_ID


############################################################
# create service account for test app and grant secret access
# *** assuming secret created by TF in cloud-config/environments/dev ***
############################################################
export SA_NAME="app-sa"
export SA_EMAIL="$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"

# create service account
gcloud iam service-accounts create $SA_NAME \
    --description="$SA_NAME" \
    --display-name="$DISPLAY_NAME"

# grant myself user role
gcloud iam service-accounts add-iam-policy-binding $SA_EMAIL \
    --member="user:$PROJECT_USER" \
    --role="roles/iam.serviceAccountUser"
gcloud secrets add-iam-policy-binding $SECRET_ID \
    --member="user:$PROJECT_USER" \
    --role="roles/secretmanager.secretAccessor"

# grant service account secret accessor
gcloud secrets add-iam-policy-binding $SECRET_ID \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/secretmanager.secretAccessor"


############################################################
# push test images to the repo 
# *** assuming repo created by TF in cloud-config/environments/01_shared ***
############################################################
export REPO_NAME="mike-test-repo"
export IMAGE1_NAME="app"
export TAG1_NAME="v1"
export IMAGE1_URL=${GCP_REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE1_NAME}:${TAG1_NAME}
# optional (or use public image in manifest)
export IMAGE2_NAME="proxy"
export TAG2_NAME="v1"
export IMAGE2_URL=${GCP_REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE2_NAME}:${TAG2_NAME}
export PROJECT_DIR=$(pwd)

# configure auth
gcloud auth configure-docker ${GCP_REGION}-docker.pkg.dev

# run this in app dir
cd $PROJECT_DIR/app
gcloud builds submit --tag $IMAGE1_URL

# (optional) run this in app-proxy dir
cd $PROJECT_DIR/app-proxy
gcloud builds submit --tag $IMAGE2_URL

cd $PROJECT_DIR


############################################################
# Test app runs and accesses secret manager in temp Cloud Run service
# - note: PORT env var automatically set with Cloud Run
############################################################
export SERVICE_NAME="app-test"
export SERVICE_PORT="3000" # override default 8080 for this nodejs app test

gcloud run deploy $SERVICE_NAME \
    --platform managed \
    --region $GCP_REGION \
    --service-account $SA_EMAIL \
    --allow-unauthenticated \
    --image $IMAGE1_URL \
    --port $SERVICE_PORT \
    --set-env-vars "PROJECT_ID=$PROJECT_ID" \
    --set-env-vars "SECRET_ID=$SECRET_ID" \
    --set-env-vars "SECRET_VERSION_ID=$SECRET_VERSION_ID"

# confirm service is running
gcloud run services list \
    --platform managed \
    --region $GCP_REGION

# get service url and test
export SVC_URL=$(gcloud run services describe $SERVICE_NAME --platform managed --region $GCP_REGION --format="value(status.url)")
curl -X GET $SVC_URL


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
0.organizationName        = DoiT International
organizationalUnitName    = engineering
commonName                = app.example.com
emailAddress              = mike.sparr@doit.com

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
  
# create kubernetes TLS secret (when cluster avail)
kubectl create secret tls app-example-com \
    --cert=$CERTIFICATE_FILE \
    --key=$PRIVATE_KEY_FILE



##########################################################
# K8S / GKE cluster resources
# *** assuming cluster created by TF in cloud-config/environments/dev ***
##########################################################
# apply pod-level security policies
# - https://cloud.google.com/kubernetes-engine/docs/how-to/podsecurityadmission
# - https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/#applying-to-all-namespaces
# another option
# - https://cloud.google.com/kubernetes-engine/docs/how-to/podsecurityadmission#alternatives

# assume secrets created [foo, bar, buzz, baz] from TF so assign values
# recommend using workload identity and accessing from your code (best practice)
# - https://cloud.google.com/kubernetes-engine/docs/tutorials/workload-identity-secrets
# other options
# - https://cloud.google.com/kubernetes-engine/docs/how-to/encrypting-secrets
# - https://github.com/GoogleCloudPlatform/secrets-store-csi-driver-provider-gcp 
# - https://cloud.google.com/secret-manager/docs/access-secret-version
