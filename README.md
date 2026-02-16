# CrossV9 Kubernetes Deployment (Helm)

This repo currently runs best via `dockerDeploy/` for local development. This folder adds a **Helm-first** path so you can:

- **Test locally** on `kind`/`k3d`
- Later promote to **EKS** with an AWS Load Balancer and **managed Postgres (RDS)**

## Quick start (local)

Prereqs:
- `kubectl`
- `helm`
- a local cluster (`kind` or `k3d`)

1. Build/push images somewhere your cluster can pull, or load them into `kind`.
2. Install:

```bash
helm upgrade --install crossv9 ./helm/crossv9 -n crossv9 --create-namespace -f ./helm/crossv9/values-local.yaml
```

3. Port-forward the web UI:

```bash
kubectl -n crossv9 port-forward svc/crossv9-webinterface 5020:80
```

Open `http://localhost:5020`.

## K3 deploy with GHCR + MinIO + external Postgres

Use `helm/crossv9/values-k3-benchmark.yaml`.

1. Push images to GHCR
   - Workflow: `.github/workflows/build-push-ghcr.yml`
   - Images produced:
     - `ghcr.io/<owner>/crossv9-agent`
     - `ghcr.io/<owner>/crossv9-gateway`
     - `ghcr.io/<owner>/crossv9-cross`
     - `ghcr.io/<owner>/crossv9-webinterface`

2. Create pull secret in cluster:

```bash
kubectl create namespace crossv9 --dry-run=client -o yaml | kubectl apply -f -
kubectl -n crossv9 create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io \
  --docker-username=<github-username> \
  --docker-password=<github-personal-access-token> \
  --docker-email=<email>
```

3. Edit values:
   - `images.*.repository` => your GHCR images
   - `externalPostgres.*` => your in-cluster Postgres connection
   - `agent.s3.*` => MinIO endpoint and bucket credentials

4. Install/upgrade:

```bash
helm upgrade --install crossv9 ./helm/crossv9 \
  -n crossv9 \
  -f ./helm/crossv9/values-k3-benchmark.yaml
```

5. Verify:

```bash
kubectl -n crossv9 get pods -o wide
kubectl -n crossv9 get svc
kubectl -n crossv9 logs deploy/crossv9-cross -f
```

Notes:
- `agent.workloadKind: DaemonSet` schedules one agent per node for benchmark locality.
- `mode.crossMode: local` keeps routing stable while benchmarking.
- If your MinIO uses TLS, set `agent.s3.useSsl: true`.

## EKS notes (later)

- Use `helm/crossv9/values-eks.yaml` as a starting point.
- Recommended:
  - **RDS Postgres** (disable the in-cluster Postgres in values)
  - **AWS Load Balancer Controller** (Ingress) or `Service type=LoadBalancer` for the web UI


