# terraform aws webserver cluster Module

This Terraform module is creates for a reusable web server cluster on AWS

- Security groups
- Launch template
- Auto Scaling Group
- Application Load Balancer
- Target group
- Listener


### Inputs

- cluster_name
- instance_type
- min_size
- max_size
- server_port
- public_subnet_a_cidr
- public_subnet_b_cidr
- public_subnet_c_cidr
- key_name
- aws_region

### Outputs
- alb_dns_name
- asg_name
- alb_security_group_id
- instance_security_group_id
