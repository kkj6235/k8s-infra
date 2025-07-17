# Create eks cluster

data "aws_caller_identity" "current" {}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 20.37"
  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # EBS 관련 정책 추가
  iam_role_additional_policies = {
    AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    AmazonEC2FullAccess      = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
  }

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      cluster_name = var.cluster_name
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
    aws-efs-csi-driver = {
      most_recent = true
      service_account_role_arn = module.attach_efs_csi_role.iam_role_arn
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
  }
  enable_cluster_creator_admin_permissions = true
  vpc_id                   = aws_vpc.vpc.id
  subnet_ids               = [for s in aws_subnet.private : s.id]

  # EKS Managed Node Group
  eks_managed_node_group_defaults = {
    instance_types = ["t3.medium"]
  }

  eks_managed_node_groups = {
    green = {
      min_size     = 2
      max_size     = 5
      desired_size = 2

      instance_types = ["t3.medium"]
      iam_role_additional_policies = {
        # AWS 관리형 정책 추가
        AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }
    }
  }
}

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.59"

  role_name = "${var.cluster_name}-ebs-csi-controller"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

module "vpc_cni_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.59"

  role_name_prefix      = "VPC-CNI-IRSA"
  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
    common = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }
}

# EFS 파일시스템 및 마운트 타겟 생성

resource "aws_efs_file_system" "stw_node_efs" {
  creation_token = "efs-for-stw-node"

  tags = {
    Name        = "${var.cluster_name}-efs"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# 모든 가용영역에 EFS 마운트 타겟 생성
resource "aws_efs_mount_target" "stw_node_efs_mt" {
  for_each = var.availability_zones

  file_system_id  = aws_efs_file_system.stw_node_efs.id
  subnet_id       = aws_subnet.private[each.key].id
  security_groups = [aws_security_group.allow_nfs.id]
}