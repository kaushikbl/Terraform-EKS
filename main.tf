provider "aws" {
  region = "us-east-2"
}

resource "aws_vpc" "my_eks_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "my-eks-vpc"
  }
}

resource "aws_subnet" "my_eks_subnet" {
  count = 2
  vpc_id                  = aws_vpc.my_eks_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.my_eks_vpc.cidr_block, 8, count.index)
  availability_zone       = element(["us-east-2a", "us-east-2b"], count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "my-eks-subnet-${count.index}"
  }
}

resource "aws_internet_gateway" "my_eks_igw" {
  vpc_id = aws_vpc.my_eks_vpc.id

  tags = {
    Name = "my-eks-igw"
  }
}

resource "aws_route_table" "my_eks_route_table" {
  vpc_id = aws_vpc.my_eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_igw.id
  }

  tags = {
    Name = "my-eks-route-table"
  }
}

resource "aws_route_table_association" "my_eks_association" {
  count          = 2
  subnet_id      = aws_subnet.my_eks_subnet[count.index].id
  route_table_id = aws_route_table.my_eks_route_table.id
}

resource "aws_security_group" "my_eks_cluster_sg" {
  vpc_id = aws_vpc.my_eks_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "my-eks-cluster-sg"
  }
}

resource "aws_security_group" "my_eks_node_sg" {
  vpc_id = aws_vpc.my_eks_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "my-eks-node-sg"
  }
}

resource "aws_eks_cluster" "my_eks" {
  name     = "my-eks-cluster"
  role_arn = aws_iam_role.my_eks_cluster_role.arn

  vpc_config {
    subnet_ids         = aws_subnet.my_eks_subnet[*].id
    security_group_ids = [aws_security_group.my_eks_cluster_sg.id]
  }
}


resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name    = aws_eks_cluster.eks.name
  addon_name      = "aws-ebs-csi-driver"
  
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}


resource "aws_eks_node_group" "my_eks" {
  cluster_name    = aws_eks_cluster.my_eks.name
  node_group_name = "my-eks-node-group"
  node_role_arn   = aws_iam_role.my_eks_node_group_role.arn
  subnet_ids      = aws_subnet.my_eks_subnet[*].id

  scaling_config {
    desired_size = 3
    max_size     = 3
    min_size     = 3
  }

  instance_types = ["t2.medium"]

  remote_access {
    ec2_ssh_key = var.ssh_key_name
    source_security_group_ids = [aws_security_group.my_eks_node_sg.id]
  }
}

resource "aws_iam_role" "my_eks_cluster_role" {
  name = "my_eks-cluster-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "my_eks_cluster_role_policy" {
  role       = aws_iam_role.my_eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "my_eks_node_group_role" {
  name = "my-eks-node-group-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "my_eks_node_group_role_policy" {
  role       = aws_iam_role.my_eks_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "my_eks_node_group_cni_policy" {
  role       = aws_iam_role.my_eks_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "my_eks_node_group_registry_policy" {
  role       = aws_iam_role.my_eks_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "my_eks_node_group_ebs_policy" {
  role       = aws_iam_role.my_eks_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
