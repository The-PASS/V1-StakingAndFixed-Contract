// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol"; 

// 需要修改合约增加总量的限制，去除mint限制
// fixed price PASS contract. Users pay specific erc20 tokens to purchase PASS from creator DAO
contract Gamma is Context, ERC721, Ownable {
    using Counters for Counters.Counter;
    using Strings for uint256;

    event Mint(address indexed from, uint256 indexed tokenId);
    event Withdraw(address indexed to, uint256 amount);

    address public currentowner;       // contract owner/admin is normally the creator
    address public erc20;       // erc20 token used to purchase PASS
    uint256 public rate;        // price rate of erc20 tokens/PASS
    uint256 public maxSupply; // Maximum supply
    
    // Optional mapping for token URIs
    mapping (uint256 => string) private _tokenURIs;

    // Base URI
    string private _baseURIextended;

    // token id counter. For erc721 contract, PASS number = token id
    Counters.Counter private tokenIdTracker = Counters.Counter({
        _value: 1
    });
//    mapping(address => uint256) private holders;    // check if user minted PASS to limit that each address can only mint one PASS in the contract

    constructor(string memory _name, string memory _symbol, string memory _bURI, address _erc20, uint256 _rate, uint256 _maxSupply) ERC721(_name, _symbol) {
        currentowner = tx.origin;      // the creator of DAO will be the owner/admin of PASS contract
        _baseURIextended = _bURI;
        erc20 = _erc20;         
        rate = _rate;
        maxSupply = _maxSupply;
    }
    
    function setBaseURI(string memory baseURI_) public {

        require(currentowner == _msgSender(), "Error: must have admin role");  // only contract owner/admin can setTokenURI

        _baseURIextended = baseURI_;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseURIextended;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

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

    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual {
        require(_exists(tokenId), "ERC721Metadata: URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
    }

    function setTokenURI(uint256 tokenId, string memory _tokenURI) public {

        require(currentowner == _msgSender(), "Error: must have admin role");  // only contract owner/admin can setTokenURI

        _setTokenURI(tokenId, _tokenURI);
    }

    // user buy PASS from contract with specific erc20 tokens
    function mint() public returns (uint256 tokenId) {
//        require(holders[_msgSender()] == 0, "error: each user can only mint once");   // each user can only mint once in this contract
        require((tokenIdTracker.current() <= maxSupply), "Error: exceeds maximum supply");
        tokenId = tokenIdTracker.current();                             // accumulate the token id

        // IERC20(erc20).transferFrom(_msgSender(), address(this), rate);  // send erc20 tokens from user to contract
        bool success = IERC20(erc20).transferFrom(_msgSender(), address(this), rate);
        require(success, "Transfer failed.");

        _safeMint(_msgSender(), tokenId);                               // mint PASS to user address
//        holders[_msgSender()] = tokenId;                                // associate the user address with token id

        emit Mint(_msgSender(), tokenId);

        _setTokenURI(tokenId, tokenId.toString());

        tokenIdTracker.increment();                                     // automate token id increment
    }

    // contract owner/admin withdraw erc20 tokens from contract
    function withdraw() public {
        require(currentowner == _msgSender(), "Error: must have admin role");  // only contract owner/admin can withdraw reserve of erc20 tokens
        uint256 amount = IERC20(erc20).balanceOf(address(this));        // get the amount of erc20 tokens reserved in contract
        IERC20(erc20).transfer(_msgSender(), amount);                   // transfer erc20 tokens to contract owner address

        emit Withdraw(_msgSender(), amount);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}