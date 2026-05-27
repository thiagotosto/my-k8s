variable "project_id" {
  type = string
}

variable "project_number" {
  type = string
}

variable "region" {
  type = string
}

variable "max_converter_instances" {
  type    = number
  default = 10
}

variable "max_delivery_attempts" {
  type    = number
  default = 5
}
