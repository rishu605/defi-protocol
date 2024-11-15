// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {console} from "forge-std/console.sol";

/* @title DSCEngine
 * The system is designed to be as minimal as possible and have the token
 * maintain a 1 token == $1 peg
 *
 Stablecoin has following properties:
 * 1. Collateral: Exogenous (ETH & BTC)
 * 2. Relative Stability: Pegged to USD
 * 3. Algorithmically Stable
 *
 * Our DSC System should always be over-collateralized.
 * At no point should the value of all collateral be less than $ backed value of all the DSC
 * It is similar to DAI if DAI had no governance, no fees and was only backed by wETH and wBTC
 * This contract is the core of the DSC System. It handles all the logic for mining
 * and redeeming the DSC as well as depositing and withdrawing collateral
 * This contract is very loosly based o the MakerDAO DSC System
 */

contract DSCEngine is ReentrancyGuard {
    //////////////////
    //////ERRORS//////
    //////////////////
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesArraysMustBeOfSameLength();
    error DSCEngine__TokenNotSupported();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorBelowThreshold(uint256);
    error DSCEngine__MintFailed();

    ///////////////////
    //State Variables//
    ///////////////////

    mapping(address token => address priceFeed) private s_priceFeed;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    DecentralizedStableCoin private immutable i_dsc;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    address[] private s_collateralTokens;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10; // Chainlik returns numbers with 8 decimal places,
    // so we need to multiply by 1e10 to get the correct value
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // Therefore 200% collateralization ratio
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    ///////////////////
    ///////Events//////
    ///////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    //////////////////
    ////MODIFIERS/////
    //////////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeed[token] == address(0)) {
            revert DSCEngine__TokenNotSupported();
        }
        _;
    }

    //////////////////
    ////FUNCTIONS/////
    //////////////////

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesArraysMustBeOfSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeed[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }
    /**
     * @param tokenCollateralAddress The address of the token to be deposited as collateral
     * @param amountCollateral The amount of the token to be deposited as collateral
     * @param amountDscToMint The amount of DSC to mint
     * @notice This function is a convenience function to deposit collateral and mint DSC in single transaction 
     */
    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @dev Deposit collateral to mint DSC
     * @param tokenCollateralAddress The address of the token to be deposited as collateral
     * @param amountCollateral The amount of the token to be deposited as collateral
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if(!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    /**
     * @dev Mint DSC
     * @param amountDscToMint The amount of DSC to mint
     * Check if the user has enough collateral to mint DSC
     * Collateral value >> DSC amount to be minted
     */
    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if(!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    function _getAccountInformation(address user) private view returns(uint256, uint256) {
        uint256 totalDscMinted = s_DSCMinted[user];
        uint256 collateralValueInUsd = getCollateralValue(user);
        return (totalDscMinted, collateralValueInUsd);
    }

    /**
     * @dev Calculate the health factor of a user
     * @param user The address of the user
     * Returns how close the user is to being liquidated
     * If the user goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns(uint256){
        // Need the values of:
        // 1. total DSC minted
        // 2. total collateral deposited
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function  revertIfHealthFactorIsBroken(address user) internal view {
        // Check if the user has enough collateral to mint DSC
        // Revert if not enough collateral
        uint256 userHealthFactor = _healthFactor(user);
        if(userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorBelowThreshold(userHealthFactor);

        }
    }

    function getCollateralValue(address user) public view returns(uint256 totalCollateralValueInUsd) {
        // Loop through each collateral token, get the amount of tokens they have deposited,
        // map it to the price to get the USD value of the collateral
        for(uint256 i = 0; i<s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns(uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[token]);
        console.log("priceFeed: ", address(priceFeed));
        (, int256 price, , , ) = priceFeed.latestRoundData();
        // If 1 Eth = $1000 then returned value from Chainlink pricefeed will be:
        // 1000 * 1e8 = 100000000000
        console.log("price: ",  price);
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
