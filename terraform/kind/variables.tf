variable "kind_node_image" {
    description = "Docker Image"
    type = string
    default = "kindest/node:v1.35.1"
}

variable "kind_cluster_name" {
    description = "The name of the Kind Cluster"
    type = string
    default = "test"
}

variable "sops_age_key_path" {
    description = "Location of the sops age.key"
    type = string
    default = ""
}