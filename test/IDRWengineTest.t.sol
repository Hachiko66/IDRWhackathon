// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
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

    // User accounts
    address public user = makeAddr("user");

    function setUp() public {
        // Deploy mock tokens and price feeds
        weth = new ERC20Mock();
        wbtc = new ERC20Mock();
        ethPriceFeed = new AggregatorV3Mock(8, 2700e8); // ETH/USD = $2700
        btcPriceFeed = new AggregatorV3Mock(8, 54000e8); // BTC/USD = $54000

        // Deploy IDRWStableCoin and IDRWEngine
        idrw = new IDRWStableCoin(address(this));
        engine = new IDRWEngine(
            address(idrw), address(weth), address(wbtc), address(ethPriceFeed), address(btcPriceFeed), address(this)
        );

        // Transfer ownership of IDRWStableCoin to IDRWEngine
        idrw.transferOwnership(address(engine));

        // Mint mock tokens to the user
        weth.mint(user, 100 ether);
        wbtc.mint(user, 100 ether);

        // Approve engine to spend user's tokens
        vm.prank(user);
        weth.approve(address(engine), type(uint256).max);
        vm.prank(user);
        wbtc.approve(address(engine), type(uint256).max);
    }

    // Test depositing collateral
    function testDepositCollateral() public {
        uint256 amount = 10 ether;

        vm.prank(user);
        engine.deposit(address(weth), amount);

        assertEq(engine.ethCollateral(user), amount, "ETH collateral balance mismatch");
        assertEq(weth.balanceOf(address(engine)), amount, "Engine WETH balance mismatch");
    }

    // Test minting IDRWS with sufficient collateral
    function testMintMaxIDRW() public {
        // Deposit 10 ETH (harga = $27000)
        vm.prank(user);
        engine.deposit(address(weth), 10 ether);

        // Hitung maksimal IDRW yang dapat dicetak
        uint256 maxIDRW = engine.getMaxMintableIDRW(user);

        // Mint IDRW maksimal
        vm.prank(user);
        engine.mintIDRW(maxIDRW);

        // Verifikasi saldo IDRW pengguna
        assertEq(idrw.balanceOf(user), maxIDRW, "User IDRW balance mismatch");

        // Verifikasi saldo kolateral di kontrak
        assertEq(weth.balanceOf(address(engine)), 10 ether, "Engine WETH balance mismatch");

    }

    function testMintMaxIDRWuseWbtc() public {
        vm.prank(user);
        engine.deposit(address(wbtc), 1 ether);

        uint256 maxIDRW = engine.getMaxMintableIDRW(user);

        vm.prank(user);
        engine.mintIDRW(maxIDRW);

        assertEq(idrw.balanceOf(address(user)), maxIDRW, "User IDRW Balance Mismatch");

        assertEq(wbtc.balanceOf(address(engine)),1 ether, "engine wbtc balance mistmatch");
    }

    // Test minting IDRWS with insufficient collateral
    function testRevertWhenBreaksCollateralRatio() public {
        uint256 collateralAmount = 1 ether;
        uint256 mintAmount = 5000 ether; // Exceeds collateral ratio

        vm.prank(user);
        engine.deposit(address(weth), collateralAmount);

        vm.expectRevert(IDRWEngine.IDRWEngine__BreaksCollateralRatio.selector);
        vm.prank(user);
        engine.mintIDRW(mintAmount);
    }

    // Test withdrawing collateral
    function testWithdrawCollateral() public {
        uint256 depositAmount = 10 ether;
        uint256 withdrawAmount = 5 ether;

        vm.prank(user);
        engine.deposit(address(weth), depositAmount);

        vm.prank(user);
        engine.withdraw(address(weth), withdrawAmount);

        assertEq(engine.ethCollateral(user), depositAmount - withdrawAmount, "ETH collateral balance mismatch");
        assertEq(weth.balanceOf(user), withdrawAmount, "User WETH balance mismatch");
    }

    // Test withdrawing more than deposited collateral
    function testRevertWhenWithdrawMoreThanDeposited() public {
        uint256 depositAmount = 10 ether;
        uint256 withdrawAmount = 11 ether;

        vm.prank(user);
        engine.deposit(address(weth), depositAmount);

        vm.expectRevert(IDRWEngine.IDRWEngine__InsufficientCollateral.selector);
        vm.prank(user);
        engine.withdraw(address(weth), withdrawAmount);
    }

    // Test repaying debt
    function testRepayDebt() public {
        uint256 repayAmount = 5 ether;

        // Deposit 10 ETH (harga = $27000)
        vm.prank(user);
        engine.deposit(address(weth), 10 ether);

        // Hitung maksimal IDRW yang dapat dicetak
        uint256 maxIDRW = engine.getMaxMintableIDRW(user);

        // Mint IDRW maksimal
        vm.prank(user);
        engine.mintIDRW(maxIDRW);

        // Verifikasi saldo IDRW pengguna
        assertEq(idrw.balanceOf(user), maxIDRW, "User IDRW balance mismatch");

        vm.prank(user);
        engine.repay(repayAmount);

        assertEq(engine.debt(user), maxIDRW - repayAmount, "Debt balance mismatch");
    }

    // Test switching collateral
    function testSwitchCollateral() public {
        uint256 depositAmount = 10 ether;
        uint256 switchAmount = 5 ether;

        vm.prank(user);
        engine.deposit(address(weth), depositAmount);

        vm.prank(user);
        engine.switchCollateral(address(weth), address(wbtc), switchAmount);

        assertEq(engine.ethCollateral(user), depositAmount - switchAmount, "ETH collateral balance mismatch");
        assertEq(
            engine.btcCollateral(user),
            _getCollateralAmount(address(wbtc), _getCollateralValue(address(weth), switchAmount)),
            "BTC collateral balance mismatch"
        );
    }

    // Helper functions for collateral value calculations
    function _getCollateralValue(address collateralToken, uint256 amount) private view returns (uint256) {
        AggregatorV3Mock priceFeed = collateralToken == address(weth) ? ethPriceFeed : btcPriceFeed;
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint256 adjustedPrice = uint256(price) * 1e10; // Convert price to 18 decimals
        return (amount * adjustedPrice) / (10 ** (18 + 8)); // Adjust for decimals
    }

    function _getCollateralAmount(address collateralToken, uint256 usdValue) private view returns (uint256) {
        AggregatorV3Mock priceFeed = collateralToken == address(weth) ? ethPriceFeed : btcPriceFeed;
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint256 adjustedPrice = uint256(price) * 1e10; // Convert price to 18 decimals
        return (usdValue * 10 ** (18 + 8)) / adjustedPrice;
    }
}
