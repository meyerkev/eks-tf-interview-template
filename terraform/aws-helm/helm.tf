locals {
  namespaces = {
    "aws-load-balancer-controller" = "aws-load-balancer-controller"
    "external-dns"                 = "external-dns"
    "cluster-autoscaler"           = "cluster-autoscaler"
    "metrics-server"               = "kube-system"
  }

  service_accounts = {
    "aws-load-balancer-controller" = "aws-load-balancer-controller"
    "external-dns"                 = "external-dns"
    "cluster-autoscaler"           = "cluster-autoscaler"
  }

  # v6 of the IAM module renamed the role ARN output from `iam_role_arn` to
  # plain `arn`.
  irsa_roles = {
    "aws-load-balancer-controller" = module.aws-load-balancer-irsa.arn
    "external-dns"                 = module.external-dns-irsa.arn
    "cluster-autoscaler"           = module.aws-cluster-autoscaler-irsa.arn
  }
}

data "aws_ssm_parameter" "oidc_provider" {
  name = "/eks/${var.eks_cluster_name}/oidc_provider"
}

# kubernetes provider 3.x deprecated the un-versioned resource names in favor
# of the explicit `_v1` suffix. The old names still work but emit warnings;
# we use the new names.
resource "kubernetes_namespace_v1" "namespaces" {
  for_each = { for namespace, value in local.namespaces : namespace => value if value != "kube-system" }
  metadata {
    name = each.value
  }
}

resource "kubernetes_service_account_v1" "service_accounts" {
  for_each = local.service_accounts
  metadata {
    name      = each.value
    namespace = local.namespaces[each.key]
    annotations = {
      "eks.amazonaws.com/role-arn" = local.irsa_roles[each.key]
    }
  }
  depends_on = [kubernetes_namespace_v1.namespaces]
}

# IAM module v6 consolidated and renamed several submodules. The
# `iam-role-for-service-accounts-eks` submodule was renamed to
# `iam-role-for-service-accounts`, and `role_name` is now `name`. v6 also
# defaults `use_name_prefix = true`, which adds a 26-char random suffix and
# enforces a 38-char limit on the supplied name; we set
# `use_name_prefix = false` so we get the literal role name we asked for.
module "aws-load-balancer-irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.0"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = data.aws_ssm_parameter.oidc_provider.value
      namespace_service_accounts = ["${local.namespaces.aws-load-balancer-controller}:${local.service_accounts.aws-load-balancer-controller}"]
    }
  }
  name            = "aws-load-balancer-controller-${var.eks_cluster_name}-role"
  use_name_prefix = false
}

module "external-dns-irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.0"

  attach_external_dns_policy = true
  # v6 of the IAM module dropped the permissive `*` default for the
  # external-dns hosted-zone scope - users now have to be explicit. We pass
  # `*` here because this is an interview cluster with no real DNS to
  # manage; in production, scope this to specific hosted zone ARNs.
  external_dns_hosted_zone_arns = ["*"]

  oidc_providers = {
    main = {
      provider_arn               = data.aws_ssm_parameter.oidc_provider.value
      namespace_service_accounts = ["${local.namespaces.external-dns}:${local.service_accounts.external-dns}"]
    }
  }
  name            = "external-dns-${var.eks_cluster_name}-role"
  use_name_prefix = false
}

module "aws-cluster-autoscaler-irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.0"

  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [var.eks_cluster_name]

  oidc_providers = {
    main = {
      provider_arn               = data.aws_ssm_parameter.oidc_provider.value
      namespace_service_accounts = ["${local.namespaces.cluster-autoscaler}:${local.service_accounts.cluster-autoscaler}"]
    }
  }
  name            = "aws-cluster-autoscaler-${var.eks_cluster_name}-role"
  use_name_prefix = false
}

# helm provider 3.x: `set` is now a list of objects (`set = [{...}]`) rather
# than a series of `set { ... }` blocks.
resource "helm_release" "aws-load-balancer-controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = local.namespaces["aws-load-balancer-controller"]
  # Chart jumped from the long-running 1.x line (1.5.3 was pinned previously)
  # to a 3.x line aligned with the controller appVersion. The `clusterName`
  # and `serviceAccount.*` value paths are unchanged.
  # Note: helm provider 3.x rejects `~>` style constraints in helm_release;
  # all chart versions in this file are pinned to exact strings.
  version = "3.3.0"

  wait = true

  # EKS module v21 sets the IMDS hop limit to 1 by default (was 2 in v20),
  # so the controller pod can't reach IMDS to auto-discover its VPC at
  # startup. Pass `vpcId` and `region` explicitly; IRSA still handles all
  # the actual AWS API calls so we don't need IMDS for credentials either.
  # This keeps the node IAM role un-impersonatable from inside pods.
  set = [
    {
      name  = "clusterName"
      value = var.eks_cluster_name
    },
    {
      name  = "vpcId"
      value = data.aws_eks_cluster.cluster.vpc_config[0].vpc_id
    },
    {
      name  = "region"
      value = var.aws_region
    },
    {
      name  = "serviceAccount.create"
      value = "false"
    },
    {
      name  = "serviceAccount.name"
      value = local.service_accounts.aws-load-balancer-controller
    },
  ]

  depends_on = [kubernetes_service_account_v1.service_accounts]
}

# external-dns: switched the chart source from Bitnami (whose public catalog
# is being retired in favor of bitnamicharts/secure images) to the official
# kubernetes-sigs maintained chart. Same `serviceAccount.create/name` keys.
resource "helm_release" "external-dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  namespace  = local.namespaces["external-dns"]
  version    = "1.21.1"

  wait = true

  set = [
    {
      name  = "serviceAccount.create"
      value = "false"
    },
    {
      name  = "serviceAccount.name"
      value = local.service_accounts.external-dns
    },
  ]

  depends_on = [kubernetes_service_account_v1.service_accounts]
}

resource "helm_release" "cluster-autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = local.namespaces["cluster-autoscaler"]
  version    = "9.57.0"

  wait = true

  set = [
    {
      name  = "autoDiscovery.clusterName"
      value = var.eks_cluster_name
    },
    {
      name  = "awsRegion"
      value = var.aws_region
    },
    {
      name  = "rbac.serviceAccount.create"
      value = "false"
    },
    {
      name  = "rbac.serviceAccount.name"
      value = local.service_accounts.cluster-autoscaler
    },
  ]

  depends_on = [kubernetes_service_account_v1.service_accounts]
}

resource "helm_release" "metrics-server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server"
  chart      = "metrics-server"
  namespace  = local.namespaces["metrics-server"]
  version    = "3.13.0"

  wait = true
  # If you don't have a namespace named kube-system yet, what are we even doing here kids?
  create_namespace = false
}
