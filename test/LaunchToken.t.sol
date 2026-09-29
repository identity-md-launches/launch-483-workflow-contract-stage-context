// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

/// @dev Models only factory CREATE2 deployment, not protocol liquidity or reward allocation.
contract TokenFactoryProbe {
    function deploy(bytes32 salt) external returns (LaunchToken) {
        return new LaunchToken{salt: salt}();
    }
}

/// @dev Models the ERC-20 pull made by a router, including atomic settlement failure.
contract TokenSpenderProbe {
    error SettlementFailed();

    function settle(IERC20 token, address payer, address recipient, uint256 amount, bool fail) external {
        require(token.transferFrom(payer, recipient, amount), "token transfer failed");
        if (fail) revert SettlementFailed();
    }
}

contract TokenRecipientProbe {
    bool public called;

    fallback() external {
        called = true;
        revert("unexpected callback");
    }
}

contract LaunchTokenTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0xCAFE);
    LaunchToken private token;

    function setUp() public {
        token = new LaunchToken();
    }

    function test_metadataAndExactSupply() public view {
        assertEq(token.name(), "Great Family");
        assertEq(token.symbol(), "GFAM");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 10 ** 27);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_constructorEmitsMintEvent() public {
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), address(this), SUPPLY);
        new LaunchToken();
    }

    function test_factoryCreate2ReceivesAllSupplyWithoutInitialization() public {
        TokenFactoryProbe factory = new TokenFactoryProbe();
        bytes32 salt = keccak256("Great Family");
        address expected = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(factory), salt, keccak256(type(LaunchToken).creationCode)
                        )
                    )
                )
            )
        );
        vm.prank(ALICE);
        LaunchToken deployed = factory.deploy(salt);
        assertEq(address(deployed), expected);
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(ALICE), 0);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.allowance(address(factory), ALICE), 0);
    }

    function test_transferEmitsEventAndMovesExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), ALICE, 7 ether);
        assertTrue(token.transfer(ALICE, 7 ether));
        assertEq(token.balanceOf(ALICE), 7 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 7 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferEntireSupply() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function test_zeroAndSelfTransfersPreserveBalances() public {
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferDoesNotInvokeRecipient() public {
        TokenRecipientProbe recipient = new TokenRecipientProbe();
        assertTrue(token.transfer(address(recipient), 1 ether));
        assertEq(token.balanceOf(address(recipient)), 1 ether);
        assertFalse(recipient.called());
    }

    function test_transferRejectsZeroRecipientIncludingZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferRejectsInsufficientBalance() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_approvalEmitsEventAndCanBeReplacedAndRevoked() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), SPENDER, 10 ether);
        assertTrue(token.approve(SPENDER, 10 ether));
        assertTrue(token.approve(SPENDER, 3 ether));
        assertEq(token.allowance(address(this), SPENDER), 3 ether);
        assertTrue(token.approve(SPENDER, 0));
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approvalRejectsZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_transferFromConsumesOnlyCallerAllowance() public {
        token.approve(SPENDER, 10 ether);
        token.approve(BOB, 20 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 4 ether));
        assertEq(token.allowance(address(this), SPENDER), 6 ether);
        assertEq(token.allowance(address(this), BOB), 20 ether);
        assertEq(token.balanceOf(ALICE), 4 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 4 ether);
    }

    function test_maximumAllowanceIsNotDecremented() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1 ether));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
    }

    function test_zeroTransferFromNeedsNoAllowance() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromRejectsUnauthorizedSpender() public {
        token.approve(SPENDER, SUPPLY);
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.allowance(address(this), SPENDER), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transferFromRejectsExcessAllowanceAndPreservesState() public {
        token.approve(SPENDER, 10);
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 10, 11));
        token.transferFrom(address(this), ALICE, 11);
        assertEq(token.allowance(address(this), SPENDER), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_transferFromInsufficientBalanceRestoresAllowance() public {
        vm.prank(ALICE);
        token.approve(SPENDER, 10);
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 10));
        token.transferFrom(ALICE, BOB, 10);
        assertEq(token.allowance(ALICE, SPENDER), 10);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromRejectsZeroAddresses() public {
        token.approve(SPENDER, 10);
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(address(this), address(0), 10);
        assertEq(token.allowance(address(this), SPENDER), 10);
        // Allowance spending validates its owner before the transfer validates its sender.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
    }

    function test_contractSpenderCanSettleWithExactApproval() public {
        TokenSpenderProbe router = new TokenSpenderProbe();
        token.transfer(ALICE, 10 ether);
        vm.prank(ALICE);
        token.approve(address(router), 10 ether);
        router.settle(token, ALICE, BOB, 10 ether, false);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 10 ether);
        assertEq(token.balanceOf(address(router)), 0);
        assertEq(token.allowance(ALICE, address(router)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_failedSettlementRollsBackBalancesAndApproval() public {
        TokenSpenderProbe router = new TokenSpenderProbe();
        token.transfer(ALICE, 10 ether);
        vm.prank(ALICE);
        token.approve(address(router), 10 ether);
        vm.expectRevert(TokenSpenderProbe.SettlementFailed.selector);
        router.settle(token, ALICE, BOB, 10 ether, true);
        assertEq(token.balanceOf(ALICE), 10 ether);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.allowance(ALICE, address(router)), 10 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_commonAdminAndBurnSelectorsRevert() public {
        string[14] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "pause()",
            "unpause()",
            "setMinter(address)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "setFee(uint256)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, uint256(1));
            (bool deployerSuccess,) = address(token).call(data);
            assertFalse(deployerSuccess, signatures[i]);
            vm.prank(ALICE);
            (bool strangerSuccess,) = address(token).call(data);
            assertFalse(strangerSuccess, signatures[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_plainETHAndUnknownCallsRevert() public {
        vm.deal(address(this), 1 ether);
        (bool ethAccepted,) = address(token).call{value: 1 ether}("");
        assertFalse(ethAccepted);
        (bool unknownAccepted,) = address(token).call(hex"ffffffff");
        assertFalse(unknownAccepted);
        assertEq(address(token).balance, 0);
    }

    function test_runtimeIsBoundedAndHasNoEscapeOpcodes() public view {
        bytes memory code = address(token).code;
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        for (uint256 i; i < code.length; ++i) {
            uint8 opcode = uint8(code[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff, "forbidden opcode");
        }
    }

    function testFuzz_transferConservesSupply(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromConservesBalancesAndAllowance(uint256 rawApproval, uint256 rawAmount) public {
        uint256 approval = bound(rawApproval, 0, SUPPLY);
        uint256 amount = bound(rawAmount, 0, approval);
        token.approve(SPENDER, approval);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        assertEq(token.allowance(address(this), SPENDER), approval - amount);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
