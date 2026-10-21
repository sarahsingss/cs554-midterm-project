# CS 554 Midterm: Deployment Project

This repository contains my Node.js deployment project and its submission documents. I built `cs554-midterm-app:1.0` in Ubuntu WSL, loaded it into an Ubuntu VirtualBox guest for Compose, and imported it into a separate k3d cluster in WSL.

## Submission documents

- [Technical report](MidtermProjectReport.pdf)
- [Evidence log](MidtermProjectEvidenceLog.pdf)
- [Recorded walkthrough](MidtermProjectVideo.mp4)

The report explains the deployment choices and OpenStack plan. The evidence PDF records the experiments, and the video demonstrates the working service and selector troubleshooting.

## Prepare the two environments

The Compose environment is an Ubuntu 24.04 guest named `CS554-Compose`. My VM has 1 vCPU, 2 GiB RAM, and a 16 GiB disk. To reproduce it, create an equivalent VirtualBox guest, install Docker Engine, Compose v2, curl, and OpenSSH Server, and enable SSH login. The commands below use account `ubuntu` and hostname `cs554-compose`; substitute your account if different.

Add two TCP forwarding rules to the VM's NAT adapter: Windows `127.0.0.1:2223` to guest port 22 for SSH, and Windows `127.0.0.1:18081` to guest port 8080 for HTTP.

The other environment is Ubuntu WSL with Docker Engine, Compose v2, k3d, kubectl, curl, and tar available. I used k3d v5.9.0 and a compatible kubectl client. Place the project at `~/cs454-midterm-project` in the WSL filesystem and make sure Docker is running. The Dockerfile supplies Node.js and wget inside the container.

**Where to run commands:** use WSL for the image build and Kubernetes, the VM's SSH session for Compose, and Windows PowerShell for the external VM request. The VirtualBox guest and WSL distribution are separate environments on the Windows computer.

## Package and load the application

First build the image from the project directory in **WSL**:

```bash
cd ~/cs454-midterm-project
docker compose build
```

Send the Compose file to the guest, then stream the image into its Docker daemon. Run these commands in **WSL**, using Windows OpenSSH to reach the NAT forward:

```bash
ssh.exe -p 2223 ubuntu@127.0.0.1 'mkdir -p ~/cs454-midterm-project'
tar -cf - compose.yaml | ssh.exe -p 2223 ubuntu@127.0.0.1 'tar -xf - -C ~/cs454-midterm-project'
docker save cs554-midterm-app:1.0 | ssh.exe -p 2223 ubuntu@127.0.0.1 docker load
```

If WSL cannot find `ssh.exe`, use its full path, `/mnt/c/Windows/System32/OpenSSH/ssh.exe`. Set up Windows SSH authentication first. The guest receives the image built above, so no second build is needed.

## Run and check the VM deployment

Open the guest session from **Windows PowerShell**:

```powershell
ssh -p 2223 ubuntu@127.0.0.1
```

In that **SSH session**, start the loaded image and inspect its responses and logs:

```bash
cd ~/cs454-midterm-project
docker compose up -d --no-build --wait
docker compose ps
curl -i -w '\n' http://127.0.0.1:8080/health
curl -i -w '\n' http://127.0.0.1:8080/
docker compose logs --no-color --tail=10 app
```

The root response identifies the service and container and includes a counter local to the application process. Requests to `/` increment it; health checks do not. Restarting the process resets it, and replicas maintain independent counts. The health endpoint reports HTTP 200 while ready. Container logs expose the application's startup and request messages.

From a **Windows PowerShell** session outside the guest, check the forwarded address:

```powershell
curl.exe -i http://127.0.0.1:18081/health
curl.exe -i http://127.0.0.1:18081/
```

These host requests pass through NAT from port 18081 to VM port 8080, then through Docker's published port to the application. `compose.yaml` supplies `PORT`, `SERVICE_NAME`, `MESSAGE`, and `NOT_READY_FILE`.

## Deploy the WSL cluster

Return to the project directory in **WSL** to create the single-node cluster and namespace:

```bash
export PATH="$HOME/.local/bin:$PATH"
k3d cluster create cs554-midterm --servers 1 --agents 0
kubectl config use-context k3d-cs554-midterm
kubectl create namespace cs554-midterm --dry-run=client -o yaml | kubectl apply -f -
```

If this cluster already exists but is stopped, resume it with `k3d cluster start cs554-midterm --wait` and skip the creation command.

Load `cs554-midterm-app:1.0` into the node's Kubernetes image store. In my setup, the k3d import helper reported a truncated archive, so I used this direct containerd import:

```bash
docker save cs554-midterm-app:1.0 | docker exec -i k3d-cs554-midterm-server-0 \
  ctr -a /run/k3s/containerd/containerd.sock -n k8s.io images import -
```

Create the Kubernetes resources and use the client Pod to request both endpoints through the Service:

```bash
kubectl -n cs554-midterm apply -f kubernetes/
kubectl -n cs554-midterm rollout status deployment/cs554-midterm --timeout=180s
kubectl -n cs554-midterm wait --for=condition=Ready pod/midterm-client --timeout=60s
kubectl -n cs554-midterm get deployment,pods,service
kubectl -n cs554-midterm exec midterm-client -- wget -q -S -T 3 -t 1 -O - http://cs554-midterm/health
kubectl -n cs554-midterm exec midterm-client -- wget -q -S -T 3 -t 1 -O - http://cs554-midterm/
```

The Deployment should show `2/2` Ready, and both HTTP requests should succeed. Service port 80 targets application port 8080 on Pods labeled `app=cs554-midterm`. `midterm-client` is only the request generator; it is separate from the two application replicas. Reapply its manifest and wait for Ready if that standalone Pod has been deleted.

My CS 554 configuration requests 100m CPU and 64Mi memory per application container, limits them to 500m CPU and 128Mi memory, and checks `/health` with wget for readiness. A marker at `/tmp/midterm-not-ready` makes one Pod's health response return 503 without stopping its process. Removing the marker restores readiness. The report and evidence PDF explain these settings and document readiness, Pod replacement, and selector failure and recovery.

## Remove or stop the deployments

To remove the Compose service and its network, run inside the **VM**:

```bash
cd ~/cs454-midterm-project
docker compose down
sudo poweroff
```

To remove the namespace and local cluster, run in **WSL**:

```bash
kubectl delete namespace cs554-midterm
k3d cluster delete cs554-midterm
```

To keep the deployments for later, use `sudo poweroff` in the VM and `wsl --terminate Ubuntu-24.04` in Windows PowerShell instead of the removal commands. Closing the terminal windows alone leaves background workloads running. VM disks, container archives, dependency folders, and credentials are not submission files.

## Sources

I adapted the [course Node.js starter](https://github.com/UAH-Computer-Science/cs454-Course-Exercises/tree/main/cs454-midterm-starter), used my Python Project 1 as a packaging reference, and followed the [Exercise 04 Kubernetes example](https://github.com/UAH-Computer-Science/cs454-Course-Exercises/tree/main/exercise-04-local-kubernetes) for the manifests. OpenStack citations are included in the technical report.
