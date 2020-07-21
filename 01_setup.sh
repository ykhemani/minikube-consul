#!/usr/bin/env bash
source helper.sh

CONSUL_HELM_VERSION=0.23.1
helm repo add hashicorp https://helm.releases.hashicorp.com

c1_kctx
if helm status cluster-1 > /dev/null; then
helm upgrade cluster-1 hashicorp/consul -f values1.yaml \
    --version $CONSUL_HELM_VERSION \
    --set global.datacenter=cluster-1 \
    --wait
else
helm install cluster-1 hashicorp/consul -f values1.yaml \
    --version $CONSUL_HELM_VERSION \
    --set global.datacenter=cluster-1 \
    --wait
fi
kubectl wait --for=condition=available --timeout=1m deployment.apps/consul-mesh-gateway

kubectl get secret consul-federation -o yaml > consul-federation-secret.yaml

c2_kctx
if helm status cluster-2 > /dev/null; then
helm upgrade cluster-2 hashicorp/consul -f values2.yaml \
    --version $CONSUL_HELM_VERSION \
    --set global.datacenter=cluster-2 \
    --wait
else
kubectl apply -f consul-federation-secret.yaml

helm install cluster-2 hashicorp/consul -f values2.yaml \
    --version $CONSUL_HELM_VERSION \
    --set global.datacenter=cluster-2 \
    --wait
fi
kubectl wait --for=condition=available --timeout=1m deployment.apps/consul-mesh-gateway

c1_kctl apply -f c1_manifests/
c2_kctl apply -f c2_manifests/

c1_kctl wait --for=condition=available --timeout=1m deployment.apps/dashboard-service
# Configuring consul (via local consul client and helper scripts)
# These settings global, so only one config entry is needed.
consul1 "config write" "consul_config/dashboard-defaults.hcl"
consul1 "config write" "consul_config/webapp-defaults.hcl"
consul1 "config write" "consul_config/webapp-resolver.hcl"
consul1 "config write" "consul_config/webapp-splitter.hcl"

# Setup default deny intention.
consul1 'intention create' '-deny "*" "*"' || true
# Setup allow intentions
consul1 'intention create' '-allow dashboard-service external-counting' || true
consul1 'intention create' '-allow webapp external-counting' || true
consul1 'intention create' '-allow dashboard-ingress-gateway dashboard-service' || true
consul1 'intention create' '-allow dashboard-ingress-gateway webapp' || true

consul1 "config write" "consul_config/dashboard-ingress-tcp.hcl"

# adding hosts to your /etc/hosts file
addhost dashboard-service.ingress.cluster-1.consul $(minikube ip -p cluster-1)
addhost dashboard-service.ingress.cluster-2.consul $(minikube ip -p cluster-2)
addhost webapp.ingress.consul $(minikube ip -p cluster-1)

# Enterprise trial license (optional)
# consul1 "license put" "@$HOME/Documents/consul_v2lic.hclic"
# consul2 "license put" "@$HOME/Documents/consul_v2lic.hclic"


c1_kctx
echo ""
echo "Cluster 1 Consul UI $(minikube service consul-ui -p cluster-1 --https --url)"
echo "Cluster 2 Consul UI : $(minikube service consul-ui -p cluster-2 --https --url)"
echo "Dashboard url https://webapp.ingress.consul:30080"
echo "Dashboard url https://webapp.ingress.consul:30080/?x-debug"
echo "Dashboard url https://dashboard-service.ingress.cluster-1.consul:30443"
echo "Dashboard url https://dashboard-service.ingress.cluster-2.consul:30443"
echo ""

minikube service list -p cluster-1
minikube service list -p cluster-2
