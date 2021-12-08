// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./util/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// fixed price PASS contract. Users pay specific erc20 tokens to purchase PASS from creator DAO
contract FixedPrice is Context, Ownable, ERC721, ReentrancyGuard {
  using Counters for Counters.Counter;
  using Strings for uint256;
  using SafeERC20 for IERC20;

  event Mint(address indexed from, uint256 indexed tokenId);
  event Withdraw(address indexed to, uint256 amount);
  event SetBaseURI(string baseURI_);
  event SetTokenURI(uint256 indexed tokenId, string _tokenURI);
  event ChangeBeneficiary(address _newBeneficiary);
  event UrlFreezed();
  event ChangeBeneficiaryUnlock(uint256 cooldownStartTimestamp);

  uint256 public immutable COOLDOWN_SECONDS = 2 days;

  /// @notice Seconds available to operate once the cooldown period is fullfilled
  uint256 public immutable OPERATE_WINDOW = 1 days;

  bool public urlFreezed;
  uint256 public cooldownStartTimestamp;
  uint256 public rate; // price rate of erc20 tokens/PASS
  uint256 public maxSupply; // Maximum supply of PASS
  address public erc20; // erc20 token used to purchase PASS
  address payable public platform; // thePass platform's commission account
  address payable public beneficiary; // thePass benfit receiving account
  uint256 public platformRate; // thePass platform's commission rate in pph

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
    uint256 _rate,
    uint256 _maxSupply,
    uint256 _platformRate
  ) Ownable(tx.origin) ERC721(_name, _symbol) {
    platform = _platform;
    platformRate = _platformRate;

    _baseURIextended = _bURI;
    erc20 = _erc20;
    rate = _rate;
    maxSupply = _maxSupply;
    beneficiary = _beneficiary;
  }

  // only contract owner can setTokenURI
  function setBaseURI(string memory baseURI_) public onlyOwner {
    require(!urlFreezed, "FixedPrice: baseurl has freezed");
    _baseURIextended = baseURI_;
  }

  // only contract admin can freeze Base URI
  function freezeUrl() public onlyOwner {
    require(!urlFreezed, "FixedPrice: baseurl has freezed");
    urlFreezed = true;
    emit UrlFreezed();
  }

  function _baseURI() internal view virtual override returns (string memory) {
    return _baseURIextended;
  }

  function _getBalance() internal view returns (uint256) {
    return address(this).balance;
  }

  function changeBeneficiary(address payable _newBeneficiary)
    public
    nonReentrant
    onlyOwner
  {
    require(_newBeneficiary != address(0), "FixedPrice: new address is zero");
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
    string memory base = _baseURI();

    // If there is no base URI, return the token URI.
    if (bytes(base).length == 0) {
      return _tokenURI;
    }
    // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
    if (bytes(_tokenURI).length > 0) {
      return string(abi.encodePacked(base, _tokenURI));
    }
    // If there is a baseURI but no tokenURI, concatenate the tokenID to the baseURI.
    return string(abi.encodePacked(base, tokenId.toString()));
  }

  function _setTokenURI(uint256 tokenId, string memory _tokenURI)
    internal
    virtual
  {
    require(_exists(tokenId), "URI set of nonexistent token");
    _tokenURIs[tokenId] = _tokenURI;
    emit SetTokenURI(tokenId, _tokenURI);
  }

  // only contract owner can setTokenURI
  function setTokenURI(uint256 tokenId, string memory _tokenURI)
    public
    onlyOwner
  {
    require(!urlFreezed, "FixedPrice: baseurl has freezed");
    _setTokenURI(tokenId, _tokenURI);
  }

  // user buy PASS from contract with specific erc20 tokens
  function mint() public nonReentrant returns (uint256 tokenId) {
    require(address(erc20) != address(0), "FixPrice: erc20 address is null.");
    require((tokenIdTracker.current() <= maxSupply), "exceeds maximum supply");

    tokenId = tokenIdTracker.current(); // accumulate the token id

    IERC20(erc20).safeTransferFrom(_msgSender(), address(this), rate);

    if (platform != address(0)) {
      IERC20(erc20).safeTransfer(platform, (rate * platformRate) / 100);
    }

    _safeMint(_msgSender(), tokenId); // mint PASS to user address
    emit Mint(_msgSender(), tokenId);

    tokenIdTracker.increment(); // automate token id increment
  }

  function mintEth() public payable nonReentrant returns (uint256 tokenId) {
    require(address(erc20) == address(0), "ERC20 address is NOT null.");
    require((tokenIdTracker.current() <= maxSupply), "Exceeds maximum supply");

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

  // withdraw erc20 tokens from contract
  // anyone can withdraw reserve of erc20 tokens to beneficiary
  function withdraw() public nonReentrant {
    if (address(erc20) == address(0)) {
      emit Withdraw(beneficiary, _getBalance());

      (bool success, ) = payable(beneficiary).call{value: _getBalance()}("");
      require(success, "Failed to send Ether");
    } else {
      uint256 amount = IERC20(erc20).balanceOf(address(this)); // get the amount of erc20 tokens reserved in contract
      IERC20(erc20).safeTransfer(beneficiary, amount); // transfer erc20 tokens to contract owner address

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
