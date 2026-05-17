terraform {
  required_version = ">= 1.7.0"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = ">= 0.4"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.4"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
  }
}

locals {
  # Use the kubeconfig file that kind writes into this module directory when present.
  # Fallback to the user's default kubeconfig otherwise.
  module_kubeconfig = "${path.module}/woohoosvcs-config"
  k8s_config_path   = fileexists(local.module_kubeconfig) ? local.module_kubeconfig : pathexpand("~/.kube/config")
}

provider "kubernetes" {
  config_path    = local.k8s_config_path
  config_context = "kind-${var.kind_cluster_name}"
}

resource "kind_cluster" "this" {
  name           = var.kind_cluster_name
  node_image     = var.kind_node_image
  wait_for_ready = true
}

variable "cluster_name" {
  description = "Name of the target cluster directory"
  type        = string
  default     = "cluster3"
}

resource "null_resource" "kubectl_apply_flux_gotk_components" {
  provisioner "local-exec" {
    command = "kubectl apply -f \"${path.module}/../../clusters/${var.cluster_name}/flux-system/gotk-components.yaml\" --kubeconfig=\"${local.k8s_config_path}\" --context=\"kind-${var.kind_cluster_name}\""
  }

  triggers = {
    components_file_hash = filemd5("${path.module}/../../clusters/${var.cluster_name}/flux-system/gotk-components.yaml")
    cluster_id           = kind_cluster.this.id
  }

  depends_on = [kind_cluster.this, null_resource.wait_for_kube]
}

resource "null_resource" "kubectl_create_sops_secret" {
  provisioner "local-exec" {
    command = "\"${path.module}/scripts/create_sops_secret.sh\" \"${local.k8s_config_path}\" \"kind-${var.kind_cluster_name}\" \"${var.sops_age_key_path}\""
  }

  # Use filemd5 so Terraform only re-runs this when the key file changes.
  triggers = {
    sops_key_hash = filemd5(var.sops_age_key_path)
    cluster_id    = kind_cluster.this.id
  }
  depends_on = [null_resource.kubectl_apply_flux_gotk_components, null_resource.wait_for_kube]
}

resource "null_resource" "wait_for_crds" {
  provisioner "local-exec" {
    command = "\"${path.module}/scripts/wait_for_crds.sh\" \"${local.k8s_config_path}\" \"kind-${var.kind_cluster_name}\" 120"
  }
  triggers = {
    gotk_components = filemd5("${path.module}/../../clusters/${var.cluster_name}/flux-system/gotk-components.yaml")
    cluster_id      = kind_cluster.this.id
  }

  depends_on = [null_resource.kubectl_apply_flux_gotk_components]
}

resource "null_resource" "wait_for_kube" {
  provisioner "local-exec" {
    command = "\"${path.module}/scripts/wait_for_kube.sh\" \"${local.k8s_config_path}\" \"kind-${var.kind_cluster_name}\""
  }

  triggers = {
    # tie the waiter to the cluster resource by name (re-run when cluster recreated)
    cluster_name = kind_cluster.this.name
    # also include the cluster resource id so triggers change when the cluster is destroyed and recreated
    cluster_id = kind_cluster.this.id
  }
}

resource "null_resource" "kubectl_apply_flux_gotk_sync" {
  provisioner "local-exec" {
    command = "kubectl apply -f \"${path.module}/../../clusters/${var.cluster_name}/flux-system/gotk-sync.yaml\" --kubeconfig=\"${local.k8s_config_path}\" --context=\"kind-${var.kind_cluster_name}\""
  }

  triggers = {
    sync_file_hash = filemd5("${path.module}/../../clusters/${var.cluster_name}/flux-system/gotk-sync.yaml")
    cluster_id     = kind_cluster.this.id
  }

  depends_on = [null_resource.kubectl_create_sops_secret, null_resource.wait_for_crds]
}
