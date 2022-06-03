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
import {IDelegateRegistry} from "../interfaces/snapshot/IDelegateRegistry.sol";
import {IBribesProcessor} from "../interfaces/badger/IBribesProcessor.sol";

contract MyStrategy is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    bool public withdrawalSafetyCheck = false;

    // If nothing is unlocked, processExpiredLocks will revert
    bool public processLocksOnReinvest = false;

    address public constant BADGER_TREE = address(0x660802Fc641b154aBA66a62137e71f331B6d787A);

    address public constant BADGER = address(0x3472A5A71965499acd81997a54BBA8D852C6E53d);

    IAuraLocker public constant LOCKER = IAuraLocker(0xDA00527EDAabCe6F97D89aDb10395f719E5559b9);

    IBalancerVault public constant BALANCER_VAULT = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    IERC20Upgradeable public constant WETH = IERC20Upgradeable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20Upgradeable public constant BAL = IERC20Upgradeable(0xba100000625a3754423978a60c9317c58a424e3D);
    IERC20Upgradeable public constant AURA = IERC20Upgradeable(address(0));
    IERC20Upgradeable public constant AURABAL = IERC20Upgradeable(address(0));
    IERC20Upgradeable public constant BALETH_BPT = IERC20Upgradeable(0x5c6Ee304399DBdB9C8Ef030aB642B10820DB8F56);

    bytes32 public constant AURABAL_BALETH_BPT_POOL_ID = bytes32(0);
    bytes32 public constant BAL_ETH_POOL_ID = 0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014;
    bytes32 public constant AURA_ETH_POOL_ID = bytes32(0);

    uint256 private constant WETH_INDEX = 1;

    IDelegateRegistry public constant SNAPSHOT = IDelegateRegistry(0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446);

    bytes32 public constant DELEGATED_SPACE = 0x6376782e65746800000000000000000000000000000000000000000000000000;

    // The initial INITIAL_DELEGATE for the strategy // NOTE we can change it by using manualSetDelegate below
    address public constant INITIAL_DELEGATE = address(0x781E82D5D49042baB750efac91858cB65C6b0582);

    address public constant BRIBES_PROCESSOR = address(0xb2Bf1d48F2C2132913278672e6924efda3385de2);

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

        // Delegate voting to INITIAL_DELEGATE
        SNAPSHOT.setDelegate(DELEGATED_SPACE, INITIAL_DELEGATE);
        autoCompoundRatio = MAX_BPS;
    }

    /// ===== Extra Functions =====

    /// @dev Change Delegation to another address
    function manualSetDelegate(address delegate) external {
        _onlyGovernance();
        // Set delegate is enough as it will clear previous delegate automatically
        SNAPSHOT.setDelegate(DELEGATED_SPACE, delegate);
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

    /// ===== View Functions =====

    function getBoostPayment() public view returns (uint256) {
        // uint256 maximumBoostPayment = LOCKER.maximumBoostPayment();
        // require(maximumBoostPayment <= 1500, "over max payment"); //max 15%
        // return maximumBoostPayment;
        return 0;
    }

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
                userData: abi.encode(ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, balEthBptBalance, WETH_INDEX),
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
        _deposit(harvested[0].amount);
    }

    /// @dev allows claiming of multiple bribes, badger is sent to tree
    /// @notice Hidden hand only allows to claim all tokens at once, not individually
    /// @notice allows claiming any token as it uses the difference in balance
    function claimBribesFromHiddenHand(IRewardDistributor hiddenHandDistributor, IRewardDistributor.Claim[] calldata _claims) external {
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
        IBribesProcessor(BRIBES_PROCESSOR).notifyNewRound();
    }

    /// @dev Send funds to the bribes receiver
    function _sendTokenToBribesProcessor(address token, uint256 amount) internal {
        IERC20Upgradeable(token).safeTransfer(BRIBES_PROCESSOR, amount);
        emit RewardsCollected(token, amount);
    }

    /// @dev Send the BADGER token to the badgerTree
    function _sendBadgerToTree(uint256 amount) internal {
        IERC20Upgradeable(BADGER).safeTransfer(BADGER_TREE, amount);
        _processExtraToken(address(BADGER), amount);
    }
}
