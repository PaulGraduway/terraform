variable "region" {
  type    = string
  default = "us-east-1"
}


variable "app_name" {
  type    = string
  default = "paul"
}

variable "ssh_key_name" {
  type    = string
  default = "staging-peerpal-chat-api-ssh"
}
