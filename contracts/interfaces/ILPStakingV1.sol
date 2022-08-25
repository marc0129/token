// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface ILPStakingV1 {
    function _LPSupply_ (  ) external view returns ( uint256 );
    function addressBook (  ) external view returns ( address );
    function availableRewardsInUsdc ( address staker_ ) external returns ( uint256 );
    function boostedAmountInUsdc ( address staker_ ) external returns ( uint256 );
    function claimRewards (  ) external;
    function compound (  ) external;
    function getRemainingLockedTime ( address stakerAddress ) external view returns ( uint256 );
    function initialize (  ) external;
    function lpAddress (  ) external view returns ( address );
    function owner (  ) external view returns ( address );
    function pathFromTokenToUSDC ( address, uint256 ) external view returns ( address );
    function pause (  ) external;
    function paused (  ) external view returns ( bool );
    function pendingReward ( address stakerAddress_ ) external view returns ( uint256 pending_ );
    function proxiableUUID (  ) external view returns ( bytes32 );
    function registerAddress (  ) external;
    function removeShareholder ( address _holder ) external;
    function renounceOwnership (  ) external;
    function resetStakingPeriod ( uint256 durationIndex_ ) external;
    function rewardedAmountInUsdc ( address staker_ ) external returns ( uint256 );
    function router (  ) external view returns ( address );
    function routerAddress (  ) external view returns ( address );
    function setAddressBook ( address address_ ) external;
    function setSwapPathFromTokenToUSDC ( address token_, address[] memory pathToUSDC_ ) external;
    function stake ( address paymentAddress_, uint256 paymentAmount_, uint256 durationIndex_ ) external;
    function stakeFor ( address paymentAddress_, uint256 paymentAmount_, uint256 durationIndex_, address staker_ ) external;
    function stakeWithEth ( uint256 paymentAmount_, uint256 durationIndex_ ) external;
    function stakers ( address ) external view returns ( uint256 stakingAmount, uint256 boostedAmount, uint256 rewardDebt, uint256 lastStakingUpdateTime, uint256 stakingPeriod );
    function stakingAmountInUsdc ( address staker_ ) external returns ( uint256 );
    function tokenAddress (  ) external view returns ( address );
    function totalStakerNum (  ) external view returns ( uint256 );
    function totalStakingAmount (  ) external view returns ( uint256 );
    function totalStakingAmountInUsdc (  ) external returns ( uint256 );
    function transferOwnership ( address newOwner ) external;
    function unpause (  ) external;
    function unstake (  ) external;
    function updateAddresses (  ) external;
    function updateRewardPool (  ) external;
    function upgradeTo ( address newImplementation ) external;
    function upgradeToAndCall ( address newImplementation, bytes memory data ) external;
    function usdcAddress (  ) external view returns ( address );
    function withdrawFUR (  ) external;
    function withdrawLP (  ) external;
    function withdrawUSDC (  ) external;
}
