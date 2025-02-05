// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {AggregatorV3Mock} from "./mocks/AggregatorV3Mock.sol";
import {IDRWStableCoin} from "../src/IDRWStableCoin.sol";
import {IDRWEngine} from "../src/IDRWEngine.sol";

contract IDRWEngineTest is Test {
    // Mock contracts
    ERC20Mock public weth;
    ERC20Mock public wbtc;
    AggregatorV3Mock public ethPriceFeed;
    AggregatorV3Mock public btcPriceFeed;
    IDRWStableCoin public idrw;
    IDRWEngine public engine;

    address public user = makeAddr("user");
    uint256 public constant INITIAL_BALANCE = 1000 ether; // Meningkatkan saldo awal

    function setUp() public {
        // Deploy mock tokens and price feeds
        weth = new ERC20Mock();
        weth.mint(user, INITIAL_BALANCE);
        wbtc = new ERC20Mock();
        wbtc.mint(user,INITIAL_BALANCE);
        ethPriceFeed = new AggregatorV3Mock(8, 1800e8); // $1800 per ETH
        btcPriceFeed = new AggregatorV3Mock(8, 27000e8); // $27,000 per BTC

        // Deploy IDRWStableCoin
        idrw = new IDRWStableCoin(address(this));

        // Deploy IDRWEngine
        engine = new IDRWEngine(
            address(idrw),
            address(weth),
            address(wbtc),
            address(ethPriceFeed),
            address(btcPriceFeed),
            address(this)
        );

        // Transfer ownership of IDRWStableCoin to IDRWEngine
        idrw.transferOwnership(address(engine));
    }

    // Helper function to get collateral value
    function _getCollateralValue(address collateralToken, uint256 amount) private view returns (uint256) {
        AggregatorV3Mock priceFeed = collateralToken == address(weth) ? ethPriceFeed : btcPriceFeed;
        (, int256 price, , , ) = priceFeed.latestRoundData();
        uint256 adjustedPrice = uint256(price) * 1e10; // Convert price to 18 decimals
        return (amount * adjustedPrice) / (10 ** (18 + 8)); // COLLATERAL_DECIMALS + PRICE_FEED_DECIMALS
    }

    // Helper function to get collateral amount
    function _getCollateralAmount(address collateralToken, uint256 usdValue) private view returns (uint256) {
        AggregatorV3Mock priceFeed = collateralToken == address(weth) ? ethPriceFeed : btcPriceFeed;
        (, int256 price, , , ) = priceFeed.latestRoundData();
        uint256 adjustedPrice = uint256(price) * 1e10; // Convert price to 18 decimals
        return (usdValue * 10 ** (18 + 8)) / adjustedPrice; // COLLATERAL_DECIMALS + PRICE_FEED_DECIMALS
    }

    // Test: Deposit collateral
    function testDepositCollateral() public {
        uint256 depositAmount = 1 ether;

        // Approve WETH for transfer
        vm.prank(user);
        weth.approve(address(engine), depositAmount);

        // Deposit WETH
        vm.prank(user);
        engine.deposit(address(weth), depositAmount);

        // Check balances
        assertEq(weth.balanceOf(address(engine)), depositAmount);
        assertEq(engine.ethCollateral(user), depositAmount);
    }

    // Test: Mint IDRW tokens
    function testMintIDRW() public {
        uint256 depositAmount = 10 ether;
        uint256 mintAmount = 8 ether;

        // Approve WETH for transfer
        vm.prank(user);
        weth.approve(address(engine), depositAmount);

        // Deposit WETH
        vm.prank(user);
        engine.deposit(address(weth), depositAmount);

        // Mint IDRW
        vm.prank(user);
        engine.mintIDRW(mintAmount);

        // Check balances
        assertEq(idrw.balanceOf(user), mintAmount);
        assertEq(engine.debt(user), mintAmount);
    }

    // Test: Withdraw collateral
    function testWithdrawCollateral() public {
        uint256 depositAmount = 2 ether;
        uint256 withdrawAmount = 1 ether;

        // Approve WETH for transfer
        vm.prank(user);
        weth.approve(address(engine), depositAmount);

        // Deposit WETH
        vm.prank(user);
        engine.deposit(address(weth), depositAmount);

        // Withdraw WETH
        vm.prank(user);
        engine.withdraw(address(weth), withdrawAmount);

        // Check balances
        assertEq(weth.balanceOf(address(engine)), depositAmount - withdrawAmount);
        assertEq(engine.ethCollateral(user), depositAmount - withdrawAmount);
    }

    // Test: Repay debt
    function testRepayDebt() public {
        uint256 depositAmount = 1 ether;
        uint256 mintAmount = 1000 ether;
        uint256 repayAmount = 500 ether;

        // Approve WETH for transfer
        vm.prank(user);
        weth.approve(address(engine), depositAmount);

        // Deposit WETH
        vm.prank(user);
        engine.deposit(address(weth), depositAmount);

        // Mint IDRW
        vm.prank(user);
        engine.mintIDRW(mintAmount);

        // Approve IDRW for repayment
        vm.prank(user);
        idrw.approve(address(engine), repayAmount);

        // Repay debt
        vm.prank(user);
        engine.repay(repayAmount);

        // Check balances
        assertEq(idrw.balanceOf(user), mintAmount - repayAmount);
        assertEq(engine.debt(user), mintAmount - repayAmount);
    }

    // Test: Switch collateral
    function testSwitchCollateral() public {
        uint256 depositAmount = 1 ether;

        // Approve WETH for transfer
        vm.prank(user);
        weth.approve(address(engine), depositAmount);

        // Deposit WETH
        vm.prank(user);
        engine.deposit(address(weth), depositAmount);

        // Calculate WBTC amount equivalent to deposited WETH
        uint256 wbtcAmount = _getCollateralAmount(address(wbtc), _getCollateralValue(address(weth), depositAmount));

        // Approve WBTC for switch
        vm.prank(user);
        wbtc.approve(address(engine), wbtcAmount);

        // Switch collateral
        vm.prank(user);
        engine.switchCollateral(address(weth), address(wbtc), depositAmount);

        // Check balances
        assertEq(weth.balanceOf(address(engine)), 0);
        assertEq(wbtc.balanceOf(address(engine)), wbtcAmount);
        assertEq(engine.ethCollateral(user), 0);
        assertEq(engine.btcCollateral(user), wbtcAmount);
    }

    // Test: Revert when depositing zero collateral
    function testRevertWhenDepositZeroCollateral() public {
        vm.prank(user);
        vm.expectRevert();
        engine.deposit(address(weth), 0);
    }

    // Test: Revert when minting zero IDRW
    function testRevertWhenMintZeroIDRW() public {
        vm.prank(user);
        vm.expectRevert();
        engine.mintIDRW(0);
    }

    // Test: Revert when repaying more than debt
    function testRevertWhenRepayMoreThanDebt() public {
        uint256 depositAmount = 1 ether;
        uint256 mintAmount = 1000 ether;

        // Approve WETH for transfer
        vm.prank(user);
        weth.approve(address(engine), depositAmount);

        // Deposit WETH
        vm.prank(user);
        engine.deposit(address(weth), depositAmount);

        // Mint IDRW
        vm.prank(user);
        engine.mintIDRW(mintAmount);

        // Approve IDRW for repayment
        vm.prank(user);
        idrw.approve(address(engine), mintAmount + 1);

        // Attempt to repay more than debt
        vm.prank(user);
        vm.expectRevert();
        engine.repay(mintAmount + 1);
    }

    // Test: Revert when withdrawing more than deposited
    function testRevertWhenWithdrawMoreThanDeposited() public {
        uint256 depositAmount = 1 ether;

        // Approve WETH for transfer
        vm.prank(user);
        weth.approve(address(engine), depositAmount);

        // Deposit WETH
        vm.prank(user);
        engine.deposit(address(weth), depositAmount);

        // Attempt to withdraw more than deposited
        vm.prank(user);
        vm.expectRevert();
        engine.withdraw(address(weth), depositAmount + 1);
    }
}