# VPC Module

Three-tier VPC spanning multiple Availability Zones.

| Tier | Contains | Internet access |
|---|---|---|
| Public | ALB, NAT Gateway | inbound + outbound via IGW |
| Private application | ECS Fargate tasks | outbound only, via NAT |
| Private data | RDS | **none in either direction** |

## Design notes

**A subnet lives in exactly one AZ and cannot span AZs.** That is why there is
one subnet per tier per AZ. Spreading across AZs is what makes the architecture
survive the loss of a datacentre.

**The data tier has no default route.** Its route table contains only the
implicit local VPC route. This is the strongest network posture available for a
database: it cannot be reached from the internet and cannot reach out.

**One route table per private-app AZ**, not one shared table. Each AZ points at
its own NAT Gateway when `single_nat_gateway = false`, which both preserves
availability and avoids cross-AZ data transfer charges.

**`enable_dns_support` and `enable_dns_hostnames` are both required** for
interface endpoint private DNS. Without them the AWS service hostname resolves
to a public IP and traffic silently leaves via NAT.

## VPC endpoints

Gateway endpoints (S3, DynamoDB) are always created — they are free and are
route-table entries rather than ENIs.

Interface endpoints are optional (`enable_interface_endpoints`) because they
cost roughly $7/month per endpoint per AZ. Created: ECR API, ECR Docker,
Secrets Manager, CloudWatch Logs, STS, SSM, SSM Messages.

**Both matter for container image pulls.** ECS calls the ECR API for the token
and manifest, then downloads image layers from S3. Omitting the S3 gateway
endpoint means pulls still traverse NAT.

## Cost

The NAT Gateway dominates: ~$33/month each plus ~$0.045/GB processed. Use
`single_nat_gateway = true` in non-production.

## Inputs / Outputs

Generate the full table with `terraform-docs markdown table --output-file README.md modules/vpc`.
