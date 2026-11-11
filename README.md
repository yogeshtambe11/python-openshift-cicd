# Python CI/CD with OpenShift Pipelines and OpenShift GitOps

This is a production-style learning project for OpenShift 4.18 / Kubernetes 1.31.
It uses one application namespace: python-cicd

- Tekton builds and tests the Python application.
- Buildah builds and pushes an image to the OpenShift internal registry.
- Tekton updates `gitops/deployment.yaml` with the immutable Git commit SHA and pushes that change to GitHub.
- Argo CD watches `gitops/` and deploys the application.

> Learning-lab security note: the included Buildah Task requests a privileged container for broad compatibility with OpenShift lab clusters. Do not copy that privilege model unchanged into a production cluster. For production, use a tested rootless Buildah configuration and a narrowly scoped SCC, or your organization's approved remote build service. Use short-lived credentials and rotate them.

## Repository layout

.
├── app/
│   ├── __init__.py
│   ├── app.py
│   └── requirements.txt
├── tests/
│   └── test_app.py
├── pipelines/
│   ├── tasks/
│   │   ├── clone-source.yaml
│   │   ├── python-test.yaml
│   │   ├── buildah-push.yaml
│   │   └── update-gitops.yaml
│   ├── pipeline.yaml
│   └── pipeline-run.yaml
├── gitops/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── route.yaml
│   └── kustomization.yaml
└── argocd/
    └── application.yaml

## 1. Prepare the local repository

Clone your repository, copy these files into it, then commit and push:

git clone https://github.com/yogeshtambe11/python-openshift-cicd.git
cd python-openshift-cicd

# Copy the contents of this project into this directory.
# Keep any existing files you still need.

git add .
git commit -m "Add Tekton and Argo CD CI/CD project"
git push origin main


If the repository already contains files with the same names, review before overwriting them.

## 2. Create the OpenShift application namespace

oc new-project python-cicd

If it already exists:

oc project python-cicd


Verify the operators and API resources:

oc get pods -n openshift-pipelines
oc get pods -n openshift-gitops
oc api-resources | grep -E '(^| )pipelines|^tasks|^pipelineruns'
oc get storageclass


The PipelineRun uses a 1 GiB PVC for the shared source workspace. Your cluster needs a default StorageClass. If it does not have one, edit `pipelines/pipeline-run.yaml` and add the appropriate `storageClassName` under `volumeClaimTemplate.spec`.

## 3. Create the pipeline service account and permissions

Create a dedicated service account and grant it permission to push images into this project:

oc create serviceaccount cicd-pipeline -n python-cicd

oc policy add-role-to-user system:image-builder \
  system:serviceaccount:python-cicd:cicd-pipeline \
  -n python-cicd


The Buildah task in this lab uses `privileged: true`. Grant the required SCC only if your cluster policy permits this lab configuration:

oc adm policy add-scc-to-user privileged \
  system:serviceaccount:python-cicd:cicd-pipeline \
  -n python-cicd

This is intentionally a lab shortcut with elevated permissions. If your organization disallows this, do not weaken cluster security; replace the Buildah task with your cluster's approved rootless build approach.

## 4. Configure internal registry credentials

Create a short-lived service-account token and a Docker registry secret. The token below is valid for 24 hours; refresh the secret when it expires.

REGISTRY_TOKEN=$(oc create token cicd-pipeline --duration=24h)

oc create secret docker-registry registry-auth \
  --docker-server=image-registry.openshift-image-registry.svc:5000 \
  --docker-username=cicd-pipeline \
  --docker-password="${REGISTRY_TOKEN}" \
  --docker-email=unused@example.com \
  -n python-cicd

oc secrets link cicd-pipeline registry-auth -n python-cicd
unset REGISTRY_TOKEN

The service account's `system:image-builder` role permits the image push. Tekton uses the linked Docker credential when the Buildah step pushes to the internal registry.

## 5. Create a GitHub token secret

The `update-gitops` Task pushes the new image tag to the `main` branch. Create a GitHub fine-grained personal access token with **Contents: Read and write** access limited to this repository. Do not put the token in a YAML file or commit it to Git.

