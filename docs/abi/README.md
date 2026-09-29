# LaunchToken ABI

[`LaunchToken.json`](LaunchToken.json) is the full ABI array exported by Solidity
0.8.26 via `forge inspect src/LaunchToken.sol:LaunchToken abi --json`. The exported
artifact has no constructor arguments and its constructor is nonpayable. All
amounts and allowances below are `uint256` values in minor units (18 decimals).

| Function | Result and behavior |
| --- | --- |
| `name()` | `string`: `Great Family` |
| `symbol()` | `string`: `GFAM` |
| `decimals()` | `uint8`: `18` |
| `totalSupply()` | `uint256`: always `1000000000000000000000000000` |
| `balanceOf(address account)` | `uint256`: current account balance; zero for unused addresses |
| `allowance(address owner, address spender)` | `uint256`: remaining approved amount |
| `transfer(address to, uint256 value)` | Moves caller's tokens to a nonzero recipient; returns `true` |
| `approve(address spender, uint256 value)` | Replaces caller's allowance for nonzero spender; returns `true` |
| `transferFrom(address from, address to, uint256 value)` | Moves `from`'s tokens using caller's allowance; returns `true` |

Read functions are `view`; the three state-changing functions are nonpayable.
Failures revert rather than return `false`. Transfers charge no fee, accept zero
amounts when addresses are valid, and support self-transfers without balance
changes. Finite allowances decrease on `transferFrom`; `type(uint256).max` is
treated as unlimited and remains unchanged. A reverted transfer or enclosing
settlement transaction restores both balance and allowance state.

Events:

- `Transfer(address indexed from, address indexed to, uint256 value)` is emitted
  for transfers, including zero/self transfers. Construction emits one mint
  event with `from = address(0)` and the full supply.
- `Approval(address indexed owner, address indexed spender, uint256 value)` is
  emitted by `approve`. This implementation does **not** emit it when
  `transferFrom` spends allowance; query `allowance` for current state.

The ABI includes OpenZeppelin's ERC-6093 errors:

| Error | Meaning |
| --- | --- |
| `ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed)` | Transfer exceeds the source balance |
| `ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed)` | Delegated transfer exceeds the caller's allowance |
| `ERC20InvalidReceiver(address receiver)` | Zero transfer recipient |
| `ERC20InvalidSpender(address spender)` | Zero approval spender |
| `ERC20InvalidApprover(address approver)` | Zero allowance owner |
| `ERC20InvalidSender(address sender)` | Zero transfer source at transfer validation |

Validation order matters: `transferFrom` spends/checks allowance before transfer
validation. For example, `transferFrom(address(0), recipient, 0)` reverts with
`ERC20InvalidApprover`, while a positive amount from that address fails allowance
first. Integrations should handle any revert as a failed transaction, without
assuming that multiple invalid inputs have one particular first error.

There are no administrative, burn, permit, recovery, payable or swap methods.
Unknown selectors and empty-calldata calls revert. Obtain the separate protocol
router ABI from the deployed service integration, not from this token export.
