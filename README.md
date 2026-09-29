# Great Family (GFAM)

The approved brief is “Hello.we are the great family” and gives connected wallets
one action: **Swap**. This contribution implements the launch token for the
protocol's factory-provided pool. It uses the supported token-only launch shape:
`LaunchToken` plus an empty application-contract list. There is no separate
project AMM, router, vault, lottery, or custody contract.

The brief does not specify a formal token name or ticker, so this implementation
uses **Great Family / GFAM**. Swap execution, quotes, native ETH handling and
liquidity are responsibilities of the protocol pool/router and the later frontend
integration. The token itself implements ERC-20 transfers and allowances, not a
`swap()` method. Those external protocol implementations and deployed addresses
were not supplied and are not represented as locally verified.

## Delivered contract

| Parameter | Value |
| --- | --- |
| Source and artifact | `src/LaunchToken.sol:LaunchToken` |
| Constructor | Nonpayable, no arguments |
| Name / symbol | `Great Family` / `GFAM` |
| Decimals | `18` |
| Fixed total supply | `1000000000000000000000000000` minor units (1 billion GFAM) |
| Initial recipient | Constructor `msg.sender`, i.e. ProjectFactory on a protocol launch |
| Administrative roles | None |
| Application contracts | None; manifest `contracts` is `[]` |

All supply is minted once during construction. There is no public mint, burn,
owner, pause, blocklist, fee, upgrade, initialization or rescue function. The
factory is the initial holder, not an administrator. Transfers do not invoke
recipient callbacks and move exactly the requested amount. No token approval is
created by the constructor. OpenZeppelin ERC-20 v5.0.2 supplies the standard
implementation, vendored as ordinary files with its license.

## Local checks

Install Foundry and make Solidity **0.8.26** available in its normal compiler
cache. All Solidity source dependencies are included under `lib/`; no package
installation, submodule, RPC URL, private key, environment configuration, FFI or
Solidity filesystem access is needed. The compiler is version-pinned in
`foundry.toml`; no compiler binary is part of this deliverable.

```sh
forge build
forge test
forge fmt --check
python3 scripts/export_abi.py --check
```

The tests cover exact supply and metadata, constructor mint events, factory
CREATE2 deployment, successful and failed transfers, self/zero transfers,
approvals and revocation, delegated spending, settlement rollback, rejection of
common administrative selectors, ETH rejection and runtime opcode/size limits.
Two fuzz properties run 512 cases each. A stateful invariant runs 128 sequences
of 64 operations, comparing all balances and allowances for four actors against
an independent model and checking supply conservation after each operation.

The factory and spender probes in tests check local deployment and token
settlement behavior only. They do not implement a production factory, exchange,
price model or liquidity pool. No fork tests or live pool swaps are claimed.
Slither and Mythril were not run. Local tests are not an independent audit; the
stage's separate reviewer must inspect accepted source and the generated manifest
before release.

## ABI and handoff

- [ABI JSON](docs/abi/LaunchToken.json) is the compiler-generated ABI array.
- [ABI documentation](docs/abi/README.md) describes calls, errors and events.
- [Deployment and swap integration](docs/DEPLOYMENT.md) records parameters,
  assumptions, responsibilities and remaining service configuration.
- [Dependency provenance](lib/README.md) records versions and archive hashes.

Regenerate the ABI after source changes with `python3 scripts/export_abi.py`.
`--check` compares it with the pinned compiler output without changing the export.
The script uses only Python's standard library and the local `forge` executable.

This is the source-producing assignment. The separate manifest assignment writes
`launch.json`; the independent review examines source and that manifest. Services
publish to GitHub, link signed artifacts and policy, attest, admit and deploy,
then publish/start the frontend on IPFS. These later outcomes are not prerequisites
for compiling and reviewing this contribution. No transactions are broadcast here.
