# Deployment and swap integration

## Manifest handoff

The manifest contributor should describe the accepted source using these facts.
This document is not a replacement manifest or a signed policy.

| Item | Required value or responsibility |
| --- | --- |
| Kind | `evm_project` |
| Launch token | `LaunchToken`, source `src/LaunchToken.sol` |
| Token constructor arguments | Empty; no value sent |
| Token decimals | `18` |
| Token supply | `1000000000000000000000000000` minor units |
| Application `contracts` | `[]` (token-only launch) |
| Application owners / beneficiaries | None |
| Post-deployment initialization | None |
| Compiler | `0.8.26`, optimizer enabled, 200 runs, Cancun EVM |
| Bytecode metadata | `bytecode_hash = "none"`, CBOR metadata disabled |

ProjectFactory must execute the token creation code directly, receiving the whole
supply before protocol allocation. Deploying through another helper would give
that helper the supply; deploying from a wallet would give it to that wallet.
Neither is the intended launch path. There is no constructor owner argument,
privileged hard-coded wallet or application dependency order to resolve. Any
project owner in policy is a protocol-level role, not a role in `LaunchToken`.

The supplied canonical guidance permits a native ETH pair (zero address) on
Sepolia, fee `3000`, tick spacing `60`, no hook, and manifest initial price
`79228162514264337593543950336` (`sqrtPriceX96`). Its stated policy v5 specifies a
20 ETH opening FDV and rewards of 2% for launch contributors and 8% shared equally
among wallets with accepted work in the preceding 12 hours. These are protocol
policy responsibilities, not token logic or allocations made in the constructor.
When the pinned policy specifies `initialMarketCapWei`, the deployer derives the
effective opening price from that policy; the manifest price is a legacy fallback.

Services must select and verify the target chain, factory, pool manager, router,
pool identity, signed policy and effective price. No chain address was supplied
in this assignment, so none is invented or embedded in source. The factory
supplies the LP and MerkleDistributor and initially seeds liquidity with the
launch token only. The frontend must obtain live route/liquidity information;
token-only initial funding does not promise executable quotes in both directions
or a fixed redemption value.

## Connected-wallet Swap

The later frontend integrates the protocol's actual pool/router. Required flow:

1. Confirm the wallet chain and use deployed addresses from the admitted service
   result. Read `decimals`, `balanceOf` and `allowance` from the deployed token.
2. Obtain a fresh quote for the direction, input amount and recipient. The quote
   must handle actual pool liquidity and native ETH according to the router's
   verified ABI; sending ETH to `LaunchToken` is not a swap.
3. For token input, approve only the required amount to the verified spender
   designated by that route. If it requires an approval intermediary, use that
   protocol's reviewed flow. This token has no `permit` or meta-transaction API.
4. Submit the swap with a user-approved minimum output and short expiry/deadline
   using the actual router's interface. Keep amounts in integer minor units.
   Surface quote expiry, insufficient liquidity, balances, allowances and
   settlement failures. Simulate the transaction before requesting a signature.
5. After confirmation, refresh balances and allowances from chain. Do not infer
   current allowance exclusively from events. Offer approval revocation when
   an allowance remains. Set an existing nonzero allowance to zero and confirm
   it before replacing it when concurrent spending is possible.

The token accepts zero-value transfers under ERC-20 rules; the swap frontend
should reject zero-value trade submissions. Maximum ERC-20 approvals are
supported for compatibility but are not needed by this contribution. Approval
does not itself swap or transfer tokens. Users remain exposed to the spender
they approve, price movement and transaction ordering; a minimum output limits
acceptable execution but does not guarantee availability or eliminate MEV.

## Operational responsibilities and limits

- The manifest contributor generates only `launch.json` from accepted source.
  The independent reviewer checks the source and concrete constructor/manifest
  parameters; unresolved source, authorization or policy conflicts are findings.
- Services own source publication, policy and signed-artifact linkage,
  attestation, admission, deployment, pool funding and frontend publication to
  IPFS. Explorer verification and publishing actual addresses follow deployment.
- The frontend/service owners validate the real router's behavior, quote
  accuracy, minimum-output/expiry enforcement, liquidity and buy/sell execution.
  Local tests exercise ERC-20 settlement and rollback, not those external systems.
- There is no upgrade, emergency stop or recovery operator for the token. Nobody
  can reverse a transfer or recover tokens sent to an unintended address or to
  the token contract itself. Plain ETH transfers revert, but ETH forcibly sent to
  the token cannot be rescued. The token does not custody swap input on behalf of
  users, calculate prices or promise redemption.
- The supplied independent source/manifest review remains a release step. A
  successful local build, property test or opcode scan does not replace it.
