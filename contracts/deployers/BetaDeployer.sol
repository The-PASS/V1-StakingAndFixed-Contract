// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../Beta.sol";

contract BetaDeployer {
    function deployBeta(
        string memory _name,
        string memory _symbol,
        address _erc721
    ) public returns (address) {
        address addr = address(new Beta(_name, _symbol, _erc721));
        return addr;
    }
}
