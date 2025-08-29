---
title: "Cloudflare on K8S"
date: 2025-08-22
summary: "cloudflare"
description: ""
tags: ["Kubernetes", "Cloudflare"]
toc: false
---

This post is still in progress - it will get updated. Stay tuned.

Provisioning the resources
We set up a bare metal cluster on Hetzner using kube-hetzner. In kube-hetzner, we define resources that we want to use in Hetzner. This means we describe in Terraform (HCL) how many servers, what kind of servers, and what private networks we need. We also provide our Hetzner API token to authenticate resource creation. When we apply the terraform chart it will create these resources for us (it will book the servers etc.).


kube-hetzner via Terraform provisions Hetzner resources and turns them into a k3s on openSUSE MicroOS cluster with a HA control plane, CCM/CSI and a choice of TRaefik/NGINX/HAProxy ingress (as we are most familiar with nginx we will describe the nginx approach in this doc). 
The cluster will be accessed via kubectl and rarely ever via ssh on actual nodes (node-level maintenance is uncommon).

Ingress Controller
The ingress controller (nginx) should only have a ClusterIP (adjust it that way). We should also disable k3s ServiceLB so nodes do not bind 80/443. We have the cloudflare tunnel for external access and nginx should only control the ingress within the cluster. We need to configure the ingress to trust Cloudflare headers, otherwise logs/rate-limits see tunnel pod IPs. Only cloudflared namespaces should be able to connect to the Ingress.
The ingress controller (nginx) is itself a deployment (with multiple replicas) fronted by a Service so other applications can send it traffic (note that ‘Deployment’ and ‘Service’ have very specific meanings in Kubernetes). The ingress itself is not a service object itself but a separate API object that defines HTTP/S rules. Therefore, the cloudflared pods should target the ingress controller's Service, not an ingress object.



