variable "resource_group_name" {
  type    = string
  default = "rg-it-tools-azure"
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "acr_name" {
  type        = string
  description = "Globally unique name for the ACR — letters/numbers only"
  default     = "ittoolsazure"
}

variable "container_app_name" {
  type    = string
  default = "it-tools"
}

variable "image_tag" {
  type    = string
  default = "f636ea9"
}
