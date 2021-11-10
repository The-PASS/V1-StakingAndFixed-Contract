// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../FixedPricePeriod.sol";

contract FixedPricePeriodDeployer {
  function deployFixedPrice(
    string memory _name,
    string memory _symbol,
    string memory _bURI,
    address _erc20,
    uint256 _initialRate,
    uint256 _startTime,
    uint256 _termOfValidity,
    uint256 _maxSupply
  ) public returns (address) {
    return
      address(
        new FixedPricePeriod(
          _name,
          _symbol,
          _bURI,
          _erc20,
          _initialRate,
          _startTime,
          _termOfValidity,
          _maxSupply
        )
      );
  }
}