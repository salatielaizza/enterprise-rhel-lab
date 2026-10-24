# Mismo backend que 10-plataforma, otro Secret: cada capa tiene su estado y su bloqueo
terraform {
  backend "kubernetes" {
    secret_suffix = "config"
    namespace     = "tfstate"
    config_path   = "~/.kube/config"
  }
}
