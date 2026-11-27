variable "tags" {
  description = "Tags applied to the key pair and its secret (merged with key_pair.tags)"
  type        = map(string)
  default     = {}
}

variable "env" {
  description = "(Required) env value used in name generation"
  type        = string
}

variable "userDefinedString" {
  description = "(Required) UserDefinedString part of the name of the key pair (and of its secret)"
  type        = string
}

variable "key_pair" {
  description = "Object describing where the key pair comes from (see TFVars Parameters in the README): nothing (the default) makes one at the apply and deletes it at the destroy, key_name names one that exists, public_key imports one. Optional `name` key overrides the auto-derived \"<env>-<userDefinedString>-key\" name."
  type        = any
  default     = {}

  validation {
    condition     = !(try(var.key_pair.key_name, null) != null && try(var.key_pair.public_key, null) != null)
    error_message = "key_pair names a key pair that exists (key_name) or imports one (public_key), not both."
  }
}
