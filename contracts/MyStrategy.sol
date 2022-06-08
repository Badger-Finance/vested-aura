// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {IERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeMathUpgradeable} from "@openzeppelin-contracts-upgradeable/math/SafeMathUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import {BaseStrategy} from "@badger-finance/BaseStrategy.sol";

import {IVault} from "../interfaces/badger/IVault.sol";
import {IAsset} from "../interfaces/balancer/IAsset.sol";
import {ExitKind, IBalancerVault} from "../interfaces/balancer/IBalancerVault.sol";
import {IAuraLocker} from "../interfaces/aura/IAuraLocker.sol";
import {IRewardDistributor} from "../interfaces/hiddenhand/IRewardDistributor.sol";
import {IBribesProcessor} from "../interfaces/badger/IBribesProcessor.sol";

contract MyStrategy is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    bool public withdrawalSafetyCheck;
    // If nothing is unlocked, processExpiredLocks will revert
    bool public processLocksOnReinvest;

    IBribesProcessor public bribesProcessor;

    IBalancerVault public constant BALANCER_VAULT = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    address public constant BADGER = 0x3472A5A71965499acd81997a54BBA8D852C6E53d;
    address public constant BADGER_TREE = 0x660802Fc641b154aBA66a62137e71f331B6d787A;

    // TODO: Mainnet
    IAuraLocker public constant LOCKER = IAuraLocker(0x117f8Ec16C00C9F321129651abBc4A38caD350D2);

    // TODO: Mainnet
    IERC20Upgradeable public constant BAL = IERC20Upgradeable(0xcb355677E36f390Ccc4a5d4bEADFbF1Eb2071c81);
    IERC20Upgradeable public constant WETH = IERC20Upgradeable(0xdFCeA9088c8A88A76FF74892C1457C17dfeef9C1);
    IERC20Upgradeable public constant AURA = IERC20Upgradeable(0x16fe78B330B8C628DEA89344DB003a86B54Bb69d);
    IERC20Upgradeable public constant AURABAL = IERC20Upgradeable(0x11B2655B2F64a70888BcAF4AD340992AB6fc8cfa);
    IERC20Upgradeable public constant BALETH_BPT = IERC20Upgradeable(0xDC2EcFDf2688f92c85064bE0b929693ACC6dBcA6);

    // TODO: Mainnet
    bytes32 public constant AURABAL_BALETH_BPT_POOL_ID = 0xd97b6a43ee27267950aa55e9e38cc0ee4cf211c600020000000000000000092e;
    bytes32 public constant BAL_ETH_POOL_ID = 0xdc2ecfdf2688f92c85064be0b929693acc6dbca6000200000000000000000701;
    bytes32 public constant AURA_ETH_POOL_ID = 0x5e43529b3135181497b94869b7115aa318d56b94000200000000000000000930;

    uint256 private constant BPT_WETH_INDEX = 1;

    event RewardsCollected(address token, uint256 amount);

    /// @dev Initialize the Strategy with security settings as well as tokens
    /// @notice Proxies will set any non constant variable you declare as default value
    /// @dev add any extra changeable variable at end of initializer as shown
    function initialize(address _vault) public initializer {
        assert(IVault(_vault).token() == address(AURA));

        __BaseStrategy_init(_vault);

        want = address(AURA);

        /// @dev do one off approvals here
        // Permissions for Locker
        AURA.safeApprove(address(LOCKER), type(uint256).max);

        AURABAL.safeApprove(address(BALANCER_VAULT), type(uint256).max);
        WETH.safeApprove(address(BALANCER_VAULT), type(uint256).max);
    }

    /// ===== Extra Functions =====

    /// @dev Change Delegation to another address
    function manualSetDelegate(address delegate) external {
        _onlyGovernance();
        // Set delegate is enough as it will clear previous delegate automatically
        LOCKER.delegate(delegate);
    }

    ///@dev Should we check if the amount requested is more than what we can return on withdrawal?
    function setWithdrawalSafetyCheck(bool newWithdrawalSafetyCheck) external {
        _onlyGovernance();
        withdrawalSafetyCheck = newWithdrawalSafetyCheck;
    }

    ///@dev Should we processExpiredLocks during reinvest?
    function setProcessLocksOnReinvest(bool newProcessLocksOnReinvest) external {
        _onlyGovernance();
        processLocksOnReinvest = newProcessLocksOnReinvest;
    }

     ///@dev Change the contract that handles bribes
    function setBribesProcessor(IBribesProcessor newBribesProcessor) external {
        _onlyGovernance();
        bribesProcessor = newBribesProcessor;
    }

   /// ===== View Functions =====

    /// @dev Return the name of the strategy
    function getName() external pure override returns (string memory) {
        return "vlAURA Voting Strategy";
    }

    /// @dev Specify the version of the Strategy, for upgrades
    function version() external pure returns (string memory) {
        return "1.0";
    }

    /// @dev Does this function require `tend` to be called?
    function _isTendable() internal pure override returns (bool) {
        return false; // Change to true if the strategy should be tended
    }

    /// @dev Return the balance (in want) that the strategy has invested somewhere
    function balanceOfPool() public view override returns (uint256) {
        // Return the balance in locker
        IAuraLocker.Balances memory balances = LOCKER.balances(address(this));
        return balances.locked;
    }

    /// @dev Return the balance of rewards that the strategy has accrued
    /// @notice Used for offChain APY and Harvest Health monitoring
    function balanceOfRewards() external view override returns (TokenAmount[] memory rewards) {
        IAuraLocker.EarnedData[] memory earnedData = LOCKER.claimableRewards(address(this));
        uint256 numRewards = earnedData.length;
        rewards = new TokenAmount[](numRewards);
        for (uint256 i; i < numRewards; ++i) {
            rewards[i] = TokenAmount(earnedData[i].token, earnedData[i].amount);
        }
    }

    /// @dev Return a list of protected tokens
    /// @notice It's very important all tokens that are meant to be in the strategy to be marked as protected
    /// @notice this provides security guarantees to the depositors they can't be sweeped away
    function getProtectedTokens() public view virtual override returns (address[] memory) {
        address[] memory protectedTokens = new address[](2);
        protectedTokens[0] = want; // AURA
        protectedTokens[1] = address(AURABAL);
        return protectedTokens;
    }

    /// ===== Internal Core Implementations =====

    /// @dev Deposit `_amount` of want, investing it to earn yield
    function _deposit(uint256 _amount) internal override {
        // Lock tokens for 16 weeks, send credit to strat
        LOCKER.lock(address(this), _amount);
    }

    /// @dev utility function to withdraw all AURA that we can from the lock
    function prepareWithdrawAll() external {
        manualProcessExpiredLocks();
    }

    /// @dev Withdraw all funds, this is used for migrations, most of the time for emergency reasons
    function _withdrawAll() internal override {
        //NOTE: This probably will always fail unless we have all tokens expired
        require(
            balanceOfPool() == 0 && LOCKER.balanceOf(address(this)) == 0,
            "You have to wait for unlock or have to manually rebalance out of it"
        );

        // Make sure to call prepareWithdrawAll before _withdrawAll
    }

    /// @dev Withdraw `_amount` of want, so that it can be sent to the vault / depositor
    /// @notice just unlock the funds and return the amount you could unlock
    function _withdrawSome(uint256 _amount) internal override returns (uint256) {
        uint256 max = balanceOfWant();

        if (_amount > max) {
            // Try to unlock, as much as possible
            // @notice Reverts if no locks expired
            LOCKER.processExpiredLocks(false);
            max = balanceOfWant();
        }

        if (withdrawalSafetyCheck) {
            require(max >= _amount.mul(9_980).div(MAX_BPS), "Withdrawal Safety Check"); // 20 BP of slippage
        }

        if (_amount > max) {
            return max;
        }

        return _amount;
    }

    function _harvest() internal override returns (TokenAmount[] memory harvested) {
        // Claim auraBAL from locker
        LOCKER.getReward(address(this));

        harvested = new TokenAmount[](1);
        harvested[0].token = address(AURA);

        uint256 auraBalBalance = AURABAL.balanceOf(address(this));
        // auraBAL -> BAL/ETH BPT -> WETH -> AURA
        if (auraBalBalance > 0) {
            // Common structs for swaps
            IBalancerVault.SingleSwap memory singleSwap;
            IBalancerVault.FundManagement memory fundManagement = IBalancerVault.FundManagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(address(this)),
                toInternalBalance: false
            });

            // Swap auraBal -> BAL/ETH BPT
            singleSwap = IBalancerVault.SingleSwap({
                poolId: AURABAL_BALETH_BPT_POOL_ID,
                kind: IBalancerVault.SwapKind.GIVEN_IN,
                assetIn: IAsset(address(AURABAL)),
                assetOut: IAsset(address(BALETH_BPT)),
                amount: auraBalBalance,
                userData: new bytes(0)
            });
            uint256 balEthBptBalance = BALANCER_VAULT.swap(singleSwap, fundManagement, 0, type(uint256).max);

            // Withdraw BAL/ETH BPT -> WETH
            IAsset[] memory assets = new IAsset[](2);
            assets[0] = IAsset(address(BAL));
            assets[1] = IAsset(address(WETH));
            IBalancerVault.ExitPoolRequest memory exitPoolRequest = IBalancerVault.ExitPoolRequest({
                assets: assets,
                minAmountsOut: new uint256[](2),
                userData: abi.encode(ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, balEthBptBalance, BPT_WETH_INDEX),
                toInternalBalance: false
            });
            BALANCER_VAULT.exitPool(BAL_ETH_POOL_ID, address(this), payable(address(this)), exitPoolRequest);

            // Swap WETH -> AURA
            uint256 wethBalance = WETH.balanceOf(address(this));
            singleSwap = IBalancerVault.SingleSwap({
                poolId: AURA_ETH_POOL_ID,
                kind: IBalancerVault.SwapKind.GIVEN_IN,
                assetIn: IAsset(address(WETH)),
                assetOut: IAsset(address(AURA)),
                amount: wethBalance,
                userData: new bytes(0)
            });
            harvested[0].amount = BALANCER_VAULT.swap(singleSwap, fundManagement, 0, type(uint256).max);
        }

        _reportToVault(harvested[0].amount);
        if (harvested[0].amount > 0) {
            _deposit(harvested[0].amount);
        }
    }

    // TODO: Check this
    /// @dev allows claiming of multiple bribes, badger is sent to tree
    /// @notice Hidden hand only allows to claim all tokens at once, not individually
    /// @notice allows claiming any token as it uses the difference in balance
    function claimBribesFromHiddenHand(IRewardDistributor hiddenHandDistributor, IRewardDistributor.Claim[] calldata _claims) external {
        require(address(bribesProcessor) != address(0), "Bribes processor not set");

        uint256[] memory beforeBalance = new uint256[](_claims.length);
        uint256 beforeVaultBalance = _getBalance();
        uint256 beforePricePerFullShare = _getPricePerFullShare();

        // Track token balances before bribes claim
        for (uint256 i = 0; i < _claims.length; i++) {
            (address token, , , ) = hiddenHandDistributor.rewards(_claims[i].identifier);
            beforeBalance[i] = IERC20Upgradeable(token).balanceOf(address(this));
        }
        // Claim bribes
        hiddenHandDistributor.claim(_claims);

        bool nonZeroDiff; // Cached value but also to check if we need to notifyProcessor
        // Ultimately it's proof of non-zero which is good enough

        for (uint256 i = 0; i < _claims.length; i++) {
            (address token, , , ) = hiddenHandDistributor.rewards(_claims[i].identifier);
            uint256 difference = IERC20Upgradeable(token).balanceOf(address(this)).sub(beforeBalance[i]);
            if (difference > 0) {
                nonZeroDiff = true;
                _handleRewardTransfer(token, difference);
            }
        }

        if (nonZeroDiff) {
            _notifyBribesProcessor();
        }

        require(beforeVaultBalance == _getBalance(), "Balance can't change");
        require(beforePricePerFullShare == _getPricePerFullShare(), "Ppfs can't change");
    }

    // Example tend is a no-op which returns the values, could also just revert
    function _tend() internal override returns (TokenAmount[] memory tended) {
        revert("no op");
    }

    /// MANUAL FUNCTIONS ///

    /// @dev manual function to reinvest all Aura that was locked
    function reinvest() external whenNotPaused returns (uint256) {
        _onlyGovernance();

        if (processLocksOnReinvest) {
            // Withdraw all we can
            LOCKER.processExpiredLocks(false);
        }

        // Redeposit all into vlAURA
        uint256 toDeposit = IERC20Upgradeable(want).balanceOf(address(this));

        // Redeposit into vlAURA
        _deposit(toDeposit);

        return toDeposit;
    }

    /// @dev process all locks, to redeem
    /// @notice No Access Control Checks, anyone can unlock an expired lock
    function manualProcessExpiredLocks() public whenNotPaused {
        // Unlock vlAURA that is expired and redeem AURA back to this strat
        LOCKER.processExpiredLocks(false);
    }

    /// @dev Send all available Aura to the Vault
    /// @notice you can do this so you can earn again (re-lock), or just to add to the redemption pool
    function manualSendAuraToVault() external whenNotPaused {
        _onlyGovernance();
        uint256 auraAmount = balanceOfWant();
        _transferToVault(auraAmount);
    }

    function _getBalance() internal returns (uint256) {
        return IVault(vault).balance();
    }

    function _getPricePerFullShare() internal returns (uint256) {
        return IVault(vault).getPricePerFullShare();
    }

    /// *** Handling of rewards ***
    function _handleRewardTransfer(address token, uint256 amount) internal {
        // NOTE: BADGER is emitted through the tree
        if (token == BADGER) {
            _sendBadgerToTree(amount);
        } else {
            // NOTE: All other tokens are sent to bribes processor
            _sendTokenToBribesProcessor(token, amount);
        }
    }

    /// @dev Notify the BribesProcessor that a new round of bribes has happened
    function _notifyBribesProcessor() internal {
        bribesProcessor.notifyNewRound();
    }

    /// @dev Send funds to the bribes receiver
    function _sendTokenToBribesProcessor(address token, uint256 amount) internal {
        IERC20Upgradeable(token).safeTransfer(address(bribesProcessor), amount);
        emit RewardsCollected(token, amount);
    }

    /// @dev Send the BADGER token to the badgerTree
    function _sendBadgerToTree(uint256 amount) internal {
        IERC20Upgradeable(BADGER).safeTransfer(BADGER_TREE, amount);
        _processExtraToken(address(BADGER), amount);
    }
}
