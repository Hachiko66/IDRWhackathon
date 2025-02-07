// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IDRWStableCoin} from "./IDRWStableCoin.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract IDRWEngine is Ownable {
    using SafeERC20 for IERC20;

    error IDRWEngine__InvalidCollateral();
    error IDRWEngine__TransferFailed();
    error IDRWEngine__BreaksCollateralRatio();
    error IDRWEngine__InsufficientCollateral();
    error IDRWEngine__MintFailed();
    error IDRWEngine__BurnFailed();
    error IDRWEngine__NotAllowed();
    error IDRWEngine__MustBeMoreThanZero();
    error IDRWEngine_InvalidPricefeed();

    IDRWStableCoin private immutable i_idrw;
    address private immutable i_weth;
    address private immutable i_wbtc;
    AggregatorV3Interface private immutable i_ethPriceFeed;
    AggregatorV3Interface private immutable i_btcPriceFeed;

    uint256 private constant COLLATERAL_RATIO = 150; // 150%
    uint256 private constant PRICE_FEED_DECIMALS = 8;
    uint256 private constant COLLATERAL_DECIMALS = 18;

    mapping(address => uint256) public ethCollateral;
    mapping(address => uint256) public btcCollateral;
    mapping(address => uint256) public debt;

    event CollateralDeposited(address indexed user, address collateral, uint256 amount);
    event CollateralWithdrawn(address indexed user, address collateral, uint256 amount);
    event IDRWMinted(address indexed user, uint256 amount);
    event IDRWRepaid(address indexed user, uint256 amount);
    event CollateralSwitched(address indexed user, address fromCollateral, address toCollateral, uint256 amount);

    constructor(
        address idrwAddress,
        address wethAddress,
        address wbtcAddress,
        address ethPriceFeed,
        address btcPriceFeed,
        address initialOwner
    ) Ownable(initialOwner) {
        i_idrw = IDRWStableCoin(idrwAddress);
        i_weth = wethAddress;
        i_wbtc = wbtcAddress;
        i_ethPriceFeed = AggregatorV3Interface(ethPriceFeed);
        i_btcPriceFeed = AggregatorV3Interface(btcPriceFeed);
    }

    function deposit(address collateralToken, uint256 amount) external {
        if (collateralToken != i_weth && collateralToken != i_wbtc) revert IDRWEngine__InvalidCollateral();
        if (amount == 0) revert IDRWEngine__MustBeMoreThanZero();

        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), amount);

        if (collateralToken == i_weth) {
            ethCollateral[msg.sender] += amount;
        } else {
            btcCollateral[msg.sender] += amount;
        }

        emit CollateralDeposited(msg.sender, collateralToken, amount);
    }

    function mintIDRW(uint256 amount) external {
        if (amount == 0) revert IDRWEngine__MustBeMoreThanZero();

        // Hitung total nilai kolateral pengguna
        uint256 totalCollateralValue = _getTotalCollateralValue(msg.sender);

        // Hitung utang baru
        uint256 newDebt = debt[msg.sender] + amount;

        // Hitung nilai kolateral minimum yang diperlukan
        uint256 minCollateralValue = (newDebt * COLLATERAL_RATIO) / 100;

        // Pastikan nilai kolateral memenuhi rasio minimum
        if (totalCollateralValue < minCollateralValue) revert IDRWEngine__BreaksCollateralRatio();

        // Update utang dan cetak IDRW
        debt[msg.sender] = newDebt;
        if (!i_idrw.mint(msg.sender, amount)) revert IDRWEngine__MintFailed();
        emit IDRWMinted(msg.sender, amount);
    }

    function getMaxMintableIDRW(address user) public view returns (uint256) {
        uint256 totalCollateralValue = _getTotalCollateralValue(user);
        uint256 currentDebt = debt[user];

        // Hitung maksimal IDRW yang dapat dicetak
        uint256 maxIDRW = (totalCollateralValue * 100) / COLLATERAL_RATIO;
        if (maxIDRW <= currentDebt) return 0; // Tidak bisa mencetak lebih banyak

        return maxIDRW - currentDebt;
    }

    function withdraw(address collateralToken, uint256 amount) external {
        if (collateralToken != i_weth && collateralToken != i_wbtc) revert IDRWEngine__InvalidCollateral();
        if (amount == 0) revert IDRWEngine__MustBeMoreThanZero();

        if (collateralToken == i_weth) {
            if (ethCollateral[msg.sender] < amount) revert IDRWEngine__InsufficientCollateral();
            ethCollateral[msg.sender] -= amount;
        } else {
            if (btcCollateral[msg.sender] < amount) revert IDRWEngine__InsufficientCollateral();
            btcCollateral[msg.sender] -= amount;
        }

        if (_getTotalCollateralValue(msg.sender) < (debt[msg.sender] * COLLATERAL_RATIO) / 100) {
            revert IDRWEngine__BreaksCollateralRatio();
        }

        IERC20(collateralToken).safeTransfer(msg.sender, amount);
        emit CollateralWithdrawn(msg.sender, collateralToken, amount);
    }

    function repay(uint256 amount) external {
        if (amount == 0) revert IDRWEngine__MustBeMoreThanZero();
        if (debt[msg.sender] < amount) revert IDRWEngine__BurnFailed();

        //pengurangan Hutang untuk memeriksa Ratio
        uint256 simulatedDebt = debt[msg.sender] - amount;
        uint256 totalCollateralValue = _getTotalCollateralValue(msg.sender);
        uint256 minCollateralValue = (simulatedDebt * COLLATERAL_RATIO) / 100;
        if (totalCollateralValue < minCollateralValue) revert IDRWEngine__BreaksCollateralRatio();

        debt[msg.sender] -= amount;
        emit IDRWRepaid(msg.sender, amount);
    }

    function switchCollateral(address fromCollateral, address toCollateral, uint256 amount) external {
        if (
            (fromCollateral != i_weth && fromCollateral != i_wbtc) || (toCollateral != i_weth && toCollateral != i_wbtc)
        ) revert IDRWEngine__InvalidCollateral();
        if (amount == 0) revert IDRWEngine__MustBeMoreThanZero();

        // Hitung nilai USD dari kolateral yang di-switch
        uint256 fromValue = _getCollateralValue(fromCollateral, amount);
        uint256 toAmount = _getCollateralAmount(toCollateral, fromValue);

        // Kurangi saldo kolateral lama
        if (fromCollateral == i_weth) {
            if (ethCollateral[msg.sender] < amount) revert IDRWEngine__InsufficientCollateral();
            ethCollateral[msg.sender] -= amount;
            IERC20(i_weth).safeTransfer(msg.sender, amount); // Kembalikan kolateral lama ke pengguna
        } else {
            if (btcCollateral[msg.sender] < amount) revert IDRWEngine__InsufficientCollateral();
            btcCollateral[msg.sender] -= amount;
            IERC20(i_wbtc).safeTransfer(msg.sender, amount); // Kembalikan kolateral lama ke pengguna
        }

        // Tambah saldo kolateral baru
        IERC20(toCollateral).safeTransferFrom(msg.sender, address(this), toAmount);
        if (toCollateral == i_weth) {
            ethCollateral[msg.sender] += toAmount;
        } else {
            btcCollateral[msg.sender] += toAmount;
        }

        emit CollateralSwitched(msg.sender, fromCollateral, toCollateral, amount);
    }
    
    function _getTotalCollateralValue(address user) public view returns (uint256) {
        return _getCollateralValue(i_weth, ethCollateral[user]) + _getCollateralValue(i_wbtc, btcCollateral[user]);
    }

    function _getCollateralValue(address collateralToken, uint256 amount) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = collateralToken == i_weth ? i_ethPriceFeed : i_btcPriceFeed;
        (, int256 price,,,) = priceFeed.latestRoundData();
        if (price <= 0) revert IDRWEngine_InvalidPricefeed();
        uint256 adjustedPrice = uint256(price) * 1e10; // Convert price to 18 decimals

        return (amount * adjustedPrice) / (10 ** (COLLATERAL_DECIMALS + PRICE_FEED_DECIMALS));
    }

    function _getCollateralAmount(address collateralToken, uint256 usdValue) private view returns (uint256) {
        AggregatorV3Interface priceFeed = collateralToken == i_weth ? i_ethPriceFeed : i_btcPriceFeed;
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint256 adjustedPrice = uint256(price) * 1e10; // Convert price to 18 decimals

        return (usdValue * 10 ** (COLLATERAL_DECIMALS + PRICE_FEED_DECIMALS)) / adjustedPrice;
    }

    function getIDRWAddress() public view returns (address) {
        return address(i_idrw);
    }

    function getWETHAddress() public view returns (address) {
        return i_weth;
    }

    function getWBTCAddress() public view returns (address) {
        return i_wbtc;
    }

    function getEthPriceFeed() public view returns (address) {
        return address(i_ethPriceFeed);
    }

    function getBtcPriceFeed() public view returns (address) {
        return address(i_btcPriceFeed);
    }
}
