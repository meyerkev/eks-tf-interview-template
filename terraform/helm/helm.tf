locals {
    namespaces = {
        "aws-load-balancer-controller" = "aws-load-balancer-controller"
        "external-dns" = "external-dns"
    }

    service_accounts = {
        "aws-load-balancer-controller" = "aws-load-balancer-controller"
        "external-dns" = "external-dns"
    }
}

data "aws_ssm_parameter" "oidc_provider" {
  name = "/eks/${var.eks_cluster_name}/oidc_provider"
}

resource "kubernetes_namespace" "namespaces" {
    for_each = local.namespaces
    metadata {
        name = each.value
    }
}

resource "kubernetes_service_account" "service_accounts" {
    for_each = local.service_accounts
    metadata {
        name      = each.value
        namespace = local.namespaces[each.key]
    }
    depends_on = [ kubernetes_namespace.namespaces ]
}

resource "aws_iam_policy" "aws-load-balancer-controller" {
    name = "aws-load-balancer-controller-${var.eks_cluster_name}-policy"
    path = "/"
    policy = file("${path.module}/assets/aws-lb-controller-iam-policy.json")
}


module "aws-load-balancer-irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = data.aws_ssm_parameter.oidc_provider.value
      namespace_service_accounts = ["${local.namespaces.aws-load-balancer-controller}:${local.service_accounts.aws-load-balancer-controller}"]
    }
  }
  depends_on = [ kubernetes_service_account.service_accounts["aws-load-balancer-controller"] ]
}

module "external-dns-irsa" {
    source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
    
    attach_external_dns_policy = true
    
    oidc_providers = {
        main = {
        provider_arn               = data.aws_ssm_parameter.oidc_provider.value
        namespace_service_accounts = ["${local.namespaces.external-dns}:${local.service_accounts.external-dns}"]
        }
    }
    depends_on = [ kubernetes_service_account.service_accounts["external-dns"] ]
}


resource "helm_release" "aws-load-balancer-controller" {
    name       = "aws-load-balancer-controller"
    repository = "https://aws.github.io/eks-charts"
    chart      = "aws-load-balancer-controller"
    namespace  = "aws-load-balancer-controller"
    version    = "1.5.3"
    
    set {
        name  = "clusterName"
        value = var.eks_cluster_name
    }

    set {
        name  = "serviceAccount.create"
        value = "false"
    }

    set {
        name  = "serviceAccount.name"
        value = local.service_accounts.aws-load-balancer-controller
    }
    depends_on = [ module.aws-load-balancer-irsa, kubernetes_service_account.service_accounts["aws-load-balancer-controller"] ]
}

resource "helm_release" "external-dns" {
    name = "external-dns"
    repository = "https://charts.bitnami.com/bitnami"
    chart = "external-dns"
    namespace = "external-dns"
    version = "6.20.3"

    set {
        name = "serviceAccount.create"
        value = "false"
    }
}