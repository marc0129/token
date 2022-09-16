// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./abstracts/BaseContract.sol";
import "./interfaces/ISwapV2.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/// @custom:security-contact security@furio.io
contract AddLiquidityV2 is BaseContract
{
    /**
     * Contract initializer.
     * @dev This intializes all the parent contracts.
     */
    function initialize() public initializer
    {
        __BaseContract_init();
    }

    /**
     * Addresses.
     */
    address public lpStakingAddress;

    /**
     * Tokens.
     */
    IERC20 public fur;
    IERC20 public usdc;

    /**
     * Exchanges.
     */
    IUniswapV2Router02 public router;
    ISwapV2 public swap;

    /**
     * Intervals.
     */
    uint256 public addLiquidityInterval;
    uint256 public lastAdded;

    /**
     * Add liquidity.
     */
    function addLiquidity() external
    {
        if(lastAdded + addLiquidityInterval > block.timestamp) return;
        uint256 _usdcBalance_ = usdc.balanceOf(address(this));
        if(_usdcBalance_ == 0) return;
        // Swap half of USDC for FUR in order to add liquidity.
        usdc.approve(address(swap), _usdcBalance_ / 2);
        swap.buy(address(usdc), _usdcBalance_ / 2);
        // Get output from swap.
        uint256 _furBalance_ = fur.balanceOf(address(this));
        // Add liquidity.
        usdc.approve(address(router), _usdcBalance_ / 2);
        fur.approve(address(router), _furBalance_);
        router.addLiquidity(
            address(usdc),
            address(fur),
            _usdcBalance_ / 2,
            _furBalance_,
            0,
            0,
            lpStakingAddress,
            block.timestamp
        );
        lastAdded = block.timestamp;
    }

    /**
     * Setup.
     */
    function setup() external
    {
        // Addresses.
        lpStakingAddress = addressBook.get("lpStaking");
        // Tokens.
        fur = IERC20(addressBook.get("token"));
        usdc = IERC20(addressBook.get("payment"));
        // Exchanges.
        router = IUniswapV2Router02(addressBook.get("router"));
        swap = ISwapV2(addressBook.get("swap"));
        // Intervals.
        addLiquidityInterval = 2 days;
    }
}