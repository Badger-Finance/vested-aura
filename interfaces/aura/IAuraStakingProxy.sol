// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IAuraStakingProxy {
    function owner() external view returns (address);

    function keeper() external view returns (address);
    function setKeeper(address _keeper) external;

    function distribute(uint256 _minOut) external;
    function distribute() external;
}