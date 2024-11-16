// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;
    address wethUsdPriceFeed;
    address weth;
    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (wethUsdPriceFeed, , weth, , ) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    function testRevertsIfTokenLengthDoesNotMatchPriceFeedsLength() public {
        vm.startPrank(USER);
        address[] memory tokenAddresses = new address[](1);
        address[] memory priceFeedAddresses = new address[](2);
        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddressesArraysMustBeOfSameLength
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        vm.stopPrank();
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testDepositCollateral() public {
        // Start impersonating the USER address
        vm.startPrank(USER);

        // Approve the `dscEngine` to spend `AMOUNT_COLLATERAL`
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        // Check initial collateral balance
        uint256 initialCollateral = dscEngine.getCollateralBalance(USER, weth);
        assertEq(
            initialCollateral,
            0,
            "Initial collateral balance should be zero"
        );

        // Deposit collateral
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);

        // Check updated collateral balance
        uint256 updatedCollateral = dscEngine.getCollateralBalance(USER, weth);
        assertEq(
            updatedCollateral,
            AMOUNT_COLLATERAL,
            "Collateral balance not updated correctly"
        );

        // Stop impersonating the USER address
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedColateralValueInUsd = dscEngine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(collateralValueInUsd, expectedColateralValueInUsd);
    }

    function testRevertsWithUnapprovedCollateral() public {
        // Start impersonating the USER address
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);

        // Attempt to deposit collateral without approval
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotSupported.selector);
        dscEngine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);

        // Stop impersonating the USER address
        vm.stopPrank();
    }

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        console.log("ETH Amount:", ethAmount);
        uint256 expectedUsd = 30000e18;
        console.log("Expected USD:", expectedUsd);
        uint256 actualUsd = dscEngine.getUsdValue(weth, ethAmount);
        console.log("Actual USD:", actualUsd);
        assertEq(actualUsd, expectedUsd);
    }

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approveInternal(
            msg.sender,
            address(dscEngine),
            AMOUNT_COLLATERAL
        );

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }
}
