---
title: "Cloudflare on K8S"
date: 2025-08-22
summary: "cloudflare"
description: ""
tags: ["Kubernetes", "Cloudflare"]
toc: false
---

Provisioning the resources
We set up a bare metal cluster on Hetzner using kube-hetzner. In kube-hetzner, we define resources that we want to use in Hetzner. This means we describe in Terraform (HCL) how many servers, what kind of servers, and what private networks we need. We also provide our Hetzner API token to authenticate resource creation. When we apply the terraform chart it will create these resources for us (it will book the servers etc.).

This post is still in progress ..
