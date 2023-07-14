// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {IERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import {IRewardDistributor} from "../../interfaces/hiddenhand/IRewardDistributor.sol";

contract MockRewardDistributor {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    mapping(bytes32 => address) public mockRewards;

    function addReward(bytes32 _identifier, address _token) external {
        mockRewards[_identifier] = _token;
    }

    function rewards(bytes32 _identifier)
        external
        view
        returns (
            address token,
            bytes32 merkleRoot,
            bytes32 proof,
            uint256 updateCount
        )
    {
        token = mockRewards[_identifier];
    }

    function claim(IRewardDistributor.Claim[] memory _claims) external {
        for (uint256 i; i < _claims.length; ++i) {
            IRewardDistributor.Claim memory claim = _claims[i];
            IERC20Upgradeable token = IERC20Upgradeable(mockRewards[claim.identifier]);
            token.safeTransfer(claim.account, claim.amount);
        }
    }

    receive() external payable {}
}
