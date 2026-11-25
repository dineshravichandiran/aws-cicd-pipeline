# AWS CI/CD Pipeline: CodePipeline, CodeBuild, SonarQube, ECR and CloudFront

![ci](https://github.com/dineshravichandiran/aws-cicd-pipeline/actions/workflows/ci.yml/badge.svg)

A small, complete delivery pipeline on AWS, defined entirely in CloudFormation: a push to a branch is built and tested with Maven,
checked against a SonarQube quality gate, packaged as a Docker image and pushed to ECR. Production adds a manual approval and a
no-rebuild promote step. A second template serves a static site from a private S3 bucket through CloudFront.

| | |
|---|---|
| Built with | AWS CodePipeline, CodeBuild, ECR, S3, CloudFront, CloudFormation, IAM, Maven, JUnit 5, JaCoCo, SonarQube, Docker, GitHub Actions |
| App | a tiny Java 17 HTTP service (`/health`, `/greet`) with unit and HTTP tests; it exists only to give the pipeline something real to build |
| Environments | `dev`, `stage`, `prod`: one stack each, mapped to `develop`, `release`, `main` (see [docs/BRANCHING.md](docs/BRANCHING.md)) |
| Status | **`dev` deployed and run once in my own AWS account (ap-south-1), then torn down**; the SonarQube gate, `stage` and the `prod` approval and promote were not run on AWS (details below) |

## How it flows
```mermaid
flowchart LR
  gh[GitHub branch] -->|CodeConnections| src[Source]
  src --> build[CodeBuild: mvn verify, SonarQube gate, docker build]
  build -->|push env-sha| ecr[(ECR, immutable tags, scan on push)]
  build --> appr{prod only: manual approval}
  appr --> promote[CodeBuild: re-tag release-sha]
  promote --> ecr
  site[site/ files] --> s3[(private S3)] --> cf[CloudFront, OAC, HTTPS only]
```

## What is in the repo
| Path | What it does |
|---|---|
| `app/` | Java app, Maven build with JaCoCo coverage, Dockerfile (non-root user) |
| `buildspec.yml`, `buildspec-promote.yml` | CodeBuild steps: test, quality gate, build and push; approved-image re-tag |
| `cloudformation/pipeline.yml` | ECR repo, artifact bucket, CodeBuild projects, CodePipeline, least-privilege IAM roles |
| `cloudformation/static-site.yml` | private S3 + CloudFront with origin access control, security headers, access logs |
| `sonarqube/docker-compose.yml` | local SonarQube Community for trying the gate |
| `.github/workflows/ci.yml` | runs the Maven tests, `cfn-lint` and `checkov` on every push and pull request |
| `scripts/deploy.sh`, `scripts/destroy.sh` | deploy one environment, and tear it down with a leftover check |

## Design choices
- **IAM is scoped, not broad.** CodeBuild can push only to its own ECR repository, write only to its artifact bucket and read only the one Sonar token secret.
- **Images are immutable and traceable.** Tags are `<env>-<commit>`; ECR scans on push; a lifecycle rule keeps the last 20.
- **Production is not rebuilt.** The approved image is re-tagged, so what was tested is what ships.
- **The static site bucket is never public.** Only the CloudFront distribution can read it, and plain HTTP is denied.
- **Secrets stay out of Git.** The SonarQube token lives in Secrets Manager and CodeBuild reads it at run time.

## What was and was not checked
Done in this repository:
- `cfn-lint` on both templates: passes.
- `checkov` on both templates: 53 passed, 0 failed, 5 skipped. Each skip is written next to the resource with its reason (no WAF on a static demo, default CloudFront certificate cannot enforce a TLS minimum, no access logs on short-lived artifacts or on the log bucket itself, no customer-managed KMS key for build logs).
- The Java code compiles, and the greeting logic and both HTTP endpoints were exercised by hand against a running instance.
- The shell scripts pass `bash -n` (syntax only).

**Run for real on AWS (`dev`, 26 Nov 2026, commit `18e0a7d`):**
- `scripts/deploy.sh dev` created both stacks, `greeter-pipeline-dev` and `greeter-site-dev`, and both reached `CREATE_COMPLETE`.
- The `greeter-dev` pipeline ran Source and BuildAndTest to green. The CodeBuild run took about a minute and its unit-test report shows 6 of 6 tests passed.
- The build pushed an image tagged `dev-18e0a7d6` to the ECR repository, and the CloudFront URL served the static site.
- `scripts/destroy.sh dev` then removed both stacks, and its leftover check for the pipeline, ECR repository and CloudFront distribution came back empty.

**Not run on AWS:**
- The SonarQube quality gate. `SONAR_HOST_URL` was left empty, so the build skipped that step by design. The same gate was run locally in [jenkins-maven-docker-pipeline](https://github.com/dineshravichandiran/jenkins-maven-docker-pipeline).
- The `stage` and `prod` environments, the `prod` manual approval and the no-rebuild promote step.
- A custom domain with Route 53 and ACM. The site uses the default CloudFront domain and certificate.
- The branch-protection rules in `docs/BRANCHING.md` are a recommendation, not something this repo enforces.
- The Maven/JUnit suite also runs in the GitHub Actions `test` job and passes there. I could not run it on my own machine while building, because Maven Central was unreachable from that environment.

## Run it on your own account
Cost is small but not zero: CodePipeline V2 bills per action-minute after the free allowance, CodeBuild bills per build minute, CloudFront and S3 cost cents for a demo, and ECR charges for stored images. Set a budget alarm first, and run `scripts/destroy.sh` when done.
1. In the AWS console create a GitHub connection (Developer Tools -> Settings -> Connections) and authorize it; copy its ARN.
2. Optional SonarQube: `docker compose -f sonarqube/docker-compose.yml up -d`, create a token, store it in Secrets Manager, and pass its URL and the secret ARN to the script. A SonarQube running on your laptop is not reachable from CodeBuild, so use a hosted or EC2-hosted server for a cloud run, or leave Sonar empty to skip the gate.
3. `scripts/deploy.sh dev <connection-arn>`; push to `develop`; watch the pipeline run.
4. `scripts/destroy.sh dev`.