read -s GITHUB_TOKEN
oc create secret generic github-token \
  --from-literal=token="${GITHUB_TOKEN}" \
  -n python-cicd
unset GITHUB_TOKEN


If the secret already exists, update it instead:

read -s GITHUB_TOKEN
oc create secret generic github-token \
  --from-literal=token="${GITHUB_TOKEN}" \
  --dry-run=client -o yaml | oc apply -f -
unset GITHUB_TOKEN


## 6. Apply Tekton Tasks and Pipeline

Run these commands from the repository root:

oc apply -f pipelines/tasks/clone-source.yaml -n python-cicd
oc apply -f pipelines/tasks/python-test.yaml -n python-cicd
oc apply -f pipelines/tasks/buildah-push.yaml -n python-cicd
oc apply -f pipelines/tasks/update-gitops.yaml -n python-cicd
oc apply -f pipelines/pipeline.yaml -n python-cicd

oc get tasks -n python-cicd
oc get pipelines -n python-cicd


## 7. Start the Pipeline

The PipelineRun YAML uses `generateName`, so use `oc create`, not `oc apply`:

oc create -f pipelines/pipeline-run.yaml -n python-cicd


Watch the run:

tkn pipelinerun list -n python-cicd
tkn pipelinerun logs -f -L -n python-cicd


Or use:

oc get pipelineruns -n python-cicd
oc get taskruns -n python-cicd

The pipeline performs these steps:

1. Clone the GitHub repository's `main` branch.
2. Run Python unit tests.
3. Build and push an image tagged with the source commit SHA.
4. Update `gitops/deployment.yaml` to use that image tag and push a Git commit to `main`.

If the GitHub push fails, check the `github-token` secret and its repository Contents permission. If the image push fails, check the `registry-auth` secret, token expiry, `system:image-builder` role, and SCC events.

## 8. Configure Argo CD

The Argo CD Application object is created in the operator namespace (`openshift-gitops`), while the application workloads are deployed into `python-cicd`. This is normal: the app namespace remains the single workload namespace.

Review `argocd/application.yaml`, then apply it:


oc apply -f argocd/application.yaml


Check the Application:

oc get applications.argoproj.io -n openshift-gitops

Check the deployment:

oc get deploy,svc,route,pods -n python-cicd


Argo CD is configured for automated sync, pruning, and self-healing. If the Application is OutOfSync, inspect its status and events before forcing a sync.

## 9. Test the application

Get the route:

oc get route python-cicd -n python-cicd

Open the host shown by that command in a browser, or test it with curl:

ROUTE=$(oc get route python-cicd -n python-cicd -o jsonpath='{.spec.host}')
curl -i "http://${ROUTE}/"
curl -i "http://${ROUTE}/health"


## 10. Practice another release

Make a small change in `app/app.py`, commit and push it:

git add app/
git commit -m "Update application response"
git push origin main


Start another PipelineRun:

oc create -f pipelines/pipeline-run.yaml -n python-cicd


The pipeline builds a new SHA-tagged image and updates the GitOps manifest. Argo CD detects the Git change and rolls out the new image.

## Troubleshooting commands

oc get pods -n python-cicd
oc get events -n python-cicd --sort-by=.lastTimestamp
oc describe pipelinerun -n python-cicd
oc describe taskrun <taskrun-name> -n python-cicd
tkn pipelinerun logs <pipelinerun-name> -n python-cicd
oc describe application python-cicd -n openshift-gitops


## Important operational notes

- Do not store GitHub tokens, registry passwords, or kubeconfigs in Git.
- The initial pipeline is manually started. This avoids an accidental webhook loop when Tekton itself pushes a GitOps commit. Add a webhook later with event filtering that ignores the pipeline-generated GitOps update commit or uses a separate deployment branch/repository.
- For a real production design, protect `main` with pull-request review, use image scanning and signing, use a controlled promotion process, and use a non-root build strategy.
- The GitOps manifest is the desired state. Avoid manually editing the live Deployment; commit changes to Git instead.
