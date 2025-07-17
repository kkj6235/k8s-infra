# EC2 인스턴스용 IAM 역할
# EC2 인스턴스가 AWS 서비스에 접근할 수 있도록 하는 IAM 역할을 생성합니다.

resource "aws_iam_role" "ec2_role" {
  # IAM 역할 이름
  name = "cwave_ec2_role"

  # 신뢰 관계 정책 (Trust Policy)
  # EC2 인스턴스가 이 역할을 수임(assume)할 수 있도록 허용
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"  # 역할 수임 권한
        Effect = "Allow"           # 허용
        Sid    = ""               # 정책 ID (선택사항)
        Principal = {
          Service = "ec2.amazonaws.com"  # EC2 서비스만 이 역할을 수임 가능
        }
      }
    ]
  })
}

# ECR PowerUser 정책 연결
resource "aws_iam_role_policy_attachment" "ecr_poweruser" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

# IAM Policy 설정

data "http" "iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.6.2/docs/install/iam_policy.json"
}

resource "aws_iam_role_policy" "cwave-eks-controller" {
  name_prefix = "AWSLoadBalancerControllerIAMPolicy"
  role        = module.lb_controller_role.iam_role_name
  policy      = data.http.iam_policy.response_body
}

# EKS Namespace IAM Roles
resource "aws_iam_role" "eks_namespace_role" {
  for_each = var.eks_namespace_roles

  name = "eks-namespace-${each.value.name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = each.value.environment
    ManagedBy   = "terraform"
  }
}

# Attach basic policies to namespace roles
resource "aws_iam_role_policy_attachment" "eks_namespace_policy" {
  for_each = var.eks_namespace_roles

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_namespace_role[each.key].name
}

# Attach additional policies if specified
resource "aws_iam_role_policy_attachment" "eks_namespace_additional_policies" {
  for_each = {
    for policy in flatten([
      for ns_key, ns in var.eks_namespace_roles : [
        for policy in ns.additional_policies : {
          ns_key = ns_key
          policy = policy
        }
      ]
    ]) : "${policy.ns_key}-${policy.policy}" => policy
  }

  policy_arn = each.value.policy
  role       = aws_iam_role.eks_namespace_role[each.value.ns_key].name
}

# EFS role 설정

module "attach_efs_csi_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name             = "efs-csi"
  attach_efs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:efs-csi-controller-sa"]
    }
  }
}