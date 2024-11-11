// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

    ///////////////////
    //State Variables//
    ///////////////////

    mapping(address token => address priceFeed) private s_priceFeed;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    DecentralizedStableCoin private immutable i_dsc;


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
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    function depositCollateralAndMintDsc() external {}

    /**
     * @dev Deposit collateral to mint DSC
     * @param tokenCollateralAddress The address of the token to be deposited as collateral
     * @param amountCollateral The amount of the token to be deposited as collateral
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        external
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

    function mintDsc() external {}

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
