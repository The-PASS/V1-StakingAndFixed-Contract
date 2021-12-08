// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./util/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @dev Users pay specific erc20 tokens to purchase PASS from creator DAO in a fixed period.
 * The price of PASS decreases linerly over time.
 * Price formular: f(x) = initialRate - solpe * x
 * f(x) = PASS Price when current time is x + startTime
 * startTime <= x <= endTime
 */
contract FixedPeriod is Context, Ownable, ERC721, ReentrancyGuard {
  using Counters for Counters.Counter;
  using Strings for uint256;
  using SafeERC20 for IERC20;

  event Mint(address indexed from, uint256 indexed tokenId);
  event Withdraw(address indexed to, uint256 amount);
  event SetBaseURI(string baseURI_);
  event ChangeBeneficiary(address _newBeneficiary);
  event SetTokenURI(uint256 indexed tokenId, string _tokenURI);
  event BaseURIFrozen();
  event ChangeBeneficiaryUnlock(uint256 cooldownStartTimestamp);

  uint256 public immutable COOLDOWN_SECONDS = 2 days;

  /// @notice Seconds available to operate once the cooldown period is fullfilled
  uint256 public immutable OPERATE_WINDOW = 1 days;

  bool public baseURIFrozen;
  uint256 public cooldownStartTimestamp;
  uint256 public initialRate; // initial exchange rate of erc20 tokens/PASS
  uint256 public startTime; // start time of PASS sales
  uint256 public endTime; // endTime = startTime + salesValidity
  uint256 public maxSupply; // Maximum supply of PASS
  uint256 public slope; // slope = initialRate / salesValidity
  address public erc20; // erc20 token used to purchase PASS
  address payable public platform; // The Pass platform commission account
  address payable public beneficiary; // creator's beneficiary account
  uint256 public platformRate; // The Pass platform commission rate in pph

  // Optional mapping for token URIs
  mapping(uint256 => string) private _tokenURIs;

  // Base URI
  string private _baseURIextended;

  // token id counter. For erc721 contract, PASS number = token id
  Counters.Counter private tokenIdTracker = Counters.Counter({_value: 1});

  constructor(
    string memory _name,
    string memory _symbol,
    string memory _bURI,
    address _erc20,
    address payable _platform,
    address payable _beneficiary,
    uint256 _initialRate,
    uint256 _startTime,
    uint256 _endTime,
    uint256 _maxSupply,
    uint256 _platformRate
  ) Ownable(tx.origin) ERC721(_name, _symbol) {
    platform = _platform;
    platformRate = _platformRate;

    _baseURIextended = _bURI;
    erc20 = _erc20;
    initialRate = _initialRate;
    startTime = _startTime;
    endTime = _endTime;
    slope = _initialRate / (_endTime - _startTime);
    maxSupply = _maxSupply;
    beneficiary = _beneficiary;
  }

  // only contract admin can set Base URI
  function setBaseURI(string memory baseURI_) public onlyOwner {
    require(!baseURIFrozen, "baseURI has been frozen");
    _baseURIextended = baseURI_;
    emit SetBaseURI(baseURI_);
  }

  // only contract admin can freeze Base URI
  function freezeUrl() public onlyOwner {
    require(!baseURIFrozen, "baseURI has been frozen");
    baseURIFrozen = true;
    emit BaseURIFrozen();
  }

  function _baseURI() internal view virtual override returns (string memory) {
    return _baseURIextended;
  }

  function _getBalance() internal view returns (uint256) {
    return address(this).balance;
  }

  function getCurrentCostToMint() public view returns (uint256 cost) {
    return _getCurrentCostToMint();
  }

  function _getCurrentCostToMint() internal view returns (uint256) {
    require(
      (block.timestamp >= startTime) && (block.timestamp <= endTime),
      "Not in the period"
    );
    return initialRate - (slope * (block.timestamp - startTime));
  }

  // only contract admin can change beneficiary account
  function changeBeneficiary(address payable _newBeneficiary)
    public
    nonReentrant
    onlyOwner
  {
    require(_newBeneficiary != address(0), "FixedPeriod: new address is zero");
    require(
      block.timestamp > cooldownStartTimestamp + COOLDOWN_SECONDS,
      "INSUFFICIENT_COOLDOWN"
    );
    require(
      block.timestamp - (cooldownStartTimestamp + COOLDOWN_SECONDS) <=
        OPERATE_WINDOW,
      "OPERATE_WINDOW_FINISHED"
    );

    beneficiary = _newBeneficiary;
    emit ChangeBeneficiary(_newBeneficiary);

    // clear cooldown after changeBeneficiary
    if (cooldownStartTimestamp != 0) {
      cooldownStartTimestamp = 0;
    }
  }

  // only contract admin can change beneficiary account
  function changeBeneficiaryUnlock() public onlyOwner {
    cooldownStartTimestamp = block.timestamp;

    emit ChangeBeneficiaryUnlock(block.timestamp);
  }

  function tokenURI(uint256 tokenId)
    public
    view
    virtual
    override
    returns (string memory)
  {
    require(_exists(tokenId), "URI query for nonexistent token");

    string memory _tokenURI = _tokenURIs[tokenId];

    // If token URI exists, return the token URI.
    if (bytes(_tokenURI).length > 0) {
      return _tokenURI;
    } else {
      return super.tokenURI(tokenId);
    }
  }

  function _setTokenURI(uint256 tokenId, string memory _tokenURI)
    internal
    virtual
  {
    require(_exists(tokenId), "URI set of nonexistent token");

    string memory tokenURI_ = _tokenURIs[tokenId];
    require(bytes(tokenURI_).length == 0, "already set TokenURI");

    _tokenURIs[tokenId] = _tokenURI;
    emit SetTokenURI(tokenId, _tokenURI);
  }

  // only contract admin can set Token URI
  function setTokenURI(uint256 tokenId, string memory _tokenURI)
    public
    onlyOwner
  {
    _setTokenURI(tokenId, _tokenURI);
  }

  // user buy PASS from contract with specific erc20 tokens
  function mint() public nonReentrant returns (uint256 tokenId) {
    require(address(erc20) != address(0), "ERC20 address is null.");
    require((tokenIdTracker.current() <= maxSupply), "Exceeds maximum supply");
    uint256 rate = _getCurrentCostToMint();

    tokenId = tokenIdTracker.current(); // accumulate the token id

    IERC20(erc20).safeTransferFrom(_msgSender(), address(this), rate);

    if (platform != address(0)) {
      IERC20(erc20).safeTransfer(platform, (rate * platformRate) / 100);
    }

    _safeMint(_msgSender(), tokenId); // mint PASS to user address
    emit Mint(_msgSender(), tokenId);

    tokenIdTracker.increment(); // automate token id increment
  }

  // user buy PASS from contract with ETH
  function mintEth() public payable nonReentrant returns (uint256 tokenId) {
    require(address(erc20) == address(0), "ERC20 address is NOT null.");
    require((tokenIdTracker.current() <= maxSupply), "Exceeds maximum supply");

    uint256 rate = _getCurrentCostToMint();
    require(msg.value >= rate, "Not enough ether sent.");
    if (msg.value - rate > 0) {
      (bool success, ) = payable(_msgSender()).call{value: msg.value - rate}(
        ""
      );
      require(success, "Failed to send Ether");
    }

    tokenId = tokenIdTracker.current(); // accumulate the token id

    _safeMint(_msgSender(), tokenId); // mint PASS to user address
    emit Mint(_msgSender(), tokenId);

    if (platform != address(0)) {
      (bool success, ) = platform.call{value: (rate * (platformRate)) / 100}(
        ""
      );
      require(success, "Failed to send Ether");
    }

    tokenIdTracker.increment(); // automate token id increment
  }

  // anyone can withdraw reserve of erc20 tokens/ETH to creator's beneficiary account
  function withdraw() public nonReentrant {
    if (address(erc20) == address(0)) {
      uint256 amount = _getBalance();
      (bool success, ) = beneficiary.call{value: amount}(""); // withdraw ETH to beneficiary account
      require(success, "Failed to send Ether");

      emit Withdraw(beneficiary, amount);
    } else {
      uint256 amount = IERC20(erc20).balanceOf(address(this));
      IERC20(erc20).safeTransfer(beneficiary, amount); // withdraw erc20 tokens to beneficiary account

      emit Withdraw(beneficiary, amount);
    }
  }

  function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(ERC721)
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }
}
