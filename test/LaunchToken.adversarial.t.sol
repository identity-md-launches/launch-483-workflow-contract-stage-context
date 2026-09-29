// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "src/LaunchToken.sol";

/// forge-config: default.fuzz.runs = 1000
contract LaunchTokenAdversarialTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0xCAFE);
    LaunchToken private token;

    function setUp() public {
        token = new LaunchToken();
    }

    function test_constructorRejectsETH() public {
        bytes memory creationCode = type(LaunchToken).creationCode;
        vm.deal(address(this), 1);
        address deployed;
        assembly ("memory-safe") {
            deployed := create(1, add(creationCode, 32), mload(creationCode))
        }
        assertEq(deployed, address(0));
        assertEq(address(this).balance, 1);

        // The identical creation code is valid when no ETH accompanies it.
        assembly ("memory-safe") {
            deployed := create(0, add(creationCode, 32), mload(creationCode))
        }
        assertTrue(deployed != address(0));
        assertEq(LaunchToken(deployed).totalSupply(), SUPPLY);
        assertEq(LaunchToken(deployed).balanceOf(address(this)), SUPPLY);
        assertEq(deployed.balance, 0);
    }

    function test_knownMutatorsRejectETHWithoutChangingState() public {
        vm.deal(address(this), 3);
        token.approve(SPENDER, 7);
        token.approve(address(this), 1);
        bytes[3] memory calls = [
            abi.encodeCall(IERC20.transfer, (ALICE, 1)),
            abi.encodeCall(IERC20.approve, (SPENDER, 1)),
            abi.encodeCall(IERC20.transferFrom, (address(this), ALICE, 1))
        ];

        for (uint256 i; i < calls.length; ++i) {
            (bool success,) = address(token).call{value: 1}(calls[i]);
            assertFalse(success, "ERC20 mutator accepted ETH");
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.balanceOf(ALICE), 0);
            assertEq(token.allowance(address(this), SPENDER), 7);
            assertEq(token.allowance(address(this), address(this)), 1);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(address(token).balance, 0);
            assertEq(address(this).balance, 3);
        }
    }

    function test_maximumUintTransferRevertsWithoutArithmeticPanic() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumUintTransferFromRestoresInfiniteAllowance() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transferFrom(address(this), ALICE, type(uint256).max);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumMinusOneAllowanceIsFiniteAcrossRepeatedSpends() public {
        uint256 approval = type(uint256).max - 1;
        token.approve(SPENDER, approval);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        assertEq(token.allowance(address(this), SPENDER), approval - SUPPLY);

        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), SUPPLY));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, SUPPLY));
        assertEq(token.allowance(address(this), SPENDER), approval - 2 * SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_consumedAllowanceCannotBeReusedAfterOwnerIsRefunded() public {
        token.approve(SPENDER, 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), 1));

        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_infiniteAllowanceCanBeRevokedAfterUse() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);

        assertTrue(token.approve(SPENDER, 0));
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(ALICE), 1);
    }

    function test_ownerTransferFromStillRequiresApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);

        token.approve(address(this), 1);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(ALICE), 1);
    }

    function test_selfTransferFromCannotExceedBalanceDespiteZeroNetMovement() public {
        token.approve(SPENDER, SUPPLY + 1);
        vm.prank(SPENDER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transferFrom(address(this), address(this), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), SUPPLY + 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_insufficientBalanceTransferIsAtomic(uint256 rawBalance, uint256 rawAmount) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        token.transfer(ALICE, balance);

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        token.transfer(BOB, amount);
        _assertHolderBalances(balance, 0);
    }

    function testFuzz_insufficientBalanceTransferFromIsAtomic(uint256 rawBalance, uint256 rawAmount) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        token.transfer(ALICE, balance);
        vm.prank(ALICE);
        token.approve(SPENDER, amount);

        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.allowance(ALICE, SPENDER), amount);
        _assertHolderBalances(balance, 0);
    }

    function testFuzz_insufficientAllowanceIsAtomic(uint256 rawBalance, uint256 rawApproval, uint256 rawAmount) public {
        uint256 balance = bound(rawBalance, 1, SUPPLY);
        uint256 approval = bound(rawApproval, 0, balance - 1);
        uint256 amount = bound(rawAmount, approval + 1, balance);
        token.transfer(ALICE, balance);
        vm.prank(ALICE);
        token.approve(SPENDER, approval);

        vm.prank(SPENDER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, approval, amount)
        );
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.allowance(ALICE, SPENDER), approval);
        _assertHolderBalances(balance, 0);
    }

    function testFuzz_selfTransferFromConservesBalanceAndConsumesAllowance(uint256 rawAmount, uint256 rawApproval)
        public
    {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        uint256 approval = bound(rawApproval, amount, type(uint256).max - 1);
        token.approve(SPENDER, approval);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), address(this), amount);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), amount));
        assertEq(token.allowance(address(this), SPENDER), approval - amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalsBelongToOwnerAndSpenderPair(uint256 firstApproval, uint256 secondApproval) public {
        token.approve(SPENDER, firstApproval);
        token.approve(BOB, secondApproval);
        vm.prank(ALICE);
        token.approve(SPENDER, type(uint256).max);

        assertEq(token.allowance(address(this), SPENDER), firstApproval);
        assertEq(token.allowance(address(this), BOB), secondApproval);
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
        assertEq(token.allowance(address(this), ALICE), 0);
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), firstApproval);
        assertEq(token.allowance(address(this), BOB), secondApproval);
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function _assertHolderBalances(uint256 aliceBalance, uint256 bobBalance) private view {
        assertEq(token.balanceOf(ALICE), aliceBalance);
        assertEq(token.balanceOf(BOB), bobBalance);
        assertEq(token.balanceOf(address(this)), SUPPLY - aliceBalance - bobBalance);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
