# OpsFleet EKS Cluster with Karpenter

## Overview

This Terraform module sets up a Kubernetes EKS cluster using Karpenter for autoscaling, supporting both `x86_64` and `arm64` (Graviton) instance types on AWS.

## Features

- EKS cluster (v1.30)
- Dedicated VPC with 3 AZs
- Karpenter installed for autoscaling
- Supports x86 (t3.medium, m5.large) and ARM (t4g.medium, m6g.large)
- Spot instance configuration

## Prerequisites

- Terraform 1.4+
- `kubectl` configured
- AWS CLI authenticated with necessary permissions

## High-Level Architecture Diagram
+---------------------+
|      End Users      |
+---------+-----------+
          |
          v
+---------------------+
|    Route 53 / CDN   |
+---------+-----------+
          |
          v
+---------------------+
|      AWS WAF        |
+---------+-----------+
          |
          v
+---------------------+
|  Application Load   |
|     Balancer (ALB)  |
+---------+-----------+
          |
+---------------------+
|  Amazon EKS Cluster |  
+---------+-----------+
          |
  +-------+--------+
  |                |
  v                v
Frontend Pod   Backend Pod
 (React SPA)    (Flask API)
    |                |
    |                v
    |       +-----------------+
    |       | Amazon RDS (PG) |
    |       +-----------------+
    |                ^
    |                |
    v         +-------------+
Secrets ----> | Secrets      |
Manager       | Manager (IRSA)|
              +-------------+
    |
    v
+------------------------+
|  CI/CD (GitHub Actions)|
| - Build/Test/Deploy    |
| - Push to ECR          |
+------------------------+
          |
          v
+------------------------+
| Amazon ECR (Images)    |
+------------------------+
          |
          v
+------------------------+

## Usage

1. Clone the repo:
   ```bash
   git clone <repo-url>
   cd <repo>
   ```

2. Initialize and apply:
   ```bash
   terraform init
   terraform apply
   ```

3. After creation, update your kubeconfig:
   ```bash
   aws eks update-kubeconfig --region us-east-1 --name opsfleet-eks
   ```

## Deploying Pods to ARM or x86 Nodes

To run a pod on a specific architecture, set the `nodeSelector` or `nodeAffinity`.

### Example ARM Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: arm-test
spec:
  nodeSelector:
    kubernetes.io/arch: arm64
  containers:
    - name: nginx
      image: nginx
```

### Example x86 Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: x86-test
spec:
  nodeSelector:
    kubernetes.io/arch: amd64
  containers:
    - name: nginx
      image: nginx
```
