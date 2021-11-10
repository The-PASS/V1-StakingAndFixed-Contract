// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../FixedPricePeriodic.sol";

contract FixedPricePeriodicDeployer {
  function deployFixedPrice(
    string memory _name,
    string memory _symbol,
    string memory _bURI,
    address _erc20,
    uint256 _rate,
    uint256 _maxSupply
  ) public returns (address) {
    address addr = address(
      new FixedPricePeriodic(_name, _symbol, _bURI, _erc20, _rate, _maxSupply)
    );
    return addr;
  }
}
