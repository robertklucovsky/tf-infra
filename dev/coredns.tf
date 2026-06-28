# CoreDNS custom hosts — resolve platform hostnames to the cluster node on the LAN.
#
# The CoreDNS Corefile lives in the `ck-dns-coredns` ConfigMap, which is owned by
# Canonical Kubernetes' built-in DNS feature (Helm release `ck-dns`, chart
# coredns-1.39.2). We don't own the whole ConfigMap, so we patch only the
# `Corefile` data key via kubernetes_config_map_v1_data with force = true to take
# field ownership from Helm. CoreDNS's `reload` plugin re-reads the Corefile within
# ~30s, so no pod restart is needed.
#
# The `hosts` block makes in-cluster lookups of these names return the node IP
# (172.16.1.11) instead of going out to public DNS — used so workloads and the
# Terraform providers resolve the platform endpoints to the gateway on the LAN.
# `fallthrough` passes any other name on to the next plugin (kubernetes, forward).
#
# WATCHOUT: this freezes the entire Corefile. If the ck-dns chart is upgraded and
# its templated Corefile changes, Terraform will revert those changes on next apply
# (and Helm may revert ours). Keep this block in sync with the chart's Corefile.
resource "kubernetes_config_map_v1_data" "coredns_hosts" {
  metadata {
    name      = "ck-dns-coredns"
    namespace = "kube-system"
  }

  force = true

  data = {
    Corefile = <<-EOT
      .:53 {
          errors
          health {
              lameduck 5s
          }
          ready
          kubernetes cluster.local in-addr.arpa ip6.arpa {
              pods insecure
              fallthrough in-addr.arpa ip6.arpa
              ttl 30
          }
          hosts {
              172.16.1.11 registry.klucovsky.com nexus.klucovsky.com auth.klucovsky.com
              fallthrough
          }
          prometheus 0.0.0.0:9153
          forward . /etc/resolv.conf
          cache 30
          loop
          reload
          loadbalance
      }
    EOT
  }
}
