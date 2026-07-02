# MandiGo GitOps & Infrastructure Repository

Welcome to the **MandiGo GitOps** repository! This repository acts as the single source of truth for the MandiGo B2B marketplace's production infrastructure, cloud provisioning, and Kubernetes deployment state.

It follows strict **GitOps and Infrastructure-as-Code (IaC)** methodologies. All AWS infrastructure, Kubernetes configurations, and application deployments are declared here as code. Any changes pushed to this repository are automatically synchronized to the production environments.

## 🏗 Enterprise Architecture Overview

The MandiGo production environment is a highly scalable, automated cloud ecosystem utilizing AWS, Kubernetes, and modern CI/CD practices.

```mermaid
graph TD
    subgraph "CI/CD & Source Control"
        GitHubApp((MandiGo App Repo))
        GitHubGitOps((MandiGo GitOps Repo))
        GHActions[GitHub Actions CI/CD]
        
        GitHubApp -->|Trigger Build| GHActions
        GHActions -->|Push Images| ECR[AWS ECR]
        GHActions -->|Update Manifests| GitHubGitOps
    end

    subgraph "AWS Cloud Infrastructure (Provisioned via Terraform)"
        ECR
        Lambda[AWS Lambda - Serverless Tasks]
        
        subgraph "EC2 Instance (K3s Kubernetes Cluster)"
            Traefik[Traefik Ingress Controller]
            
            subgraph "Namespace: argocd"
                ArgoCD[ArgoCD Controller]
            end
            
            subgraph "Namespace: default"
                Frontend[MandiGo Frontend Pods]
                Backend[MandiGo Backend API Pods]
            end
            
            subgraph "Namespace: database"
                DB[(PostgreSQL Pod)]
                PVC[EBS Persistent Volume]
            end
            
            subgraph "Namespace: monitoring"
                Prometheus[Prometheus]
                Grafana[Grafana Dashboards]
            end
            
            Traefik -->|projectbyradhe.xyz| Frontend
            Traefik -->|api.projectbyradhe.xyz| Backend
            Backend --> DB
            DB --> PVC
            
            ArgoCD -.->|Watches & Syncs| Frontend
            ArgoCD -.->|Watches & Syncs| Backend
            ArgoCD -.->|Watches & Syncs| DB
            ArgoCD -.->|Watches & Syncs| Traefik
            ArgoCD -.->|Watches & Syncs| Prometheus
        end
    end
    
    GitHubGitOps -.->|ArgoCD Pulls State| ArgoCD
    User((Users)) -->|HTTPS| Traefik
```

## 🗂 Complete Repository Directory Structure

This repository is structured to separate cloud provisioning (Terraform) from Kubernetes workload configurations (K8s).

```text
mandigo-gitops/
├── .github/                  
│   └── workflows/            # GitHub Actions for GitOps linting & Terraform plans
│
├── terraform/                # Infrastructure as Code (IaC)
│   ├── main.tf               # Core AWS resources (VPC, EC2, ECR, IAM, Security Groups)
│   ├── lambda/               # Future AWS Lambda serverless functions (e.g., image processing)
│   ├── variables.tf          # Terraform variable definitions
│   └── outputs.tf            # Output variables (e.g., EC2 public IP)
│
├── k8s/                      # Kubernetes Manifests (Managed by ArgoCD)
│   ├── frontend/             # Namespace: default
│   │   ├── deployment.yaml   # React SPA deployment (auto-updated by CI)
│   │   └── service.yaml      # Internal K8s service
│   │
│   ├── backend/              # Namespace: default
│   │   ├── deployment.yaml   # Hono Node.js API deployment (auto-updated by CI)
│   │   └── service.yaml      # Internal K8s service
│   │
│   ├── database/             # Namespace: database
│   │   ├── postgres.yaml     # Postgres Stateful Deployment + PVC + Service
│   │   └── init-db.sql       # Optional database initialization scripts
│   │
│   ├── argocd/               # Namespace: argocd
│   │   ├── application.yaml  # Core ArgoCD app definition pointing to this repo
│   │   └── ingress.yaml      # Exposes ArgoCD UI (argocd.projectbyradhe.xyz)
│   │
│   └── monitoring/           # Namespace: monitoring (Future/Planned)
│       ├── prometheus.yaml   # Metrics scraping & aggregation
│       └── grafana.yaml      # Metrics visualization dashboards
│
└── docs/                     # Additional architectural & runbook documentation
```

