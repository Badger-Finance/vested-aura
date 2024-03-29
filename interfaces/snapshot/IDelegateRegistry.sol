// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

///@dev Snapshot Delegate registry so we can delegate voting to XYZ
interface IDelegateRegistry {
    function setDelegate(bytes32 id, address delegate) external;

    function clearDelegate(bytes32 id) external;

    function delegation(address, bytes32) external view returns (address);
}
