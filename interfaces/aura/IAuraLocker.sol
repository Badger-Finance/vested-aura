// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface IAuraLocker {
    struct EarnedData {
        address token;
        uint256 amount;
    }

    struct Balances {
        uint112 locked;
        uint32 nextUnlockIndex;
    }

    function maximumBoostPayment() external view returns (uint256);

    function lock(address _account, uint256 _amount) external;

    function getReward(address _account) external;

    function getReward(address _account, bool _stake) external;

    function claimableRewards(address _account) external view returns (EarnedData[] memory userRewards);

    //BOOSTED balance of an account which only includes properly locked tokens as of the most recent eligible epoch
    function balanceOf(address _user) external view returns (uint256 amount);

    function balances(address _user) external view returns (Balances memory bals);

    // Withdraw/relock all currently locked tokens where the unlock time has passed
    function processExpiredLocks(
        bool _relock,
        uint256 _spendRatio,
        address _withdrawTo
    ) external;

    // Withdraw/relock all currently locked tokens where the unlock time has passed
    function processExpiredLocks(bool _relock) external;

    function delegate(address newDelegatee) external;

    function delegates(address account) external view returns (address);
}
