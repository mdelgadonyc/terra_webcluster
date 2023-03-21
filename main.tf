provider "aws" {
    region = "us-east-2"
}

resource "aws_launch_configuration" "lconfig_example" {
    image_id            = "ami-0fb653ca2d3203ac1"
    instance_type       = "t2.micro"
    security_groups     = [aws_security_group.sg_webserve.id]

    user_data = <<-EOF
                #!/bin/bash
                echo "Hello world!" > index.html
                nohup busybox httpd -f -p ${var.server_port} &
                EOF

    # Required when using a launch configuration with an auto scaling group.
    lifecycle {
        create_before_destroy = true
    }
}

resource "aws_autoscaling_group" "asg_example" {
    launch_configuration    = aws_launch_configuration.lconfig_example.name
    vpc_zone_identifier     = data.aws_subnets.subnets_default.ids

    target_group_arns = [aws_lb_target_group.tg_asg.arn]
    health_check_type = "ELB"

    min_size = 2
    max_size = 10

    tag {
        key                 = "Name"
        value               = "terraform-asg-example"
        propagate_at_launch = true
    }
}

resource "aws_lb" "lb_example" {
    name                = "terraform-asg-example"
    load_balancer_type  = "application"
    subnets             = data.aws_subnets.subnets_default.ids
    security_groups     = [aws_security_group.sg_alb.id]
}

resource "aws_lb_listener" "http-listen" {
    load_balancer_arn   = aws_lb.lb_example.arn
    port                = 80
    protocol            = "HTTP"

    #By default, return a simple 404 page
    default_action {
        type = "fixed-response"
    
        fixed_response {
            content_type = "text/plain"
            message_body = "404: page not found"
            status_code = 404
        }
    }
}

resource "aws_lb_listener_rule" "listen-rule-asg" {
    listener_arn    = aws_lb_listener.http-listen.arn
    priority        = 100

    condition {
        path_pattern {
            values = ["*"]
        }
    }

    action {
        type                = "forward"
        target_group_arn    = aws_lb_target_group.tg_asg.arn
    }
}
resource "aws_lb_target_group" "tg_asg" {
    name        = "terraform-asg-example"
    port        = var.server_port
    protocol    = "HTTP"
    vpc_id      = data.aws_vpc.vpc_default.id

    health_check {
        path                        = "/"
        protocol                    = "HTTP"
        matcher                     = "200"
        interval                    = 15
        timeout                     = 3
        healthy_threshold           = 2
        unhealthy_threshold         = 2
    }
}

resource "aws_security_group" "sg_webserve" {
    name = "terraform-example-instance"

    ingress {
        from_port       = var.server_port
        to_port         = var.server_port
        protocol        = "tcp"
        #cidr_blocks     = [var.source_ip]
        cidr_blocks     = ["0.0.0.0/0"]
    }
}
resource "aws_security_group" "sg_alb" {
    name = "terraform-example-alb"

    # Allow inbound HTTP requests
    ingress {
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
        #cidr_blocks = [var.source_ip]
    }

    # Allow all outbound requests
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

data "aws_vpc" "vpc_default" {
    default = true
}

data "aws_subnets" "subnets_default" {
    filter {
        name        = "vpc-id"
        values      = [data.aws_vpc.vpc_default.id]
    }
}

variable "server_port" {
    description = "The port the server will use for HTTP requests"
    type        = number
}

variable "source_ip" {
    description = "Allowed source IP for HTTP requests"
    type        = string
}

output "alb_dns_name" {
    value       = aws_lb.lb_example.dns_name
    description = "The domain name of the load balancer"
}