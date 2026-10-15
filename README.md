# University Learning Management Portal — DevOps Starter

This starter is designed for a local Windows lab using Git, GitHub, Docker Desktop, Jenkins, and Docker Desktop's Kubernetes cluster.

## Files

- `index.html` — sample university LMS page (HTML/CSS only)
- `healthz.html` — HTTP endpoint used by Kubernetes health probes
- `Dockerfile` — packages the website into an Nginx image
- `deployment.yaml` — 2-replica Kubernetes Deployment and NodePort Service
- `Jenkinsfile` — build, smoke test, publish, deploy, rollback, and verification pipeline

## Before the first Jenkins run

1. Change `IMAGE_REPO` in `Jenkinsfile` to `docker.io/YOUR_REAL_DOCKERHUB_USERNAME/university-lms`.
2. In Jenkins credentials create:
   - Username with password, ID `dockerhub-creds` (Docker Hub username + Docker Hub access token).
   - Secret file, ID `kubeconfig-file` (your Docker Desktop kubeconfig file, commonly `%USERPROFILE%\.kube\config`).
3. Ensure Jenkins can run `git`, `docker`, `kubectl`, and the Jenkins `powershell` Pipeline step on the same Windows machine.
4. Create a Jenkins Pipeline job configured as **Pipeline script from SCM**, use your GitHub repository URL and branch `*/main`, script path `Jenkinsfile`.
5. Configure **Poll SCM** as `H/1 * * * *` in the job, or use the repository-push webhook method if your Jenkins server has a public HTTPS endpoint. The Pipeline itself also contains `pollSCM`.
6. Enable Kubernetes in Docker Desktop and verify `kubectl get nodes` shows a Ready `docker-desktop` node.

## Local test

Open PowerShell in this folder and substitute your Docker Hub username:

```powershell
docker build -t YOUR_DOCKERHUB_USERNAME/university-lms:1 .
docker run -d --name university-lms-local -p 8081:80 YOUR_DOCKERHUB_USERNAME/university-lms:1
```

Visit `http://localhost:8081` and `http://localhost:8081/healthz.html`, then clean up:

```powershell
docker rm -f university-lms-local
```

## Demonstrate the rollback

First run a healthy pipeline and confirm `http://localhost:30080` works. Then add this deliberate fault to `Dockerfile`, immediately after the two `COPY` lines:

```dockerfile
RUN rm -f /usr/share/nginx/html/healthz.html
```

Commit and push the fault. The Docker image build and homepage smoke test still pass, and the bad image is pushed. Kubernetes readiness/liveness probes then fail because `/healthz.html` returns 404. The rollout times out; the Jenkinsfile runs `kubectl rollout undo`, verifies the previous revision, and checks the homepage. That faulty pipeline should be red/failed by design, even when rollback restores service, so the release failure remains visible. Remove the fault line and push again to return to a successful build.

**Lab note:** This setup is for a local educational environment. For production, use protected credentials, least-privilege Kubernetes access, HTTPS, image scanning, immutable release policies, and a properly secured webhook/agent setup.
