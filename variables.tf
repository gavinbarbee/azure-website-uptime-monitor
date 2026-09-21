variable "yourname" {
  description = "Your name, lowercase, no spaces. Used to name all resources."
  type        = string
}

variable "location" {
  description = "Azure region. If you hit a quota error in East US, use West US 2."
  type        = string
  default     = "East US"
}

variable "target_url" {
  description = "The website URL to monitor. Must include https://."
  type        = string
}

variable "alert_email" {
  description = "Email address that receives downtime alerts."
  type        = string
}

variable "alert_phone" {
  description = "Phone number for SMS alerts. E.164 format: +14045550100"
  type        = string
}

variable "tags" {
  type = map(string)
  default = {
    project    = "uptime-monitor"
    managed_by = "terraform"
  }
}