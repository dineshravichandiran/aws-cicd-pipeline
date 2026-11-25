# Branching strategy

Three long-lived branches map to three environments, and each environment has its own pipeline stack.

| Branch | Environment | Pipeline behaviour |
|---|---|---|
| `develop` | dev | every push builds, tests, runs the SonarQube gate and pushes `dev-<sha>` to ECR |
| `release` | stage | same, pushed as `stage-<sha>`; used to check a release candidate |
| `main` | prod | same, then a **manual approval**, then the approved image is re-tagged `release-<sha>` (no rebuild) |

Work flows `feature/*` -> `develop` -> `release` -> `main` through pull requests. The same commit is never rebuilt on the way to
production: the promote step re-tags the image that was already tested.

## Rules to switch on in GitHub (Settings -> Branches)
These are repository settings, not code, so they are not enforced by this repo until you turn them on:
- `main`, `release`, `develop`: require a pull request, require the `ci` checks (`test`, `templates`) to pass, block force-pushes.
- `main`: require one review.
- Hotfixes: branch from `main`, merge to `main` first, then back-merge to `develop`.

## Why this shape
- Small feature branches keep each change reviewable and the `ci` run short.
- One pipeline per environment means a stage or prod problem cannot stop dev work.
- Immutable ECR tags (`<env>-<sha>`) make every deployed image traceable to one commit.
