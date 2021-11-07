// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

// import "@openzeppelin/contracts/access/Ownable.sol";

// fixed price PASS contract. Users pay specific erc20 tokens to purchase PASS from creator DAO
contract FixedPrice is Context, AccessControl, ERC721 {
  using Counters for Counters.Counter;
  using Strings for uint256;
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  event Mint(address indexed from, uint256 indexed tokenId);
  event Withdraw(address indexed to, uint256 amount);

  bytes32 public constant CREATOR = keccak256("CREATOR");
  
  address public owner; // contract owner is normally the creator
  address public erc20; // erc20 token used to purchase PASS
  uint256 public rate; // price rate of erc20 tokens/PASS
  uint256 public maxSupply; // Maximum supply of PASS
  address payable public platform; // thePass platform's commission account
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
    uint256 _rate,
    uint256 _maxSupply
  ) ERC721(_name, _symbol) {
    _setupRole(CREATOR, tx.origin);
    owner = tx.origin; // the creator of DAO will be the owner of PASS contract
    _baseURIextended = _bURI;
    erc20 = _erc20;
    rate = _rate;
    maxSupply = _maxSupply;
  }

  // only contract owner can setTokenURI
  function setBaseURI(string memory baseURI_) public onlyRole(CREATOR) {
    _baseURIextended = baseURI_;
  }

  // commission account and rate initilization
  function setFeeParameters(address payable _platform, uint256 _platformRate)
    public
    onlyRole(CREATOR)
  {
    require(
      platform == address(0),
      "FixedPrice: commission account and rate cannot be modified."
    );
    platform = _platform;
    platformRate = _platformRate;
  }

  function _baseURI() internal view virtual override returns (string memory) {
    return _baseURIextended;
  }

  function tokenURI(uint256 tokenId)
    public
    view
    virtual
    override
    returns (string memory)
  {
    require(
      _exists(tokenId),
      "ERC721Metadata: URI query for nonexistent token"
    );

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
    require(_exists(tokenId), "ERC721Metadata: URI set of nonexistent token");
    _tokenURIs[tokenId] = _tokenURI;
  }

  // only contract owner can setTokenURI
  function setTokenURI(uint256 tokenId, string memory _tokenURI)
    public
    onlyRole(CREATOR)
  {
    _setTokenURI(tokenId, _tokenURI);
  }

  // user buy PASS from contract with specific erc20 tokens
  function mint() public returns (uint256 tokenId) {
    require(
      (tokenIdTracker.current() <= maxSupply),
      "FixedPrice: exceeds maximum supply"
    );
    tokenId = tokenIdTracker.current(); // accumulate the token id

    IERC20(erc20).safeTransferFrom(_msgSender(), address(this), rate);

    if (platform != address(0)) {
      IERC20(erc20).safeTransfer(platform, rate.mul(platformRate).div(100));
    }

    _safeMint(_msgSender(), tokenId); // mint PASS to user address
    emit Mint(_msgSender(), tokenId);

    tokenIdTracker.increment(); // automate token id increment
  }

  // owner withdraw erc20 tokens from contract
  // only contract owner can withdraw reserve of erc20 tokens
  function withdraw() public onlyRole(CREATOR) {
    uint256 amount = IERC20(erc20).balanceOf(address(this)); // get the amount of erc20 tokens reserved in contract
    IERC20(erc20).safeTransfer(_msgSender(), amount); // transfer erc20 tokens to contract owner address

    emit Withdraw(_msgSender(), amount);
  }

  function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(ERC721, AccessControl)
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }
}
