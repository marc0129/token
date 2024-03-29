// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./abstracts/BaseContract.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
// Interfaces
import "./interfaces/IVault.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

/**
 * @title FurBot
 * @notice This is the NFT contract for FurBot.
 */

/// @custom:security-contact security@furio.io
contract FurBot is BaseContract, ERC721Upgradeable
{
    /**
     * Contract initializer.
     * @dev This intializes all the parent contracts.
     */
    function initialize() initializer public
    {
        __BaseContract_init();
        __ERC721_init("FurBot", "$FURBOT");
    }

    /**
     * Global stats.
     */
    uint256 public totalSupply;
    uint256 public totalInvestment;
    uint256 public totalDividends;

    /**
     * External contracts.
     */
    IERC20 private _paymentToken;
    IVault private _vault;
    address private _market;

    /**
     * Generations.
     */
    uint256 private _generationIdTracker;
    mapping(uint256 => uint256) private _generationMaxSupply;
    mapping(uint256 => uint256) private _generationTotalSupply;
    mapping(uint256 => uint256) private _generationInvestment;
    mapping(uint256 => uint256) private _generationDividends;
    mapping(uint256 => string) private _generationImageUri;

    /**
     * Sales.
     */
    uint256 private _saleIdTracker;
    mapping(uint256 => uint256) private _saleGenerationId;
    mapping(uint256 => uint256) private _salePrice;
    mapping(uint256 => uint256) private _saleStart;
    mapping(uint256 => uint256) private _saleEnd;
    mapping(uint256 => bool) private _saleRestricted;

    /**
     * Tokens.
     */
    uint256 private _tokenIdTracker;
    mapping(uint256 => uint256) private _tokenGenerationId;
    mapping(uint256 => uint256) private _tokenInvestment;
    mapping(uint256 => uint256) private _tokenDividendsClaimed;

    /**
     * Events.
     */
    event GenerationCreated(uint256 indexed id_);
    event SaleCreated(uint256 indexed id_);
    event TokenPurchased(uint256 indexed id_);
    event DividendsAdded(uint256 indexed id_, uint256 amount_);
    event DividendsClaimed(address indexed owner_, uint256 amount_);

    /**
     * Setup.
     */
    function setup() external
    {
        _paymentToken = IERC20(addressBook.get("payment"));
        _vault = IVault(addressBook.get("vault"));
        _market = addressBook.get("market");
    }

    /**
     * Token of owner by index.
     * @param owner_ The owner address.
     * @param index_ The index of the token.
     */
    function tokenOfOwnerByIndex(address owner_, uint256 index_) public view returns (uint256)
    {
        require(balanceOf(owner_) > index_, "Index out of bounds");
        for(uint256 i = 1; i <= totalSupply; i++) {
            if(ownerOf(i) == owner_) {
                if(index_ == 0) return i;
                index_--;
            }
        }
        return 0;
    }

    /**
     * Token URI.
     * @param tokenId_ The token ID.
     * @return string The metadata json.
     */
    function tokenURI(uint256 tokenId_) public view override returns(string memory)
    {
        require(tokenId_ > 0 && tokenId_ <= totalSupply, "Invalid token ID");
        return string(
            abi.encodePacked(
                'data:application/json;base64,',
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            '{"name":"FurBot #',
                            Strings.toString(tokenId_),
                            '","description":"FurBot NFT Description","image":"',
                            _generationImageUri[_tokenGenerationId[tokenId_]],
                            '","attributes":',
                            abi.encodePacked(
                                '[{"trait_type":"Generation","value":"',
                                Strings.toString(_tokenGenerationId[tokenId_]),
                                '"},{"trait_type":"Investment","value":"',
                                Strings.toString(_tokenInvestment[tokenId_]),
                                '},{"trait_type":"Dividends Available","value":"',
                                Strings.toString(availableDividendsByToken(tokenId_)),
                                '},{"trait_type":"Dividends Claimed","value":"',
                                Strings.toString(_tokenDividendsClaimed[tokenId_]),
                                '}]'
                            ),
                            '}'
                        )
                    )
                )
            )
        );
    }

    /**
     * Get active sale.
     * @return uint256 The sale ID.
     */
    function getActiveSale() public view returns(uint256)
    {
        for(uint256 i = 1; i <= _saleIdTracker; i++) {
            if(_saleStart[i] <= block.timestamp && _saleEnd[i] >= block.timestamp) return i;
        }
        return 0;
    }

    /**
     * Get next sale.
     * @return uint256 The sale ID.
     */
    function getNextSale() public view returns(uint256)
    {
        for(uint256 i = 1; i <= _saleIdTracker; i++) {
            if(_saleStart[i] > block.timestamp) return i;
        }
        return 0;
    }

    /**
     * Get active sale price.
     * @return uint256 The price.
     */
    function getActiveSalePrice() external view returns(uint256)
    {
        return _salePrice[getActiveSale()];
    }

    /**
     * Get next sale price.
     * @return uint256 The price.
     */
    function getNextSalePrice() external view returns(uint256)
    {
        return _salePrice[getNextSale()];
    }

    /**
     * Buy.
     * @param amount_ The amount of tokens to buy.
     */
    function buy(uint256 amount_) external whenNotPaused
    {
        uint256 _saleId_ = getActiveSale();
        require(_saleId_ > 0, "No active sale.");
        if(_saleRestricted[_saleId_]) require(_vault.rewardRate(msg.sender) == 250, "Not eligible for sale.");
        uint256 _generationId_ = _saleGenerationId[_saleId_];
        require(_generationTotalSupply[_generationId_] + amount_ <= _generationMaxSupply[_generationId_], "Max supply reached.");
        uint256 _investmentAmount_ = _salePrice[_saleId_] * amount_;
        require(_paymentToken.transferFrom(msg.sender, address(this), _investmentAmount_), "Payment failed.");
        for(uint256 i = 1; i <= amount_; i++) {
            _tokenIdTracker++;
            totalSupply++;
            _generationTotalSupply[_generationId_]++;
            totalInvestment += _salePrice[_saleId_];
            _generationInvestment[_generationId_] += _salePrice[_saleId_];
            _tokenGenerationId[_tokenIdTracker] = _generationId_;
            _tokenInvestment[_tokenIdTracker] = _salePrice[_saleId_];
            _mint(msg.sender, _tokenIdTracker);
            emit TokenPurchased(_tokenIdTracker);
        }
    }

    /**
     * Available dividends by owner.
     * @param owner_ The owner address.
     * @return uint256 The available dividends.
     */
    function availableDividendsByAddress(address owner_) external view returns(uint256)
    {
        uint256 _dividends_;
        for(uint256 i = 1; i <= totalSupply; i++) {
            if(ownerOf(i) == owner_) _dividends_ += availableDividendsByToken(i);
        }
        return _dividends_;
    }

    /**
     * Available dividends by token.
     * @param tokenId_ The token ID.
     * @return uint256 The available dividends.
     */
    function availableDividendsByToken(uint256 tokenId_) public view returns(uint256)
    {
        require(_tokenGenerationId[tokenId_] > 0, "Invalid token ID.");
        return (_generationDividends[_tokenGenerationId[tokenId_]] / _generationTotalSupply[_tokenGenerationId[tokenId_]]) - _tokenDividendsClaimed[tokenId_];
    }

    /**
     * Claim dividends.
     */
    function claimDividends() external whenNotPaused
    {
        require(balanceOf(msg.sender) > 0, "No tokens owned.");
        uint256 _dividends_;
        uint256 _totalDividends_;
        for(uint256 i = 1; i <= totalSupply; i++) {
            if(ownerOf(i) == msg.sender) {
                _dividends_ = availableDividendsByToken(i);
                _totalDividends_ += _dividends_;
                _tokenDividendsClaimed[i] += _dividends_;
            }
        }
        require(_paymentToken.transfer(msg.sender, _totalDividends_), "Transfer failed.");
        emit DividendsClaimed(msg.sender, _totalDividends_);
    }

    /**
     * Approve.
     * @param to_ The address to approve.
     * @param tokenId_ The token ID.
     * @dev Overridden to prevent token sales through third party marketplaces.
     */
    function approve(address to_, uint256 tokenId_) public virtual override whenNotPaused
    {
        require(to_ == _market, "Third party marketplaces not allowed.");
        super.approve(to_, tokenId_);
    }

    /**
     * Set approval for all.
     * @param operator_ The operator address.
     * @param approved_ The approval status.
     * @dev Overridden to prevent token sales through third party marketplaces.
     */
    function setApprovalForAll(address operator_, bool approved_) public virtual override whenNotPaused
    {
        require(operator_ == _market, "Third party marketplaces not allowed.");
        super.setApprovalForAll(operator_, approved_);
    }

    /**
     * -------------------------------------------------------------------------
     * ADMIN FUNCTIONS.
     * -------------------------------------------------------------------------
     */

    /**
     * Create generation.
     * @param maxSupply_ The maximum supply of this generation.
     * @param imageUri_ The image URI for this generation.
     */
    function createGeneration(uint256 maxSupply_, string memory imageUri_) external onlyOwner
    {
        _generationIdTracker++;
        _generationMaxSupply[_generationIdTracker] = maxSupply_;
        _generationImageUri[_generationIdTracker] = imageUri_;
        emit GenerationCreated(_generationIdTracker);
    }

    /**
     * Create sale.
     * @param generationId_ The generation ID for this sale.
     * @param price_ The price for this sale.
     * @param start_ The start time for this sale.
     * @param end_ The end time for this sale.
     * @param restricted_ Whether this sale is restricted to whitelisted addresses.
     */
    function createSale(uint256 generationId_, uint256 price_, uint256 start_, uint256 end_, bool restricted_) external onlyOwner
    {
        require(generationId_ > 0 && generationId_ <= _generationIdTracker, "Invalid generation ID.");
        require(start_ > block.timestamp, "Start time must be in the future.");
        if(_saleIdTracker > 0) {
            require(start_ > _saleEnd[_saleIdTracker], "Start time must be after the previous sale.");
        }
        require(end_ > start_, "End time must be after start time.");
        _saleIdTracker++;
        _saleGenerationId[_saleIdTracker] = generationId_;
        _salePrice[_saleIdTracker] = price_;
        _saleStart[_saleIdTracker] = start_;
        _saleEnd[_saleIdTracker] = end_;
        _saleRestricted[_saleIdTracker] = restricted_;
        emit SaleCreated(_saleIdTracker);
    }

    /**
     * Add dividends.
     * @param generationId_ The generation ID for these dividends.
     * @param amount_ Amount of dividends to add.
     */
    function addDividends(uint256 generationId_, uint256 amount_) external onlyOwner
    {
        require(generationId_ > 0 && generationId_ <= _generationIdTracker, "Invalid generation ID.");
        require(_paymentToken.transferFrom(msg.sender, address(this), amount_), "Payment failed.");
        _generationDividends[generationId_] += amount_;
        totalDividends += amount_;
        emit DividendsAdded(generationId_, amount_);
    }
}
