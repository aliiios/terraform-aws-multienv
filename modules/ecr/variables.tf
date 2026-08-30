variable "name" {
  description = "Name of the ECR repository."
  type        = string
}

variable "image_tag_mutability" {
  description = "IMMUTABLE prevents overwriting an existing tag. Strongly recommended so a deployed tag can never silently change."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Run a vulnerability scan automatically when an image is pushed."
  type        = bool
  default     = true
}

variable "untagged_image_expiry_days" {
  description = "Delete untagged images after this many days (they are usually orphaned layers)."
  type        = number
  default     = 7
}

variable "max_tagged_images" {
  description = "Keep at most this many tagged images; older ones are expired."
  type        = number
  default     = 20
}

variable "force_delete" {
  description = "Allow destroying the repository even if it still contains images. True is convenient for dev only."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