## 🔄 The CI/CD & Deployment Flow

This project utilizes a fully automated, zero-touch deployment flow connecting the application repo (`mandigo-app`) to this infrastructure repo (`mandigo-gitops`):

1.  **Code Commit**: A developer pushes code to the `main` branch of `mandigo-app`.
2.  **Continuous Integration (GitHub Actions)**: Actions in `mandigo-app` run tests, build the Docker images (Frontend and/or Backend), tag them with the Git commit SHA, and push them securely to **AWS ECR**.
3.  **GitOps Manifest Update**: The GitHub Action automatically commits the new image tags directly into the `k8s/frontend/deployment.yaml` or `k8s/backend/deployment.yaml` files within *this* `mandigo-gitops` repository.
4.  **Continuous Deployment (ArgoCD)**: **ArgoCD**, running continuously inside the EC2 K3s cluster, detects the changes in this repository. It automatically pulls the new manifests and instructs Kubernetes to perform a rolling update of the pods with zero downtime.

## 🛠 Cloud Provisioning (Terraform)

The `terraform/` directory contains the blueprint for the AWS environment.
*   It provisions the EC2 instance running K3s.
*   It sets up the Elastic Container Registry (ECR) repositories.
*   It configures IAM roles allowing the EC2 instance to pull images from ECR without manual secrets.
*   *Future:* It will provision AWS Lambda functions in `terraform/lambda/` for offloading heavy tasks like batch notifications or image resizing.

## 🔐 Secrets Management

For strict enterprise security, plaintext passwords and secrets **are intentionally excluded from this repository**. 

When deploying a fresh cluster, you must manually create the necessary Kubernetes secrets before ArgoCD can successfully start the application pods.

### Required Secrets

You must SSH into the EC2 instance and create the following secrets:

**1. Database Credentials (for Backend)**
The backend pod requires the connection string to talk to Postgres.
```bash
kubectl create secret generic mandigo-db-credentials \
  --namespace=default \
  --from-literal=DATABASE_URL="postgresql://mandigo_admin:YOUR_PASSWORD@mandigo-db-service.database.svc.cluster.local:5432/mandigo_marketplace"
```

**2. Database Credentials (for Postgres)**
The Postgres pod requires the raw credentials to initialize the database.
```bash
kubectl create secret generic mandigo-db-credentials \
  --namespace=database \
  --from-literal=POSTGRES_USER="mandigo_admin" \
  --from-literal=POSTGRES_PASSWORD="YOUR_PASSWORD" \
  --from-literal=POSTGRES_DB="mandigo_marketplace"
```

## 🛑 Troubleshooting & Runbook

### 1. Pods stuck in `ImagePullBackOff`
If ArgoCD updates the deployment but the pods fail to start with an `ErrImagePull` or `ImagePullBackOff` error, K3s cannot pull the image from AWS ECR. 
*   **Resolution**: Verify that your EC2 IAM Role has ECR read permissions (managed via Terraform). Check if the `ecr-sync.sh` script (if applicable) is running successfully to cache the images locally.

### 2. Pods stuck in `CreateContainerConfigError`
If a pod fails to start with this error, it is missing a required Secret or ConfigMap.
*   **Resolution**: Verify that you have manually created the `mandigo-db-credentials` secrets as described in the "Secrets Management" section. Run `kubectl get secrets -n <namespace>` to confirm.

### 3. ArgoCD is not updating the cluster
If the image tags in this repository have changed but the live cluster is still running older pods (verify with `kubectl get pods -n default`), ArgoCD might have Auto-Sync disabled or be stuck.
*   **Resolution**: Log into the ArgoCD Web UI (`argocd.projectbyradhe.xyz`) and click **Sync**, or enable Auto-Sync in the application settings. Alternatively, you can force a manual update directly via `kubectl apply -f k8s/backend/deployment.yaml`.
