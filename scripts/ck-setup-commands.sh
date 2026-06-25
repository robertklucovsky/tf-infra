#!/usr/bin/env bash
# =============================================================================
# Canonical Kubernetes (ck) — out-of-band setup commands
#
# These are the IMPERATIVE kubectl / k8s-snap commands run by hand during the
# platform/tenant ingress separation work (2026-06-25). They are NOT a full
# bootstrap script.
#
# IMPORTANT: the bulk of the platform configuration (Gateways, HTTPRoutes,
# TLSRoutes, relay Service/Endpoints, MetalLB shared-IP annotations,
# certificates, Keycloak, etc.) is managed by TERRAFORM in ../dev and is NOT
# repeated here. This file only documents the steps that live outside Terraform
# (node-level k8s-snap feature config + one-off CNPG storage maintenance).
#
# These commands MUTATE a shared cluster. Review before running. Not idempotent.
# Run sections individually — do NOT execute the whole file blindly.
# =============================================================================

set -euo pipefail

NODE="${NODE:-cwwk}"          # ssh host for the Canonical K8s node
NS_CNPG="cnpg-system"
NS_GW="gateway"

# -----------------------------------------------------------------------------
# 1) MetalLB address pool — widen via the Canonical K8s load-balancer feature
#
# ck bundles MetalLB (L2 mode) behind its `load-balancer` feature. The pool is
# reconciled from `load-balancer.cidrs`; editing the MetalLB IPAddressPool CR
# directly gets reverted by the feature controller, so set it via `k8s set`.
# Run on the NODE (snap CLI), not via remote kubectl.
# -----------------------------------------------------------------------------

# Inspect current config:
ssh "$NODE" 'sudo k8s get load-balancer'

# Widen the pool so additional Gateways/LB Services can get IPs
# (.11 = original gateway, .12 = shared front IP, .13 = terminating gateway):
ssh "$NODE" 'sudo k8s set load-balancer.cidrs="172.16.1.11-172.16.1.13"'

# Verify the MetalLB pool reconciled:
kubectl get ipaddresspool -n metallb-system \
  -o jsonpath='{range .items[*]}{.metadata.name}={.spec.addresses}{"\n"}{end}'

# -----------------------------------------------------------------------------
# 2) MetalLB shared-IP annotations on the cilium-gateway-* Services
#
# Cilium does NOT propagate Gateway.metadata.annotations to the generated
# cilium-gateway-* Service, so MetalLB shared-IP must be set on the Service.
# These are now also codified in Terraform (kubernetes_annotations in
# dev/gateway-platform.tf); kept here as the manual equivalent / bootstrap aid.
#
# Both front Gateways share ONE IP (ports 443 + 80 do not overlap).
# The terminating Gateway is reached internally via the relay, so its external
# IP is unused — pin it off the fronts' IP to avoid an allocation conflict.
# -----------------------------------------------------------------------------

# Fronts share the public IP (172.16.1.11 is the router's NAT target):
kubectl annotate svc cilium-gateway-platform-front-tls cilium-gateway-platform-front-http \
  -n "$NS_GW" \
  metallb.io/allow-shared-ip=platform-front \
  metallb.io/loadBalancerIPs=172.16.1.11 --overwrite

# Terminating gateway off on its own IP (internal only):
kubectl annotate svc cilium-gateway-platform-terminating -n "$NS_GW" \
  metallb.io/loadBalancerIPs=172.16.1.13 --overwrite

# MetalLB does NOT auto-retry after an AllocationFailed; re-applying identical
# annotations is a no-op. If a Service stays <pending> after the target IP is
# freed, force a reconcile with a throwaway annotation toggle:
kubectl annotate svc cilium-gateway-platform-front-tls cilium-gateway-platform-front-http \
  -n "$NS_GW" nudge=1 --overwrite
sleep 3
kubectl annotate svc cilium-gateway-platform-front-tls cilium-gateway-platform-front-http \
  -n "$NS_GW" nudge-

# Verify assigned external IPs:
kubectl get svc -n "$NS_GW" \
  -o jsonpath='{range .items[*]}{.metadata.name}={.status.loadBalancer.ingress[0].ip}{"\n"}{end}' \
  | grep cilium-gateway

# -----------------------------------------------------------------------------
# 3) CNPG PostgreSQL storage resize (5Gi -> 100Gi) — "recreating storage"
#
# The csi-rawfile-default StorageClass does NOT support volume expansion. The
# cluster spec was changed via Terraform (dev/cnpg.tf: storage.size=100Gi AND
# resizeInUseVolumes=false — without the latter the operator's reconcile errors
# on the existing PVC and never recreates the replica). The PVC re-creation is
# the manual part below: one instance at a time, replica first, then switchover,
# then the old primary. CNPG renames instances on recreation (shared-db-2 ->
# shared-db-3 -> shared-db-4).
# -----------------------------------------------------------------------------

# (Precondition: terraform apply set spec.storage.size=100Gi and
#  resizeInUseVolumes=false on the shared-db Cluster.)

# 3a) Recreate the REPLICA at the new size (delete PVC + pod; operator rebuilds):
kubectl delete pvc shared-db-2 -n "$NS_CNPG" --wait=false
kubectl delete pod shared-db-2 -n "$NS_CNPG"
# wait until the new (larger) replica is Ready and the cluster has 2 instances:
#   kubectl get cluster shared-db -n cnpg-system \
#     -o jsonpath='{.status.readyInstances}{"\n"}'
#   kubectl get pvc -n cnpg-system -l cnpg.io/cluster=shared-db

# 3b) Graceful switchover onto the recreated (larger) instance.
#     Patch status.targetPrimary (this is what `kubectl cnpg promote` does):
kubectl patch cluster shared-db -n "$NS_CNPG" --subresource status \
  --type merge -p '{"status":{"targetPrimary":"shared-db-3"}}'
# wait for status.currentPrimary to become the target.

# 3c) Recreate the OLD primary (now a replica) at the new size:
kubectl delete pvc shared-db-1 -n "$NS_CNPG" --wait=false
kubectl delete pod shared-db-1 -n "$NS_CNPG"
# verify both PVCs are now 100Gi and the cluster is healthy:
#   kubectl get pvc -n cnpg-system -l cnpg.io/cluster=shared-db \
#     -o custom-columns=NAME:.metadata.name,CAP:.status.capacity.storage

echo "Done. Review each section's verification output above."
