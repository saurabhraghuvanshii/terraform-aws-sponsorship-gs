# Define a KMS main key to encrypt the EKS cluster
resource "aws_kms_key" "cijenkinsio_agents_2" {
  description         = "EKS Secret Encryption Key for the cluster cijenkinsio-agents-2"
  enable_key_rotation = true

  tags = merge(local.common_tags, {
    associated_service = "eks/cijenkinsio-agents-2"
  })
}

# EKS Cluster definition
module "cijenkinsio_agents_2" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.29.0"

  cluster_name = "cijenkinsio-agents-2"
  # Kubernetes version in format '<MINOR>.<MINOR>', as per https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
  cluster_version = "1.29"
  create_iam_role = true

  # 2 AZs are mandatory for EKS https://docs.aws.amazon.com/eks/latest/userguide/network-reqs.html#network-requirements-subnets
  # so 2 subnets at least (private ones)
  subnet_ids = slice(module.vpc.private_subnets, 1, 3)

  # Required to allow EKS service accounts to authenticate to AWS API through OIDC (and assume IAM roles)
  # useful for autoscaler, EKS addons and any AWS API usage
  enable_irsa = true

  # Allow the terraform CI IAM user to be co-owner of the cluster
  enable_cluster_creator_admin_permissions = true

  # Avoid using config map to specify admin accesses (decrease attack surface)
  authentication_mode = "API"

  access_entries = {
    # One access entry with a policy associated
    human_cluster_admins = {
      principal_arn = "arn:aws:iam::326712726440:role/infra-admin"
      type          = "STANDARD"

      policy_associations = {
        example = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type       = "cluster"
            namespaces = null
          }
        }
      }
    }

    # see https://docs.aws.amazon.com/eks/latest/userguide/creating-access-entries.html
    ci_jenkins_io = {
      principal_arn =  aws_iam_instance_profile.arn
      type          = "STANDARD"
      kubernetes_groups = local.cijenkinsio_agents_2.kubernetes_groups  # Create Kubernetes RoleBinding or ClusterRoleBinding objects on your cluster that specify the group name as a subject for kind: Group
    }
  }

  create_kms_key = false
  cluster_encryption_config = {
    provider_key_arn = aws_kms_key.cijenkinsio_agents_2.arn
    resources        = ["secrets"]
  }

  ## We only want to private access to the Control Plane except from infra.ci agents and VPN CIDRs (running outside AWS)
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = [for admin_ip in local.ssh_admin_ips : "${admin_ip}/32"]
  # Nodes and Pods require access to the Control Plane - https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html#cluster-endpoint-private
  # without needing to allow their IPs
  cluster_endpoint_private_access = true

  tags = merge(local.common_tags, {
    GithubRepo = "terraform-aws-sponsorship"
    GithubOrg  = "jenkins-infra"

    associated_service = "eks/cijenkinsio-agents-2"
  })

  vpc_id = module.vpc.vpc_id

  cluster_addons = {
    coredns = {
      # https://docs.aws.amazon.com/cli/latest/reference/eks/describe-addon-versions.html
      # TODO: track with updatecli
      addon_version = "v1.11.3-eksbuild.2"
      configuration_values = jsonencode({
        "tolerations" = local.cijenkinsio_agents_2["node_groups"]["applications"]["tolerations"],
      })
    }
    # Kube-proxy on an Amazon EKS cluster has the same compatibility and skew policy as Kubernetes
    # See https://kubernetes.io/releases/version-skew-policy/#kube-proxy
    kube-proxy = {
      # https://docs.aws.amazon.com/cli/latest/reference/eks/describe-addon-versions.html
      # TODO: track with updatecli
      addon_version = "v1.29.11-eksbuild.2"
    }
    # https://github.com/aws/amazon-vpc-cni-k8s/releases
    vpc-cni = {
      # https://docs.aws.amazon.com/cli/latest/reference/eks/describe-addon-versions.html
      # TODO: track with updatecli
      addon_version = "v1.19.0-eksbuild.1"
    }
    eks-pod-identity-agent = {
      # https://docs.aws.amazon.com/cli/latest/reference/eks/describe-addon-versions.html
      # TODO: track with updatecli
      addon_version = "v1.3.4-eksbuild.1"
    }
    ## https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/CHANGELOG.md
    aws-ebs-csi-driver = {
      # https://docs.aws.amazon.com/cli/latest/reference/eks/describe-addon-versions.html
      # TODO: track with updatecli
      addon_version = "v1.38.1-eksbuild.1"
      configuration_values = jsonencode({
        "controller" = {
          "tolerations" = local.cijenkinsio_agents_2["node_groups"]["applications"]["tolerations"],
        },
        "node" = {
          "tolerations" = local.cijenkinsio_agents_2["node_groups"]["applications"]["tolerations"],
        },
      })
      service_account_role_arn = module.cijenkinsio_agents_2_ebscsi_irsa_role.iam_role_arn
    }
  }

  eks_managed_node_groups = {
    # This worker pool is expected to host the "technical" services such as cluster-autoscaler, data cluster-agent, ACP, etc.
    applications = {
      name           = local.cijenkinsio_agents_2["node_groups"]["applications"]["name"]
      instance_types = ["t4g.xlarge"]
      capacity_type  = "ON_DEMAND"
      # Starting on 1.30, AL2023 is the default AMI type for EKS managed node groups
      ami_type = "AL2023_ARM_64_STANDARD"
      # TODO: track with updatecli
      ami_release_version = "1.29.10-20241213"
      min_size            = 2
      max_size            = 3 # Usually 2 nodes, but accept 1 additional surging node
      desired_size        = 2

      subnet_ids = slice(module.vpc.private_subnets, 1, 2) # Only 1 subnet in 1 AZ (for EBS)

      labels = {
        jenkins = local.ci_jenkins_io["service_fqdn"]
        role    = local.cijenkinsio_agents_2["node_groups"]["applications"]["name"]
      }
      taints = { for toleration_key, toleration_value in local.cijenkinsio_agents_2["node_groups"]["applications"]["tolerations"] :
        toleration_key => {
          key    = toleration_value["key"],
          value  = toleration_value.value
          effect = local.toleration_taint_effects[toleration_value.effect]
        }
      }
    },
  }

  # Allow egress from nodes (and pods...)
  node_security_group_additional_rules = {
    egress_jenkins_jnlp = {
      description      = "Allow egress to Jenkins TCP"
      protocol         = "TCP"
      from_port        = 50000
      to_port          = 50000
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    },
    egress_http = {
      description      = "Allow egress to plain HTTP"
      protocol         = "TCP"
      from_port        = 80
      to_port          = 80
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    },
  }
}

