// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;


interface IAsset {
    // solhint-disable-previous-line no-empty-blocks
}

interface IBalancerVault {

    enum SwapKind { GIVEN_IN, GIVEN_OUT }

    struct BatchSwapStep {
        bytes32 poolId;
        uint256 assetInIndex;
        uint256 assetOutIndex;
        uint256 amount;
        bytes userData;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address  recipient;
        bool toInternalBalance;
    }


    function batchSwap(
        SwapKind kind,
        BatchSwapStep[] swaps,
        IAsset[] assets,
        FundManagement funds,
        int256[] limits,
        uint256 deadline
    ) external payable returns (int256[] memory);


}
