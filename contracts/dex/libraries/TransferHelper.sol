// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @notice Helper methods for interacting with ERC20 tokens that do not consistently return true/false.
/// @dev Inspired by common DEX transfer helper patterns.
library TransferHelper {
    error TransferHelper__ApproveFailed();
    error TransferHelper__TransferFailed();
    error TransferHelper__TransferFromFailed();
    error TransferHelper__ETHTransferFailed();

    function safeApprove(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSignature("approve(address,uint256)", to, value)
        );
        if (!(success && (data.length == 0 || abi.decode(data, (bool))))) {
            revert TransferHelper__ApproveFailed();
        }
    }

    function safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSignature("transfer(address,uint256)", to, value)
        );
        if (!(success && (data.length == 0 || abi.decode(data, (bool))))) {
            revert TransferHelper__TransferFailed();
        }
    }

    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, value)
        );
        if (!(success && (data.length == 0 || abi.decode(data, (bool))))) {
            revert TransferHelper__TransferFromFailed();
        }
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        if (!success) revert TransferHelper__ETHTransferFailed();
    }
}
