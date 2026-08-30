# Architecture Diagrams

The ASCII architecture diagram is maintained in the root `README.md` so it
renders wherever the repository is viewed.

For the project defense, export a diagram from one of:

- **draw.io / diagrams.net** — has an official AWS 2024 icon set
- **Cloudcraft** — 3D AWS diagrams, can import from a live account
- **AWS Perspective** — generates diagrams from actual deployed resources

Recommended set of three:

1. **Network topology** — VPC, AZs, three subnet tiers, route tables, NAT, IGW,
   VPC endpoints.
2. **Request flow** — client → ALB → target group → Fargate task → RDS, with
   security groups annotated on each hop.
3. **CI/CD flow** — developer → PR → checks → OIDC → AWS → apply, showing where
   each gate sits.

Save exports here as `network.png`, `request-flow.png` and `cicd.png`, then
reference them from the root README.
