// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./interfaces/IToken.sol";
import "./abstracts/BaseContract.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";


/**
 * @title FUR-USDC LP staking
 * @author Steve Harmeyer
 * @notice This contract offers LP holders can stake with any crypto.
 */

/// @custom:security-contact security@furio.io
contract LPStakingV1 is BaseContract
{
    using SafeMath for uint256;

    // is necessary to receive unused bnb from the swaprouter
    receive() external payable {}

    /**
     * Contract initializer.
     * @dev This intializes all the parent contracts.
     */
    function initialize() public initializer {
        __BaseContract_init();
        _lastUpdateTime = block.timestamp;
        _dividendsPerShareAccuracyFactor = 1e36;
    }
    /**
     * Staker struct.
     */
    struct Staker {
        uint256 stakingAmount;
        uint256 boostedAmount;
        uint256 rewardDebt;
        uint256 lastStakingUpdateTime;
        uint256 stakingPeriod;
    }
    /**
     * variables
     */
    address  public lpAddress;
    address  public usdcAddress;
    address  public routerAddress;
    address  public tokenAddress;
    IUniswapV2Router02 public router;
    address  _LPLockReceiver; //address for LP lock
    address[] LPholders; // LP holders address. to get LP reflection, they have to register thier address here.

    uint256  _lastUpdateTime; //LP RewardPool Updated time
    uint256  _accLPPerShare;  //Accumulated LPs per share, times 1e36. See below.
    uint256  _dividendsPerShareAccuracyFactor; //1e36

    uint256 public totalStakerNum; //total staker number
    uint256 public totalStakingAmount; //total staked LP amount
    uint256  _totalBoostedAmount; //total boosted amount for reward distrubution
    uint256  _totalReward;  //total LP amount for LP reward to LP stakers
    uint256  _totalReflection; //total LP amount to LP reflection to LP holders
    uint256  _LPLockAmount; // total locked LP amount. except from LP reflection

    /**
     * Mappings.
     */
    mapping(address => Staker) public stakers;
    mapping(address => uint256) _LPholderIndexes;
    mapping(address => address[]) public pathFromTokenToUSDC;

    /**
     * Event.
     */
    event Stake(address indexed staker, uint256 amount, uint256 duration);
    event ClaimRewards(address indexed staker, uint256 amount);
    event Compound(address indexed staker, uint256 amount);
    event Unstake(address indexed staker, uint256 amount);

    /**
     * Update addresses.
     * @dev Updates stored addresses.
     */
    function updateAddresses() public {

        IUniswapV2Factory _factory_ = IUniswapV2Factory(addressBook.get("factory"));
        lpAddress = _factory_.getPair(addressBook.get("payment"), addressBook.get("token"));
        _LPLockReceiver = addressBook.get("lpLockReceiver");
        usdcAddress = addressBook.get("payment");
        routerAddress = addressBook.get("router");
        tokenAddress = addressBook.get("token");
    }

    /**
     * Remaining Locked Time.
     */
    function getRemainingLockedTime(address stakerAddress) public view returns(uint256){

        if(stakers[stakerAddress].stakingPeriod == 0) return 0;
        return stakers[stakerAddress].lastStakingUpdateTime + stakers[stakerAddress].stakingPeriod - block.timestamp;
    }

    /**
     * total LP amount holded this contract
     */
    function _LPSupply_() external view returns (uint256) {

        return IERC20(lpAddress).balanceOf(address(this));
    }

    /**
     * claimable Reward for LP stakers
     * @param stakerAddress_ staker address
     * @return pending_ claimable LP amount
     */
    function pendingReward(address stakerAddress_)
        public
        view
        returns (uint256 pending_)
    {
        if (stakers[stakerAddress_].stakingAmount <= 0) return 0;

        pending_ = stakers[stakerAddress_].boostedAmount
            .mul(_accLPPerShare)
            .div(_dividendsPerShareAccuracyFactor)
            .sub(stakers[stakerAddress_].rewardDebt);
    }

    /**
     * Update reward pool for LP stakers.
     * @dev update _accLPPerShare
     */
    function updateRewardPool() public {

        if (lpAddress == address(0)) updateAddresses();

        uint256 _deltaTime_ = block.timestamp - _lastUpdateTime;
        if (_deltaTime_ < 24 hours) return;

        _distributeReflectionRewards();

        uint256 _times_ = _deltaTime_.div(24 hours);
        if (_times_ > 40) _times_ = 40;

        _totalReward = IERC20(lpAddress).balanceOf(address(this))
            .sub(totalStakingAmount)
            .sub(_totalReflection);

        if(_totalReward <= 0){
            _lastUpdateTime = block.timestamp;
            return;
        }

        uint256 _amountForReward_ = _totalReward.mul(25).div(1000).mul(_times_);

        uint256 _RewardPerShare_ = _amountForReward_
            .mul(_dividendsPerShareAccuracyFactor)
            .div(_totalBoostedAmount);

        _accLPPerShare = _accLPPerShare.add(_RewardPerShare_);

        _totalReward = _totalReward.sub(_amountForReward_);
        _lastUpdateTime = _lastUpdateTime.add(_times_.mul(24 hours));
    }

    /**
     * Stake for.
     * @param paymentAddress_ Payment token address.
     * @param paymentAmount_ Amount to stake.
     * @param durationIndex_ Duration index.
     * @param staker_ Staker address.
     */
    function stakeFor(address paymentAddress_, uint256 paymentAmount_, uint256 durationIndex_, address staker_) external
    {
        _stake(paymentAddress_, paymentAmount_, durationIndex_, staker_);
    }

    /**
     * Stake.
     * @param paymentAddress_ Payment token address.
     * @param paymentAmount_ Amount to stake.
     * @param durationIndex_ Duration index.
     */
    function stake(address paymentAddress_, uint256 paymentAmount_, uint256 durationIndex_) external
    {
        _stake(paymentAddress_, paymentAmount_, durationIndex_, msg.sender);
    }

    /**
     * Internal stake.
     * @param paymentAddress_ Payment token address.
     * @param paymentAmount_ Amount to stake.
     * @param durationIndex_ Duration index.
     * @param staker_ Staker address.
     */
    function _stake(address paymentAddress_, uint256 paymentAmount_, uint256 durationIndex_, address staker_) internal {

        if (lpAddress == address(0) || _LPLockReceiver == address(0) || usdcAddress == address(0))
            updateAddresses();

        require(durationIndex_ <= 3, "Non exist duration!");

        (uint256 _lpAmount_,,) = _buyLP(paymentAddress_, paymentAmount_);

        if (stakers[staker_].stakingAmount == 0) totalStakerNum++;

        updateRewardPool();

        //already staked member
        if (stakers[staker_].stakingAmount > 0) {

            if(stakers[staker_].stakingPeriod == 30 days)
                require(durationIndex_ >= 1, "you have to stake more than a month");

            if(stakers[staker_].stakingPeriod == 60 days)
                require(durationIndex_ >= 2, "you have to stake more than two month");

            if(stakers[staker_].stakingPeriod == 90 days)
                require(durationIndex_ == 3, "you have to stake during three month");

            uint256 _pending_ = pendingReward(staker_);
            if(_pending_ > 0){
                uint256 _usdcAmount_ = _sellLP(_pending_);
                IERC20(usdcAddress).transfer(staker_, _usdcAmount_);
            }

        }

        IERC20(lpAddress).transfer(
            _LPLockReceiver,
            _lpAmount_.mul(30).div(1000)
        );

        uint256 _boosting_lpAmount_;
        if (durationIndex_ == 0) {
            _boosting_lpAmount_ = _lpAmount_;
            stakers[staker_].stakingPeriod = 0;
        }

        if (durationIndex_ == 1) {
            _boosting_lpAmount_ = _lpAmount_.mul(102).div(100);
            stakers[staker_].stakingPeriod = 30 days;
        }
        if (durationIndex_ == 2) {
            _boosting_lpAmount_ = _lpAmount_.mul(105).div(100);
            stakers[staker_].stakingPeriod = 60 days;
        }
        if (durationIndex_ == 3) {
            _boosting_lpAmount_ = _lpAmount_.mul(110).div(100);
            stakers[staker_].stakingPeriod = 90 days;
        }

        stakers[staker_].stakingAmount = stakers[staker_].stakingAmount
            .add(_lpAmount_.mul(900).div(1000));

        stakers[staker_].boostedAmount = stakers[staker_].boostedAmount
            .add(_boosting_lpAmount_.mul(900).div(1000));

        stakers[staker_].rewardDebt = stakers[staker_].boostedAmount
            .mul(_accLPPerShare)
            .div(_dividendsPerShareAccuracyFactor);

        stakers[staker_].lastStakingUpdateTime = block.timestamp;

        totalStakingAmount = totalStakingAmount.add(_lpAmount_.mul(900).div(1000));
        _totalBoostedAmount = _totalBoostedAmount.add(
            _boosting_lpAmount_.mul(900).div(1000)
        );
        _totalReflection = _totalReflection.add(_lpAmount_.mul(20).div(1000));
        _LPLockAmount = _LPLockAmount.add(_lpAmount_.mul(30).div(1000));

        emit Stake(
            staker_,
            _lpAmount_,
            stakers[staker_].stakingPeriod
        );
    }

    /**
     * stake function
     * @param paymentAmount_ eth amount
     * @param durationIndex_ duration index.
     * @dev approve LP before staking.
     */
    function stakeWithEth(uint256 paymentAmount_, uint256 durationIndex_) public payable{

        if (lpAddress == address(0) || _LPLockReceiver == address(0) || usdcAddress == address(0))
            updateAddresses();

        require(durationIndex_ <= 3, "Non exist duration!");
        (uint256 _lpAmount_,,) = _buyLPWithEth(paymentAmount_);

        if (stakers[msg.sender].stakingAmount == 0) totalStakerNum++;

        updateRewardPool();

        //already staked member
        if (stakers[msg.sender].stakingAmount > 0) {

            if(stakers[msg.sender].stakingPeriod == 30 days)
                require(durationIndex_ >= 1, "you have to stake more than a month");

            if(stakers[msg.sender].stakingPeriod == 60 days)
                require(durationIndex_ >= 2, "you have to stake more than two month");

            if(stakers[msg.sender].stakingPeriod == 90 days)
                require(durationIndex_ == 3, "you have to stake during three month");

            uint256 _pending_ = pendingReward(msg.sender);
            if(_pending_ > 0){
                uint256 _usdcAmount_ = _sellLP(_pending_);
                IERC20(usdcAddress).transfer(msg.sender, _usdcAmount_);
            }
        }

        IERC20(lpAddress).transfer(
            _LPLockReceiver,
            _lpAmount_.mul(30).div(1000)
        );

        uint256 _boosting_lpAmount_;
        if (durationIndex_ == 0) {
            _boosting_lpAmount_ = _lpAmount_;
            stakers[msg.sender].stakingPeriod = 0;
        }

        if (durationIndex_ == 1) {
            _boosting_lpAmount_ = _lpAmount_.mul(102).div(100);
            stakers[msg.sender].stakingPeriod = 30 days;
        }
        if (durationIndex_ == 2) {
            _boosting_lpAmount_ = _lpAmount_.mul(105).div(100);
            stakers[msg.sender].stakingPeriod = 60 days;
        }
        if (durationIndex_ == 3) {
            _boosting_lpAmount_ = _lpAmount_.mul(110).div(100);
            stakers[msg.sender].stakingPeriod = 90 days;
        }

        stakers[msg.sender].stakingAmount = stakers[msg.sender].stakingAmount
            .add(_lpAmount_.mul(900).div(1000));

        stakers[msg.sender].boostedAmount = stakers[msg.sender].boostedAmount
            .add(_boosting_lpAmount_.mul(900).div(1000));

        stakers[msg.sender].rewardDebt = stakers[msg.sender].boostedAmount
            .mul(_accLPPerShare)
            .div(_dividendsPerShareAccuracyFactor);

        stakers[msg.sender].lastStakingUpdateTime = block.timestamp;

        totalStakingAmount = totalStakingAmount.add(_lpAmount_.mul(900).div(1000));
        _totalBoostedAmount = _totalBoostedAmount.add(
            _boosting_lpAmount_.mul(900).div(1000)
        );
        _totalReflection = _totalReflection.add(_lpAmount_.mul(20).div(1000));
        _LPLockAmount = _LPLockAmount.add(_lpAmount_.mul(30).div(1000));

        emit Stake(
            msg.sender,
            _lpAmount_,
            stakers[msg.sender].stakingPeriod
        );
    }

    /**
     * claim reward function for LP stakers
     @notice stakers can claim every 24 hours and receive it with USDC.
     */
    function claimRewards() public {

        if (lpAddress == address(0)) updateAddresses();

        if (stakers[msg.sender].stakingAmount <= 0) return;

        uint256 _pending_ = pendingReward(msg.sender);
        if (_pending_ == 0) return;
        uint256 _usdcAmount_ = _sellLP(_pending_);
        IERC20(usdcAddress).transfer(msg.sender, _usdcAmount_);

        stakers[msg.sender].rewardDebt = stakers[msg.sender].boostedAmount
            .mul(_accLPPerShare)
            .div(_dividendsPerShareAccuracyFactor);

        updateRewardPool();

        emit ClaimRewards(msg.sender, _pending_);
    }

    /**
     * compound function for LP stakers
     @notice stakers restake claimable LP every 24 hours without staking fee.
     */
    function compound() public {

        if (lpAddress == address(0)) updateAddresses();
        if (stakers[msg.sender].stakingAmount <= 0) return;

        uint256 _pending_ = pendingReward(msg.sender);
        if (_pending_ == 0) return;

        stakers[msg.sender].stakingAmount = stakers[msg.sender].stakingAmount
            .add(_pending_);
        stakers[msg.sender].boostedAmount = stakers[msg.sender].boostedAmount
            .add(_pending_);
        stakers[msg.sender].rewardDebt = stakers[msg.sender].boostedAmount
            .mul(_accLPPerShare)
            .div(_dividendsPerShareAccuracyFactor);

        totalStakingAmount = totalStakingAmount.add(_pending_);
        _totalBoostedAmount = _totalBoostedAmount.add(_pending_);

        updateRewardPool();

        emit Compound(msg.sender, _pending_);
    }

    /**
     * unstake function
     @notice stakers have to claim rewards before finishing stake.
     */
    function unstake() public {

        if (lpAddress == address(0) || _LPLockReceiver == address(0))
            updateAddresses();

        uint256 _lpAmount_ = stakers[msg.sender].stakingAmount;
        if (_lpAmount_ <= 0) return;
        require(
            block.timestamp - stakers[msg.sender].lastStakingUpdateTime >= stakers[msg.sender].stakingPeriod,
            "Don't finish your staking period!"
        );

        updateRewardPool();

        uint256 _pending_ = pendingReward(msg.sender);
        if(_pending_ > 0)
        {
            uint256 _Pendingusdc_ = _sellLP(_pending_);
            IERC20(usdcAddress).transfer(msg.sender, _Pendingusdc_);
        }

        uint256 _usdcAmount_ = _sellLP(_lpAmount_.mul(900).div(1000));
        IERC20(usdcAddress).transfer(msg.sender, _usdcAmount_);
        IERC20(lpAddress).transfer(_LPLockReceiver, _lpAmount_.mul(30).div(1000));

        _totalReflection = _totalReflection.add(_lpAmount_.mul(20).div(1000));
        _LPLockAmount = _LPLockAmount.add(_lpAmount_.mul(30).div(1000));
        _totalBoostedAmount = _totalBoostedAmount.sub(
            stakers[msg.sender].boostedAmount
        );
        totalStakingAmount = totalStakingAmount.sub(
            stakers[msg.sender].stakingAmount
        );
        totalStakerNum--;

        stakers[msg.sender].stakingAmount = 0;
        stakers[msg.sender].boostedAmount = 0;
        stakers[msg.sender].lastStakingUpdateTime = block.timestamp;
        stakers[msg.sender].stakingPeriod = 0;

        emit Unstake(msg.sender, _lpAmount_);
    }

    /**
     * reset staking duration function
     * @param durationIndex_ duration index.
     */
    function resetStakingPeriod(uint256 durationIndex_) public {

        require(durationIndex_ <= 3, "Non exist duration!");
        require (stakers[msg.sender].stakingAmount > 0, "Don't exist staked amount!");

        updateRewardPool();
        if(durationIndex_ == 0) return;
        if(stakers[msg.sender].stakingPeriod == 30 days)
            require(durationIndex_ >= 1, "you have to stake more than a month");
        if(stakers[msg.sender].stakingPeriod == 60 days)
            require(durationIndex_ >= 2, "you have to stake more than two month");
        if(stakers[msg.sender].stakingPeriod == 90 days)
            require(durationIndex_ == 3, "you have to stake during three month");

        uint256 _pending_ = pendingReward(msg.sender);
        if(_pending_ > 0){
            uint256 _usdcAmount_ = _sellLP(_pending_);
            IERC20(usdcAddress).transfer(msg.sender, _usdcAmount_);
        }

        uint256 _boosting_lpAmount_;
        if (durationIndex_ == 1) {
            _boosting_lpAmount_ = stakers[msg.sender].stakingAmount.mul(102).div(100);
            stakers[msg.sender].stakingPeriod = 30 days;
        }
        if (durationIndex_ == 2) {
            _boosting_lpAmount_ = stakers[msg.sender].stakingAmount.mul(105).div(100);
            stakers[msg.sender].stakingPeriod = 60 days;
        }
        if (durationIndex_ == 3) {
            _boosting_lpAmount_ = stakers[msg.sender].stakingAmount.mul(110).div(100);
            stakers[msg.sender].stakingPeriod = 90 days;
        }


        stakers[msg.sender].boostedAmount = _boosting_lpAmount_;
        stakers[msg.sender].rewardDebt = stakers[msg.sender].boostedAmount
            .mul(_accLPPerShare)
            .div(_dividendsPerShareAccuracyFactor);
        stakers[msg.sender].lastStakingUpdateTime = block.timestamp;

        emit Stake(
            msg.sender,
            stakers[msg.sender].stakingAmount,
            stakers[msg.sender].stakingPeriod
        );
    }

    /**
     * register LP holders address
     @notice LP holders have to register their address to get LP reflection.
     */
    function registerAddress() public {

        if (_LPLockReceiver == address(0)) updateAddresses();
        if (msg.sender == _LPLockReceiver) return;
        _LPholderIndexes[msg.sender] = LPholders.length;
        LPholders.push(msg.sender);
    }

    /**
     * remove LP holders address
     */
    function removeShareholder(address _holder) public {

        LPholders[_LPholderIndexes[_holder]] = LPholders[LPholders.length - 1];
        _LPholderIndexes[LPholders[LPholders.length - 1]] = _LPholderIndexes[_holder];
        LPholders.pop();
    }

    /**
     * LP reflection whenever stake and unstake
      *@notice give rewards with USDC
     */
    function _distributeReflectionRewards() internal {

        if (lpAddress == address(0)) updateAddresses();
        if (_totalReflection <= 0) return;

        //convert LP to USDC
        uint256 _totalReflectionUSDC_ = _sellLP(_totalReflection);

        uint256 _totalDividends_ = IERC20(lpAddress).totalSupply()
            .sub(totalStakingAmount)
            .sub(IERC20(lpAddress).balanceOf(_LPLockReceiver));

        uint256 _ReflectionPerShare_ = _totalReflectionUSDC_
            .mul(_dividendsPerShareAccuracyFactor)
            .div(_totalDividends_);

        for (uint256 i = 0; i < LPholders.length ; i++) {
            uint256 _balance_ = IERC20(lpAddress).balanceOf(LPholders[i]);
            if (_balance_ > 0)
                IERC20(usdcAddress).transfer(
                    LPholders[i],
                    _ReflectionPerShare_.mul(_balance_).div(_dividendsPerShareAccuracyFactor)
                );
            if (_balance_ == 0) removeShareholder(LPholders[i]);
        }
        _totalReflection = 0;
    }

    /**
     * Set Swap router path to swap any token to USDC
     * @param token_ token address to swap
     * @param pathToUSDC_ path address array
     */
    function setSwapPathFromTokenToUSDC(
        address token_,
        address[] memory pathToUSDC_
    ) public onlyOwner {

        if (usdcAddress == address(0)) updateAddresses();

        require(token_ != address(0), "Invalid token address");
        require(pathToUSDC_.length >= 2, "Invalid path length");
        require(pathToUSDC_[0] == token_, "Invalid starting token");
        require(pathToUSDC_[pathToUSDC_.length - 1] == usdcAddress,"Invalid ending token");

        pathFromTokenToUSDC[token_] = pathToUSDC_;
    }

    /**
     * buy LP with any crypto
     * @param paymentAddress_ token address that user is going to buy LP
     * @param paymentAmount_ token amount that user is going to buy LP
     * @return lpAmount_ LP amount that user received
     * @return unusedUSDC_ USDC amount that don't used to buy LP
     * @return unusedToken_ token amount that don't used to buy LP
     * @dev approve token before buyLP, LP goes to LPStaking contract, unused tokens go to buyer.
     */
    function _buyLP(address paymentAddress_, uint256 paymentAmount_)
        internal
        returns (
            uint256 lpAmount_,
            uint256 unusedUSDC_,
            uint256 unusedToken_
        )
    {

        if (routerAddress == address(0) || usdcAddress == address(0) || tokenAddress == address(0)) updateAddresses();

        require(routerAddress != address(0), "router address is not set");
        require(usdcAddress != address(0), "usdc address is not set");
        require(tokenAddress != address(0), "token address is not set");

        router = IUniswapV2Router02(routerAddress);
        IERC20 _usdc_ = IERC20(usdcAddress);
        require(address(paymentAddress_) != address(0), "Invalid Address");
        IERC20 _payment_ = IERC20(paymentAddress_);

        require(paymentAmount_ > 0, "Invalid amount");
        require(_payment_.balanceOf(msg.sender) >= paymentAmount_,"insufficient amount");
        _payment_.transferFrom(msg.sender, address(this), paymentAmount_);

        if (paymentAddress_ == usdcAddress) {
            (lpAmount_, unusedUSDC_, unusedToken_) = _buyLPwithUSDC(paymentAmount_);
            return (lpAmount_, unusedUSDC_, unusedToken_);
        }

        if (paymentAddress_ == tokenAddress) {
            (lpAmount_, unusedUSDC_, unusedToken_) = _buyLPwithFUR(paymentAmount_);
            return (lpAmount_, unusedUSDC_, unusedToken_);
        }

        address[] memory _pathFromTokenToUSDC = pathFromTokenToUSDC[paymentAddress_];
        require(_pathFromTokenToUSDC.length >=2, "Don't exist path");
        _payment_.approve(address(router), paymentAmount_);
        uint256 _USDCBalanceBefore1_ = _usdc_.balanceOf(address(this));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            paymentAmount_,
            0,
            _pathFromTokenToUSDC,
            address(this),
            block.timestamp + 1
        );
        uint256 _USDCBalance1_ = _usdc_.balanceOf(address(this)) - _USDCBalanceBefore1_;

        (lpAmount_, unusedUSDC_, unusedToken_) = _buyLPwithUSDC(_USDCBalance1_);
        return (lpAmount_, unusedUSDC_, unusedToken_);
    }

    /**
     * buy LP with eth
     * @param paymentAmount_ eth amount that user is going to buy LP
     * @return lpAmount_ LP amount that user received
     * @return unusedUSDC_ USDC amount that don't used to buy LP
     * @return unusedToken_ token amount that don't used to buy LP
     * @dev approve token before buyLP, LP goes to LPStaking contract, unused tokens go to buyer.
     */
    function _buyLPWithEth(uint256 paymentAmount_)
        internal
        returns (
            uint256 lpAmount_,
            uint256 unusedUSDC_,
            uint256 unusedToken_
        )
    {

        if (routerAddress == address(0) || usdcAddress == address(0) || tokenAddress == address(0)) updateAddresses();

        require(routerAddress != address(0), "router address is not set");
        require(usdcAddress != address(0), "usdc address is not set");
        require(tokenAddress != address(0), "token address is not set");

        router = IUniswapV2Router02(routerAddress);
        IERC20 _usdc_ = IERC20(usdcAddress);

        require(paymentAmount_ > 0, "Invalid amount");
        require(msg.value >= paymentAmount_, "insufficient amount");

        address[] memory _path_ = new address[](2);
        _path_[0] = address(router.WETH());
        _path_[1] = address(_usdc_);
        uint256 _USDCBalanceBefore_ = _usdc_.balanceOf(address(this));
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: paymentAmount_}(
            0,
            _path_,
            address(this),
            block.timestamp + 1
        );
        uint256 _USDCBalance_ = _usdc_.balanceOf(address(this)) - _USDCBalanceBefore_;

        (lpAmount_, unusedUSDC_, unusedToken_) = _buyLPwithUSDC(_USDCBalance_);
        return (lpAmount_, unusedUSDC_, unusedToken_);

    }

    /**
     * buy LP with USDC
     * @param paymentAmount_ USDC amount that user is going to buy LP
     * @return lpAmount_ LP amount that user received
     * @return unusedUSDC_ USDC amount that don't used to buy LP
     * @return unusedToken_ FUR amount that don't used to buy LP
     * @notice buyer can get unused USDC and token automatically, LP goes LPStaking contract
     */
    function _buyLPwithUSDC(uint256 paymentAmount_)
        internal
        returns (
            uint256 lpAmount_,
            uint256 unusedUSDC_,
            uint256 unusedToken_
        )
    {

        IERC20 _usdc_ = IERC20(usdcAddress);
        IToken _token_ = IToken(tokenAddress);
        router = IUniswapV2Router02(routerAddress);

        uint256 _amountToLiquify_ = paymentAmount_ / 2;
        uint256 _amountToSwap_ = paymentAmount_ - _amountToLiquify_;
        if (_amountToSwap_ == 0) return (0, 0, 0);

        address[] memory _path_ = new address[](2);
        _path_[0] = address(_usdc_);
        _path_[1] = address(_token_);
        _usdc_.approve(address(router), _amountToSwap_);
        uint256 _balanceBefore_ = _token_.balanceOf(address(this));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amountToSwap_,
            0,
            _path_,
            address(this),
            block.timestamp + 1
        );
        uint256 _amountUSDC_ = _token_.balanceOf(address(this)) -_balanceBefore_;

        if (_amountToLiquify_ <= 0 || _amountUSDC_ <= 0) return (0, 0, 0);
        _usdc_.approve(address(router), _amountToLiquify_);
        _token_.approve(address(router), _amountUSDC_);

        (
            uint256 _usedPaymentToken_,
            uint256 _usedToken_,
            uint256 _lpValue_
        ) = router.addLiquidity(
                address(_usdc_),
                address(_token_),
                _amountToLiquify_,
                _amountUSDC_,
                0,
                0,
                address(this),
                block.timestamp + 1
            );
        lpAmount_ = _lpValue_;
        unusedUSDC_ = _amountToLiquify_ - _usedPaymentToken_;
        unusedToken_ = _amountUSDC_ - _usedToken_;

        // send back unused tokens
        _usdc_.transfer(msg.sender, unusedUSDC_);
        _token_.transfer(msg.sender, unusedToken_);
    }

    /**
     * buy LP with FUR
     * @param paymentAmount_ $FUR amount that user is going to buy LP
     * @return lpAmount_ LP amount that user received
     * @return unusedUSDC_ USDC amount that don't used to buy LP
     * @return unusedToken_ $FUR amount that don't used to buy LP
     * @notice buyer can get unused USDC and token automatically, LP goes LPStaking contract
     */
    function _buyLPwithFUR(uint256 paymentAmount_)
        internal
        returns (
            uint256 lpAmount_,
            uint256 unusedUSDC_,
            uint256 unusedToken_
        )
    {

        IERC20 _usdc_ = IERC20(usdcAddress);
        IToken _token_ = IToken(tokenAddress);
        router = IUniswapV2Router02(routerAddress);

        uint256 _amountToLiquify_ = paymentAmount_ / 2;
        uint256 _amountToSwap_ = paymentAmount_ - _amountToLiquify_;
        if (_amountToSwap_ == 0) return (0, 0, 0);

        address[] memory _path_ = new address[](2);
        _path_[0] = address(_token_);
        _path_[1] = address(_usdc_);
        _token_.approve(address(router), _amountToSwap_);
        uint256 _balanceBefore_ = _usdc_.balanceOf(address(this));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amountToSwap_,
            0,
            _path_,
            address(this),
            block.timestamp + 1
        );
        uint256 _amountUSDC_ = _usdc_.balanceOf(address(this)) -_balanceBefore_;

        if (_amountToLiquify_ <= 0 || _amountUSDC_ <= 0) return (0, 0, 0);
        _token_.approve(address(router), _amountToLiquify_);
        _usdc_.approve(address(router), _amountUSDC_);

        (
            uint256 _usedPaymentToken_,
            uint256 _usedToken_,
            uint256 _lpValue_
        ) = router.addLiquidity(
                address(_usdc_),
                address(_token_),
                _amountUSDC_,
                _amountToLiquify_,
                0,
                0,
                address(this),
                block.timestamp + 1
            );
        lpAmount_ = _lpValue_;
        unusedToken_ = _amountToLiquify_ - _usedToken_;
        unusedUSDC_ = _amountUSDC_ - _usedPaymentToken_;

        // send back unused tokens
        _usdc_.transfer(msg.sender, unusedUSDC_);
        _token_.transfer(msg.sender, unusedToken_);
    }

    /**
     * Sell LP
     * @param lpAmount_ LP amount that user is going to sell
     * @return paymentAmount_ USDC amount that user received
     * @dev approve LP before this function calling, usdc goes to LPStaking contract
     */
    function _sellLP(uint256 lpAmount_) internal returns (uint256 paymentAmount_) {
        if (
            routerAddress == address(0) ||
            tokenAddress == address(0) ||
            usdcAddress == address(0) ||
            lpAddress == address(0)
        ) updateAddresses();

        IERC20 _usdc_ = IERC20(usdcAddress);
        IERC20 _token_ = IERC20(tokenAddress);
        router = IUniswapV2Router02(routerAddress);
        IERC20 _lptoken_ = IERC20(lpAddress);
        require(address(_usdc_) != address(0), "Payment not set");
        require(address(_token_) != address(0), "Token not set");
        require(address(router) != address(0), "Router not set");
        require(address(_lptoken_) != address(0), "_lptoken_ not set");

        if (lpAmount_ <= 0) return 0;

        _lptoken_.approve(address(router), lpAmount_);
        uint256 _tokenBalanceBefore_ = _token_.balanceOf(address(this));
        (uint256 _USDCFromRemoveLiquidity_, ) = router.removeLiquidity(
            address(_usdc_),
            address(_token_),
            lpAmount_,
            0,
            0,
            address(this),
            block.timestamp + 1
        );

        uint256 _tokenBalance_ = _token_.balanceOf(address(this)) -_tokenBalanceBefore_;
        if (_tokenBalance_ == 0) return 0;

        _token_.approve(address(router), _tokenBalance_);
        address[] memory path = new address[](2);
        path[0] = address(_token_);
        path[1] = address(_usdc_);
        uint256 _USDCbalanceBefore_ = _usdc_.balanceOf(address(this));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _tokenBalance_,
            0,
            path,
            address(this),
            block.timestamp + 1
        );
        uint256 _USDCFromSwap = _usdc_.balanceOf(address(this)) - _USDCbalanceBefore_;

        paymentAmount_ = _USDCFromRemoveLiquidity_ + _USDCFromSwap;
    }

    function withdrawLP() external onlyOwner {
        if (lpAddress == address(0)) updateAddresses();
        IERC20(lpAddress).transfer(msg.sender, IERC20(lpAddress).balanceOf(address(this)));
    }
    function withdrawUSDC() external onlyOwner {
        if (usdcAddress == address(0)) updateAddresses();
        IERC20(usdcAddress).transfer(msg.sender, IERC20(usdcAddress).balanceOf(address(this)));
    }
    function withdrawFUR() external onlyOwner {
        if (tokenAddress == address(0)) updateAddresses();
        IERC20(tokenAddress).transfer(msg.sender, IERC20(tokenAddress).balanceOf(address(this)));
    }

    /**
     * Total staking amount in USDC.
     * @return uint256 Total amount staked in USDC.
     * @dev Calculates the USDC value of the total staked amount.
     */
    function totalStakingAmountInUsdc() external returns (uint256)
    {
        return 0;
    }

    /**
     * Staking amount in USDC.
     * @param staker_ Staker address.
     * @return uint256 Amount staked by address in USDC.
     * @dev Calculates the USDC value of the amount staked by an address.
     */
    function stakingAmountInUsdc(address staker_) external returns (uint256)
    {
        return 0;
    }

    /**
     * Boosted amount in USDC.
     * @param staker_ Staker address.
     * @return uint256 Boosted amount by address in USDC.
     * @dev Calculates the USDC value of the boosted amount by an address.
     */
    function boostedAmountInUsdc(address staker_) external returns (uint256)
    {
        return 0;
    }

    /**
     * Rewarded amount in USDC.
     * @param staker_ Staker address.
     * @return uint256 Rewarded amount by address in USDC.
     * @dev Calculates the USDC value of the rewarded amount by an address.
     */
    function rewardedAmountInUsdc(address staker_) external returns (uint256)
    {
        return 0;
    }

    /**
     * Available rewards in USDC.
     * @param staker_ Staker address.
     * @return uint256 Available rewards by address in USDC.
     * @dev Calculates the USDC value of the available rewards by an address.
     */
    function availableRewardsInUsdc(address staker_) external returns (uint256)
    {
        return 0;
    }

    /**
     * Get LP price in USDC.
     * @return uint256 LP price.
     * @dev Internal function to get the LP price in USDC.
     */
    function _getLpPriceInUsdc() internal returns (uint256)
    {
        return 0;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[45] private __gap;
}
