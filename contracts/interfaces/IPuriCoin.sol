// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Minimal interface for your PuriCoin token.
/// @dev PuriCoin in your repo has `mint(address,uint256)` restricted by agent role.
interface IPuriCoin is IERC20 {
    function mint(address to, uint256 amount) external;

    function identityRegistry() external view returns (address);
}
