#!/bin/bash
###### Pre-requisites:
## 1. Authenticate docker to the image registry you want to use (see Kind option below)
## 2. Set kube context to the Kubernetes cluster you want to use (see Kind option below)
## 3. Install kapp-controller to the cluster (see kapp-controller instruction below)
## 4. Install Carvel CLIs and kctrl CLI
## 5. Install demorunner (https://github.com/mgbrodi/demorunner)

###### You can run this script to satisfy

# Carvel CLIs
if  command -v vendir &> /dev/null &&
    command -v kbld &> /dev/null &&
    command -v ytt &> /dev/null &&
    command -v kapp &> /dev/null &&
    command -v imgpkg &> /dev/null; then
      echo "All Carvel CLIs are installed"
else
    echo "ERROR: Please install all Carvel CLIs"
fi

# kctrl CLI
if ! command -v kctrl &> /dev/null; then echo "Please install kctrl CLI"; fi

# Demorunner
if [ -x scripts/demorunner.sh ]; then
  echo "demorunner.sh exists and is executable"
else
  echo "Downloading demorunner"

  echo curl https://github.com/mgbrodi/demorunner/blob/master/demorunner.sh -o scripts/demorunner.sh \
       && chmod +x scripts/demorunner.sh
fi

# Cluster and kapp-controller
if [[ $(kubectl api-resources --api-group=kappctrl.k14s.io -o name) == "apps.kappctrl.k14s.io" ]]; then
  echo "Kubecontext is set to a valid cluster with kapp-controller installed"
else
  echo "Creating kind cluster and installing kapp-controller"

  # Kind with registry installation:
  curl https://kind.sigs.k8s.io/examples/kind-with-registry.sh -o kind-with-registry.sh \
    && chmod +x kind-with-registry.sh \
    && ./kind-with-registry.sh \
    && kubectl cluster-info --context kind-kind \
    && rm kind-with-registry.sh
   export MY_REG=localhost:5001/gitopscon
   export EDGE_REG=localhost:5001/gitopscon-edge

  # kapp-controller installation and RBAC configuration:
  kapp deploy -a kc -f https://github.com/vmware-tanzu/carvel-kapp-controller/releases/latest/download/release.yml
  kubectl apply -f deployments/ns-rbac-default.yml
fi

