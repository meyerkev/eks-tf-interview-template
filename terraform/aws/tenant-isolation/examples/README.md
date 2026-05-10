# Examples

Three escalating examples that show different aspects of the module.
Each one is independently `terraform init` + `terraform validate`-able
and is referenced from the design-decisions table in the parent README.

| Example | What it demonstrates | Read this if you want to see... |
|---|---|---|
| [`basic/`](basic/) | Minimum viable usage. One tenant, defaults everywhere. | The smallest possible call site - what's required vs optional. |
| [`multi-tenant/`](multi-tenant/) | `for_each` over a map of tenants with mixed CIDRs and `connectivity` modes (one tenant in `isolated` mode, two in `egress_only`). | The actual deployment shape for a SaaS platform. The reusability story. |
| [`with-workload/`](with-workload/) | The producer/consumer contract in code: provisions a tenant AND a sample IAM role that correctly attaches the boundary + applies the required tags. | The producer/consumer contract turned into something concrete. The role's identity policy grants `*:*` deliberately to make the punch line obvious - the boundary still caps the effective set. |

None of these are intended to `terraform apply`. They exist to show
*how the module is invoked*, not to provision real infrastructure.

## Verifying without applying

```bash
cd examples/<name>
terraform init -backend=false
terraform validate
```