moved {
  from = module.autoscaler_irsa_role
  to   = module.cijenkinsio_agents_2_autoscaler_irsa_role
}
module "cijenkinsio_agents_2_autoscaler_irsa_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  # TODO track with updatecli
  version = "5.48.0"

  role_name                        = "${module.cijenkinsio_agents_2.cluster_name}-cluster-autoscaler"
  attach_cluster_autoscaler_policy = true

  cluster_autoscaler_cluster_names = [module.cijenkinsio_agents_2.cluster_name]

  oidc_providers = {
    main = {
      provider_arn               = module.cijenkinsio_agents_2.oidc_provider_arn
      namespace_service_accounts = ["${local.cijenkinsio_agents_2["autoscaler"]["namespace"]}:${local.cijenkinsio_agents_2["autoscaler"]["serviceaccount"]}"]
    }
  }

  tags = local.common_tags
}

module "cijenkinsio_agents_2_ebscsi_irsa_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  # TODO track with updatecli
  version = "5.52.1"

  role_name             = "${module.cijenkinsio_agents_2.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true
  # Pass ARNs instead of IDs: https://github.com/terraform-aws-modules/terraform-aws-iam/issues/372
  ebs_csi_kms_cmk_ids = [aws_kms_key.cijenkinsio_agents_2.arn]

  oidc_providers = {
    main = {
      provider_arn               = module.cijenkinsio_agents_2.oidc_provider_arn
      namespace_service_accounts = ["${local.cijenkinsio_agents_2["ebs-csi"]["namespace"]}:${local.cijenkinsio_agents_2["ebs-csi"]["serviceaccount"]}"]
    }
  }

  tags = local.common_tags
}

# From https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/examples/kubernetes/storageclass/manifests/storageclass.yaml
resource "kubernetes_storage_class" "cijenkinsio_agents_2_ebs_csi_premium_retain" {
  provider = kubernetes.cijenkinsio_agents_2
  # We want one class per Availability Zone
  for_each = toset([for private_subnet in local.vpc_private_subnets : private_subnet.az if startswith(private_subnet.name, "eks")])

  metadata {
    name = "ebs-csi-premium-retain-${each.key}"
  }
  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Retain"
  parameters = {
    "csi.storage.k8s.io/fstype" = "xfs"
    "type"                      = "gp3"
  }
  allowed_topologies {
    match_label_expressions {
      key    = "topology.kubernetes.io/zone"
      values = [each.key]
    }
  }
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"
}

# Used by kubernetes/helm provider to authenticate to cluster with the AWS IAM identity (using a token)
data "aws_eks_cluster_auth" "cijenkinsio_agents_2" {
  name = module.cijenkinsio_agents_2.cluster_name
}

## Install Cluster Autoscaler
moved {
  from = helm_release.cluster_autoscaler
  to   = helm_release.cijenkinsio_agents_2_cluster_autoscaler
}
resource "helm_release" "cijenkinsio_agents_2_cluster_autoscaler" {
  provider   = helm.cijenkinsio_agents_2
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  # TODO: track with updatecli
  version          = "9.43.2"
  create_namespace = true
  namespace        = local.cijenkinsio_agents_2["autoscaler"]["namespace"]

  values = [
    templatefile("./helm/cluster-autoscaler-values.yaml.tfpl", {
      region             = local.region,
      serviceAccountName = local.cijenkinsio_agents_2["autoscaler"]["serviceaccount"],
      autoscalerRoleArn  = module.cijenkinsio_agents_2_autoscaler_irsa_role.iam_role_arn,
      clusterName        = module.cijenkinsio_agents_2.cluster_name,
      nodeSelectors      = module.cijenkinsio_agents_2.eks_managed_node_groups["applications"].node_group_labels,
      nodeTolerations    = local.cijenkinsio_agents_2["node_groups"]["applications"]["tolerations"],
    })
  ]
}

### Define admin credential to be used in jenkins-infra/kubernetes-management
module "cijenkinsio_agents_2_admin_sa" {
  providers = {
    kubernetes = kubernetes.cijenkinsio_agents_2
  }
  source                     = "./.shared-tools/terraform/modules/kubernetes-admin-sa"
  cluster_name               = module.cijenkinsio_agents_2.cluster_name
  cluster_hostname           = module.cijenkinsio_agents_2.cluster_endpoint
  cluster_ca_certificate_b64 = module.cijenkinsio_agents_2.cluster_certificate_authority_data
}
output "kubeconfig_cijenkinsio_agents_2" {
  sensitive = true
  value     = module.cijenkinsio_agents_2_admin_sa.kubeconfig
}
