# Create a VPC

resource "aws_vpc" "vpc" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

# Create Public & Private Subnet

resource "aws_subnet" "public" {
  for_each                = var.public_subnet_cidrs
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = each.value
  availability_zone       = var.availability_zones[each.key]
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "public-subnet-${each.key}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
}

resource "aws_subnet" "private" {
  for_each                = var.private_subnet_cidrs
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = each.value
  availability_zone       = var.availability_zones[each.key]
  map_public_ip_on_launch = true
  tags = {
    Name                                        = "private-subnet-${each.key}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}




# Create Internet gateway & Nat gateway

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${var.cluster_name}-igw"
  }
}
resource "aws_nat_gateway" "nat" {
  for_each      = var.availability_zones
  subnet_id     = aws_subnet.public[each.key].id
  allocation_id = aws_eip.nat[each.key].id

  tags = {
    Name = "${var.cluster_name}-nat-${each.key}"
  }
}

resource "aws_eip" "nat" {
  for_each = var.availability_zones
  domain   = "vpc"
  lifecycle {
    create_before_destroy = true
  }
}

# Create Route Table & Route

resource "aws_route_table" "public-rtb" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "${var.cluster_name}-public-rtb"
  }
}

resource "aws_route_table" "private-rtb" {
  for_each = var.private_subnet_cidrs
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[each.key].id
  }
  tags = {
    Name = "${var.cluster_name}-private-rtb-${each.key}"
  }
}

resource "aws_route_table_association" "public-rtb" {
  for_each       = { for k, subnet in aws_subnet.public : k => subnet }
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public-rtb.id
}

resource "aws_route_table_association" "private-rtb" {
  for_each       = { for k, subnet in aws_subnet.private : k => subnet }
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public-rtb.id

}