# Define a KMS main key to encrypt the EKS cluster
resource "aws_kms_key" "cijenkinsio-agents-2" {
  description         = "EKS Secret Encryption Key for the cluster cijenkinsio-agents-2"
  enable_key_rotation = true

  tags = merge(local.common_tags, {
    associated_service = "eks/cijenkinsio-agents-2"
  })
}

# EKS Cluster definition
module "cijenkinsio-agents-2" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.26.1"

  cluster_name = "cijenkinsio-agents-2"
  # Kubernetes version in format '<MINOR>.<MINOR>', as per https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
  cluster_version = "1.29"
  create_iam_role = true

  # 2 AZs are mandatory for EKS https://docs.aws.amazon.com/eks/latest/userguide/network-reqs.html#network-requirements-subnets
  subnet_ids = slice(module.vpc.private_subnets, 2, 3)
  # Required to allow EKS service accounts to authenticate to AWS API through OIDC (and assume IAM roles)
  # useful for autoscaler, EKS addons and any AWS APi usage
  enable_irsa = true

  # Allow the terraform CI IAM user to be co-owner of the cluster
  enable_cluster_creator_admin_permissions = true

  # avoid using config map to specify admin accesses (decrease attack surface)
  authentication_mode = "API"

  create_kms_key = false
  cluster_encryption_config = {
    provider_key_arn = aws_kms_key.cijenkinsio-agents-2.arn
    resources        = ["secrets"]
  }

  cluster_endpoint_public_access = true
  cluster_endpoint_public_access_cidrs = [
    "20.122.14.108/32",   # curl --silent --location https://reports.jenkins.io/jenkins-infra-data-reports/azure-net.json | jq -r '."infracijenkinsioagents1.jenkins.io"' ip1
    "20.186.70.154/32",   # curl --silent --location https://reports.jenkins.io/jenkins-infra-data-reports/azure-net.json | jq -r '."infracijenkinsioagents1.jenkins.io"' ip2
    "172.176.126.194/32", # VPN TODO export VPN outbound ip to https://reports.jenkins.io/jenkins-infra-data-reports/azure-net.json (https://github.com/jenkins-infra/azure-net/blob/518a250bb7d7f76f0b6b8c90b8f362a686253853/vpn.tf#L118C11-L118C40)
  ]

  create_cluster_primary_security_group_tags = false

  # Do not use interpolated values from `local` in either keys and values of provided tags (or `cluster_tags)
  # To avoid having and implicit dependency to a resource not available when parsing the module (infamous errror `Error: Invalid for_each argument`)
  # Ref. same error as having a `depends_on` in https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2337
  tags = merge(local.common_tags, {
    Environment = "jenkins-infra-${terraform.workspace}"
    GithubRepo  = "terraform-aws-sponsorship"
    GithubOrg   = "jenkins-infra"

    associated_service = "eks/cijenkinsio-agents-2"
  })

  # VPC is defined in vpc.tf
  vpc_id = module.vpc.vpc_id

  ## Manage EKS addons with module - https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon
  # See new versions with `aws eks describe-addon-versions --kubernetes-version <k8s-version> --addon-name <addon>`
  cluster_addons = {
    # https://github.com/coredns/coredns/releases
    coredns = {
      addon_version = "v1.11.3-eksbuild.1"
    }
    # Kube-proxy on an Amazon EKS cluster has the same compatibility and skew policy as Kubernetes
    # See https://kubernetes.io/releases/version-skew-policy/#kube-proxy
    kube-proxy = {
      addon_version = "v1.29.7-eksbuild.9"
    }
    # https://github.com/aws/amazon-vpc-cni-k8s/releases
    vpc-cni = {
      addon_version = "v1.18.5-eksbuild.1"
    }
    # https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/CHANGELOG.md
    aws-ebs-csi-driver = {
      addon_version = "v1.36.0-eksbuild.1"
      # TODO specify service account
      # service_account_role_arn = module.cijenkinsio-agents-2_irsa_ebs.iam_role_arn
    }
  }

  eks_managed_node_groups = {
    tiny_ondemand_linux = {
      # This worker pool is expected to host the "technical" services such as pod autoscaler, etc.
      name = "tiny-ondemand-linux"
      # role is create within terraform-states
      create_iam_role = false
      iam_role_arn    = "arn:aws:iam::326712726440:role/cijio-agents-2-np-tiny-ondemand-linux"

      instance_types       = ["t3a.xlarge"] # 2vcpu 8Gio
      capacity_type        = "ON_DEMAND"
      min_size             = 1
      max_size             = 2 # Allow manual scaling when running operations or upgrades
      desired_size         = 1
      bootstrap_extra_args = "--kubelet-extra-args '--node-labels=node.kubernetes.io/lifecycle=normal'"
      suspended_processes  = ["AZRebalance"]
      tags = merge(local.common_tags, {
        "k8s.io/cluster-autoscaler/enabled" = false # No autoscaling for these 2 machines
      }),
      attach_cluster_primary_security_group = true
    },



    # # This list of worker pool is aimed at mixed spot instances type, to ensure that we always get the most available (e.g. the cheaper) spot size
    # # as per https://aws.amazon.com/blogs/compute/cost-optimization-and-resilience-eks-with-spot-instances/
    # # Pricing table for 2023: https://docs.google.com/spreadsheets/d/1_C0I0jE-X0e0vDcdKOFIWcnwpOqWC8RQ4YOCgXNnplY/edit?usp=sharing
    # spot_linux_4xlarge = {
    #   # 4xlarge: Instances supporting 3 pods (limited to 4 vCPUs/8 Gb) each with 1 vCPU/1Gb margin
    #   name          = "spot-linux-4xlarge"
    #   capacity_type = "SPOT"
    #   # Less than 5% eviction rate, cost below $0.08 per pod per hour
    #   instance_types = [
    #     "c5.4xlarge",
    #     "c5a.4xlarge"
    #   ]
    #   block_device_mappings = {
    #     xvda = {
    #       device_name = "/dev/xvda"
    #       ebs = {
    #         volume_size           = 90 # With 3 pods / machine, that can use ~30 Gb each at the same time (`emptyDir`)
    #         volume_type           = "gp3"
    #         iops                  = 3000 # Max included with gp3 without additional cost
    #         throughput            = 125  # Max included with gp3 without additional cost
    #         encrypted             = false
    #         delete_on_termination = true
    #       }
    #     }
    #   }
    #   spot_instance_pools      = 3              # Amount of different instance that we can use depends on spot_allocation_strategy = lowest-price
    #   spot_allocation_strategy = "lowest-price" # depends on spot_instance_pools
    #   min_size                 = 0
    #   max_size                 = 50
    #   desired_size             = 0
    #   kubelet_extra_args       = "--node-labels=node.kubernetes.io/lifecycle=spot"
    #   tags = merge(local.common_tags, {
    #     "k8s.io/cluster-autoscaler/enabled"              = true,
    #     "k8s.io/cluster-autoscaler/cijenkinsio-agents-2" = "owned",
    #     "ci.jenkins.io/agents-density"                   = 3,
    #   })
    #   attach_cluster_primary_security_group = true
    #   labels = {
    #     "ci.jenkins.io/agents-density" = 3,
    #   }
    # },
    # # This list of worker pool is aimed at mixed spot instances type, to ensure that we always get the most available (e.g. the cheaper) spot size
    # # as per https://aws.amazon.com/blogs/compute/cost-optimization-and-resilience-eks-with-spot-instances/
    # # Pricing table for 2023: https://docs.google.com/spreadsheets/d/1_C0I0jE-X0e0vDcdKOFIWcnwpOqWC8RQ4YOCgXNnplY/edit?usp=sharing
    # spot_linux_4xlarge_bom = {
    #   # 4xlarge: Instances supporting 3 pods (limited to 4 vCPUs/8 Gb) each with 1 vCPU/1Gb margin
    #   name          = "spot-linux-4xlarge-bom"
    #   capacity_type = "SPOT"
    #   # Less than 5% eviction rate, cost below $0.08 per pod per hour
    #   instance_types = [
    #     "c5.4xlarge",
    #     "c5a.4xlarge"
    #   ]
    #   block_device_mappings = {
    #     xvda = {
    #       device_name = "/dev/xvda"
    #       ebs = {
    #         volume_size           = 90 # With 3 pods / machine, that can use ~30 Gb each at the same time (`emptyDir`)
    #         volume_type           = "gp3"
    #         iops                  = 3000 # Max included with gp3 without additional cost
    #         throughput            = 125  # Max included with gp3 without additional cost
    #         encrypted             = false
    #         delete_on_termination = true
    #       }
    #     }
    #   }
    #   spot_instance_pools = 3 # Amount of different instance that we can use
    #   min_size            = 0
    #   max_size            = 50
    #   desired_size        = 0
    #   kubelet_extra_args  = "--node-labels=node.kubernetes.io/lifecycle=spot"
    #   tags = merge(local.common_tags, {
    #     "k8s.io/cluster-autoscaler/enabled"              = true,
    #     "k8s.io/cluster-autoscaler/cijenkinsio-agents-2" = "owned",
    #     "ci.jenkins.io/agents-density"                   = 3,
    #   })
    #   attach_cluster_primary_security_group = true
    #   labels = {
    #     "ci.jenkins.io/agents-density" = 3,
    #     "ci.jenkins.io/bom"            = true,
    #   }
    #   taints = [
    #     {
    #       key    = "ci.jenkins.io/bom"
    #       value  = "true"
    #       effect = "NO_SCHEDULE"
    #     }
    #   ]
    # },
    # spot_linux_24xlarge_bom = {
    #   # 24xlarge: Instances supporting 23 pods (limited to 4 vCPUs/8 Gb) each with 1 vCPU/1Gb margin
    #   name          = "spot-linux-24xlarge"
    #   capacity_type = "SPOT"
    #   # Less than 5% eviction rate, cost below $0.05 per pod per hour
    #   instance_types = [
    #     "m5.24xlarge",
    #     "c5.24xlarge",
    #   ]
    #   block_device_mappings = {
    #     xvda = {
    #       device_name = "/dev/xvda"
    #       ebs = {
    #         volume_size           = 575 # With 23 pods / machine, that can use ~25 Gb each at the same time (`emptyDir`)
    #         volume_type           = "gp3"
    #         iops                  = 3000 # Max included with gp3 without additional cost
    #         throughput            = 125  # Max included with gp3 without additional cost
    #         encrypted             = false
    #         delete_on_termination = true
    #       }
    #     }
    #   }
    #   spot_instance_pools = 2 # Amount of different instance that we can use
    #   min_size            = 0
    #   max_size            = 15
    #   desired_size        = 0
    #   kubelet_extra_args  = "--node-labels=node.kubernetes.io/lifecycle=spot"
    #   tags = merge(local.common_tags, {
    #     "k8s.io/cluster-autoscaler/enabled"              = true,
    #     "k8s.io/cluster-autoscaler/cijenkinsio-agents-2" = "owned",
    #   })
    #   attach_cluster_primary_security_group = true
    #   labels = {
    #     "ci.jenkins.io/agents-density" = 23,
    #   }
    #   taints = [
    #     {
    #       key    = "ci.jenkins.io/bom"
    #       value  = "true"
    #       effect = "NO_SCHEDULE"
    #     }
    #   ]
    # },
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

# module "cijenkinsio-agents-2_iam_role_autoscaler" {
#   source                        = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
#   version                       = "v5.47.1"
#   create_role                   = true
#   role_name                     = "${local.autoscaler_account_name}-cijenkinsio-agents-2"
#   provider_url                  = replace(module.cijenkinsio-agents-2.cluster_oidc_issuer_url, "https://", "")
#   role_policy_arns              = [aws_iam_policy.cluster_autoscaler_cijenkinsio-agents-2.arn]
#   oidc_fully_qualified_subjects = ["system:serviceaccount:${local.autoscaler_account_namespace}:${local.autoscaler_account_name}"]

#   tags = merge(local.common_tags, {
#     associated_service = "eks/${module.cijenkinsio-agents-2.cluster_name}"
#   })
# }

# module "cijenkinsio-agents-2_irsa_ebs" {
#   source                        = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
#   version                       = "v5.47.1"
#   create_role                   = true
#   role_name                     = "${local.ebs_account_name}-cijenkinsio-agents-2"
#   provider_url                  = replace(module.cijenkinsio-agents-2.cluster_oidc_issuer_url, "https://", "")
#   role_policy_arns              = [aws_iam_policy.ebs_csi.arn]
#   oidc_fully_qualified_subjects = ["system:serviceaccount:${local.ebs_account_namespace}:${local.ebs_account_name}"]

#   tags = merge(local.common_tags, {
#     associated_service = "eks/${module.cijenkinsio-agents-2.cluster_name}"
#   })
# }

# # Configure the jenkins-infra/kubernetes-management admin service account
# module "cijenkinsio-agents-2_admin_sa" {
#   providers = {
#     kubernetes = kubernetes.cijenkinsio-agents-2
#   }
#   source                     = "./.shared-tools/terraform/modules/kubernetes-admin-sa"
#   cluster_name               = module.cijenkinsio-agents-2.cluster_name
#   cluster_hostname           = module.cijenkinsio-agents-2.cluster_endpoint
#   cluster_ca_certificate_b64 = module.cijenkinsio-agents-2.cluster_certificate_authority_data
#   svcaccount_admin_name      = "ciadmin"
# }

# output "kubeconfig_cijenkinsio-agents-2" {
#   sensitive = true
#   value     = module.cijenkinsio-agents-2_admin_sa.kubeconfig
# }

# data "aws_eks_cluster" "cijenkinsio-agents-2" {
#   name = module.cijenkinsio-agents-2.cluster_name
# }

# data "aws_eks_cluster_auth" "cijenkinsio-agents-2" {
#   name = module.cijenkinsio-agents-2.cluster_name
# }

# ## No restriction on the resources: either managed outside terraform, or already scoped by conditions
# #trivy:ignore:aws-iam-no-policy-wildcards
# data "aws_iam_policy_document" "cluster_autoscaler_cijenkinsio-agents-2" {
#   # Statements as per https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md#full-cluster-autoscaler-features-policy-recommended
#   statement {
#     sid    = "unrestricted"
#     effect = "Allow"

#     actions = [
#       "autoscaling:DescribeAutoScalingGroups",
#       "autoscaling:DescribeAutoScalingInstances",
#       "autoscaling:DescribeLaunchConfigurations",
#       "autoscaling:DescribeScalingActivities",
#       "autoscaling:DescribeTags",
#       "ec2:DescribeInstanceTypes",
#       "ec2:DescribeLaunchTemplateVersions"
#     ]

#     resources = ["*"]
#   }

#   statement {
#     sid    = "restricted"
#     effect = "Allow"

#     actions = [
#       "autoscaling:SetDesiredCapacity",
#       "autoscaling:TerminateInstanceInAutoScalingGroup",
#       "ec2:DescribeImages",
#       "ec2:GetInstanceTypesFromInstanceRequirements",
#       "eks:DescribeNodegroup"
#     ]

#     resources = ["*"]
#   }
# }

# resource "aws_iam_policy" "cluster_autoscaler_cijenkinsio-agents-2" {
#   name_prefix = "cluster-autoscaler-cijenkinsio-agents-2"
#   description = "EKS cluster-autoscaler policy for cluster ${module.cijenkinsio-agents-2.cluster_name}"
#   policy      = data.aws_iam_policy_document.cluster_autoscaler_cijenkinsio-agents-2.json
# }
