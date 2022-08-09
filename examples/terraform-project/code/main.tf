# creates ecs cluster

resource "aws_ecs_cluster" "ecs_cluster" {
  name = "${var.name}-ecs-cluster"
  tags = var.tags
}

# Creates VPC

data "aws_availability_zones" "zones" {
}

# https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = ">=3.14.0"
  name = "${var.name}-vpc"
  
  cidr = "10.0.0.0/16"

  private_subnets         = ["10.0.1.0/24"]
  public_subnets          = ["10.0.101.0/24"]
  map_public_ip_on_launch = false

  azs = length(var.ecs_vpc_region_azs) > 0 ? var.ecs_vpc_region_azs : [
    data.aws_availability_zones.zones.names[0],
    data.aws_availability_zones.zones.names[1]
  ]

  enable_dns_hostnames = true
  enable_dns_support   = true
  enable_nat_gateway   = true
  enable_vpn_gateway   = false

  tags = var.tags
}

# imports aws region

data "aws_region" "current" {}

# creates ecs service

resource "aws_ecs_service" "service" {
  name            = "${var.name}-ecs-service"
  cluster         = var.ecs_cluster_name
  desired_count   = var.service_desired_count
  launch_type     = "FARGATE"
  task_definition = aws_ecs_task_definition.task_definition.arn
  tags            = var.tags

  network_configuration {
    subnets          = var.ecs_vpc_subnets_private_ids
    assign_public_ip = false
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
  
}

# Task definition for deploying image in container

resource "aws_ecs_task_definition" "task_definition" {
  family                   = "${var.name}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.execution.arn
  # ARN of the task execution role that the Amazon ECS container agent and the Docker daemon can assume
  task_role_arn = local.ecs_task_role_arn
  # ARN of IAM role that allows your Amazon ECS container task to make calls to other AWS services.
  cpu    = var.container_cpu
  memory = var.container_memory

  container_definitions = jsonencode([
    {
      name        = "${var.name}-container"
      image       = var.image
      essential   = true
      command     = ["-mode", var.mode, "-mgmt-console-url", var.mgmt-console-url, "-mgmt-console-port", var.mgmt-console-port, "-deepfence-key", var.deepfence-key]
   
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.log.id
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "ecs"
        }
      }
    },

  ])
  tags = var.tags
}




