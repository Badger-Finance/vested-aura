// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {IERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import {IRewardDistributor} from "../../interfaces/hiddenhand/IRewardDistributor.sol";

contract MockRewardDistributor {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address constant public BRIBE_VAULT = address(1);
    bytes32 constant private ETH_IDENTIFIER = keccak256("ETH");

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
        ) {
        if (_identifier == ETH_IDENTIFIER) {
            token = BRIBE_VAULT;
        } else {
            token = mockRewards[_identifier];
        }
    }

    function claim(IRewardDistributor.Claim[] memory _claims) external {
        for (uint256 i; i < _claims.length; ++i) {
            IRewardDistributor.Claim memory claim = _claims[i];

            if (claim.identifier == ETH_IDENTIFIER) {
                (bool sent, ) = payable(claim.account).call{value: claim.amount}("");
                require(sent, "Transfer failed");
            } else {
                IERC20Upgradeable token = IERC20Upgradeable(mockRewards[claim.identifier]);
                token.safeTransfer(claim.account, claim.amount);
            }
        }
    }

    receive() external payable {}
}