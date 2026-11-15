# terraform-azurerm-<name>

One or two sentences: what this Terraform module or configuration builds, and who uses it.

| | |
|---|---|
| **Code owners** | `@{{ORGANIZATION}}/{{PLATFORM_OWNERS_TEAM}}`, in [`.github/CODEOWNERS`](.github/CODEOWNERS). A platform owner approves every change |
| **Branch rules** | Set by this repository's `criticality` tier (Settings > Custom properties), from [{{PLATFORM_REPOSITORY}}](https://github.com/{{PLATFORM_REPOSITORY}}) |
| **CI** | `terraform fmt`, `validate` (root, `examples/*`, `modules/*`), tflint, `terraform test` and Checkov: [`.github/workflows/ci.yml`](.github/workflows/ci.yml) |
| **Security** | Report vulnerabilities as the organisation's security policy says, never in an issue |

## What it builds

<!-- The resources, and the design choices worth knowing. -->

## Usage

<!-- A minimal module block, or a link to examples/. -->

## Inputs and outputs

<!-- The variables people set most, and what the outputs are for. -->

## After creating this repository

- [ ] Replace the placeholders in this README
- [ ] Add `versions.tf` (Terraform `>= 1.9`, provider ranges) and the module files
- [ ] Add an example under `examples/` and tests under `tests/` (mocked providers, so CI needs no credentials)
- [ ] Check its description, topics and custom properties
