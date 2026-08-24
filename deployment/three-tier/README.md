# SPX Bank three-tier deployment

This repository deploys three separate tiers in one VPC:

1. **Web EC2 (public subnet):** Nginx and static `/public` assets only.
2. **Application EC2 (public subnet):** Flask/Gunicorn on port `5000`; inbound traffic is restricted to the web EC2 security group.
3. **Amazon RDS MySQL (private DB subnets):** no public access; port `3306` only from the application EC2 security group.

GitHub Actions packages a release into a private S3 deployment bucket, then uses GitHub OIDC and AWS Systems Manager Run Command to deploy the application tier first and the web tier second. This avoids exposing SSH to GitHub-hosted runners.

## Required GitHub configuration

Repository secret:

- `AWS_GITHUB_OIDC_ROLE_ARN`

Repository variables:

- `AWS_REGION` (for example `us-east-1`)
- `DEPLOYMENT_BUCKET` (private, versioned S3 bucket)
- `APP_EC2_INSTANCE_ID`
- `WEB_EC2_INSTANCE_ID`
- `DEPLOY_ENABLED` (`true` only after both servers and RDS are configured)

Both EC2 instances need an instance profile allowing `AmazonSSMManagedInstanceCore` and `s3:GetObject` for the release prefix in the deployment bucket. The GitHub OIDC role needs only `s3:PutObject`, `ssm:SendCommand`, and `ssm:GetCommandInvocation` for these resources.

## Security groups

| Security group | Inbound rule |
|---|---|
| `spx-web-sg` | TCP 80/443 from Internet; TCP 22 only from an administrator IP if SSH is retained. |
| `spx-app-sg` | TCP 5000 from `spx-web-sg` only. |
| `spx-rds-sg` | TCP 3306 from `spx-app-sg` only. |

Do not expose ports `5000` or `3306` to the Internet.

## One-time EC2 configuration

Each instance must have an instance profile containing `AmazonSSMManagedInstanceCore` plus read access to the private deployment S3 bucket. Confirm that both instances appear as **Managed nodes** in AWS Systems Manager before enabling the workflow.

On each EC2 instance, clone this repository, then run the relevant one-step setup script from its checked-out directory. The scripts install the initial release as well as the service configuration.

```bash
git clone https://github.com/Weltsphere-Technologies-Pvt-Ltd/SPX-Banking-Three-Tier-App.git
cd SPX-Banking-Three-Tier-App
```

On the **application EC2**, run:

```bash
sudo bash deployment/three-tier/app/scripts/setup-app-complete.sh
```

The script prompts for the RDS endpoint and master credentials, creates the `spxbank` schema and limited `spxapp` MySQL user, writes the protected `/etc/spx-banking.env` file, and starts Gunicorn. It never prints the supplied secrets.

On the **web EC2**, run:

```bash
sudo bash deployment/three-tier/web/scripts/setup-web-complete.sh spxbank.nextsla.com APP_EC2_PRIVATE_IP
```

This script verifies the web-to-app connection, deploys the static assets, writes the Nginx virtual host, removes the default Nginx site, and reloads an already-running Nginx service.

See [rds/README.md](rds/README.md) for the RDS security and verification checklist. The real environment file and RDS master credentials never go into GitHub.

## Deployment workflow

The `deploy-three-tier.yml` workflow is deliberately disabled until the repository variable `DEPLOY_ENABLED` is set to `true`. A push to `main` then does the following:

1. Creates one release archive, excluding `.env` and Git metadata.
2. Uploads it to the private deployment bucket.
3. Uses short-lived GitHub OIDC credentials to call Systems Manager.
4. Updates the application EC2 first and verifies its local health endpoint.
5. Updates the web EC2 second, serves the static files, and reloads Nginx.

The deployment does not use an SSH private key or open port 22 to GitHub-hosted runners. For internet-facing production traffic, put an Application Load Balancer and HTTPS certificate in front of the web EC2 when you are ready to enable TLS.

