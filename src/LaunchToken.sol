// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Great Family launch token
/// @notice Fixed-supply, 18-decimal ERC-20 for the factory-provided swap pool.
/// @dev ProjectFactory receives the entire supply during deployment. No administrative role exists.
contract LaunchToken is ERC20 {
    /// @notice Creates exactly one billion GFAM and assigns all of it to the deployer.
    constructor() ERC20("Great Family", "GFAM") {
        _mint(msg.sender, 1_000_000_000 * 10 ** 18);
    }
}
