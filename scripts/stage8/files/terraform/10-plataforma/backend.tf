# El estado vive DENTRO del clúster, en un Secret (tfstate-default-plataforma) del namespace
# tfstate, con bloqueo por Lease: dos "terraform apply" a la vez -> el segundo espera o falla.
# El namespace tfstate se crea a mano UNA vez (el backend no puede crear el sitio donde guarda
# su propio estado): kubectl create namespace tfstate
terraform {
  backend "kubernetes" {
    secret_suffix = "plataforma"
    namespace     = "tfstate"
    config_path   = "~/.kube/config"
  }
}
