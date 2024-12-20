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

  create_cluster_primary_security_group_tags = false

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
      addon_version = "v1.29.10-eksbuild.3"
    }
    # https://github.com/aws/amazon-vpc-cni-k8s/releases
    vpc-cni = {
      # https://docs.aws.amazon.com/cli/latest/reference/eks/describe-addon-versions.html
      # TODO: track with updatecli
      addon_version = "v1.19.0-eksbuild.1"
      configuration_values = jsonencode({
        "tolerations" = local.cijenkinsio_agents_2["node_groups"]["applications"]["tolerations"],
      })
    }
    eks-pod-identity-agent = {
      # https://docs.aws.amazon.com/cli/latest/reference/eks/describe-addon-versions.html
      # TODO: track with updatecli
      addon_version = "v1.3.4-eksbuild.1"
      configuration_values = jsonencode({
        "tolerations" = local.cijenkinsio_agents_2["node_groups"]["applications"]["tolerations"],
      })
    }
    ## https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/CHANGELOG.md
    # aws-ebs-csi-driver = {
    #   # https://docs.aws.amazon.com/cli/latest/reference/eks/describe-addon-versions.html
    #   addon_version = "v1.37.0-eksbuild.1"
    #   # TODO specify service account
    #   # service_account_role_arn = module.cijenkinsio_agents_2_irsa_ebs.iam_role_arn
    # }
    # locals: ebs_account_namespace = "kube-system"
    # locals: ebs_account_name      = "ebs-csi-controller-sa"
  }

  eks_managed_node_groups = {
    # This worker pool is expected to host the "technical" services such as cluster-autoscaler, data cluster-agent, ACP, etc.
    tiny_ondemand_linux = {
      name = "tiny-ondemand-linux"

      instance_types = ["t4g.large"] # 2vcpu 8Gio
      capacity_type  = "ON_DEMAND"
      # Starting on 1.30, AL2023 is the default AMI type for EKS managed node groups
      ami_type     = "AL2023_ARM_64_STANDARD"
      min_size     = 1
      max_size     = 1
      desired_size = 1

      subnet_ids = slice(module.vpc.private_subnets, 1, 2) # Only 1 subnet in 1 AZ (for EBS)

      labels = {
        jenkins = local.ci_jenkins_io["service_fqdn"]
        role    = "applications"
      }
      taints = { for toleration_key, toleration_value in local.cijenkinsio_agents_2["node_groups"]["applications"]["tolerations"] :
        toleration_key => {
          key    = toleration_value["key"],
          value  = toleration_value.value
          effect = local.toleration_taint_effects[toleration_value.effect]
        }
      }
    },
    # This worker pool is expected to host the "technical" services such as cluster-autoscaler, data cluster-agent, ACP, etc.
    applications = {
      name           = local.cijenkinsio_agents_2["node_groups"]["applications"]["name"]
      instance_types = ["t4g.xlarge"]
      capacity_type  = "ON_DEMAND"
      # Starting on 1.30, AL2023 is the default AMI type for EKS managed node groups
      ami_type     = "AL2023_ARM_64_STANDARD"
      min_size     = 1
      max_size     = 3 # Usually 2 nodes, but accept 1 additional surging node
      desired_size = 1

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

module "autoscaler_irsa_role" {
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

# Used by kubernetes/helm provider to authenticate to cluster with the AWS IAM identity (using a token)
data "aws_eks_cluster_auth" "cijenkinsio_agents_2" {
  name = module.cijenkinsio_agents_2.cluster_name
}

### Install Cluster Autoscaler
resource "helm_release" "cluster_autoscaler" {
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
      autoscalerRoleArn  = module.autoscaler_irsa_role.iam_role_arn,
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
