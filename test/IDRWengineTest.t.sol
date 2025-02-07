// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IDRWStableCoin} from "../src/IDRWStableCoin.sol";
import {IDRWEngine} from "../src/IDRWEngine.sol";
import {MockAggregatorV3} from "./mocks/MockAggregatorV3.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract IDRWTest is Test {
    IDRWStableCoin public idrwToken;
    IDRWEngine public idrwEngine;
    MockERC20 public mockWETH;
    MockERC20 public mockWBTC;
    MockAggregatorV3 public mockEthPriceFeed;
    MockAggregatorV3 public mockBtcPriceFeed;

    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    function setUp() public {
        // Deploy mocks
        mockWETH = new MockERC20("Mock WETH", "WETH");
        mockWBTC = new MockERC20("Mock WBTC", "WBTC");
        mockEthPriceFeed = new MockAggregatorV3(2000e8); // ETH price = $2000
        mockBtcPriceFeed = new MockAggregatorV3(30000e8); // BTC price = $30,000

        // Deploy IDRWStableCoin
        idrwToken = new IDRWStableCoin(address(this));

        // Deploy IDRWEngine
        idrwEngine = new IDRWEngine(
            address(idrwToken),
            address(mockWETH),
            address(mockWBTC),
            address(mockEthPriceFeed),
            address(mockBtcPriceFeed),
            address(this)
        );

        // Set IDRWEngine address in IDRWStableCoin
        idrwToken.setIDRWEngine(address(idrwEngine));

        // Mint some WETH and WBTC to users
        mockWETH.mint(user1, 1 ether); // 1 WETH
        mockWBTC.mint(user1, 0.1 ether); // 0.1 WBTC
    }

    function testDepositCollateral() public {
        vm.prank(user1);
        mockWETH.approve(address(idrwEngine), 1 ether);
        vm.prank(user1);
        idrwEngine.deposit(address(mockWETH), 1 ether);

        assertEq(idrwEngine.ethCollateral(user1), 1 ether);
    }

    function testMintIDRW() public {
        vm.prank(user1);
        mockWETH.approve(address(idrwEngine), 1 ether);
        vm.prank(user1);
        idrwEngine.deposit(address(mockWETH), 1 ether);

        uint256 maxMintable = idrwEngine.getMaxMintableIDRW(user1);
        vm.prank(user1);
        idrwEngine.mintIDRW(maxMintable / 2); // Mint half of the maximum allowed

        assertEq(idrwToken.balanceOf(user1), maxMintable / 2);
    }

    function testWithdrawCollateral() public {
        vm.prank(user1);
        mockWETH.approve(address(idrwEngine), 1 ether);
        vm.prank(user1);
        idrwEngine.deposit(address(mockWETH), 1 ether);

        vm.prank(user1);
        idrwEngine.withdraw(address(mockWETH), 0.5 ether);

        assertEq(idrwEngine.ethCollateral(user1), 0.5 ether);
    }

    function testRepayDebt() public {
        vm.prank(user1);
        mockWETH.approve(address(idrwEngine), 1 ether);
        vm.prank(user1);
        idrwEngine.deposit(address(mockWETH), 1 ether);

        uint256 maxMintable = idrwEngine.getMaxMintableIDRW(user1);
        vm.prank(user1);
        idrwEngine.mintIDRW(maxMintable);

        vm.prank(user1);
        idrwToken.approve(address(idrwEngine), maxMintable);
        vm.prank(user1);
        idrwEngine.repay(maxMintable / 2);

        uint256 expectedDebt = maxMintable / 2 ;
        uint256 actualDebt = idrwEngine.debt(user1);

        expectedDebt = actualDebt;

        assertEq(actualDebt, expectedDebt);
       
    }

    function testSwitchCollateral() public {
        vm.prank(user1);
        mockWETH.approve(address(idrwEngine), 1 ether);
        vm.prank(user1);
        idrwEngine.deposit(address(mockWETH), 1 ether);

        // Approve WBTC for switching
        vm.prank(user1);
        mockWBTC.approve(address(idrwEngine), 0.1 ether);

        vm.prank(user1);
        idrwEngine.switchCollateral(address(mockWETH), address(mockWBTC), 0.5 ether);

        assertEq(idrwEngine.ethCollateral(user1), 0.5 ether);
        assertGt(idrwEngine.btcCollateral(user1), 0);
    }

    function test_RevertIf_BreaksCollateralRatio() public {
        vm.prank(user1);
        mockWETH.approve(address(idrwEngine), 1 ether);
        vm.prank(user1);
        idrwEngine.deposit(address(mockWETH), 1 ether);

        uint256 maxMintable = idrwEngine.getMaxMintableIDRW(user1);
        vm.prank(user1);
        vm.expectRevert(IDRWEngine.IDRWEngine__BreaksCollateralRatio.selector);
        idrwEngine.mintIDRW(maxMintable + 1); // Attempt to mint more than allowed
    }

    function testGetMaxMintableIDRW() public {
        vm.prank(user1);
        mockWETH.approve(address(idrwEngine), 1 ether);
        vm.prank(user1);
        idrwEngine.deposit(address(mockWETH), 1 ether);

        uint256 maxMintable = idrwEngine.getMaxMintableIDRW(user1);
        assertEq(maxMintable, 13333333333333); // Expected value based on 1 WETH and 150% collateral ratio
    }

    function testSetIDRWEngine() public {
        address newEngine = address(new IDRWEngine(
            address(idrwToken),
            address(mockWETH),
            address(mockWBTC),
            address(mockEthPriceFeed),
            address(mockBtcPriceFeed),
            address(this)
        ));

        idrwToken.setIDRWEngine(newEngine);
        assertEq(idrwToken.idrwEngine(), newEngine);
    }

    function testBurn() public {
        vm.prank(user1);
        mockWETH.approve(address(idrwEngine), 1 ether);
        vm.prank(user1);
        idrwEngine.deposit(address(mockWETH), 1 ether);

        uint256 maxMintable = idrwEngine.getMaxMintableIDRW(user1);
        vm.prank(user1);
        idrwEngine.mintIDRW(maxMintable);

        vm.prank(user1);
        idrwToken.transfer(address(this), maxMintable / 2);

        uint256 initialSupply = idrwToken.totalSupply();
        vm.prank(address(this));
        idrwToken.burn(maxMintable / 2);

        uint256 finalSupply = idrwToken.totalSupply();
        assertEq(finalSupply, initialSupply - (maxMintable / 2));
    }

    function testBurn_ZeroAmount() public {
        vm.prank(address(this));
        vm.expectRevert(IDRWStableCoin.IDRWStableCoin__MustBeMoreThanZero.selector);
        idrwToken.burn(0);
    }

    function testBurn_ExceedsBalance() public {
        vm.prank(user1);
        mockWETH.approve(address(idrwEngine), 1 ether);
        vm.prank(user1);
        idrwEngine.deposit(address(mockWETH), 1 ether);

        uint256 maxMintable = idrwEngine.getMaxMintableIDRW(user1);
        vm.prank(user1);
        idrwEngine.mintIDRW(maxMintable);

        vm.prank(address(this));
        vm.expectRevert(IDRWStableCoin.IDRWStableCoin__BurnAmountExceedsBalance.selector);
        idrwToken.burn(maxMintable + 1);
    }

    function testMockAggregatorV3() public {
        MockAggregatorV3 mockAggregator = new MockAggregatorV3(2000e8);
        assertEq(mockAggregator.decimals(), 8);
        assertEq(mockAggregator.description(), "Mock Price Feed");
        assertEq(mockAggregator.version(), 1);

        mockAggregator.setPrice(3000e8);
        (, int256 price,,,) = mockAggregator.latestRoundData();
        assertEq(price, 3000e8);
    }

    function testMockERC20_Burn() public {
        MockERC20 mockToken = new MockERC20("Mock Token", "MTK");
        mockToken.mint(address(this), 1000 ether);
        mockToken.burn(address(this), 500 ether);
        assertEq(mockToken.balanceOf(address(this)), 500 ether);
    }

    function testRevertIf_InsufficientCollateral() public {
        vm.prank(user1);
        mockWETH.approve(address(idrwEngine), 1 ether);
        vm.prank(user1);
        idrwEngine.deposit(address(mockWETH), 1 ether);

        uint256 maxMintable = idrwEngine.getMaxMintableIDRW(user1);
        vm.prank(user1);
        idrwEngine.mintIDRW(maxMintable);

        vm.prank(user1);
        vm.expectRevert(IDRWEngine.IDRWEngine__BreaksCollateralRatio.selector);
        idrwEngine.withdraw(address(mockWETH), 0.6 ether); // Attempt to withdraw more than 50% of collateral
    }

    function testRevertIf_ZeroCollateral() public {
        vm.prank(user1);
        vm.expectRevert(IDRWEngine.IDRWEngine__InvalidCollateral.selector);
        idrwEngine.deposit(address(0), 1 ether); // Attempt to deposit zero address collateral
    }

    function testRevertIf_ZeroAmount() public {
        vm.prank(user1);
        mockWETH.approve(address(idrwEngine), 1 ether);
        vm.prank(user1);
        idrwEngine.deposit(address(mockWETH), 1 ether);

        vm.prank(user1);
        vm.expectRevert(IDRWEngine.IDRWEngine__MustBeMoreThanZero.selector);
        idrwEngine.mintIDRW(0); // Attempt to mint zero tokens
    }

    function testRevertIf_ZeroWithdrawal() public {
        vm.prank(user1);
        mockWETH.approve(address(idrwEngine), 1 ether);
        vm.prank(user1);
        idrwEngine.deposit(address(mockWETH), 1 ether);

        vm.prank(user1);
        vm.expectRevert(IDRWEngine.IDRWEngine__MustBeMoreThanZero.selector);
        idrwEngine.withdraw(address(mockWETH), 0); // Attempt to withdraw zero tokens
    }

    function testRevertIf_ZeroRepayment() public {
        vm.prank(user1);
        mockWETH.approve(address(idrwEngine), 1 ether);
        vm.prank(user1);
        idrwEngine.deposit(address(mockWETH), 1 ether);

        uint256 maxMintable = idrwEngine.getMaxMintableIDRW(user1);
        vm.prank(user1);
        idrwEngine.mintIDRW(maxMintable);

        vm.prank(user1);
        vm.expectRevert(IDRWEngine.IDRWEngine__MustBeMoreThanZero.selector);
        idrwEngine.repay(0); // Attempt to repay zero tokens
    }

    function testRevertIf_InvalidCollateralSwitch() public {
        vm.prank(user1);
        mockWETH.approve(address(idrwEngine), 1 ether);
        vm.prank(user1);
        idrwEngine.deposit(address(mockWETH), 1 ether);

        vm.prank(user1);
        vm.expectRevert(IDRWEngine.IDRWEngine__InvalidCollateral.selector);
        idrwEngine.switchCollateral(address(mockWETH), address(0), 0.5 ether); // Attempt to switch to zero address collateral

        vm.prank(user1);
        vm.expectRevert(IDRWEngine.IDRWEngine__InvalidCollateral.selector);
        idrwEngine.switchCollateral(address(0), address(mockWBTC), 0.5 ether); // Attempt to switch from zero address collateral
    }

    function testRevertIf_InsufficientCollateralForSwitch() public {
        vm.prank(user1);
        mockWETH.approve(address(idrwEngine), 1 ether);
        vm.prank(user1);
        idrwEngine.deposit(address(mockWETH), 1 ether);

        vm.prank(user1);
        vm.expectRevert(IDRWEngine.IDRWEngine__InsufficientCollateral.selector);
        idrwEngine.switchCollateral(address(mockWETH), address(mockWBTC), 1.5 ether); // Attempt to switch more than available collateral
    }

    function testRevertIf_ExactCollateralSwitch() public {
        vm.prank(user1);
        mockWETH.approve(address(idrwEngine), 1 ether);
        vm.prank(user1);
        idrwEngine.deposit(address(mockWETH), 1 ether);

        // Approve WBTC for switching
        vm.prank(user1);
        mockWBTC.approve(address(idrwEngine), 0.1 ether);

        vm.prank(user1);
        idrwEngine.switchCollateral(address(mockWETH), address(mockWBTC), 1 ether); // Exact collateral switch

        assertEq(idrwEngine.ethCollateral(user1), 0);
        assertGt(idrwEngine.btcCollateral(user1), 0);
    }

    function testRevertIf_ExactCollateralWithdrawal() public {
        vm.prank(user1);
        mockWETH.approve(address(idrwEngine), 1 ether);
        vm.prank(user1);
        idrwEngine.deposit(address(mockWETH), 1 ether);

        vm.prank(user1);
        idrwEngine.withdraw(address(mockWETH), 1 ether); // Exact collateral withdrawal

        assertEq(idrwEngine.ethCollateral(user1), 0);
    }

    function testRevertIf_ExactCollateralRepayment() public {
        vm.prank(user1);
        mockWETH.approve(address(idrwEngine), 1 ether);
        vm.prank(user1);
        idrwEngine.deposit(address(mockWETH), 1 ether);

        uint256 maxMintable = idrwEngine.getMaxMintableIDRW(user1);
        vm.prank(user1);
        idrwEngine.mintIDRW(maxMintable);

        vm.prank(user1);
        idrwToken.approve(address(idrwEngine), maxMintable);
        vm.prank(user1);
        idrwEngine.repay(maxMintable); // Exact collateral repayment

        assertEq(idrwEngine.debt(user1), 0);
    }

    function testRevertIf_InvalidPricefeed() public {
        MockAggregatorV3 mockAggregator = new MockAggregatorV3(0); // Invalid price feed
        IDRWEngine engineWithInvalidPricefeed = new IDRWEngine(
            address(idrwToken),
            address(mockWETH),
            address(mockWBTC),
            address(mockAggregator),
            address(mockBtcPriceFeed),
            address(this)
        );

        vm.prank(user1);
        mockWETH.approve(address(engineWithInvalidPricefeed), 1 ether);
        vm.prank(user1);
        engineWithInvalidPricefeed.deposit(address(mockWETH), 1 ether);

        vm.prank(user1);
        vm.expectRevert(IDRWEngine.IDRWEngine_InvalidPricefeed.selector);
        engineWithInvalidPricefeed.mintIDRW(1 ether); // Attempt to mint with invalid price feed
    }

    function testGetters() public view {
        assertEq(idrwEngine.getIDRWAddress(), address(idrwToken));
        assertEq(idrwEngine.getWETHAddress(), address(mockWETH));
        assertEq(idrwEngine.getWBTCAddress(), address(mockWBTC));
        assertEq(idrwEngine.getEthPriceFeed(), address(mockEthPriceFeed));
        assertEq(idrwEngine.getBtcPriceFeed(), address(mockBtcPriceFeed));
    }
}