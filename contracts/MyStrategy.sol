// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {IERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeMathUpgradeable} from "@openzeppelin-contracts-upgradeable/math/SafeMathUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import {BaseStrategy} from "@badger-finance/BaseStrategy.sol";

import {IVault} from "../interfaces/badger/IVault.sol";
import {IAuraLocker} from "../interfaces/aura/IAuraLocker.sol";
import {IRewardDistributor} from "../interfaces/hiddehand/IRewardDistributor.sol";

contract MyStrategy is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    bool public withdrawalSafetyCheck = false;

    // If nothing is unlocked, processExpiredLocks will revert
    bool public processLocksOnReinvest = false;

    address public constant BADGER_TREE = 0x660802Fc641b154aBA66a62137e71f331B6d787A;

    IAuraLocker public constant LOCKER = IAuraLocker(0xDA00527EDAabCe6F97D89aDb10395f719E5559b9);

    IERC20Upgradeable public constant AURA = IERC20Upgradeable(0xc5A9848b9d145965d821AaeC8fA32aaEE026492d);
    IERC20Upgradeable public constant AURABAL = IERC20Upgradeable(0xDA0053F0bEfCbcaC208A3f867BB243716734D809);
    //TODO: Make aurabal vault
    IVault public constant AURABAL_VAULT = IVault();

    // The initial INITIAL_DELEGATE for the strategy // NOTE we can change it by using manualSetDelegate below
    address public constant INITIAL_DELEGATE = address(0x781E82D5D49042baB750efac91858cB65C6b0582);

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
        AURABAL.safeApprove(address(AURABAL_VAULT), type(uint256).max);

        autoCompoundRatio = MAX_BPS;
    }

    /// ===== Extra Functions =====

    /// @dev Change Delegation to another address
    function manualSetDelegate(address delegate) external {
        _onlyGovernance();
        // Set delegate is enough as it will clear previous delegate automatically
        //TODO: Figure out Voting snapshot for aura
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
        return LOCKER.lockedBalanceOf(address(this));
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
        // Lock tokens for 16 weeks, send credit to strat, always use max boost cause why not?
        LOCKER.lock(address(this), _amount, getBoostPayment());
    }

    /// @dev utility function to withdraw all AURA that we can from the lock
    function prepareWithdrawAll() external {
        manualProcessExpiredLocks();
    }

    /// @dev Withdraw all funds, this is used for migrations, most of the time for emergency reasons
    function _withdrawAll() internal override {
        //NOTE: This probably will always fail unless we have all tokens expired
        require(
            LOCKER.lockedBalanceOf(address(this)) == 0 && LOCKER.balanceOf(address(this)) == 0,
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
        uint256 rewardBalanceBefore = IERC20Upgradeable(AURABAL).balanceOf(address(this));

        // Get auraBal
        LOCKER.getReward(address(this));

        uint256 earnedReward =
            IERC20Upgradeable(AURABAL).balanceOf(address(this)).sub(_beforeReward);

        // Send rest of earned to tree //We send all rest to avoid dust and avoid protecting the token
        // We take difference of vault token to emit the event in shares rather than underlying
        uint256 auraBALInitialBalance = AURABAL_VAULT.balanceOf(BADGER_TREE);
        uint256 auraBalToTree = IERC20Upgradeable(AURABAL).balanceOf(address(this));

        // Deposit into auraBal vault and send to tree
        AURABAL_VAULT.depositFor(BADGER_TREE, auraBalToTree);
        uint256 auraBALAfterBalance = AURABAL_VAULT.balanceOf(BADGER_TREE);
        emit TreeDistribution(address(AURABAL_VAULT), auraBALAfterBalance.sub(auraBALInitialBalance), block.number, block.timestamp);

    }

    /// @dev allows claiming of multiple bribes, badger is sent to tree
    /// @notice Hidden hand only allows to claim all tokens at once, not individually 
    /// @notice allows claiming any token as it uses the difference in balance
    function claimBribesFromHiddenHand(
        IRewardDistributor hiddenHandDistributor,
        Claim[] calldata _claims
    ) external {
        uint256[] memory beforeBalance = new uint256[](_claims.length);
        uint256 beforeVaultBalance = _getBalance();
        uint256 beforePricePerFullShare = _getPricePerFullShare();

        // Track token balances before bribes claim
        for(uint i = 0; i < _claims.length; i++){
            address token = hiddenHandDistributor.rewards[_claims[i].identifier].token;
            beforeBalance[i] = IERC20Upgradeable(token).balanceOf(address(this));
        }
        // Claim bribes
        hiddenHandDistributor.claim(_claims);

        for(uint i = 0; i < _claims.length; i++) {
             address token = hiddenHandDistributor.rewards[_claims[i].identifier].token;
             //TODO: implement _handleRewardTransfer
            _handleRewardTransfer(token, IERC20Upgradeable(token).balanceOf(address(this)).sub(beforeBalance[i]));
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
    
}
