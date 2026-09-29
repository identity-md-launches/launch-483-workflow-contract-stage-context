// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

/// @dev Tracks the expected ledger across successful and rejected calls. Failed token calls
/// leave the model unchanged so the invariant also checks transaction rollback.
contract TokenHandler is Test {
    LaunchToken public immutable token;
    address[4] public actors = [address(0x1001), address(0x1002), address(0x1003), address(0x1004)];
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(LaunchToken token_) {
        token = token_;
        for (uint256 i; i < 4; ++i) {
            expectedBalance[actors[i]] = 10 ** 27 / 4;
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 approval = unlimited ? type(uint256).max : bound(amount, 0, type(uint256).max - 1);
        vm.prank(owner);
        assertTrue(token.approve(spender, approval));
        expectedAllowance[owner][spender] = approval;
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 available = expectedBalance[from];
        uint256 allowed = expectedAllowance[from][spender];
        if (allowed < available) available = allowed;
        uint256 amount = bound(amountSeed, 0, available);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) expectedAllowance[from][spender] -= amount;
    }

    function transferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        token.transfer(to, amount);
    }

    function transferFromOverBalance(
        uint256 fromSeed,
        uint256 toSeed,
        uint256 spenderSeed,
        uint256 amountSeed,
        bool unlimited
    ) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        uint256 approval = unlimited ? type(uint256).max : amount;
        vm.prank(from);
        assertTrue(token.approve(spender, approval));
        expectedAllowance[from][spender] = approval;

        // Sufficient approval isolates balance failure after allowance spending.
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        token.transferFrom(from, to, amount);
    }

    function transferFromOverAllowance(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 allowed = expectedAllowance[from][spender];
        // Infinite approval cannot be exceeded; replace it with the largest finite one.
        if (allowed == type(uint256).max) {
            allowed -= 1;
            vm.prank(from);
            assertTrue(token.approve(spender, allowed));
            expectedAllowance[from][spender] = allowed;
        }
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1)
        );
        token.transferFrom(from, to, allowed + 1);
    }

    function revokeAndTrySpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        address to = actors[toSeed % 4];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(owner, to, 1);
    }

    function rejectZeroRecipient(uint256 fromSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) external {
        address from = actors[fromSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 available = expectedBalance[from];
        if (delegated && expectedAllowance[from][spender] < available) {
            available = expectedAllowance[from][spender];
        }
        uint256 amount = bound(amountSeed, 0, available);
        vm.prank(delegated ? spender : from);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        if (delegated) {
            token.transferFrom(from, address(0), amount);
        } else {
            token.transfer(address(0), amount);
        }
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % 4];
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), amount);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract LaunchTokenInvariantTest is Test {
    LaunchToken private token;
    TokenHandler private handler;

    function setUp() public {
        token = new LaunchToken();
        handler = new TokenHandler(token);
        // Fund every actor so early sequences exercise nonzero transfers and approvals.
        for (uint256 i; i < 4; ++i) {
            token.transfer(handler.actors(i), 10 ** 27 / 4);
        }
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.transferOverBalance.selector;
        selectors[4] = TokenHandler.transferFromOverBalance.selector;
        selectors[5] = TokenHandler.transferFromOverAllowance.selector;
        selectors[6] = TokenHandler.revokeAndTrySpend.selector;
        selectors[7] = TokenHandler.rejectZeroRecipient.selector;
        selectors[8] = TokenHandler.rejectZeroSpender.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyBalancesAndAllowancesMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            sum += balance;
            assertEq(token.allowance(actor, address(0)), 0);
            assertEq(token.allowance(address(0), actor), 0);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(actor, spender), handler.expectedAllowance(actor, spender));
            }
        }
        assertEq(sum, 10 ** 27);
        assertEq(token.totalSupply(), 10 ** 27);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }
}
